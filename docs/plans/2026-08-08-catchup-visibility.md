# Catch-up visibility (B-1 / T2.1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When `ChoreService.catchUpOverdue` silently converts a backlog of
overdue occurrences to `missed` and reinserts fresh pending ones, tell the
returning user this happened — calmly, once, and only when it actually did.

**Architecture:** `catchUpOverdue` starts returning the *count* of chores it
changed instead of a bare `bool`. Both call sites that already exist
(`bootstrapProvider`'s cold-start run, `CatchUpController`'s resume/
day-change runs) feed that count into a new ephemeral `StateProvider<int>`,
`catchUpBannerCountProvider`. A new self-hiding banner,
`CatchUpBanner`, renders on the chores list exactly when that count is
nonzero, explains what happened in one plain sentence, and resets the
provider to 0 on dismiss. Nothing here is persisted to disk: unlike
`OnboardingNameBanner`/`DigestPrepromptBanner` (permanently dismissed once,
ever, via a settings-table flag), catch-up is a recurring background event —
the count is in-memory only, so a *new* catch-up event with a nonzero count
can show the banner again even after an earlier one was dismissed, while a
cold start where nothing changed never shows anything at all.

**Tech Stack:** Flutter + Riverpod + drift, per repo conventions (see
`CLAUDE.md`).

## Global Constraints

- Never run `flutter`/`dart` commands other than what each task step
  explicitly says to run (`flutter test <path>`, `flutter gen-l10n`,
  `flutter analyze --fatal-infos --fatal-warnings`, `dart format .`) — the
  execution agent runs these; this document is the plan, not the
  execution log.
- Every user-visible string goes through gen_l10n: `lib/l10n/app_en.arb`
  (template) + `lib/l10n/app_de.arb` (German, du-form). No inline English.
  ICU plurals where counts appear. `pubspec.yaml` has `generate: true`, so
  `flutter gen-l10n` (or any `flutter test`/`analyze`/`build`) regenerates
  `lib/l10n/app_localizations*.dart` from the ARB files — those generated
  files are tracked in git in this repo and must be committed alongside
  the ARB edits.
- Every interactive widget gets a stable id via `semantic()`
  (`lib/app/semantics.dart`); E2E selects only by id or `(?s)`-substring
  text.
