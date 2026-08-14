/// [CatchUpController] tests (spec `docs/specs/polish-round-1.md` C1):
/// re-running `ChoreService.catchUpOverdue` on app resume and on local
/// day-change, followed by a digest recompute when catch-up actually
/// changed something.
///
/// Also covers what the same two triggers do for the UI's notion of the
/// date — [todayProvider] and the [closedTodayOccurrencesProvider] rebuild
/// that hangs off it (backlog A-2 / audit P1).
///
/// Same approach as `test/app/digest_reschedule_test.dart`: the real
/// controller + real repositories/service against an in-memory database,
/// with only the bottom-most OS-facing notification plugin faked. These
/// deliberately don't pump any widget (see that file's doc comment for
/// why a bare [ProviderContainer] suffices).
///
/// Unlike `digest_reschedule_test.dart`, these tests need the app's notion
/// of "now" to actually move forward (across a local-midnight boundary),
/// so [clockProvider] is overridden with a [Clock] wrapping a *mutable*
/// variable rather than [Clock.fixed] — advanced explicitly, in lockstep
/// with pumped time, wherever a scenario needs the calendar day to change.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/domain/digest_planner.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../application/fake_digest_notification_plugin.dart';

/// A bare `await container.read(someProvider.future)` deadlocks under
/// `flutter test`'s fake clock (nothing ever drives it forward without a
/// widget tree scheduling frames), so this polls via repeated nonzero
/// `tester.pump()` calls instead — same technique as
/// `digest_reschedule_test.dart`'s `_awaitBootstrap`.
Future<String> _awaitBootstrap(
  WidgetTester tester,
  ProviderContainer container,
) async {
  for (var i = 0; i < 400; i++) {
    final value = container.read(bootstrapProvider);
    if (value.hasValue) {
      return value.requireValue;
    }
    if (value.hasError) {
      throw StateError('bootstrapProvider failed: ${value.error}');
    }
    await tester.pump(const Duration(milliseconds: 5));
  }
  throw StateError('bootstrapProvider never resolved');
}

/// Polls [condition] (pumping a small nonzero duration between attempts,
/// for the same reason [_awaitBootstrap] does) until it's true, or fails
/// after [maxIterations]. Used to await the effect of a fired `Timer`
/// (catch-up's database transaction) without a fixed, racy sleep.
Future<void> _pumpUntil(
  WidgetTester tester,
  Future<bool> Function() condition, {
  int maxIterations = 400,
}) async {
  for (var i = 0; i < maxIterations; i++) {
    if (await condition()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 5));
  }
  throw StateError('condition never became true');
}

/// Disposes [container], then closes [database].
///
/// `container.dispose()` cancels every active drift `.watch()` stream this
/// container is still subscribed to (here, `pendingOccurrencesProvider` and
/// `settingsProvider`, both watched by `DigestRescheduleController`); that
/// cancellation's bookkeeping is itself scheduled the same way drift
/// schedules any other stream re-fetch, which under `flutter_test`'s fake
/// clock only ever runs when something pumps time forward (the same
/// `Timer`-needs-a-pump constraint [_awaitBootstrap] and [_pumpUntil] work
/// around). A bare `container.dispose(); await database.close();` — with no
/// pump between them and none after — leaves that cancellation forever
/// unscheduled, and `database.close()` then hangs waiting for the query
/// executor to go idle. A single nonzero pump after `dispose()` (confirmed
/// empirically to be necessary; a zero-duration pump doesn't work, matching
/// [_awaitBootstrap]'s own finding) drives it, and only then does
/// `close()` return.
Future<void> _disposeAndClose(
  WidgetTester tester,
  ProviderContainer container,
  AppDatabase database,
) async {
  container.dispose();
  await tester.pump(const Duration(milliseconds: 5));
  await database.close();
}

