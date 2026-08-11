# Day Rollover (A-2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every date-derived piece of UI roll over at local midnight
while the app stays open, so an app left running overnight never shows
yesterday's "Done today" list or yesterday's Overdue/Today/Tomorrow
boundaries.

**Architecture:** Introduce one inert provider — `todayProvider`
(`NotifierProvider<TodayNotifier, PlainDate>`) — seeded from `clockProvider`
and republished by `TodayNotifier.refresh()`. `CatchUpController`, which
already owns a DST-safe midnight timer and an app-resume trigger, calls
`refresh()` on both triggers **unconditionally** (not gated on catch-up's
`changed` flag). Every UI-layer date derivation switches from
`ref.watch(clockProvider).now()` to `ref.watch(todayProvider)`. The provider
holds no timer of its own, so nothing changes for the ~40 widget tests that
render the chores list.

**Tech Stack:** Flutter 3.x / Dart SDK `^3.12.2`, `flutter_riverpod ^2.6.1`,
drift + SQLite, `package:clock ^1.1.2`, gen_l10n.

**Source ticket:** backlog `A-2` (`docs/backlog.md`), audit finding **P1**
(`docs/feedback/2026-08-08-prerelease-audit.md`).
**Specs touched:** `docs/specs/ui-foundation-chores.md`,
`docs/specs/ux-round-2.md` A3, `docs/specs/polish-round-1.md` C1 (all three
are binding; Task 6 amends them).

## Global Constraints

- **Do not edit `docs/backlog.md` or anything under `docs/feedback/`.** Other
  agents are working in those files concurrently in this same repo; editing
  them here produces merge conflicts. Spec files listed in Task 6 are yours.
- Every user-visible string goes through gen_l10n: `lib/l10n/app_en.arb`
  (template) AND `lib/l10n/app_de.arb` (German du-form). **This plan adds no
  new strings and no new widgets** — if you find yourself writing English
  into a widget, you have gone off-plan.
- Every interactive widget gets a stable id via the `semantic()` helper.
  This plan adds no interactive widgets.
- Strict lints: `very_good_analysis` with `--fatal-infos`. Every public
  member needs a doc comment (`TodayNotifier`, its `build`, its `refresh`).
- Widget tests are integration-style: real in-memory `AppDatabase` + a real
  `Clock`, overriding ONLY `appDatabaseProvider` and `clockProvider`
  (plus the documented plugin/gateway seams). **Never override
  `todayProvider` in a test** — it must always derive from the injected
  clock, which is what keeps `--dart-define=E2E_TODAY` working unchanged.
  Never mock a repository or service.
- Deadlocks to design around: never `await` a drift stream outside a widget
  pump; never bare-`await bootstrapProvider.future` in a `ProviderContainer`
  test (poll `.hasValue` with pump loops — `_awaitBootstrap` in
  `test/app/day_change_catchup_test.dart` already does this); put one
  `tester.pump(small duration)` between `container.dispose()` and
  `database.close()`.
- TDD, one commit per task: write the failing test → run it → implement →
  run → commit.
- Run Flutter/Dart commands as
  `env -u GIT_DIR -u GIT_INDEX_FILE flutter test <path>` (git hooks /
  worktrees otherwise poison the environment). Do NOT run more than 2
  concurrent `flutter test` processes.
- Never add `Co-Authored-By` trailers to commits.

---

## Analysis (why this design)

### The sweep: every `clockProvider` consumer, and its verdict

`grep -rn "clockProvider\|PlainDate.fromDateTime\|DateTime.now()" lib` gives
the complete set. Nine call sites read the clock; only five derive a
*calendar date that a user reads off the screen*.

| Site | What it derives | Verdict |
|---|---|---|
| `lib/app/providers.dart:548` `closedTodayOccurrencesProvider` | the date the "Done today" query filters on | **Migrate** (Task 2) — never rebuilds today; the headline bug |
| `lib/features/chores/chores_list_screen.dart:53` | `today` for the Overdue/Today/Tomorrow/This-week/This-month/Later buckets, the progress card, and every tile's due text (passed down as a parameter to `ChoreSection`/`ChoreOccurrenceTile`/`ChoreProgressCard`) | **Migrate** (Task 4) |
| `lib/features/chores/chores_list_screen.dart:313` | `today` for the undo-snackbar's "next due …" text | **Migrate** (Task 4) — a `ref.read` at tap time; migrated for a single definition of "today", not because it is stale |
| `lib/features/chores/chore_form_screen.dart:221` | `today` handed to `StartDateField` as the picker's range reference (min = today − 1 year) | **Migrate** (Task 5) |
| `lib/features/chores/chore_form_screen.dart:131` | the *default* start date for a new chore, in `initState` | **Migrate** (Task 5) as a `ref.read` — the value must still be captured once and never move under the user afterwards |
| `lib/features/settings/account_section.dart:134` | `now` for the relative "Last synced 5 minutes ago" text | **Out of scope** — a *duration*, not a date bucket; it needs a periodic ticker, a different mechanism. See Open product decision 2 |
| `lib/features/settings/export_row.dart:51` | export filename + `exported_at` at tap time | Leave — read at the moment of the action |
| `lib/features/chores/digest_preprompt_banner.dart:126` | `now` for `nextDigestSlot` at tap time | Leave — needs a time-of-day, not a date |
| `lib/app/providers.dart:517` (inside `bootstrapProvider`), `:733` (`DigestRescheduleController._recompute`), and all of `lib/application/*` (`ChoreService._today`, `data_export`, `household_archive`, …) | domain-layer "now" | Leave — invoked at action time, internally consistent, and `ChoreService` takes a `Clock` by constructor injection rather than reading a provider |

Nothing in `lib/features/shopping/` derives a date.
`active_chores_presence.dart` says "closed today" in prose only; its query is
database-driven.

### Approaches considered