- Widget tests are integration-style: real in-memory `AppDatabase` + fixed
  clock, overriding ONLY `appDatabaseProvider` and `clockProvider` — except
  where a provider's own doc comment explicitly sanctions a direct
  override for widget-level testing (this repo's precedent:
  `notificationPermissionGrantedProvider`; this plan's new
  `catchUpBannerCountProvider` follows the identical precedent for the
  banner's own rendering test). Never mock repositories or services.
- Deadlock traps: never await a drift stream outside a widget pump; never
  bare-await `bootstrapProvider.future` in a `ProviderContainer` test (poll
  `.hasValue` with pump loops, see `_awaitBootstrap` in
  `test/app/day_change_catchup_test.dart`); `tester.pump(small duration)`
  between `container.dispose()` and `database.close()`.
- Strict lints (very_good_analysis, `--fatal-infos`); public members need
  doc comments.
- TDD: write-failing-test → run → implement → run → commit.
- Specs in `docs/specs/` are binding contracts — `docs/specs/
  occurrence-lifecycle.md`'s `catchUpOverdue` section must be updated
  (Task 1) to match the new return type before/with the code change.

## Open product decisions

### OD-1 — What surface tells the user catch-up happened?

Three real options, all with precedent elsewhere in this codebase:

**(a) Self-hiding banner** (recommended) — a new `CatchUpBanner`, structurally
identical to `OnboardingNameBanner`/`DigestPrepromptBanner`
(`lib/features/chores/`): a `DepthCard` at the top of the chores list, one
sentence of plain-language explanation, an X to dismiss. Persists until
dismissed (no auto-timeout), so a user who glances at the list and looks
away doesn't miss it. Its "seen" state is NOT persisted to `settings` — it
resets only because the underlying count resets, so a genuinely new
catch-up event later can show it again.

**(b) Toast via `showAppSnackbar`** (`lib/app/snackbars.dart`) — fires once
when the chores list first builds with a nonzero count. Cheapest to build,
matches the "quiet" design language, auto-dismisses after 4s. But every
existing snackbar in this app is the *direct, synchronous* result of a user
tap (complete/skip/undo); firing one automatically from a rebuild is a new
pattern here, and 4 seconds is thin for a message whose entire job is to
stop a "the app just accused me of failing" reaction — the user needs time
to actually read and process it, not just notice it flash by.

**(c) Inline section-header note** — attach the explanation to wherever the
affected chores now live. Rejected as impractical, not just non-preferred:
there is currently no "Missed" section in the UI at all. A `missed`-status
occurrence is closed and excluded from "Done today" by spec
(`docs/specs/occurrence-lifecycle.md` reopen section); the only visible
trace of catch-up having run is the *reinserted* pending occurrence, which
renders as an ordinary overdue tile indistinguishable from one that was
always overdue. Making this option real would mean inventing a new
permanent-ish "recently caught up" tile marker or section — a materially
bigger, more invasive change than this ticket's **S** sizing, and it fights
the "quiet" design language by adding a permanent structural element for a
rare event.

**Recommendation: (a).** It is the only option that gives the explanation
room to actually explain (option (b)'s 4-second window undercuts the whole
point of the ticket), it reuses an established, low-risk visual pattern
verbatim, and its self-hiding condition (`count == 0`) already satisfies
"must not fire when nothing happened" and "must not nag" without any new
mechanism.

**What the plan assumes:** Tasks 1–3 (the count plumbing:
`catchUpOverdue` returning an `int`, `catchUpBannerCountProvider`, and both
call sites feeding it) are surface-agnostic and identical under any of the
three options. Only Tasks 4–6 (l10n copy + the `CatchUpBanner` widget +
its wiring into `chores_list_screen.dart`) are banner-specific; swapping to
option (b) would replace those three tasks with a single widget that calls
`showAppSnackbar` from a `ref.listen` callback instead, reusing the exact
same provider from Tasks 1–3.

## Resolved by judgement (not escalated — derivable from the spec/ticket)

- **Ephemeral, not permanent, dismissal.** A one-time-ever flag (the
  onboarding/digest-preprompt pattern) would silence the banner after the
  *first* lapse and never explain a *second* one — directly contradicting
  "must not fire on every cold start when nothing happened" only holding
  for the *empty* case, not the *repeat* case. The count-based provider
  handles both for free: 0 shows nothing, dismiss sets it back to 0, a new
  nonzero count (a new event) shows it again.
- **No "Undo" action on the banner.** `reopenOccurrence` could technically
  undo a *single* chore's catch-up-missed occurrence (it was closed with
  `closedOn == today`), but the banner covers however many chores changed
  in one run, and there is no existing bulk-undo affordance anywhere in
  this app to extend. `docs/specs/design-language.md` rule 3 already
  defers undo-snackbars on destructive actions to "backlog, not v1" in
  general; a bespoke bulk-undo here would be new scope well past this
  ticket's **S** sizing, not a small addition.
- **Copy avoids the words "missed" and "failed".** The persona finding
  (`docs/research/persona-ben.md` finding 1) is specifically that silent
  "missed" rows read as an accusation; naming the same status word in the
  explanation would just move the accusation into the banner. The copy
  below describes the *mechanism* ("rolled forward") instead.
- **Banner placement: above the two existing banners**, not below. A
  returning-after-a-lapse user is the exact audience this ticket is about;
  what-just-happened context outranks the evergreen onboarding/digest
  prompts for that user's attention. (Both existing banners already
  self-hide independently, so this is a pure ordering choice, not a
  layout change.)
- **Count semantics: chores changed, not occurrences.** `catchUpOverdue`
  closes exactly one occurrence and reinserts exactly one per affected
  chore, so "chores changed" and "occurrences changed" are the same
  number; the plan names it `changedCount` / "chores" in copy since that's
  the noun the rest of the UI uses (chores list, chore tiles).
- **Accumulate, don't overwrite, across back-to-back events.** If a second
  catch-up run (e.g. a day-change timer firing while the first banner is
  still unacknowledged) reports another nonzero count, the provider adds
  it (`state = state + count`) rather than replacing it, so an earlier
  count is never silently lost before the user sees it.

---

## File map

| File | Change |
| --- | --- |
| `lib/application/chore_service.dart` | `catchUpOverdue` returns `Future<int>` (count) instead of `Future<bool>` |
| `docs/specs/occurrence-lifecycle.md` | Update the `catchUpOverdue` return-value bullet to match |
| `lib/app/providers.dart` | New `catchUpBannerCountProvider`; `bootstrapProvider` and `CatchUpController._runCatchUp` feed it |
| `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb` | New `catchUpBannerMessage` (ICU plural) + `catchUpBannerDismissTooltip` keys |
| `lib/features/chores/catch_up_banner.dart` | New: the `CatchUpBanner` widget |
| `lib/features/chores/chores_list_screen.dart` | Render `CatchUpBanner` above the existing two banners |
| `test/application/chore_service_test.dart` | Update `catchUpOverdue` assertions for the new `int` return; add a multi-chore count test |
| `test/app/day_change_catchup_test.dart` | Add `catchUpBannerCountProvider` assertions to the two existing `CatchUpController.triggerOnResume` tests |
| `test/app/bootstrap_catchup_banner_test.dart` | New: cold-start (`bootstrapProvider`) sets the provider to the real count |
| `test/features/chores/catch_up_banner_test.dart` | New: widget-level render/copy/dismiss coverage |