void main() {
  setUpAll(() {
    // Every test below opens its own fresh in-memory AppDatabase, so
    // drift's "multiple database instances" warning doesn't apply here.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  group('nextLocalMidnight', () {
    test('just before midnight rolls over to just past tomorrow midnight', () {
      final now = DateTime(2026, 1, 5, 23, 59, 50);
      expect(nextLocalMidnight(now), DateTime(2026, 1, 6, 0, 0, 1));
    });

    test('mid-afternoon still resolves to the following midnight', () {
      final now = DateTime(2026, 1, 5, 14, 30);
      expect(nextLocalMidnight(now), DateTime(2026, 1, 6, 0, 0, 1));
    });

    test('rolls over the calendar month and year correctly', () {
      final now = DateTime(2026, 12, 31, 23);
      expect(nextLocalMidnight(now), DateTime(2027, 1, 1, 0, 0, 1));
    });

    test(
      'built from calendar components, not a fixed 24h duration: the '
      'result is always 00:00:01 on the next calendar day, regardless of '
      'how far into today [now] already is',
      () {
        final justAfterMidnight = DateTime(2026, 3, 28, 0, 0, 5);
        final justBeforeMidnight = DateTime(2026, 3, 28, 23, 59, 59);
        expect(
          nextLocalMidnight(justAfterMidnight),
          DateTime(2026, 3, 29, 0, 0, 1),
        );
        expect(
          nextLocalMidnight(justBeforeMidnight),
          DateTime(2026, 3, 29, 0, 0, 1),
        );
      },
    );
  });

  group('CatchUpController.triggerOnResume', () {
    testWidgets(
      're-runs catch-up when the calendar day has moved on since bootstrap, '
      'and triggers a digest recompute',
      (tester) async {
        var currentTime = DateTime(2026, 1, 5, 9);
        final database = AppDatabase(NativeDatabase.memory());
        // bootstrapProvider no longer creates a household (spec
        // docs/specs/onboarding-v2.md §2) -- seed one directly on the
        // database BEFORE the container exists, so _awaitBootstrap below
        // actually resolves instead of erroring. This must happen before
        // ANY provider read: DigestRescheduleController's constructor
        // (armed by the `..read(digestRescheduleControllerProvider)`
        // cascade below) eagerly `ref.listen`s bootstrapProvider, which
        // would otherwise capture the "no household" error the moment the
        // container is built, before a later seed could take effect
        // (FutureProviders don't re-run just because underlying data
        // changed after the fact).
        await HouseholdRepository(database).createLocalHousehold('Me');
        final plugin = FakeDigestNotificationPlugin();
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            clockProvider.overrideWithValue(Clock(() => currentTime)),
            digestNotificationPluginProvider.overrideWithValue(plugin),
          ],
        )..read(digestRescheduleControllerProvider);
        final catchUpController = container.read(catchUpControllerProvider);
        final householdId = await _awaitBootstrap(tester, container);
        await tester.pump(digestRescheduleDebounce);
        plugin.scheduledCalls.clear();

        final chore = await container
            .read(choreServiceProvider)
            .createChore(
              householdId: householdId,
              title: 'Daily',
              startDate: PlainDate.fromDateTime(currentTime),
              assignmentMode: AssignmentMode.anyone,
              recurrence: Recurrence.everyNDays(1),
            );
        final repo = container.read(choreRepositoryProvider);
        final before = await repo.pendingOccurrenceOf(chore.id);
        expect(before!.dueDate, PlainDate(2026, 1, 5));

        // The calendar day rolls over while the app is backgrounded.
        currentTime = DateTime(2026, 1, 6, 9);
        catchUpController.triggerOnResume();

        await _pumpUntil(tester, () async {
          final pending = await repo.pendingOccurrenceOf(chore.id);
          return pending?.dueDate == PlainDate(2026, 1, 6);
        });
        final missed = await repo.latestClosedOccurrence(chore.id);
        expect(missed!.status, OccurrenceStatus.missed);
        expect(missed.dueDate, PlainDate(2026, 1, 5));

        // Catch-up changed something, so a digest recompute follows
        // (debounced).
        await tester.pump(digestRescheduleDebounce);
        expect(plugin.scheduledCalls, isNotEmpty);

        // Disposed explicitly here (rather than via `addTearDown`), which
        // cancels the still-armed day-change timer: `flutter_test`'s
        // "a Timer is still pending" leak check runs *before* registered
        // tear-downs, so only cancelling before the test body itself
        // returns reliably avoids it (same discipline as
        // `test/test_utils/pump_app.dart`'s database-close comment). See
        // [_disposeAndClose]'s doc comment for why a pump must separate
        // `dispose()` from `close()` here too.
        await _disposeAndClose(tester, container, database);
      },
    );

    testWidgets(
      'leaves occurrences alone when nothing is overdue, but still rolls '
      'the digest horizon forward',
      (tester) async {
        final currentTime = DateTime(2026, 1, 5, 9);
        final database = AppDatabase(NativeDatabase.memory());
        // See the identical comment in the test above: seed the household
        // BEFORE the container (and its eager
        // DigestRescheduleController/bootstrapProvider listen) exists.
        await HouseholdRepository(database).createLocalHousehold('Me');
        final plugin = FakeDigestNotificationPlugin();
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            clockProvider.overrideWithValue(Clock(() => currentTime)),
            digestNotificationPluginProvider.overrideWithValue(plugin),
          ],
        )..read(digestRescheduleControllerProvider);
        final catchUpController = container.read(catchUpControllerProvider);
        final householdId = await _awaitBootstrap(tester, container);
        await tester.pump(digestRescheduleDebounce);

        final chore = await container
            .read(choreServiceProvider)
            .createChore(
              householdId: householdId,
              title: 'Far ahead',
              startDate: PlainDate(2026, 1, 20),
              assignmentMode: AssignmentMode.anyone,
              recurrence: Recurrence.everyNDays(1),
            );
        await tester.pump(digestRescheduleDebounce);
        plugin.scheduledCalls.clear();
        // Captured right before triggerOnResume: bootstrap's own recompute
        // and the chore creation above already pushed cancelCallCount past
        // digestHorizonSlots, so asserting an absolute floor would pass
        // trivially regardless of whether triggerOnResume's catch-up path
        // recomputes anything at all. The delta from here is what actually
        // proves it.
        final cancelCountBefore = plugin.cancelCallCount;

        catchUpController.triggerOnResume();
        // Nothing overdue: give the (no-op) transaction a moment to run,
        // then confirm nothing changed and nothing was scheduled.
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(digestRescheduleDebounce);

        final repo = container.read(choreRepositoryProvider);
        final pending = await repo.pendingOccurrenceOf(chore.id);
        expect(pending!.dueDate, PlainDate(2026, 1, 20));
        // Nothing is due inside the horizon (the chore is 15 days out), so
        // the recompute correctly arms nothing...
        expect(plugin.scheduledCalls, isEmpty);
        // ...but it MUST have run: without an unconditional recompute, an
        // app left open longer than digestHorizonSlots runs off the end of
        // its own horizon and goes silent.
        expect(
          plugin.cancelCallCount,
          greaterThanOrEqualTo(cancelCountBefore + digestHorizonSlots),
        );

        // See [_disposeAndClose]'s doc comment for why a pump must separate
        // `dispose()` from `close()`.
        await _disposeAndClose(tester, container, database);
      },
    );

    testWidgets(
      'moves todayProvider even when catch-up changes nothing — the common '
      'night, where no chore fell overdue',
      (tester) async {
        var currentTime = DateTime(2026, 1, 5, 9);
        final database = AppDatabase(NativeDatabase.memory());
        // Seed the household BEFORE the container exists — see the
        // identical comment on the first test in this file.
        await HouseholdRepository(database).createLocalHousehold('Me');
        // Faked, like every other test in this file that lets catch-up run
        // to completion: without it, the digest recompute `triggerOnResume`
        // also kicks off would reach the real (unfaked) OS notification
        // plugin, which throws in a `flutter_test` environment.
        final plugin = FakeDigestNotificationPlugin();
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            clockProvider.overrideWithValue(Clock(() => currentTime)),
            digestNotificationPluginProvider.overrideWithValue(plugin),
          ],
        );
        final catchUpController = container.read(catchUpControllerProvider);
        await _awaitBootstrap(tester, container);
        expect(container.read(todayProvider), PlainDate(2026, 1, 5));

        // Backgrounded overnight; no chores exist at all, so catch-up has
        // nothing to change and reports `changed == false`.
        currentTime = DateTime(2026, 1, 6, 9);
        catchUpController.triggerOnResume();

        // The refresh itself is synchronous, so this holds even before the
        // unawaited catch-up below has had a chance to run.
        expect(container.read(todayProvider), PlainDate(2026, 1, 6));

        // Let the catch-up (and the digest recompute it unconditionally
        // triggers) settle before disposing: otherwise that still-pending
        // work resumes after `container.dispose()` below and tries to read
        // from an already-disposed container.
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(digestRescheduleDebounce);

        // See [_disposeAndClose]'s doc comment for why a pump must separate
        // `dispose()` from `close()`.
        await _disposeAndClose(tester, container, database);
      },
    );
  });

  group('CatchUpController day-change timer', () {
    testWidgets(
      'fires just past the local-midnight boundary, re-runs catch-up, '
      'triggers a digest recompute, and re-arms for the following '
      'midnight',
      (tester) async {
        var currentTime = DateTime(2026, 1, 5, 23, 59, 50);
        final database = AppDatabase(NativeDatabase.memory());
        // See the identical comment further up this file: seed the
        // household BEFORE the container (and its eager
        // DigestRescheduleController/bootstrapProvider listen) exists.
        await HouseholdRepository(database).createLocalHousehold('Me');
        final plugin = FakeDigestNotificationPlugin();
        final container =
            ProviderContainer(
                overrides: [
                  appDatabaseProvider.overrideWithValue(database),
                  clockProvider.overrideWithValue(Clock(() => currentTime)),
                  digestNotificationPluginProvider.overrideWithValue(plugin),
                ],
              )
              ..read(digestRescheduleControllerProvider)
              ..read(catchUpControllerProvider);
        final householdId = await _awaitBootstrap(tester, container);
        await tester.pump(const Duration(milliseconds: 10));
        plugin.scheduledCalls.clear();

        final chore = await container
            .read(choreServiceProvider)
            .createChore(
              householdId: householdId,
              title: 'Daily',
              startDate: PlainDate(2026, 1, 5),
              assignmentMode: AssignmentMode.anyone,
              recurrence: Recurrence.everyNDays(1),
            );
        final repo = container.read(choreRepositoryProvider);

        // Cross the first midnight boundary. The fake Timer's countdown is
        // governed purely by *pumped* duration, independent of whatever
        // [currentTime] reads — so a first, short pump (well under the
        // ~11-second countdown) lets us mutate [currentTime] in between
        // without racing the timer, before a second pump actually reaches
        // it. Bumping [currentTime] to 23:59:50 (rather than just past
        // midnight) keeps the same calendar day (2026-01-06, so
        // `catchUpOverdue`'s "today" is exactly what the assertions below
        // expect) while *also* setting up a short ~11-second countdown for
        // the re-armed timer's re-arm calculation below — avoiding an
        // unwieldy ~24-hour pump to reach the second boundary.
        await tester.pump(const Duration(milliseconds: 500));
        currentTime = DateTime(2026, 1, 6, 23, 59, 50);
        await tester.pump(const Duration(seconds: 12));

        await _pumpUntil(tester, () async {
          final pending = await repo.pendingOccurrenceOf(chore.id);
          return pending?.dueDate == PlainDate(2026, 1, 6);
        });
        final firstMissed = await repo.latestClosedOccurrence(chore.id);
        expect(firstMissed!.status, OccurrenceStatus.missed);
        expect(firstMissed.dueDate, PlainDate(2026, 1, 5));

        await tester.pump(digestRescheduleDebounce);
        expect(plugin.scheduledCalls, isNotEmpty);
        plugin.scheduledCalls.clear();

        // Cross the SECOND midnight boundary the same way: the timer must
        // have re-armed itself after firing (this exercises exactly that).
        await tester.pump(const Duration(milliseconds: 500));
        currentTime = DateTime(2026, 1, 7, 23, 59, 50);
        await tester.pump(const Duration(seconds: 12));

        await _pumpUntil(tester, () async {
          final pending = await repo.pendingOccurrenceOf(chore.id);
          return pending?.dueDate == PlainDate(2026, 1, 7);
        });
        final secondMissed = await repo.latestClosedOccurrence(chore.id);
        expect(secondMissed!.status, OccurrenceStatus.missed);
        expect(secondMissed.dueDate, PlainDate(2026, 1, 6));

        await tester.pump(digestRescheduleDebounce);
        expect(plugin.scheduledCalls, isNotEmpty);

        // See [_disposeAndClose]'s doc comment for why a pump must separate
        // `dispose()` from `close()`.
        await _disposeAndClose(tester, container, database);
      },
    );

    testWidgets(
      'moves todayProvider when it fires, with nothing overdue and no other '
      'trigger — the regression backlog A-2 describes',
      (tester) async {
        var currentTime = DateTime(2026, 1, 5, 23, 59, 50);
        final database = AppDatabase(NativeDatabase.memory());
        // Seed the household BEFORE the container exists — see the
        // identical comment on the first test in this file.
        await HouseholdRepository(database).createLocalHousehold('Me');
        // Faked, like every other test in this file that lets catch-up run
        // to completion: without it, the digest recompute the day-change
        // timer also kicks off would reach the real (unfaked) OS
        // notification plugin, which throws in a `flutter_test`
        // environment.
        final plugin = FakeDigestNotificationPlugin();
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            clockProvider.overrideWithValue(Clock(() => currentTime)),
            digestNotificationPluginProvider.overrideWithValue(plugin),
          ],
        )..read(catchUpControllerProvider);
        await _awaitBootstrap(tester, container);
        expect(container.read(todayProvider), PlainDate(2026, 1, 5));

        // The fake Timer's countdown is governed purely by *pumped*
        // duration, independent of what [currentTime] reads — so a short
        // first pump (well under the ~11s countdown armed at bootstrap)
        // lets us move the clock without racing it, and the second pump
        // reaches the boundary. Same technique as the test above.
        await tester.pump(const Duration(milliseconds: 500));
        currentTime = DateTime(2026, 1, 6, 0, 0, 1);
        await tester.pump(const Duration(seconds: 12));

        expect(container.read(todayProvider), PlainDate(2026, 1, 6));

        // Let the digest recompute the timer unconditionally triggers
        // settle before disposing — see the identical comment in the test
        // above.
        await tester.pump(digestRescheduleDebounce);

        // See [_disposeAndClose]'s doc comment for why a pump must separate
        // `dispose()` from `close()`.
        await _disposeAndClose(tester, container, database);
      },
    );
  });

  group('closedTodayOccurrencesProvider', () {
    testWidgets(
      'empties when the calendar day rolls over: a completion made '
      'yesterday is no longer "closed today"',
      (tester) async {
        var currentTime = DateTime(2026, 1, 5, 9);
        final database = AppDatabase(NativeDatabase.memory());
        // Seed the household BEFORE the container exists — see the
        // identical comment on the first test in this file.
        await HouseholdRepository(database).createLocalHousehold('Me');
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            clockProvider.overrideWithValue(Clock(() => currentTime)),
          ],
        );
        final householdId = await _awaitBootstrap(tester, container);
        final me = await database.select(database.members).getSingle();

        final service = container.read(choreServiceProvider);
        final chore = await service.createChore(
          householdId: householdId,
          title: 'Dishes',
          startDate: PlainDate(2026, 1, 5),
          assignmentMode: AssignmentMode.anyone,
        );
        final repo = container.read(choreRepositoryProvider);
        final pending = await repo.pendingOccurrenceOf(chore.id);
        await service.completeOccurrence(pending!.id, completedBy: me.id);

        // A StreamProvider only runs while something listens to it.
        container.listen(closedTodayOccurrencesProvider, (_, _) {});
        await _pumpUntil(
          tester,
          () async =>
              container.read(closedTodayOccurrencesProvider).value?.length == 1,
        );

        // Midnight passes. Nothing else changes in the database at all.
        currentTime = DateTime(2026, 1, 6, 0, 0, 1);
        container.read(todayProvider.notifier).refresh();

        // The provider re-subscribes against the new date; until its new
        // stream emits, Riverpod keeps serving the previous value, which is
        // exactly what _pumpUntil is for.
        await _pumpUntil(
          tester,
          () async =>
              container.read(closedTodayOccurrencesProvider).value?.isEmpty ??
              false,
        );

        // See [_disposeAndClose]'s doc comment for why a pump must separate
        // `dispose()` from `close()`.
        await _disposeAndClose(tester, container, database);
      },
    );
  });
}