**1. Invalidate the affected providers from the existing midnight timer.**
No new provider: the timer callback calls
`ref.invalidate(closedTodayOccurrencesProvider)`. Rejected — it fixes only
half the bug. `ChoresListScreen`'s `today` is a plain clock read inside
`build`; no invalidation can reach it, because the thing that would have to
be invalidated is `clockProvider` itself, which (a) is overridden with
`overrideWithValue` in every test, where invalidation is a no-op, and (b)
would be a semantic lie — the clock has not changed, the date has.

**2. An inert `todayProvider`, refreshed by `CatchUpController`. ← chosen.**
The audit's suggestion. A `NotifierProvider<TodayNotifier, PlainDate>` whose
`build()` reads `clockProvider` and whose `refresh()` re-reads it.
`CatchUpController` — which already owns the DST-safe `nextLocalMidnight`
timer and is already re-armed on resume, both unit-tested — calls `refresh()`
on both triggers, unconditionally. Trade-offs: the UI's rollover now depends
on `main.dart` having activated `catchUpControllerProvider` (it does, line
49, and Task 3 tests that wiring at the container level); and the provider's
correctness is split across two files. Accepted, because it is the only
option that arms zero timers inside the widget tree.

**3. A self-timing `todayProvider`** that arms its own midnight timer in
`build()` and re-arms after each fire, with `CatchUpController` inverted to
`ref.listen(todayProvider, …)`. Architecturally the cleanest dependency
direction — the day-change signal becomes a first-class provider and
catch-up becomes one of its consumers. **Rejected on a hard mechanical
constraint:** the widget tree watches this provider, so building
`ChoresListScreen` would arm a real `Timer`, and `flutter_test`'s "a Timer is
still pending" leak check runs *before* tear-downs and before the widget tree
is unmounted — `test/test_utils/pump_app.dart` never disposes its
`ProviderScope` inside the test body. Every chores widget test in the suite
would fail. This is the exact hazard both `CatchUpController` and
`DigestRescheduleController` document as the reason they are activated only
from `main.dart`. Option 2 keeps the timer where that discipline already
holds.

**Notifier vs. `StateProvider`.** `notificationPermissionGrantedProvider` is
precedent for a `StateProvider` poked by a controller, and it would work
here. A `Notifier` with a `refresh()` method is chosen instead because the
caller cannot pass a date *in*: the value structurally always comes from
`clockProvider`, which is precisely the property that keeps E2E's
`--dart-define=E2E_TODAY` and every fixed-clock widget test honest.

### Judgement calls made while planning

1. **`refresh()` guards on equality** (`if (today != state)`). `PlainDate`
   has value `==`/`hashCode` (`lib/domain/recurrence/plain_date.dart:159`),
   but Riverpod's default `updateShouldNotify` is identity-based for some
   provider shapes, and `triggerOnResume` fires on *every* foreground. An
   unguarded write would re-subscribe the "Done today" drift stream on every
   resume. The guard is tested (Task 1, step 1, third test).
2. **`CatchUpController` keeps its name.** It now owns two day-boundary
   effects, not one, so `DayChangeController` would read better — but the
   rename touches `main.dart`, `providers.dart`, `day_change_catchup_test.dart`
   and three spec files for zero behavior change. The class doc comment is
   extended instead (Task 3).
3. **`ref.watch(todayProvider)` is hoisted ABOVE the `await` in
   `closedTodayOccurrencesProvider`.** In an `async*` provider body a `watch`
   placed after an `await` registers its dependency late — and on the welcome
   gate `bootstrapProvider` parks on a `Completer().future` that never
   completes, so the line after the `await` would never execute and the
   dependency would never be registered at all. Hoisting costs nothing and
   removes the whole class of problem.
4. **A ≤1-second skew between `todayProvider` and `clock.now()` is
   accepted.** `nextLocalMidnight` deliberately fires at 00:00:01, so between
   00:00:00 and 00:00:01 the domain layer (`ChoreService._today`) is on day
   N+1 while the UI still says N. Worst case: a chore completed in that
   window is written with `closed_on = N+1` and is missing from a "Done
   today" list still showing day N — for under a second, and it self-heals
   when the timer fires. The alternative (dropping the 1-second buffer)
   would break `nextLocalMidnight`'s specced, unit-tested contract shared
   with catch-up. Not worth it. The rule that follows: **UI-layer date
   derivation uses `todayProvider`; domain-layer date derivation uses the
   injected `Clock`. Never mix them within one screen.**
5. **The controller→provider wiring and the provider→UI wiring are tested
   separately** (Tasks 3 and 4), not end-to-end through a widget tree with a
   live timer. An end-to-end widget test would have to arm the real midnight
   timer inside a pumped tree and then dispose the container before the body
   returns to dodge the pending-timer check — fragile, slow, and it would
   duplicate what Task 3 already proves deterministically. The seam between
   the two halves is a single provider.

## Open product decisions

### 1. Should the day rolling over while the user is watching say anything?

At midnight the "Done today" section vanishes and the chores re-bucket, with
no explanation, under the user's eyes.

- **(a) Silent rollover.** The list simply becomes correct for the new day.
- **(b) Freeze until next foreground.** Keep yesterday's view until the app
  is next resumed, then roll over.
- **(c) A marker** — a snackbar or a "It's a new day" divider.

**Recommendation: (a).** The section is collapsed by default and lives at the
very bottom of the list; the overwhelmingly common case is that nobody is
looking at the screen at 00:00. (b) reintroduces exactly the bug being fixed
for anyone who leaves the app foregrounded. (c) costs two new l10n strings
and a new interruption for a once-a-day non-event.

**This plan assumes (a).** No new strings, no new widgets.

### 2. Does A-2 also cover the Settings "Last synced N minutes ago" text?