---

### Task 1: `catchUpOverdue` returns a count, not a bool

**Files:**
- Modify: `lib/application/chore_service.dart:138-178`
- Modify: `docs/specs/occurrence-lifecycle.md` (the `catchUpOverdue` section, the "Returns whether it changed anything..." paragraph)
- Test: `test/application/chore_service_test.dart:380-475`

**Interfaces:**
- Produces: `Future<int> ChoreService.catchUpOverdue(String householdId)` —
  the number of chores whose pending occurrence was closed as `missed` and
  reinserted during this call (0 if none). Replaces the old `Future<bool>`.

- [ ] **Step 1: Write the failing test — assert the new `int` return value**

Edit `test/application/chore_service_test.dart`: in the `catchUpOverdue`
group (starts at line 380), capture and assert the return value of every
existing call, and add one new test proving it counts more than one chore
in a single run. Replace the group's three existing tests' calls and add a
fourth test, so the group reads:

```dart
  group('catchUpOverdue', () {
    test(
      '3 slots behind: closes as missed and reinserts at the latest slot '
      '<= today, preserving the assignee; a same-household future-due '
      'chore is left untouched; a second call the same day is a no-op',
      () async {
        final m1 = await _insertMember(db, 'm1', householdId);
        final m2 = await _insertMember(db, 'm2', householdId);
        final overdueChore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
          householdId: householdId,
          title: 'Daily',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.rotation,
          recurrence: Recurrence.everyNDays(1),
          assigneeMemberIds: [m1, m2],
        );
        final futureChore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
          householdId: householdId,
          title: 'Far ahead',
          startDate: PlainDate(2026, 1, 20),
          assignmentMode: AssignmentMode.anyone,
          recurrence: Recurrence.everyNDays(1),
        );

        final count = await serviceOn(
          PlainDate(2026, 1, 4),
        ).catchUpOverdue(householdId);
        expect(count, 1);

        final pending = await repo.pendingOccurrenceOf(overdueChore.id);
        expect(pending!.dueDate, PlainDate(2026, 1, 4));
        expect(pending.assignedMemberId, m1);

        final missed = await repo.latestClosedOccurrence(overdueChore.id);
        expect(missed!.status, OccurrenceStatus.missed);
        expect(missed.dueDate, PlainDate(2026, 1, 1));
        expect(missed.closedOn, PlainDate(2026, 1, 4));

        final futurePending = await repo.pendingOccurrenceOf(futureChore.id);
        expect(futurePending!.dueDate, PlainDate(2026, 1, 20));
        expect(await repo.latestClosedOccurrence(futureChore.id), isNull);

        // Idempotent: a second call the same day changes nothing and
        // reports 0.
        final secondCount = await serviceOn(
          PlainDate(2026, 1, 4),
        ).catchUpOverdue(householdId);
        expect(secondCount, 0);

        final pendingAfter = await repo.pendingOccurrenceOf(overdueChore.id);
        expect(pendingAfter!.id, pending.id);
        expect(pendingAfter.dueDate, PlainDate(2026, 1, 4));
        expect(pendingAfter.assignedMemberId, m1);
        final missedAfter = await repo.latestClosedOccurrence(
          overdueChore.id,
        );
        expect(missedAfter!.id, missed.id);
      },
    );

    test('a completion-anchored chore is never auto-missed', () async {
      final chore = await serviceOn(PlainDate(2025, 12, 25)).createChore(
        householdId: householdId,
        title: 'Water plants',
        startDate: PlainDate(2025, 12, 25),
        assignmentMode: AssignmentMode.anyone,
        recurrence: Recurrence.everyNDays(
          4,
          anchor: RecurrenceAnchor.completion,
        ),
      );

      // 10 days overdue.
      final count = await serviceOn(
        PlainDate(2026, 1, 4),
      ).catchUpOverdue(householdId);
      expect(count, 0);

      final pending = await repo.pendingOccurrenceOf(chore.id);
      expect(pending!.dueDate, PlainDate(2025, 12, 25));
      expect(pending.status, OccurrenceStatus.pending);
      expect(await repo.latestClosedOccurrence(chore.id), isNull);
    });

    test(
      'a paused chore is left untouched even if its pending occurrence is '
      'overdue',
      () async {
        final chore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
          householdId: householdId,
          title: 'Paused daily',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.anyone,
          recurrence: Recurrence.everyNDays(1),
        );
        await repo.setPaused(chore.id, paused: true);

        final count = await serviceOn(
          PlainDate(2026, 1, 4),
        ).catchUpOverdue(householdId);
        expect(count, 0);

        final pending = await repo.pendingOccurrenceOf(chore.id);
        expect(pending!.dueDate, PlainDate(2026, 1, 1));
        expect(pending.status, OccurrenceStatus.pending);
        expect(await repo.latestClosedOccurrence(chore.id), isNull);
      },
    );

    test(
      'two overdue chores in the same household both count, in one call',
      () async {
        final choreA = await serviceOn(PlainDate(2026, 1, 1)).createChore(
          householdId: householdId,
          title: 'Daily A',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.anyone,
          recurrence: Recurrence.everyNDays(1),
        );
        final choreB = await serviceOn(PlainDate(2026, 1, 1)).createChore(
          householdId: householdId,
          title: 'Daily B',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.anyone,
          recurrence: Recurrence.everyNDays(2),
        );

        final count = await serviceOn(
          PlainDate(2026, 1, 4),
        ).catchUpOverdue(householdId);
        expect(count, 2);

        expect(
          (await repo.latestClosedOccurrence(choreA.id))!.status,
          OccurrenceStatus.missed,
        );
        expect(
          (await repo.latestClosedOccurrence(choreB.id))!.status,
          OccurrenceStatus.missed,
        );
      },
    );
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/application/chore_service_test.dart`
Expected: FAIL — `catchUpOverdue` still returns `bool`, so `expect(count, 1)`
etc. fail (a `bool` compared against an `int` is never equal).

