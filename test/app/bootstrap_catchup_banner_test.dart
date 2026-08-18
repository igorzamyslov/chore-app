/// Coverage for `catchUpBannerCountProvider` being fed by the COLD-START
/// catch-up run — `bootstrapProvider` itself (`lib/app/providers.dart`), as
/// opposed to the resume/day-change runs `CatchUpController` owns, which
/// `test/app/day_change_catchup_test.dart` covers.
///
/// Backlog B-1 / triage T2.1: a returning user's very first frame is exactly
/// the moment this has to be right, because `bootstrapProvider` runs
/// `catchUpOverdue` to completion before any widget builds. Same bare
/// `ProviderContainer` approach as `day_change_catchup_test.dart` (see its
/// doc comment for why no widget is pumped); the rendered result is covered
/// by `test/features/chores/catch_up_banner_test.dart`.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../application/fake_digest_notification_plugin.dart';

/// A bare `await container.read(bootstrapProvider.future)` deadlocks under
/// `flutter test`'s fake clock (nothing drives it forward without a widget
/// tree scheduling frames), so this polls instead — same technique, and same
/// reason, as `day_change_catchup_test.dart`'s `_awaitBootstrap`.
Future<void> _awaitBootstrap(
  WidgetTester tester,
  ProviderContainer container,
) async {
  for (var i = 0; i < 400; i++) {
    final value = container.read(bootstrapProvider);
    if (value.hasValue) {
      return;
    }
    if (value.hasError) {
      throw StateError('bootstrapProvider failed: ${value.error}');
    }
    await tester.pump(const Duration(milliseconds: 5));
  }
  throw StateError('bootstrapProvider never resolved');
}

void main() {
  setUpAll(() {
    // Every test below opens its own fresh in-memory AppDatabase, so drift's
    // "multiple database instances" warning doesn't apply here.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  testWidgets(
    'a cold start that finds two chores already overdue reports both, so the '
    'banner can name a number rather than say "some"',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      // The household AND the backlog must exist before the container does:
      // bootstrapProvider's catch-up run fires as soon as the household id
      // resolves, and a FutureProvider does not re-run because data changed
      // underneath it afterwards (the same ordering constraint every test in
      // day_change_catchup_test.dart documents).
      final household = await HouseholdRepository(
        database,
      ).createLocalHousehold('Me');
      final seedService = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(DateTime(2026, 1, 1, 9)),
      );
      await seedService.createChore(
        householdId: household.id,
        title: 'Daily A',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.anyone,
        recurrence: Recurrence.everyNDays(1),
      );
      // A second, differently-spaced chore: two of the same fixture would
      // not distinguish a real count from a saturating flag.
      await seedService.createChore(
        householdId: household.id,
        title: 'Daily B',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.anyone,
        recurrence: Recurrence.everyNDays(2),
      );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(
            Clock.fixed(DateTime(2026, 1, 10, 9)),
          ),
          digestNotificationPluginProvider.overrideWithValue(
            FakeDigestNotificationPlugin(),
          ),
        ],
      );

      await _awaitBootstrap(tester, container);

      expect(container.read(catchUpBannerCountProvider), 2);

      // A pump must separate dispose() from close() — see
      // day_change_catchup_test.dart's _disposeAndClose doc comment.
      container.dispose();
      await tester.pump(const Duration(milliseconds: 5));
      await database.close();
    },
  );

  testWidgets(
    'a cold start with nothing overdue leaves the count at 0: the ordinary '
    'launch must stay exactly as silent as it was',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      final household = await HouseholdRepository(
        database,
      ).createLocalHousehold('Me');
      // Not "no chores at all": a chore that exists but is simply not due
      // yet is the realistic ordinary launch, and it exercises the same loop
      // over active chores the case above does.
      final seedService = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(DateTime(2026, 1, 10, 9)),
      );
      await seedService.createChore(
        householdId: household.id,
        title: 'Not due for a while',
        startDate: PlainDate(2026, 1, 20),
        assignmentMode: AssignmentMode.anyone,
        recurrence: Recurrence.everyNDays(1),
      );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(
            Clock.fixed(DateTime(2026, 1, 10, 9)),
          ),
          digestNotificationPluginProvider.overrideWithValue(
            FakeDigestNotificationPlugin(),
          ),
        ],
      );

      await _awaitBootstrap(tester, container);

      expect(container.read(catchUpBannerCountProvider), 0);

      container.dispose();
      await tester.pump(const Duration(milliseconds: 5));
      await database.close();
    },
  );
}