`lib/features/settings/account_section.dart:134` watches `clockProvider` for
a *relative duration*. It is stale by the same root cause (the clock never
re-emits), but it is not a date bucket: fixing it needs a periodic ticker
(a `Stream.periodic`-backed provider), which is a different mechanism with
its own timer-in-the-widget-tree problem.

- **(a) Out of scope for A-2**, logged as its own backlog row.
- **(b) Fold it in**, adding a minute-granularity ticker in the same change.

**Recommendation: (a).** A-2 is sized S and is a release gate; a ticker
provider watched by the Settings screen would re-open the widget-test timer
hazard that this plan's whole design avoids, and "5 minutes ago" being stale
is a cosmetic annoyance, not the "yesterday's chores presented as today's"
trust failure A-2 is about.

**This plan assumes (a) and does not touch `account_section.dart`.** Since
this plan may not edit `docs/backlog.md` (Global Constraints), the follow-up
row must be filed by whoever integrates this branch.

---

## File structure

**Created**

| File | Responsibility |
|---|---|
| `test/app/today_provider_test.dart` | Pure provider tests for `todayProvider`/`TodayNotifier`: seeding, refresh, no-op refresh. No database. |
| `test/features/chores/day_rollover_widget_test.dart` | The UI half: a pumped `ChoreApp` on a movable clock, crossing midnight with nothing overdue. |

**Modified**

| File | Change |
|---|---|
| `lib/app/providers.dart` | Add `todayProvider` + `TodayNotifier` (Task 1); `closedTodayOccurrencesProvider` watches it (Task 2); `CatchUpController` refreshes it on both triggers (Task 3); library doc comment (Task 1). |
| `lib/features/chores/chores_list_screen.dart` | Lines 53 and 313 read `todayProvider` (Task 4). |
| `lib/features/chores/chore_form_screen.dart` | Lines 131 and 221 read `todayProvider` (Task 5). |
| `lib/features/chores/chore_form/start_date_field.dart` | `today` field's doc comment now names `todayProvider` (Task 5). |
| `test/test_utils/pump_app.dart` | Optional `Clock? clock` parameter so one test can move "now" (Task 4). |
| `test/app/day_change_catchup_test.dart` | New groups for the provider rollover and the two controller triggers (Tasks 2 and 3). |
| `docs/specs/ui-foundation-chores.md`, `docs/specs/ux-round-2.md`, `docs/specs/polish-round-1.md` | Spec amendments (Task 6). |

---

### Task 1: `todayProvider` and `TodayNotifier`

**Files:**
- Modify: `lib/app/providers.dart` (add after `resolveClock`, ~line 89; and
  extend the library doc comment at lines 3–6)
- Test: `test/app/today_provider_test.dart` (create)

**Interfaces:**
- Consumes: `clockProvider` (`Provider<Clock>`), `PlainDate`
  (`package:chore_app/domain/recurrence/plain_date.dart`).
- Produces:
  - `final todayProvider = NotifierProvider<TodayNotifier, PlainDate>(TodayNotifier.new);`
  - `class TodayNotifier extends Notifier<PlainDate>` with
    `PlainDate build()` and `void refresh()`.
  - Read the value with `ref.watch(todayProvider)` → `PlainDate`; refresh it
    with `ref.read(todayProvider.notifier).refresh()`.

- [ ] **Step 1: Write the failing test**

Create `test/app/today_provider_test.dart`:

```dart
/// [todayProvider] tests (backlog A-2 / audit P1): the single source of
/// truth for the UI's "today", seeded from [clockProvider] and republished
/// by [TodayNotifier.refresh].
///
/// No database and no widget tree needed — this provider depends on nothing
/// but the clock, so a bare [ProviderContainer] with a mutable clock is the
/// whole fixture.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('todayProvider', () {
    test('seeds from clockProvider', () {
      final container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(
            Clock.fixed(DateTime(2026, 1, 5, 9)),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(todayProvider), PlainDate(2026, 1, 5));
    });

    test('refresh() republishes the clock\'s new calendar day', () {
      var currentTime = DateTime(2026, 1, 5, 23, 59, 50);
      final container = ProviderContainer(
        overrides: [clockProvider.overrideWithValue(Clock(() => currentTime))],
      );
      addTearDown(container.dispose);
      expect(container.read(todayProvider), PlainDate(2026, 1, 5));

      currentTime = DateTime(2026, 1, 6, 0, 0, 1);
      container.read(todayProvider.notifier).refresh();

      expect(container.read(todayProvider), PlainDate(2026, 1, 6));
    });

    test(
      'refresh() notifies nobody when the calendar day has not changed — so '
      'calling it on every app resume never re-subscribes the streams that '
      'watch it',
      () {
        var currentTime = DateTime(2026, 1, 5, 9);
        final container = ProviderContainer(
          overrides: [
            clockProvider.overrideWithValue(Clock(() => currentTime)),
          ],
        );
        addTearDown(container.dispose);
        var notifications = 0;
        container.listen<PlainDate>(
          todayProvider,
          (previous, next) => notifications++,
          fireImmediately: false,
        );

        // Same day, later hour: three resumes, no notification.
        currentTime = DateTime(2026, 1, 5, 14);
        container.read(todayProvider.notifier).refresh();
        currentTime = DateTime(2026, 1, 5, 22);
        container.read(todayProvider.notifier).refresh();
        container.read(todayProvider.notifier).refresh();
        expect(notifications, 0);

        // Crossing into the next day notifies exactly once.
        currentTime = DateTime(2026, 1, 6, 0, 0, 1);
        container.read(todayProvider.notifier).refresh();
        expect(notifications, 1);
      },
    );
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/app/today_provider_test.dart`
Expected: compile failure — `Undefined name 'todayProvider'`.

- [ ] **Step 3: Write the implementation**

In `lib/app/providers.dart`, immediately after the closing brace of
`Clock resolveClock(String e2eToday) { … }` (around line 89) and before
`final choreRepositoryProvider = …`, insert:

```dart
/// Today's local calendar date — the single source of truth for every
/// date-bucketed piece of UI: the chores list's Overdue / Today / Tomorrow /
/// This week / This month / Later boundaries, the collapsed 'Done today'
/// section, the day-progress card, and the chore form's start-date picker
/// range.
///
/// Seeded from [clockProvider], so a fixed widget-test clock and the
/// `--dart-define=E2E_TODAY` hook still decide what "today" means, and
/// republished by [TodayNotifier.refresh] — which [CatchUpController] calls
/// UNCONDITIONALLY on both of its day-boundary triggers (the
/// [nextLocalMidnight] timer firing, and the app resuming). Without this,
/// nothing in the widget tree ever re-reads the date: [clockProvider] is a
/// plain [Provider] that never re-emits, so an app left open overnight kept
/// showing yesterday's completions under 'Done today' indefinitely
/// (backlog A-2 / audit P1).
///
/// Deliberately holds NO timer of its own. The widget tree watches this
/// provider directly, and `flutter_test`'s "a Timer is still pending" leak
/// check runs before the pumped tree is torn down — a provider-armed timer
/// would therefore fail every widget test that renders the chores list.
/// That is the same hazard [CatchUpController] and
/// [DigestRescheduleController] document as the reason they are only ever
/// activated from `main.dart`; the day-change timer stays there, where that
/// discipline already holds.
///
/// NEVER override this in a test. It derives from [clockProvider] by
/// construction — overriding it directly would let a test's UI disagree
/// with the same test's domain layer.
final todayProvider = NotifierProvider<TodayNotifier, PlainDate>(
  TodayNotifier.new,
);

/// The notifier behind [todayProvider].
class TodayNotifier extends Notifier<PlainDate> {
  /// Reads the current local calendar date from [clockProvider].
  @override
  PlainDate build() => PlainDate.fromDateTime(ref.watch(clockProvider).now());

  /// Re-reads [clockProvider] and republishes the current local date.
  ///
  /// A no-op when the calendar day hasn't actually changed: this is called
  /// on every app resume, and an unguarded write would re-subscribe every
  /// drift stream watching [todayProvider] (notably
  /// [closedTodayOccurrencesProvider]) each time the user so much as
  /// glances at another app.
  void refresh() {
    final today = PlainDate.fromDateTime(ref.read(clockProvider).now());
    if (today != state) {
      state = today;
    }
  }
}
```

Then extend the library doc comment at the top of the same file. Change:

```dart
/// `appDatabaseProvider` and `clockProvider` are the only two providers a
/// *widget* test or E2E run ever needs to override; every screen-facing
/// provider is built on top of them, so overriding just those two is enough
/// to make the whole app deterministic and hermetic (in-memory database,
/// fixed clock).
```

to:

```dart
/// `appDatabaseProvider` and `clockProvider` are the only two providers a
/// *widget* test or E2E run ever needs to override; every screen-facing
/// provider is built on top of them, so overriding just those two is enough
/// to make the whole app deterministic and hermetic (in-memory database,
/// fixed clock). [todayProvider] in particular is DERIVED from
/// `clockProvider` and must never be overridden directly — see its own doc
/// comment.
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/app/today_provider_test.dart`
Expected: PASS, 3 tests.

Then `env -u GIT_DIR -u GIT_INDEX_FILE flutter analyze lib/app/providers.dart test/app/today_provider_test.dart`
Expected: "No issues found!" (`--fatal-infos` means a missing doc comment is
a failure).

- [ ] **Step 5: Commit**

```bash
git add lib/app/providers.dart test/app/today_provider_test.dart
git commit -m "Add todayProvider: a clock-derived, refreshable 'today'"
```

---

### Task 2: `closedTodayOccurrencesProvider` rebuilds on rollover

**Files:**
- Modify: `lib/app/providers.dart:545-552`
- Test: `test/app/day_change_catchup_test.dart` (new group, appended before
  the closing `}` of `main()`); also update its library doc comment.

**Interfaces:**
- Consumes: `todayProvider` (Task 1).
- Produces: nothing new — `closedTodayOccurrencesProvider` keeps its type
  `StreamProvider<List<ClosedOccurrenceWithChore>>`.

- [ ] **Step 1: Write the failing test**

In `test/app/day_change_catchup_test.dart`, append this group at the end of
`main()` (it reuses the file's existing `_awaitBootstrap`, `_pumpUntil` and
`_disposeAndClose` helpers, so nothing new is needed at the top):

```dart
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/app/day_change_catchup_test.dart --plain-name "empties when the calendar day rolls over"`
Expected: FAIL — `StateError: condition never became true` from the second
`_pumpUntil`. The provider captured 2026-01-05 at build time and never
rebuilds, so the completion stays in the list forever. (This is the bug.)

- [ ] **Step 3: Write the implementation**

In `lib/app/providers.dart`, replace:

```dart
final closedTodayOccurrencesProvider =
    StreamProvider<List<ClosedOccurrenceWithChore>>((ref) async* {
      final householdId = await ref.watch(bootstrapProvider.future);
      final today = PlainDate.fromDateTime(ref.watch(clockProvider).now());
      yield* ref
          .watch(choreRepositoryProvider)
          .watchClosedOnDate(householdId, today);
    });
```

with:

```dart
final closedTodayOccurrencesProvider =
    StreamProvider<List<ClosedOccurrenceWithChore>>((ref) async* {
      // Watched BEFORE the await, deliberately: a `ref.watch` placed after
      // an await registers its dependency late, and on the welcome gate
      // `bootstrapProvider` parks on a future that never completes (see its
      // doc comment) — the line after the await would then never run and
      // this provider would never learn about a day change at all.
      final today = ref.watch(todayProvider);
      final householdId = await ref.watch(bootstrapProvider.future);
      yield* ref
          .watch(choreRepositoryProvider)
          .watchClosedOnDate(householdId, today);
    });
```