- [ ] **Step 3: Implement the count in `chore_service.dart`**

In `lib/application/chore_service.dart`, replace the `catchUpOverdue`
method body (lines 138–178) and its doc comment (lines 121–137):

```dart
  /// Runs on app start, on app resume, and on local day change (spec
  /// `docs/specs/polish-round-1.md` C1: see `CatchUpController` in
  /// `lib/app/providers.dart`). For every active, unpaused,
  /// schedule-anchored recurring chore in [householdId] with a pending
  /// occurrence where at least one later series slot is <= today: closes the
  /// pending occurrence as `missed` and inserts a new pending occurrence at
  /// the latest series slot <= today, keeping the same assigned member.
  ///
  /// Completion-anchored and one-off chores are never touched; they simply
  /// stay overdue. Idempotent: calling this again the same day changes
  /// nothing.
  ///
  /// Returns the number of chores it changed (0 if none) — `CatchUpController`
  /// uses a nonzero result to decide a digest recompute is warranted, and
  /// (spec `docs/specs/occurrence-lifecycle.md`, backlog B-1) to surface a
  /// user-visible explanation of what just happened, since the common case
  /// (nothing overdue) has nothing new for either to reflect.
  Future<int> catchUpOverdue(String householdId) async {
    final today = _today;
    var changedCount = 0;
    await database.transaction(() async {
      final activeChores = await chores.getActiveChores(householdId);
      for (final details in activeChores) {
        final chore = details.chore;
        final recurrence = chore.recurrence;
        if (chore.pausedAt != null ||
            recurrence == null ||
            recurrence.anchor != RecurrenceAnchor.schedule) {
          continue;
        }
        final pending = await chores.pendingOccurrenceOf(chore.id);
        if (pending == null) {
          continue;
        }
        final latestSlot = _latestOverdueSlot(
          rule: recurrence,
          startDate: chore.startDate,
          afterDueDate: pending.dueDate,
          today: today,
        );
        if (latestSlot == null) {
          continue;
        }
        await chores.closeOccurrence(
          pending.id,
          status: OccurrenceStatus.missed,
          closedOn: today,
        );
        await chores.insertOccurrence(
          choreId: chore.id,
          dueDate: latestSlot,
          assignedMemberId: pending.assignedMemberId,
        );
        changedCount++;
      }
    });
    return changedCount;
  }
```

- [ ] **Step 4: Update the spec**

In `docs/specs/occurrence-lifecycle.md`, in the `catchUpOverdue` section,
replace:

```
Returns whether it changed anything (closed at least one chore's
occurrence as missed and reinserted it) — `CatchUpController` uses this to
decide whether a digest recompute is warranted afterward.
```

with:

```
Returns the number of chores it changed (0 if none) — `CatchUpController`
uses a nonzero result to decide whether a digest recompute is warranted,
and (backlog B-1) to surface a user-visible explanation of what just
happened, since the common case (nothing overdue) has nothing new for
either to reflect.
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/application/chore_service_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/application/chore_service.dart docs/specs/occurrence-lifecycle.md test/application/chore_service_test.dart
git commit -m "ChoreService.catchUpOverdue returns a changed-chore count"
```

---

### Task 2: `catchUpBannerCountProvider` + wire the two catch-up call sites

**Files:**
- Modify: `lib/app/providers.dart:465-525` (`bootstrapProvider`)
- Modify: `lib/app/providers.dart:864-876` (`CatchUpController._runCatchUp`)
- Test: `test/app/day_change_catchup_test.dart`
- Test: `test/app/bootstrap_catchup_banner_test.dart` (new)

**Interfaces:**
- Consumes: `Future<int> ChoreService.catchUpOverdue(String)` (Task 1).
- Produces: `final catchUpBannerCountProvider = StateProvider<int>((ref) => 0);`
  — read by `CatchUpBanner` (Task 5/6); `count == 0` means "show nothing".

- [ ] **Step 1: Write the failing tests**

First, add assertions to the two existing tests in
`test/app/day_change_catchup_test.dart`.

In the first test in the `'CatchUpController.triggerOnResume'` group
(`'re-runs catch-up when the calendar day has moved on since bootstrap, '
'and triggers a digest recompute'`), immediately after the existing:

```dart
        // Catch-up changed something, so a digest recompute follows
        // (debounced).
        await tester.pump(digestRescheduleDebounce);
        expect(plugin.scheduledCalls, isNotEmpty);
```

add:

```dart
        expect(container.read(catchUpBannerCountProvider), 1);
```

In the second test (`'is a no-op (and triggers no digest recompute) when '
'nothing is overdue'`), immediately after the existing:

```dart
        expect(pending!.dueDate, PlainDate(2026, 1, 20));
        expect(plugin.scheduledCalls, isEmpty);
```

add:

```dart
        expect(container.read(catchUpBannerCountProvider), 0);
```

Then create `test/app/bootstrap_catchup_banner_test.dart` to cover the
cold-start path (`bootstrapProvider` itself, not `CatchUpController`),
with two overdue chores so the count is unambiguous (not just "truthy"):

```dart
/// Coverage for `catchUpBannerCountProvider` being set from the COLD-START
/// catch-up run (`bootstrapProvider`, `lib/app/providers.dart`), as
/// opposed to the app-resume/day-change runs already covered by
/// `test/app/day_change_catchup_test.dart`. Backlog B-1 / triage T2.1: a
/// returning user's very first frame is exactly the moment this needs to
/// be right, since `bootstrapProvider` runs `catchUpOverdue` before any
/// widget renders.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:clock/clock.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../application/fake_digest_notification_plugin.dart';

/// Same polling technique as `test/app/day_change_catchup_test.dart`'s
/// `_awaitBootstrap` (a bare `await container.read(bootstrapProvider.future)`
/// deadlocks under `flutter_test`'s fake clock).
Future<void> _awaitBootstrap(
  WidgetTester tester,
  ProviderContainer container,
) async {
  for (var i = 0; i < 400; i++) {
    if (container.read(bootstrapProvider).hasValue) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 5));
  }
  throw StateError('bootstrapProvider never resolved');
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  testWidgets(
    'a cold start with two chores already overdue sets '
    'catchUpBannerCountProvider to 2',
    (tester) async {
      final today = DateTime(2026, 1, 10, 9);
      final database = AppDatabase(NativeDatabase.memory());
      // Seed household AND the overdue chores BEFORE the container exists
      // -- bootstrapProvider's catch-up run fires the instant the
      // container's first `ref.watch(bootstrapProvider)` resolves the
      // household id, so the backlog must already be in the database by
      // then (same ordering constraint documented in
      // `test/app/day_change_catchup_test.dart`).
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
          clockProvider.overrideWithValue(Clock.fixed(today)),
          digestNotificationPluginProvider.overrideWithValue(
            FakeDigestNotificationPlugin(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await _awaitBootstrap(tester, container);

      expect(container.read(catchUpBannerCountProvider), 2);

      await tester.pump(const Duration(milliseconds: 5));
      await database.close();
    },
  );

  testWidgets(
    'a cold start with nothing overdue leaves catchUpBannerCountProvider '
    'at 0',
    (tester) async {
      final today = DateTime(2026, 1, 10, 9);
      final database = AppDatabase(NativeDatabase.memory());
      await HouseholdRepository(database).createLocalHousehold('Me');

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(Clock.fixed(today)),
          digestNotificationPluginProvider.overrideWithValue(
            FakeDigestNotificationPlugin(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await _awaitBootstrap(tester, container);

      expect(container.read(catchUpBannerCountProvider), 0);

      await tester.pump(const Duration(milliseconds: 5));
      await database.close();
    },
  );
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/app/day_change_catchup_test.dart test/app/bootstrap_catchup_banner_test.dart`
Expected: FAIL — `catchUpBannerCountProvider` doesn't exist yet (compile
error).