Also extend this provider's doc comment (directly above it) with:

```dart
/// Rebuilds at local midnight: the date comes from [todayProvider], not
/// from a one-shot [clockProvider] read (backlog A-2 / audit P1).
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/app/day_change_catchup_test.dart`
Expected: PASS, all groups in the file (the three pre-existing
`nextLocalMidnight` unit tests, the two resume tests, the timer test, and
the new one).

- [ ] **Step 5: Update the test file's library doc comment**

At the top of `test/app/day_change_catchup_test.dart`, change the first
paragraph from "…[CatchUpController] tests (spec `docs/specs/polish-round-1.md`
C1): re-running `ChoreService.catchUpOverdue` on app resume and on local
day-change, followed by a digest recompute when catch-up actually changed
something." to add a second sentence:

```dart
/// Also covers what the same two triggers do for the UI's notion of the
/// date — [todayProvider] and the [closedTodayOccurrencesProvider] rebuild
/// that hangs off it (backlog A-2 / audit P1).
```

- [ ] **Step 6: Commit**

```bash
git add lib/app/providers.dart test/app/day_change_catchup_test.dart
git commit -m "Rebuild closedTodayOccurrencesProvider when the day rolls over"
```

---

### Task 3: `CatchUpController` refreshes `todayProvider` unconditionally

**Files:**
- Modify: `lib/app/providers.dart` — `CatchUpController.triggerOnResume`
  (~line 848) and `_armDayChangeTimer` (~line 855), plus the class doc
  comment (~line 800).
- Test: `test/app/day_change_catchup_test.dart` (two new tests).

**Interfaces:**
- Consumes: `todayProvider` / `TodayNotifier.refresh()` (Task 1).
- Produces: no new public API. `CatchUpController` gains a private
  `void _refreshToday()`.

- [ ] **Step 1: Write the failing tests**

In `test/app/day_change_catchup_test.dart`, add this test inside the
existing `group('CatchUpController.triggerOnResume', …)`, after the
"is a no-op … when nothing is overdue" test:

```dart
    testWidgets(
      'moves todayProvider even when catch-up changes nothing — the common '
      'night, where no chore fell overdue',
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
        final catchUpController = container.read(catchUpControllerProvider);
        await _awaitBootstrap(tester, container);
        expect(container.read(todayProvider), PlainDate(2026, 1, 5));

        // Backgrounded overnight; no chores exist at all, so catch-up has
        // nothing to change and reports `changed == false`.
        currentTime = DateTime(2026, 1, 6, 9);
        catchUpController.triggerOnResume();

        expect(container.read(todayProvider), PlainDate(2026, 1, 6));

        // See [_disposeAndClose]'s doc comment for why a pump must separate
        // `dispose()` from `close()`.
        await _disposeAndClose(tester, container, database);
      },
    );
```

And add this test inside the existing
`group('CatchUpController day-change timer', …)`:

```dart
    testWidgets(
      'moves todayProvider when it fires, with nothing overdue and no other '
      'trigger — the regression backlog A-2 describes',
      (tester) async {
        var currentTime = DateTime(2026, 1, 5, 23, 59, 50);
        final database = AppDatabase(NativeDatabase.memory());
        // Seed the household BEFORE the container exists — see the
        // identical comment on the first test in this file.
        await HouseholdRepository(database).createLocalHousehold('Me');
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            clockProvider.overrideWithValue(Clock(() => currentTime)),
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

        // See [_disposeAndClose]'s doc comment for why a pump must separate
        // `dispose()` from `close()`.
        await _disposeAndClose(tester, container, database);
      },
    );
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/app/day_change_catchup_test.dart --plain-name "moves todayProvider"`
Expected: both FAIL with
`Expected: PlainDate:<2026-01-06> / Actual: PlainDate:<2026-01-05>` —
nothing currently tells the provider the day moved.

- [ ] **Step 3: Write the implementation**

In `lib/app/providers.dart`, in `CatchUpController`, replace:

```dart
  void triggerOnResume() {
    unawaited(_runCatchUp());
    _armDayChangeTimer();
  }
```

with:

```dart
  void triggerOnResume() {
    _refreshToday();
    unawaited(_runCatchUp());
    _armDayChangeTimer();
  }
```

and replace:

```dart
  void _armDayChangeTimer() {
    _dayChangeTimer?.cancel();
    final now = _ref.read(clockProvider).now();
    _dayChangeTimer = Timer(nextLocalMidnight(now).difference(now), () {
      unawaited(_runCatchUp());
      _armDayChangeTimer();
    });
  }
```

with:

```dart
  void _armDayChangeTimer() {
    _dayChangeTimer?.cancel();
    final now = _ref.read(clockProvider).now();
    _dayChangeTimer = Timer(nextLocalMidnight(now).difference(now), () {
      _refreshToday();
      unawaited(_runCatchUp());
      _armDayChangeTimer();
    });
  }

  /// Republishes [todayProvider] from the clock.
  ///
  /// UNCONDITIONAL on both day-boundary triggers, unlike the digest
  /// recompute below: the digest only has news when catch-up actually
  /// changed rows, but the DATE changes every single night whether or not
  /// anything fell overdue — and the common night is precisely the one
  /// where nothing does (backlog A-2 / audit P1). [TodayNotifier.refresh]
  /// is itself a no-op when the calendar day hasn't moved, so calling it on
  /// every resume is free.
  void _refreshToday() => _ref.read(todayProvider.notifier).refresh();
```

Then extend the `CatchUpController` class doc comment. After the paragraph
ending "…the common case (nothing overdue) has nothing new for the digest to
reflect.", append:

```dart
/// On the same two triggers this controller ALSO refreshes [todayProvider]
/// — unconditionally, whether or not catch-up changed anything — which is
/// what makes every date-bucketed screen roll over at local midnight
/// (backlog A-2 / audit P1). The timer lives here rather than in
/// [todayProvider] itself because this class is activated only from
/// `main.dart`, never from the widget tree: see [todayProvider]'s doc
/// comment for why a provider-armed timer would break every chores widget
/// test.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/app/day_change_catchup_test.dart`
Expected: PASS, every test in the file.

Then `env -u GIT_DIR -u GIT_INDEX_FILE flutter analyze lib/app/providers.dart`
Expected: "No issues found!"

- [ ] **Step 5: Commit**

```bash
git add lib/app/providers.dart test/app/day_change_catchup_test.dart
git commit -m "Refresh todayProvider on midnight and on resume, unconditionally"
```

---

### Task 4: The chores list re-buckets at midnight

**Files:**
- Modify: `lib/features/chores/chores_list_screen.dart:53` and `:313`
- Modify: `test/test_utils/pump_app.dart` (optional `Clock? clock`)
- Test: `test/features/chores/day_rollover_widget_test.dart` (create)

**Interfaces:**
- Consumes: `todayProvider` (Task 1), `closedTodayOccurrencesProvider`'s new
  rollover behavior (Task 2).
- Produces: `testChoreApp(…, {required DateTime today, List<Override>
  overrides = const [], Clock? clock})` — when `clock` is non-null it
  replaces the default `Clock.fixed(today)` override.

- [ ] **Step 1: Add the `clock` parameter to the shared harness**

In `test/test_utils/pump_app.dart`:

1. In `testChoreApp`, add `Clock? clock,` to the named parameters and pass
   `clock: clock` through to `_pumpChoreApp`.
2. In `_pumpChoreApp`, add `Clock? clock,` to the named parameters and change
   the override line from
   `clockProvider.overrideWithValue(Clock.fixed(today)),` to
   `clockProvider.overrideWithValue(clock ?? Clock.fixed(today)),`.
3. `testFreshChoreApp` passes `clock: null` — leave its signature alone.
4. Add `import 'package:clock/clock.dart';` — already present (line 14).
5. Document the new parameter on `testChoreApp`:

```dart
/// [clock] replaces the default `Clock.fixed(today)` for the rare test that
/// needs "now" to actually MOVE — day rollover
/// (`test/features/chores/day_rollover_widget_test.dart`). [today] is still
/// required: it is the date the test starts on. Pass a `Clock(() => myVar)`
/// over a mutable variable and assign that variable to move time.
```

- [ ] **Step 2: Write the failing test**

Create `test/features/chores/day_rollover_widget_test.dart`:

```dart
/// The UI half of backlog A-2 / audit P1: with NOTHING overdue and no other
/// trigger, crossing local midnight must re-bucket the list and empty the
/// 'Done today' section.
///
/// The controller half (what actually calls [TodayNotifier.refresh] at
/// midnight and on resume) is covered in `test/app/day_change_catchup_test.dart`;
/// this test calls `refresh()` directly rather than arming the real
/// day-change timer inside a pumped widget tree, which would leave a pending
/// Timer for `flutter_test`'s leak check.
library;

import 'package:chore_app/app/app.dart';
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

void main() {
  // Moved by the test body to cross local midnight. 2026-01-05 is a Monday,
  // so 'Tomorrow' (the 6th) is unambiguously not also 'This week'.
  var currentTime = DateTime(2026, 1, 5, 9);

  testChoreApp(
    'at local midnight the list re-buckets and "Done today" empties, with '
    'nothing overdue',
    today: DateTime(2026, 1, 5, 9),
    clock: Clock(() => currentTime),
    (tester, database) async {
      final householdId = await currentHouseholdId(database);
      final me = await database.select(database.members).getSingle();
      final service = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock(() => currentTime),
      );

      // Due tomorrow: sits under TOMORROW today, under TODAY after midnight.
      // Nothing is ever overdue in this test, so catch-up would change
      // nothing and the date is the ONLY signal.
      await service.createChore(
        householdId: householdId,
        title: 'Vacuum',
        startDate: PlainDate(2026, 1, 6),
        assignmentMode: AssignmentMode.anyone,
      );
      // Completed today: sits under 'Done today (1)' until midnight.
      final dishes = await service.createChore(
        householdId: householdId,
        title: 'Dishes',
        startDate: PlainDate(2026, 1, 5),
        assignmentMode: AssignmentMode.anyone,
      );
      final pending = await ChoreRepository(
        database,
      ).pendingOccurrenceOf(dishes.id);
      await service.completeOccurrence(pending!.id, completedBy: me.id);
      await tester.pumpAndSettle();

      // Section headers render uppercase (theme-v2.md §2/§4.1 item 2) via
      // the widget's own .toUpperCase(); chore titles are untouched. Same
      // idiom as list_grouping_test.dart.
      expect(find.text('Done today (1)'), findsOneWidget);
      expect(find.text('TOMORROW'), findsOneWidget);
      expect(find.text('TODAY'), findsNothing);

      // Midnight. Not one row in the database changes.
      currentTime = DateTime(2026, 1, 6, 0, 0, 1);
      ProviderScope.containerOf(
        tester.element(find.byType(ChoreApp)),
        listen: false,
      ).read(todayProvider.notifier).refresh();
      await tester.pumpAndSettle();

      expect(find.text('Done today (1)'), findsNothing);
      expect(find.text('TOMORROW'), findsNothing);
      expect(find.text('TODAY'), findsOneWidget);

      const expectedOrder = ['TODAY', 'Vacuum'];
      final renderedTexts = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(ListView),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data)
          .where(expectedOrder.contains)
          .toList();
      expect(renderedTexts, expectedOrder);
    },
  );
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/features/chores/day_rollover_widget_test.dart`
Expected: FAIL at `expect(find.text('TOMORROW'), findsNothing)` — the screen's
`today` is still a one-shot `clockProvider` read, so the buckets never move.
(If instead it fails earlier at `find.text('Done today (1)'), findsNothing`,
Task 2 was not applied.)