- [ ] **Step 3: Add the provider and wire both call sites**

In `lib/app/providers.dart`, add the new provider near
`notificationPermissionGrantedProvider` (after its declaration, around
line 441):

```dart
/// The number of chores [ChoreService.catchUpOverdue] silently closed as
/// `missed` and reinserted during the most recent catch-up run that the
/// user hasn't yet acknowledged (backlog B-1 / triage T2.1) — `0` means
/// there's nothing to show.
///
/// Set by [bootstrapProvider] (the cold-start run) and by
/// [CatchUpController] (the app-resume / day-change runs) whenever
/// `catchUpOverdue` reports a nonzero count. ACCUMULATES across runs
/// (`state += count`) rather than overwriting, so a second catch-up event
/// firing before an earlier one's banner has been acknowledged never loses
/// the earlier count. `CatchUpBanner`
/// (`lib/features/chores/catch_up_banner.dart`) is the only reader;
/// dismissing it resets this back to `0`. Deliberately NOT persisted
/// anywhere (unlike the onboarding-name/digest-preprompt banners' settings
/// flags): catch-up is a recurring background event, not a one-time
/// onboarding step, so a fresh nonzero count must be able to show the
/// banner again even after an earlier one was dismissed. Backed by a plain
/// [StateProvider] for the same reason as
/// [notificationPermissionGrantedProvider]: widget tests can override it
/// directly to exercise the banner's visible/hidden states without
/// needing a real overdue-chore backlog.
final catchUpBannerCountProvider = StateProvider<int>((ref) => 0);
```

Then, in `bootstrapProvider` (around line 515), replace:

```dart
  await ref.watch(choreServiceProvider).catchUpOverdue(householdId);
```

with:

```dart
  final caughtUpCount = await ref
      .watch(choreServiceProvider)
      .catchUpOverdue(householdId);
  if (caughtUpCount > 0) {
    ref.read(catchUpBannerCountProvider.notifier).state += caughtUpCount;
  }
```

Then, in `CatchUpController._runCatchUp` (around line 864), replace:

```dart
  Future<void> _runCatchUp() async {
    final householdId = _householdId;
    if (householdId == null) {
      return;
    }
    final changed = await _ref
        .read(choreServiceProvider)
        .catchUpOverdue(householdId);
    if (changed) {
      _ref.read(digestRescheduleControllerProvider).triggerRecompute();
    }
  }
```

with:

```dart
  Future<void> _runCatchUp() async {
    final householdId = _householdId;
    if (householdId == null) {
      return;
    }
    final changedCount = await _ref
        .read(choreServiceProvider)
        .catchUpOverdue(householdId);
    if (changedCount > 0) {
      _ref.read(catchUpBannerCountProvider.notifier).state += changedCount;
      _ref.read(digestRescheduleControllerProvider).triggerRecompute();
    }
  }
```

(The class doc comment above `CatchUpController`, around lines 815–819,
already describes the digest-recompute condition in terms of "changed
something" — leave it; it remains accurate for a nonzero count.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/app/day_change_catchup_test.dart test/app/bootstrap_catchup_banner_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/app/providers.dart test/app/day_change_catchup_test.dart test/app/bootstrap_catchup_banner_test.dart
git commit -m "Add catchUpBannerCountProvider, fed by both catch-up call sites"
```

---

### Task 3: `flutter analyze` checkpoint

**Files:** none (verification only)

- [ ] **Step 1: Run analyze**

Run: `flutter analyze --fatal-infos --fatal-warnings`
Expected: no issues. (`catchUpBannerCountProvider` is unread by any widget
yet at this point in the plan — Riverpod providers are top-level `final`s,
not classes needing a consumer to avoid an unused-element lint, so this is
expected to be clean already; this step exists to catch it early rather
than let it compound with Tasks 4–6's changes.)

---

### Task 4: l10n copy for the banner

**Files:**
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_de.arb`

**Interfaces:**
- Produces: `AppLocalizations.catchUpBannerMessage(int count)`,
  `AppLocalizations.catchUpBannerDismissTooltip` (both generated by
  `flutter gen-l10n` from the ARB keys below).

- [ ] **Step 1: Add the English ARB entries**

In `lib/l10n/app_en.arb`, insert immediately after the
`digestPrepromptDismissAction` block (after line 344, before the blank
line and `choresSnackbarDone`):

```json

  "catchUpBannerMessage": "{count, plural, one{We rolled 1 overdue chore forward while you were away.} other{We rolled {count} overdue chores forward while you were away.}}",
  "@catchUpBannerMessage": {
    "description": "Catch-up visibility banner copy at the top of the chores list (backlog B-1 / triage T2.1), shown after ChoreService.catchUpOverdue has closed at least one stale overdue occurrence as missed and reinserted a fresh one at the most recent missed slot. Deliberately avoids the words 'missed' or 'failed' -- the point of this banner is to explain the mechanism plainly, not to restate the accusation the persona finding identified. {count} is the number of chores this happened to.",
    "placeholders": {
      "count": {
        "type": "int",
        "example": "3"
      }
    }
  },
  "catchUpBannerDismissTooltip": "Dismiss",
  "@catchUpBannerDismissTooltip": {
    "description": "Tooltip for the catch-up banner's X dismiss button."
  },
```

- [ ] **Step 2: Add the German ARB entries**

In `lib/l10n/app_de.arb`, insert immediately after the
`digestPrepromptDismissAction` line (after line 84, before the blank line
and `choresSnackbarDone`):

```json

  "catchUpBannerMessage": "{count, plural, one{Wir haben 1 überfällige Aufgabe vorgerückt, während du weg warst.} other{Wir haben {count} überfällige Aufgaben vorgerückt, während du weg warst.}}",
  "catchUpBannerDismissTooltip": "Schließen",
```

- [ ] **Step 3: Regenerate localizations**

Run: `flutter gen-l10n`
Expected: exits 0; `lib/l10n/app_localizations.dart`,
`lib/l10n/app_localizations_en.dart`, `lib/l10n/app_localizations_de.dart`
are updated with `catchUpBannerMessage`/`catchUpBannerDismissTooltip`.

- [ ] **Step 4: Commit**

```bash
git add lib/l10n/app_en.arb lib/l10n/app_de.arb lib/l10n/app_localizations.dart lib/l10n/app_localizations_en.dart lib/l10n/app_localizations_de.dart
git commit -m "Add l10n copy for the catch-up visibility banner"
```

---

### Task 5: `CatchUpBanner` widget

**Files:**
- Create: `lib/features/chores/catch_up_banner.dart`
- Test: `test/features/chores/catch_up_banner_test.dart` (new)

**Interfaces:**
- Consumes: `catchUpBannerCountProvider` (Task 2),
  `AppLocalizations.catchUpBannerMessage(int)` /
  `.catchUpBannerDismissTooltip` (Task 4), `DepthCard`
  (`lib/app/depth_card.dart`), `semantic()` (`lib/app/semantics.dart`).
- Produces: `class CatchUpBanner extends ConsumerWidget` — a
  no-constructor-args widget, semantic id `catchup.banner` (root) /
  `catchup.banner.dismiss` (the X button).

- [ ] **Step 1: Write the failing widget test**

Create `test/features/chores/catch_up_banner_test.dart`. This overrides
`catchUpBannerCountProvider` directly (the same sanctioned pattern
`test/features/chores/digest_preprompt_banner_test.dart` uses for
`notificationPermissionGrantedProvider`) since this test is about the
banner's own rendering logic, not the end-to-end catch-up plumbing already
covered by Tasks 1–2's tests:

```dart
import 'package:chore_app/app/providers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// Widget coverage for the catch-up visibility banner (backlog B-1 /
/// triage T2.1): visible/hidden per `catchUpBannerCountProvider`, correct
/// singular/plural copy, and dismiss resetting the provider.
void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'hidden when catchUpBannerCountProvider is 0 (the common case: '
    'nothing was caught up)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      expect(find.bySemanticsIdentifier('catchup.banner'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'shown with singular copy when exactly 1 chore was caught up',
    today: today,
    overrides: [catchUpBannerCountProvider.overrideWith((ref) => 1)],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('catchup.banner'), findsOneWidget);
      expect(
        find.text('We rolled 1 overdue chore forward while you were away.'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'shown with plural copy when several chores were caught up',
    today: today,
    overrides: [catchUpBannerCountProvider.overrideWith((ref) => 3)],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await tester.pumpAndSettle();

      expect(
        find.text('We rolled 3 overdue chores forward while you were away.'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'dismissing hides the banner and resets the count to 0',
    today: today,
    overrides: [catchUpBannerCountProvider.overrideWith((ref) => 2)],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await tester.pumpAndSettle();
      expect(find.bySemanticsIdentifier('catchup.banner'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('catchup.banner.dismiss'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('catchup.banner'), findsNothing);

      handle.dispose();
    },
  );
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/chores/catch_up_banner_test.dart`
Expected: FAIL — `catchup.banner` is never found (the widget doesn't exist
and isn't wired into the screen yet).

- [ ] **Step 3: Implement `CatchUpBanner`**

Create `lib/features/chores/catch_up_banner.dart`:

```dart
/// The catch-up visibility banner (backlog B-1 / triage T2.1): a
/// dismissible card at the top of the chores list explaining that
/// [ChoreService.catchUpOverdue] silently rolled some overdue chores
/// forward while the user was away, so their sudden reappearance as
/// freshly-overdue tiles doesn't read as an unexplained accusation (the
/// persona finding this ticket answers, `docs/research/persona-ben.md`
/// finding 1).
library;

import 'package:chore_app/app/depth_card.dart';
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shown only while [catchUpBannerCountProvider] is nonzero; dismissing it
/// resets that provider to 0.
///
/// Unlike [OnboardingNameBanner] and [DigestPrepromptBanner] (permanently
/// dismissed once, ever, via a `settings`-table flag), this banner's
/// "seen" state is deliberately NOT persisted anywhere: catch-up is a
/// recurring background event, not a one-time onboarding step, so a fresh
/// catch-up event with a new nonzero count must be able to show this again
/// even if an earlier one was already dismissed.
class CatchUpBanner extends ConsumerWidget {
  /// Creates the banner.
  const CatchUpBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(catchUpBannerCountProvider);
    if (count == 0) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final onSecondaryContainer = theme.colorScheme.onSecondaryContainer;

    return semantic(
      'catchup.banner',
      child: DepthCard(
        color: theme.colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.catchUpBannerMessage(count),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: onSecondaryContainer,
                  ),
                ),
              ),
              semantic(
                'catchup.banner.dismiss',
                child: IconButton(
                  icon: Icon(Icons.close, color: onSecondaryContainer),
                  tooltip: l10n.catchUpBannerDismissTooltip,
                  onPressed: () =>
                      ref.read(catchUpBannerCountProvider.notifier).state = 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Wire it into the chores list screen**

In `lib/features/chores/chores_list_screen.dart`, add the import near the
other banner imports (after the `active_chores_presence.dart` import,
before `chore_action_sheet.dart`, keeping the existing alphabetical
grouping):

```dart
import 'package:chore_app/features/chores/catch_up_banner.dart';
```

Then, in the `body: Column(children: [...])` (around line 113–116), place
`CatchUpBanner` first — ahead of the two existing banners, since a
returning-after-a-lapse user (this ticket's audience) should see the
what-just-happened explanation before the evergreen onboarding/digest
prompts:

```dart
      body: Column(
        children: [
          const CatchUpBanner(),
          const OnboardingNameBanner(),
          const DigestPrepromptBanner(),
```

Update the comment immediately above that `Column` (currently describing
"The first-run banners... render above the list content") to also mention
this one:

```dart
      // The catch-up and first-run banners (backlog B-1; spec
      // docs/specs/polish-round-1.md A2/A3) render above the list content,
      // never blocking it: all three are self-hiding (SizedBox.shrink)
      // when their own conditions don't hold, so this Column adds nothing
      // visible once a household is past all of them.
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/features/chores/catch_up_banner_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/features/chores/catch_up_banner.dart lib/features/chores/chores_list_screen.dart test/features/chores/catch_up_banner_test.dart
git commit -m "Add CatchUpBanner: explain catch-up on the chores list"
```

---

### Task 6: Full verification pass

**Files:** none (verification only)

- [ ] **Step 1: Format**

Run: `dart format --output=none --set-exit-if-changed .`
Expected: exits 0 (no files need formatting). If it fails, run
`dart format .` and re-check.

- [ ] **Step 2: Analyze**

Run: `flutter analyze --fatal-infos --fatal-warnings`
Expected: no issues.

- [ ] **Step 3: Full test suite**

Run: `flutter test`
Expected: all tests pass, including every file touched or added by this
plan: `test/application/chore_service_test.dart`,
`test/app/day_change_catchup_test.dart`,
`test/app/bootstrap_catchup_banner_test.dart`,
`test/features/chores/catch_up_banner_test.dart`, plus every
pre-existing test in `test/app/` and `test/features/chores/` that pumps
`ChoreApp` (they must still pass with `CatchUpBanner` now unconditionally
present but self-hiding at `count == 0`).

- [ ] **Step 4: Final commit (only if formatting or analyze produced changes)**

```bash
git add -A
git commit -m "Format and lint fixes for catch-up visibility"
```