- [ ] **Step 4: Write the implementation**

In `lib/features/chores/chores_list_screen.dart`, line 53, replace:

```dart
    final today = PlainDate.fromDateTime(ref.watch(clockProvider).now());
```

with:

```dart
    // todayProvider, not a one-shot clock read: this is what re-buckets the
    // list at local midnight while the app stays open (backlog A-2 / audit
    // P1). It flows down to ChoreSection, every tile's due text, and the
    // progress card as a plain parameter, so this single watch covers them.
    final today = ref.watch(todayProvider);
```

And in `_showCloseSnackbar`, line 313, replace:

```dart
      final today = PlainDate.fromDateTime(ref.read(clockProvider).now());
```

with:

```dart
      // The same "today" the list itself is bucketing on, so the snackbar's
      // "next due …" text can never contradict the section the chore lands
      // in a frame later.
      final today = ref.read(todayProvider);
```

No import changes: `todayProvider` lives in the same
`package:chore_app/app/providers.dart` this file already imports, and
`PlainDate` is still used as a type at line 447 (`final PlainDate today;`),
so `plain_date.dart` stays too.

- [ ] **Step 5: Run the test to verify it passes**

Run: `env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/features/chores/day_rollover_widget_test.dart`
Expected: PASS.

Then run the whole chores suite to prove the harness change broke nothing:
`env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/features/chores/`
Expected: PASS, no "A Timer is still pending" failures.

- [ ] **Step 6: Commit**

```bash
git add lib/features/chores/chores_list_screen.dart test/test_utils/pump_app.dart test/features/chores/day_rollover_widget_test.dart
git commit -m "Re-bucket the chores list at local midnight"
```

---

### Task 5: The chore form's date reference comes from `todayProvider`

**Files:**
- Modify: `lib/features/chores/chore_form_screen.dart:131` and `:221`
- Modify: `lib/features/chores/chore_form/start_date_field.dart:33-34`
  (doc comment only)
- Test: `test/features/chores/day_rollover_widget_test.dart` (second test)

**Interfaces:**
- Consumes: `todayProvider` (Task 1), `testChoreApp`'s `clock:` parameter
  (Task 4).
- Produces: nothing new.

**Honest framing — read this before starting.** Unlike Tasks 2–4 this is
**not** a red-green cycle, and you should not manufacture one. The chore
form's `today` feeds exactly one thing: `StartDateField._pick`'s
`firstDate: today.addDays(-365)` / `lastDate: today.addDays(3650)` — bounds
the user cannot see without opening the Material date picker and probing for
a disabled cell. Migrating it changes no rendered pixel; it exists so there
is ONE definition of "today" in the UI layer (judgement call 4 above), which
is what stops a future edit from reintroducing the bug here. The test below
is therefore a characterization test: it locks the invariant that the
*value* the user picked never moves when the day does. Write it first
anyway, and expect it to pass before and after.

- [ ] **Step 1: Write the characterization test**

Append to `test/features/chores/day_rollover_widget_test.dart`, inside
`main()`:

```dart
  // A second mutable clock, independent of the one above: each testChoreApp
  // body runs once, but these variables live at file scope, so the two
  // tests must not share one.
  var formTime = DateTime(2026, 1, 5, 9);

  testChoreApp(
    'a start date the user already picked never moves under them when the '
    'day rolls over with the chore form open',
    today: DateTime(2026, 1, 5, 9),
    clock: Clock(() => formTime),
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();

      // The new-chore form defaults its start date to today, rendered by
      // StartDateField as DateFormat.yMMMd('en').
      expect(find.text('Jan 5, 2026'), findsOneWidget);

      // Midnight passes with the form still open.
      formTime = DateTime(2026, 1, 6, 0, 0, 1);
      ProviderScope.containerOf(
        tester.element(find.byType(ChoreApp)),
        listen: false,
      ).read(todayProvider.notifier).refresh();
      await tester.pumpAndSettle();

      // The picker's RANGE reference moved (today - 1 year is now
      // 2025-01-06); the user's chosen VALUE did not. `_startDate` is read
      // once in initState precisely so this stays true.
      expect(find.text('Jan 5, 2026'), findsOneWidget);
      expect(find.text('Jan 6, 2026'), findsNothing);
      expect(
        find.bySemanticsIdentifier('chore_form.start_date'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );
```

- [ ] **Step 2: Run it and confirm it passes BEFORE the change**

Run: `env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/features/chores/day_rollover_widget_test.dart --plain-name "never moves under them"`
Expected: PASS. That is the point — it establishes the current behavior so
Step 3 can be shown not to alter it. If it FAILS, the literals are wrong for
this locale/format; fix the literals to match what the widget renders, never
the other way round.

- [ ] **Step 3: Write the implementation**

In `lib/features/chores/chore_form_screen.dart`, in `initState` (line 131),
replace:

```dart
    _startDate = PlainDate.fromDateTime(ref.read(clockProvider).now());
```

with:

```dart
    // read, not watch: the default start date is captured ONCE, when the
    // form opens. A day rollover moves the picker's range reference (see
    // `today` in build) but must never move a date the user is looking at.
    _startDate = ref.read(todayProvider);
```

And in `build` (line 221), replace:

```dart
    final today = PlainDate.fromDateTime(ref.watch(clockProvider).now());
```

with:

```dart
    // One definition of "today" across the whole UI (backlog A-2 / audit
    // P1): this is the StartDateField picker's range reference, min =
    // today - 1 year.
    final today = ref.watch(todayProvider);
```

Then in `lib/features/chores/chore_form/start_date_field.dart`, update the
`today` field's doc comment from:

```dart
  /// Today, per `clockProvider` — the reference point for the picker's
  /// selectable range.
```

to:

```dart
  /// Today, per `todayProvider` — the reference point for the picker's
  /// selectable range. Derived from `clockProvider` and refreshed at local
  /// midnight, so a form left open overnight gets an honest range.
```

No import changes here either: `PlainDate` is still the declared type of
`_startDate` (line 58) and `_initialStartDate` (line 81), and `todayProvider`
ships from the already-imported `app/providers.dart`.

- [ ] **Step 4: Run the tests and confirm the behavior is unchanged**

Run: `env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/features/chores/`
Expected: PASS — the characterization test still passes (that is the
success criterion for a refactor), and so does every `chore_form*` test,
which all pump the form under `Clock.fixed` and must be unaffected.

Then `env -u GIT_DIR -u GIT_INDEX_FILE flutter analyze lib test`
Expected: "No issues found!"

- [ ] **Step 5: Commit**

```bash
git add lib/features/chores/chore_form_screen.dart lib/features/chores/chore_form/start_date_field.dart test/features/chores/day_rollover_widget_test.dart
git commit -m "Point the chore form's date reference at todayProvider"
```

---

### Task 6: Spec amendments and full-suite verification

Specs in `docs/specs/` are binding contracts; three of them now describe the
code inaccurately. No tests here — this task is documentation plus the
whole-suite run.

**Files:**
- Modify: `docs/specs/ui-foundation-chores.md` (the Providers list, ~line 22;
  the section-boundary bullet, ~line 77)
- Modify: `docs/specs/ux-round-2.md` (A3, ~line 39)
- Modify: `docs/specs/polish-round-1.md` (C1, ~line 96)
- **Do not touch** `docs/backlog.md` or `docs/feedback/` — see Global
  Constraints.

- [ ] **Step 1: `docs/specs/ui-foundation-chores.md`**

In the `### Providers (flutter_riverpod)` list, immediately after the
`clockProvider` bullet, insert:

```markdown
- `todayProvider` (`NotifierProvider<TodayNotifier, PlainDate>`) — today's
  local calendar date, seeded from `clockProvider` and republished by
  `TodayNotifier.refresh()`, which `CatchUpController` calls unconditionally
  at local midnight and on app resume. EVERY date-bucketed piece of UI reads
  this, never `clockProvider` directly; the domain layer keeps using the
  injected `Clock`. Never overridden in tests — it derives from
  `clockProvider` by construction, which is what keeps `--dart-define=E2E_TODAY`
  authoritative. Added 2026-08-08 (backlog A-2 / audit P1): `clockProvider`
  is a plain `Provider` that never re-emits, so before this an app left open
  overnight kept yesterday's section boundaries and yesterday's 'Done today'
  list indefinitely.
```

In the list-screen section bullet ("Sections in order … **Overdue** (due <
today) …"), append a sentence:

```markdown
  "today" is `todayProvider`, so the boundaries move at local midnight even
  if the app is never touched.
```

- [ ] **Step 2: `docs/specs/ux-round-2.md` A3**

After the bullet "Needs `ChoreRepository.watchClosedOnDate(householdId,
PlainDate)`.", add:

```markdown
- Amended 2026-08-08 (backlog A-2 / audit P1): the `today` passed to
  `watchClosedOnDate` comes from `todayProvider`, and
  `closedTodayOccurrencesProvider` watches it — so at local midnight the
  section empties on its own. Silently: no snackbar, no marker (product
  decision, `docs/plans/2026-08-08-day-rollover.md`).
```

- [ ] **Step 3: `docs/specs/polish-round-1.md` C1**

After the bullet ending "Also trigger a digest recompute after any catch-up
that changed rows.", add:

```markdown
- Amended 2026-08-08 (backlog A-2 / audit P1): on BOTH triggers the
  controller also refreshes `todayProvider` — unconditionally, unlike the
  digest recompute. The digest only has news when catch-up changed rows, but
  the calendar date changes every night whether or not anything fell
  overdue, and that common night is exactly the case the UI was getting
  wrong. The day-change timer stays in this controller (rather than moving
  into `todayProvider`) because this controller is activated only from
  `main.dart`: a timer armed by a provider the widget tree watches would trip
  `flutter_test`'s pending-timer check in every chores widget test.
```

- [ ] **Step 4: Run the full suite**

Run: `env -u GIT_DIR -u GIT_INDEX_FILE flutter test`
Expected: PASS, no "A Timer is still pending" failures anywhere.

Run: `env -u GIT_DIR -u GIT_INDEX_FILE flutter analyze`
Expected: "No issues found!"

- [ ] **Step 5: Verify the E2E clock hook is untouched**

Run: `grep -rn "E2E_TODAY" lib/ .github/ .maestro/ 2>/dev/null`
Expected: the only production reference is
`lib/app/providers.dart` `_e2eToday` → `resolveClock` → `clockProvider`, and
`todayProvider` derives from `clockProvider`. No E2E flow needs a change: a
fixed E2E clock means `refresh()` is a no-op there, exactly as before.

Run: `grep -rn "clockProvider" lib/features/`
Expected: only `settings/account_section.dart`,
`settings/export_row.dart` and `chores/digest_preprompt_banner.dart` remain —
the three that need a *time*, not a date (see the sweep table above). Any
other hit is a missed migration.

- [ ] **Step 6: Commit**

```bash
git add docs/specs/ui-foundation-chores.md docs/specs/ux-round-2.md docs/specs/polish-round-1.md
git commit -m "Spec the midnight rollover contract for todayProvider"
```

---

## Done when

- An app left open overnight shows an empty 'Done today', correct
  Overdue/Today/Tomorrow boundaries, and a correct progress ring the moment
  the local date changes — with nothing overdue and no user interaction.
- `flutter test` and `flutter analyze` are both clean.
- No new l10n key, no new semantic id, no new provider override in any test.
- Three specs describe what the code does.
