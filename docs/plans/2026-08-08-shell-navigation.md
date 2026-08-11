# Shell navigation (D-1 swipe between tabs · D-4 re-tap to top · D-6 back to first tab) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the tab shell answer the three gestures every mobile user
already has in their hands — swipe left/right between tabs, re-tap the
active tab to jump its list back to the top, and Android back returning to
the first tab instead of leaving the app.

**Architecture:** `lib/app/app_shell.dart`'s `IndexedStack` becomes a
`PageView` whose three children are wrapped in a shell-private
`_KeepAlivePage` (`AutomaticKeepAliveClientMixin`), so every tab's scroll
position and in-flight state survive leaving it — the exact property the
`IndexedStack` existed for. `_KeepAlivePage` also publishes one shell-owned
`ScrollController` per tab via `PrimaryScrollController`, which the three tab
screens' existing uncontrolled vertical `ListView`/`CustomScrollView`s pick
up for free, giving the shell a handle to scroll each tab to the top without
touching a single feature file. A `PopScope` on the shell routes the Android
back gesture to the Chores tab whenever another tab is selected. **A tab TAP
uses `jumpToPage` (instant, byte-identical to today); only a user's own drag
animates** — which is why not one existing E2E flow or widget test changes
its timing behavior.

**Tech Stack:** Flutter / Riverpod / drift. No new dependencies, and exactly
one new import in `app_shell.dart` (`dart:async`, for `unawaited`, added in
Task 2) — `PageView`, `PageController`, `AutomaticKeepAliveClientMixin`,
`PrimaryScrollController` and `PopScope` all come from the
`package:flutter/material.dart` import the file already has, and `dart:async`
does not collide with the two imports the notification-permission plan adds.

## Global Constraints

- **The hand-rolled tab bar is untouchable.** `_BottomTabBar` and
  `_TabContent` must come out of this plan **byte-identical** to how they go
  in — including `_BottomTabBar`'s constructor
  `({required _AppTab selected, required ValueChanged<_AppTab> onSelected})`.
  Rationale in "Coordination with in-flight plans" below. The bar stays
  hand-rolled because `NavigationBar` wraps destinations in a
  `MergeSemantics` boundary that swallows the nested `Semantics(identifier:)`
  E2E needs (existing class doc comment, `lib/app/app_shell.dart:53-57`).
- **Every `shell.tab.*` id survives unchanged**: `shell.tab.chores`,
  `shell.tab.shopping`, `shell.tab.settings` (normative, spec
  `docs/specs/ui-foundation-chores.md:42`; also `docs/specs/theme-v2.md:298`
  — "The hand-rolled bar and its `shell.tab.*` ids stay exactly as they are").
- **Per-tab keep-alive is a hard requirement**, not an optimization: spec
  `docs/specs/ui-shopping.md:63` ("The tab must keep its scroll position when
  switching tabs … don't break it") and
  `lib/features/shopping/shopping_list_screen.dart:43` both depend on the tab
  subtree surviving a switch.
- **`allowImplicitScrolling` stays `false` (the default) — never set it.**
  See "Approaches considered → keep-alive, K3": cache-region children are NOT
  excluded from the semantics tree, so it would leak an off-screen tab's
  `Semantics(identifier:)` nodes into `find.bySemanticsIdentifier` and into
  Maestro's accessibility tree.
- **No new user-visible strings**, therefore no `app_en.arb` / `app_de.arb`
  change. Everything here is gesture and navigation behavior; the one place a
  string was tempting (a "press back again to exit" toast) is rejected in
  resolved decision D-S3.
- Every interactive widget keeps a stable id via `semantic()`; E2E selects
  only by id or `(?s)`-substring text (spec
  `docs/specs/testing-strategy.md` §2.1, `e2e/README.md` convention 1).
- Widget tests stay integration-style: real in-memory `AppDatabase` + fixed
  clock via `testChoreApp`, overriding ONLY `appDatabaseProvider` and
  `clockProvider`. Never mock a repository or service.
- Strict lints (`very_good_analysis`, `flutter analyze --fatal-infos
  --fatal-warnings`). Unused imports are a build failure, so each task adds
  only the imports it actually uses.
- TDD per task: failing test → run → implement → run → commit.

---

## Analysis

### What is actually in the code today

- `lib/app/app_shell.dart` — `AppShell` is a plain `StatefulWidget` (not a
  `Consumer`). `_AppShellState` holds `_AppTab _selected` and a
  `GlobalKey<ScaffoldMessengerState> _messengerKey`; `build` returns
  `Scaffold(body: ScaffoldMessenger(key:, child: IndexedStack(index:,
  children: [ChoresListScreen, ShoppingListScreen, SettingsScreen])),
  bottomNavigationBar: _BottomTabBar(...))`. `_onTabSelected` (lines 112-115)
  clears snackbars, then `setState`s the index. There is **no `PopScope`, no
  `PageView`, no `ScrollController` and no `PrimaryScrollController` anywhere
  in `lib/`** (verified by grep).
- **All three tab screens scroll through uncontrolled, vertical scroll
  views** — no `controller:`, no `primary:` argument anywhere:
  - `lib/features/chores/chores_list_screen.dart:526` `ListView(...)`, and
    `:585` `CustomScrollView(...)` for the empty state (they are mutually
    exclusive branches of one `build`, so at most one exists at a time);
  - `lib/features/shopping/shopping_list_screen.dart:273` `ListView(...)`,
    `:346` `CustomScrollView(...)` — same either/or;
  - `lib/features/settings/settings_screen.dart:49` `ListView(...)`.
  `ScrollView`'s `effectivePrimary` is `primary ?? controller == null &&
  PrimaryScrollController.shouldInherit(context, scrollDirection)`, and
  `PrimaryScrollController`'s own `automaticallyInheritForPlatforms` defaults
  to every platform with `scrollDirection: Axis.vertical`. So inserting a
  `PrimaryScrollController` above each page makes all five of those scroll
  views attach to it **with zero edits to the feature files.** That is the
  whole basis for D-4's design.
- Every other vertical scrollable that could accidentally attach is on a
  **pushed route or an overlay**, i.e. a sibling of `AppShell` under the
  `Navigator`, not a descendant of our page: `manage_members_screen.dart:38`
  (`ListView.builder`), `manage_categories_screen.dart:156`
  (`ReorderableListView.builder`), and the `SingleChildScrollView`s in
  `category_edit_sheet.dart` / `member_edit_sheet.dart` /
  `household_rename_sheet.dart` / `join_household_sheet.dart` /
  `chore_form/category_chips.dart`. None of them inherits our controller.
- `test/app/app_shell_test.dart` asserts `find.byType(IndexedStack)` and
  `stack.children` length — the only test in the suite that names the
  container. 20 other test files and 6 E2E flows tap `shell.tab.*` and are
  agnostic to what renders the content.
- `e2e/flows/config.yaml` is `flows: ["**"]` and `.github/workflows/e2e.yml`
  runs `maestro test e2e/flows` **identically on Android and iOS**. There is
  no platform tagging, so a flow that only works on one platform cannot be
  added.

### Approaches considered — the content container (D-1)

1. **`PageView` + a shell-private keep-alive wrapper. ← chosen.** Real
   follow-the-finger paging, standard physics, page snapping and edge
   overscroll for free. The container swap is confined to `_AppShellState`.
2. **Keep `IndexedStack`, add a shell-level
   `GestureDetector(onHorizontalDragEnd:)`.** Rejected: the content would not
   follow the finger, so the gesture gives no feedback until it is over —
   which is the "clunky" feeling this whole convention wave exists to remove
   (`docs/feedback/2026-08-06-conventions-audit.md`). It also does nothing to
   dodge the `Dismissible` collision (a shell-level horizontal recognizer
   still loses the arena to a deeper one, exactly like `PageView`'s), so it
   pays a UX cost for no compensating benefit.
3. **`TabBarView` + `TabController`.** Rejected: it is `PageView` underneath
   plus a `TabController` we would never feed to a `TabBar` (the bar is
   hand-rolled and must stay so), and `TabController.animateTo` always
   animates — precisely the behavior decision D-S1 rejects for tab taps. More
   machinery, less control.

### Approaches considered — keep-alive (D-1)

- **K1: a shell-private `_KeepAlivePage` wrapper with
  `AutomaticKeepAliveClientMixin`. ← chosen.** Every line of churn stays
  inside `app_shell.dart`. Works because `PageView(children:)` builds a
  `SliverChildListDelegate` with `addAutomaticKeepAlives: true`, so each page
  is already wrapped in an `AutomaticKeepAlive` that listens for the
  `KeepAliveNotification` the mixin dispatches.
- **K2: `AutomaticKeepAliveClientMixin` on each of the three screens.**
  Rejected on two counts. `SettingsScreen` is a `ConsumerWidget` and would
  have to become stateful for no reason of its own; and all three files are
  being edited concurrently by other planned work
  (`2026-08-08-shopping-gestures.md`, `2026-08-08-acting-member-pinning.md`,
  `2026-08-08-catchup-visibility.md`, …). K1 buys total file isolation for
  ~20 lines.
- **K3: `allowImplicitScrolling: true` to pre-build the neighbouring page**
  (which would preserve today's "no loading flash on the first switch",
  since `IndexedStack` mounts all three at launch). **Rejected, and banned in
  Global Constraints.** `allowImplicitScrolling` widens the viewport's cache
  extent so neighbours are laid out — and, unlike kept-alive children,
  cache-region children are inside the viewport's semantics clip. Their
  `Semantics(identifier:)` nodes would join the semantics tree while another
  tab is on screen, which is exactly what
  `test/app/app_shell_test.dart:19`'s `expect(find.bySemanticsIdentifier
  ('settings.categories'), findsNothing)` and Maestro's `assertVisible`
  both read. Task 1 ships a regression test for this.

  Accepted consequence: shopping/settings are now built on **first visit**
  rather than at launch, so the very first switch to each can show
  `CircularProgressIndicator` for a frame or two while its stream resolves.
  Every later switch is instant (keep-alive). This is a strict startup-cost
  improvement and no test or flow depends on the eager mount; the E2E flows
  all `assertVisible` (which polls with a timeout) rather than asserting
  immediately.

### Approaches considered — where scroll controllers live (D-4)

This is the one part of the ticket with a genuine design question, since the
tab screens own their scrollables and expose no controller.

- **S1: the shell owns one `ScrollController` per tab and publishes it into
  that tab's subtree with `PrimaryScrollController`. ← chosen.** Zero edits
  to any feature file (see "What is actually in the code today" — all five
  scroll views already inherit), zero new public API, and it is the same
  mechanism the platform's own "tap the status bar to scroll to top" uses.
  The shell disposes what it creates.
  - *Known caveat, handled:* a `ScrollController` attached to more than one
    position throws on `.position` / `.offset` — but **not** on `animateTo` /
    `jumpTo`, which iterate `positions`. The implementation therefore only
    ever calls `animateTo`, guarded by `hasClients`. As analysed above each
    page has at most one attached vertical scroll view at a time anyway.
- **S2: a `GlobalKey<State>` per screen plus a public `scrollToTop()` method
  on each screen's state.** Rejected: three new public methods that exist
  only for the shell, `SettingsScreen` forced to become stateful, and three
  feature files touched — all to reimplement what `PrimaryScrollController`
  already does.
- **S3: pass a `ScrollController` down as a constructor parameter.**
  Rejected: touches every screen, *both* scroll views inside each screen (the
  list and its `_ScrollableEmptyState`), and every construction site in
  `lib/` and `test/`.
- **S4: hold the controllers in a Riverpod provider.** Rejected: controllers
  are ephemeral UI state owned by one widget's lifetime; the project's
  providers are for data, and `autoDispose` semantics would fight the
  controller's own disposal.

### Gesture collision with the shopping-list `Dismissible`

`docs/plans/2026-08-08-shopping-gestures.md` (already written, not yet
implemented) adds a `Dismissible(direction: DismissDirection.endToStart)` to
`ShoppingItemTile` and flags the collision as unresolved, saying "Flutter
does not document a stable winner for two independent recognizers on the same
axis". Resolving it is this plan's job. Reading the arena rather than
guessing:

`GestureBinding` dispatches a pointer-down along the hit-test path
**deepest-target-first**, so recognizers call `addPointer` in that order and
their routes fire in that order. `HorizontalDragGestureRecognizer` declares
victory the moment it has sufficient global distance, and the first
`resolve(accepted)` closes the arena. The `Dismissible` is strictly deeper in
the tree than the shell's `PageView`, so **on a shopping row the row wins,
deterministically.** Two consequences, both intended:

- Swipe **left** on a shopping row → the row is dismissed (delete + undo).
  The page does not move.
- Swipe **right** on a shopping row → the `Dismissible` has already won the
  arena and refuses to move in a disallowed direction, so *nothing happens*.
  You cannot page back to Chores by dragging over a row.

This is not a defect to engineer around; it is the behavior WhatsApp,
Telegram and Gmail all ship (paged tabs plus swipeable rows), and users are
already trained on it. Page-swiping on the Shopping tab still works from the
app bar, the pinned quick-add row, category headers, the "In the cart"
section header, the empty state and the bottom padding — but since Shopping
is the middle tab and its rows cover most of the screen, paging *away from
Shopping* by swipe mostly won't work. See resolved decision **D-S2** for the
product call, that accepted cost, the escape hatch and the rejected
alternatives.

Two corrections this plan records for whoever executes the shopping plan:

1. **The `onUpdate` lever that plan pre-provisioned (set the `PageView` to
   `NeverScrollableScrollPhysics` while a dismiss is in progress) is not
   needed and must not be wired.** It solves the reverse problem — the
   `PageView` eating row swipes — which the arena order shows cannot happen.
   Once the `Dismissible` has won, the `PageView` never sees the drag, so the
   physics flag would be pure dead weight (and, being driven from a child
   during a drag, a `setState`-during-layout hazard).
2. **Order independence.** This plan touches `lib/app/app_shell.dart` only;
   that plan touches `lib/features/shopping/*` only. Neither blocks nor
   regresses the other by omission. The one overlap is
   `docs/specs/ui-shopping.md`: this plan edits exactly one bullet (the
   `IndexedStack` line, §"Behaviors & constraints"), that plan appends
   gesture documentation elsewhere in the file. Whichever lands second may
   need a trivial merge.
3. **Verify on a real device once both have landed** (an emulator is enough;
   per project practice the E2E gate itself is GitHub CI): swipe left and
   right over a populated shopping list, confirm delete-on-left still works
   and that page-swipes from the quick-add row / headers still page.

### Animation, and what it means for E2E

`docs/specs/design-language.md` §Foundations: "**Motion**: standard M3
transitions ONLY (also mandated by testing-strategy determinism). No custom
animation code." `docs/specs/testing-strategy.md` §2.4: "Deterministic
animations. E2E build flag disables shimmer/staggered animations that cause
screenshot/timing flakiness."

Assessment: **no violation, and this plan deliberately keeps it that way.**

- No custom animation code is written. `PageView` is a first-party widget
  with first-party `PageScrollPhysics`; the settle is the platform's own
  spring, in the same class as `RefreshIndicator`'s spinner or the `ListView`
  overscroll glow, both already shipped.
- The determinism clause is about animations that run **without user input**
  and race an assertion. A page settle can only be reached by a finger
  dragging the page; no existing Maestro flow performs a horizontal swipe
  (verified: zero `swipe:` steps under `e2e/flows/`).
- **The tap path never animates.** `_onTabSelected` calls
  `_pageController.jumpToPage`, so every existing flow and every existing
  widget test sees exactly the instant switch it sees today. This is also the
  correct Material behavior — M3 bottom-navigation destination changes are
  not supposed to slide sideways — so it costs nothing in UX to gain full
  determinism. See resolved decision **D-S1**.
- The one new flow (Task 4) follows each swipe with an `assertVisible` on an
  id that only exists on the destination tab (`e2e/README.md` conventions 4
  and 8, testing-strategy §2.5 "no sleeps"), never a fixed wait.
- D-4's scroll-to-top uses `ScrollController.animateTo` (250 ms,
  `Curves.easeOutCubic`) — again a first-party API, again reachable only from
  a user tap, and covered in widget tests by `pumpAndSettle`.

### Judgement calls made here (not escalated as product decisions)

- **Re-tapping the active tab no longer clears snackbars.** The existing
  clear-on-switch behavior (field feedback B1) is justified by *leaving* a
  tab — "a completion toast is contextual to the tab the action happened on"
  (`app_shell.dart:104-111`). A re-tap does not leave anything, and nuking a
  fresh UNDO the user might still want would be a regression. Moving the
  clear into `onPageChanged` makes this fall out for free, and Task 1 locks
  it in with a test.
- **Scroll-to-top animates rather than jumps.** Every platform that ships
  this convention animates it; jumping 4000 px instantly is disorienting.
- **`sticky_snackbar_test.dart` and `lib/app/snackbars.dart` keep their
  `IndexedStack` mentions.** Those are *historical* narrative — a record of a
  theory that was investigated and ruled out on a specific date. Rewriting
  them to say `PageView` would falsify the record. Their assertions do not
  depend on the container (Task 1 runs them as a regression gate).
- **D-6 gets no E2E coverage.** `e2e/README.md` convention 7 —"Never use
  Maestro's bare `back` command" (on iOS it is a blind left-edge swipe that
  already failed to pop a route on the simulator) — and `pressKey: Back` is
  Android-only while `e2e/flows/config.yaml` runs every flow on both
  platforms with no tagging. Widget-test coverage via the real
  `flutter/navigation` `popRoute` platform message is both available and
  strictly more precise.

### Known trade-off to eyeball on device

During the first half of a drag (before `onPageChanged` fires and clears
snackbars), a snackbar showing on the tab being left can be briefly visible
on the incoming page too — all three tab `Scaffold`s are registered with the
same nested `ScaffoldMessenger`, so more than one can present while two pages
are simultaneously on stage. This is transient, only reachable mid-drag, and
the alternative (clearing on `ScrollStartNotification`) would wrongly clear
the snackbar when a drag snaps back without changing tabs. Left as-is;
worth a glance during the device pass.

---

## Product decisions (RESOLVED — Igor, 2026-08-08)

All three were raised as open decisions and accepted as recommended. They are
settled; the tasks below implement them. Reopening any of them means
revisiting the rationale here, not re-deriving it.

### D-S1 (was OD-1): a tab TAP switches instantly; only a drag animates — ACCEPTED

**Decision: `jumpToPage` on tap, `PageScrollPhysics` settle on drag.**

**Primary reason — it is the correct behavior, independent of testing.** The
horizontal page-slide belongs to `TabBar`/`TabBarView`, where the swipe and
the tab strip are the same control and the slide *is* the feedback for the
gesture. Bottom-navigation destinations are not arranged on a track the user
travels along: they swap. Animating a tap would make Chores → Settings slide
the **Shopping** tab past in between — a destination the user did not ask for,
visibly wrong, and worse the further apart the two destinations are. So an
animated drag and an instant tap are not an inconsistency to apologise for:
they are two different interactions, each rendered correctly. Direct
manipulation follows the finger; a discrete destination change does not
pretend to be a journey.

**Secondary benefit:** because the tap path is instant, the shell's only
animation is one a user's own finger started, so `docs/specs/testing-strategy
.md` §2.4 stays trivially satisfied and none of the 6 E2E flows or 20
widget-test files that tap a tab change their timing.

**Rejected:** `animateToPage(300 ms)`. It buys a legibility argument (you see
the tab order) that a three-item bar does not need, at the cost of the
fly-past above plus a 300 ms animated window on every tab tap in the suite.

### D-S2 (was OD-2): shopping rows own the horizontal gesture — ACCEPTED, with an obligation

Once `docs/plans/2026-08-08-shopping-gestures.md` also lands, a horizontal
drag that starts on a shopping row is claimed by that row: swipe-left
deletes, and **swipe-right does nothing at all** (the row wins the arena, then
declines to move in a disallowed direction).

**Decision: accept it.** This is the established pattern — Gmail and WhatsApp
both let a row's horizontal gesture beat the pager — and the alternative
(dropping swipe-to-delete) would remove a convention users actively reach for
and reverse a justified backlog item (D-2 / conventions audit C2, rated High).

**The cost is real and specific, and must be written down where the next
person will find it.** Shopping is the **middle** tab, and its rows cover most
of the screen, so *paging away from Shopping by swipe mostly won't work* —
only from the app bar, the pinned quick-add row, category headers, the
cart-section header, the empty state and the bottom padding. That is not a
footnote; on a full list it is the common case.

**Obligation (discharged by Task 5, Step 3):** record this in
`docs/specs/ui-shopping.md` as a known, accepted trade-off — not only in this
plan — **together with the escape hatch**: if it annoys in the field, removing
the `Dismissible` and keeping D-3's long-press delete restores paging
everywhere at the cost of exactly one gesture. Someone hitting this in six
months should find the reasoning and the exit, not rediscover the conflict.

**Also rejected:** restricting the page swipe to a ~24 dp edge zone. It
removes the dead zone but needs a custom `RawGestureDetector` + recognizer
(real custom gesture code) and makes the swipe far less discoverable, since
most users start the gesture mid-screen.

### D-S3 (was OD-3): back on the first tab exits immediately — ACCEPTED

**Decision: no "press back again to exit" toast.** Back returns to the start
destination from any other tab; from the start destination it is not
intercepted and the app closes, which is Material's stated behavior.

**Why not the double-tap-to-exit toast:** it is a dated Android idiom that
predictive back has effectively retired. With predictive back the system now
*shows* the user the app closing as they drag; intercepting that final back to
raise a toast reads as the app refusing to close, not as a helpful guard. It
would also need new copy in both ARBs and a timer, and design-language rule 6
pushes against toasts for something the user is already looking at.

---

## File map

| File | Change |
| --- | --- |
| `lib/app/app_shell.dart` | The whole change. `_AppShellState` gains a `PageController` + three `ScrollController`s; `IndexedStack` → `PageView`; new private `_KeepAlivePage`; new `PopScope`. **`_BottomTabBar` and `_TabContent` are not touched.** |
| `lib/features/shopping/shopping_list_screen.dart` | Comment-only: the `_cartExpanded` doc comment (line 43) cites the `IndexedStack` as the reason the screen stays mounted; that rationale must now cite the keep-alive. No code change. |
| `test/app/app_shell_test.dart` | Minimal edit: its first test names and asserts `IndexedStack`. Nothing else in the file changes. |
| `test/app/shell_navigation_test.dart` | **New.** All new coverage for D-1/D-4/D-6 lives here, deliberately out of `app_shell_test.dart` — see "Coordination with in-flight plans". |
| `e2e/flows/shell/tab_swipe.yaml` | **New.** The suite's first `swipe:` flow. |
| `e2e/README.md` | New authoring convention 9: swipe steps, and the `allowImplicitScrolling` trap that would silently poison every `assertVisible` in the suite. |
| `docs/specs/ui-foundation-chores.md` | Widget-test-matrix item 1 no longer says `IndexedStack`; a new binding "App shell navigation" section records the three behaviors. |
| `docs/specs/ui-shopping.md` | The `IndexedStack` bullet in §"Behaviors & constraints" is rewritten, and gains the row-vs-page gesture rule, its accepted cost and its escape hatch (decision D-S2). |

### Coordination with in-flight plans

- **`docs/plans/2026-08-08-notification-permission-recovery.md` — assume this
  plan lands FIRST.** Its Task 2 does a wholesale *"Replace the
  `_BottomTabBar` class with:"* / *"Replace the `_TabContent` class with:"*
  against the current text of those two classes, and adds
  `import 'package:chore_app/app/providers.dart';` +
  `import 'package:flutter_riverpod/flutter_riverpod.dart';`. Because this
  plan leaves both classes byte-identical and adds **no** imports, both of
  its replacement blocks still apply verbatim afterwards, and its
  `_BottomTabBar` → `ConsumerWidget` conversion needs nothing from us (the
  bar is constructed the same way, from a `_AppShellState` that is still a
  plain `State`). Its Task 2 also appends four tests to
  `test/app/app_shell_test.dart` and its Step 4 says *"Expected: PASS, all
  six tests (two pre-existing, four new)"* — after this plan that file still
  holds exactly its two pre-existing tests, so the count is unchanged. Our
  new tests live in a different file on purpose.
- **`docs/plans/2026-08-08-shopping-gestures.md`** — see "Gesture collision"
  above. No shared code file; one shared doc (`docs/specs/ui-shopping.md`),
  different sections.

---

## Task 1: `PageView` with per-page keep-alive, instant on tap (D-1)

**Files:**
- Modify: `lib/app/app_shell.dart:66-116` (`_AppShellState`), plus the class
  doc comment at `:48-57`
- Modify: `lib/features/shopping/shopping_list_screen.dart:34-47` (comment
  only)
- Modify: `test/app/app_shell_test.dart:7-25` (first test only)
- Test: create `test/app/shell_navigation_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: private to `app_shell.dart` — `_AppShellState._pageController`
  (`PageController`), `_AppShellState._onPageChanged(int index)`, and the
  private widget `_KeepAlivePage({required Widget child})`. Task 2 adds a
  `scrollController` parameter to `_KeepAlivePage`; Task 3 wraps `build`'s
  `Scaffold` in a `PopScope`. `_BottomTabBar`/`_TabContent` unchanged.

- [ ] **Step 1: Fix the one existing test that names the container**

In `test/app/app_shell_test.dart`, replace the description and the
`IndexedStack` block of the FIRST test (lines 7-25) with the following.
Everything from `await tester.tap(find.bySemanticsIdentifier
('shell.tab.shopping'));` onward, and the entire second test, stay exactly
as they are.

```dart
  testChoreApp(
    'three tabs render; switching swaps content and the shell keeps every '
    "visited tab's state alive",
    today: DateTime(2026, 7, 24, 9),
    (tester, database) async {
      final handle = tester.ensureSemantics();

      expect(find.bySemanticsIdentifier('shell.tab.chores'), findsOneWidget);
      expect(find.bySemanticsIdentifier('shell.tab.shopping'), findsOneWidget);
      expect(find.bySemanticsIdentifier('shell.tab.settings'), findsOneWidget);

      // Chores is the default tab; the other two aren't shown yet.
      expect(find.bySemanticsIdentifier('settings.categories'), findsNothing);

      // The content is a PageView (backlog D-1: horizontal swipe between
      // tabs). Per-page keep-alive -- the property the old IndexedStack
      // provided -- is covered in test/app/shell_navigation_test.dart.
      expect(find.byType(PageView), findsOneWidget);
```

- [ ] **Step 2: Write the failing tests for the new behavior**

Create `test/app/shell_navigation_test.dart`:

```dart
import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/features/shopping/shopping_list_screen.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_utils/pump_app.dart';

/// Shell navigation conventions (backlog D-1 / D-4 / D-6, conventions audit
/// C6, field feedback 2026-08-07 B3).
///
/// Kept in its own file rather than appended to `app_shell_test.dart` so
/// that file stays a stable target for the other planned edits to
/// `lib/app/app_shell.dart` (see
/// `docs/plans/2026-08-08-shell-navigation.md`, "Coordination with in-flight
/// plans").
void main() {
  final today = DateTime(2026, 7, 22, 9);

  /// Drags the shell's [PageView] by [dx] logical pixels and settles.
  ///
  /// The test surface is 800 logical pixels wide (`pump_app.dart`), and
  /// `WidgetTester.drag` imparts no fling velocity -- so `PageScrollPhysics`
  /// settles purely on the fractional page offset. 500 px is 0.625 of a
  /// page, comfortably clear of the 0.5 rounding knife-edge in both
  /// directions.
  Future<void> dragPage(WidgetTester tester, double dx) async {
    await tester.drag(find.byType(PageView), Offset(dx, 0));
    await tester.pumpAndSettle();
  }

  testChoreApp(
    'swiping right-to-left walks forward through the tabs, and left-to-right '
    'walks back (backlog D-1)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      expect(find.bySemanticsIdentifier('chores.add'), findsOneWidget);

      await dragPage(tester, -500);
      expect(find.bySemanticsIdentifier('shopping.add.input'), findsOneWidget);
      expect(find.bySemanticsIdentifier('chores.add'), findsNothing);

      await dragPage(tester, -500);
      expect(find.bySemanticsIdentifier('settings.categories'), findsOneWidget);

      await dragPage(tester, 500);
      expect(find.bySemanticsIdentifier('shopping.add.input'), findsOneWidget);

      await dragPage(tester, 500);
      expect(find.bySemanticsIdentifier('chores.add'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'swiping past the first tab does nothing (no wrap-around)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await dragPage(tester, 500);

      expect(find.bySemanticsIdentifier('chores.add'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'a visited tab keeps its in-flight state after leaving and coming back, '
    'and contributes nothing to the semantics tree while off screen',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('shell.tab.shopping'));
      await tester.pumpAndSettle();
      // `enterText` resolves the EditableText inside the identified
      // Semantics wrapper (WidgetTester.showKeyboard uses a matchRoot
      // descendant finder), so the semantic id is a valid target here.
      await tester.enterText(
        find.bySemanticsIdentifier('shopping.add.input'),
        'Milk',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsIdentifier('shell.tab.chores'));
      await tester.pumpAndSettle();

      // Kept alive: still in the element tree, but off stage...
      expect(
        find.byType(ShoppingListScreen, skipOffstage: false),
        findsOneWidget,
      );
      expect(find.byType(ShoppingListScreen), findsNothing);
      // ...and, critically, invisible to semantics. This is the regression
      // guard for `allowImplicitScrolling`: setting it true would lay the
      // neighbouring page out inside the viewport's semantics clip and leak
      // these ids into every `find.bySemanticsIdentifier` and every Maestro
      // `assertVisible`.
      expect(find.bySemanticsIdentifier('shopping.add.input'), findsNothing);

      await tester.tap(find.bySemanticsIdentifier('shell.tab.shopping'));
      await tester.pumpAndSettle();

      // The half-typed item survived the round trip -- the exact property
      // the old IndexedStack provided (spec docs/specs/ui-shopping.md).
      expect(find.text('Milk'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'swiping to another tab clears the snackbar shown on the tab being left, '
    'but re-tapping the CURRENT tab does not',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final service = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(today),
      );
      final chore = await service.createChore(
        householdId: householdId,
        title: 'One-off chore',
        startDate: PlainDate(2026, 7, 22),
        assignmentMode: AssignmentMode.anyone,
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.complete'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);

      // Re-tapping the tab you're already on isn't "leaving" it, so the
      // UNDO the user may still want stays put (field feedback B1 is about
      // a toast following you to ANOTHER tab).
      await tester.tap(find.bySemanticsIdentifier('shell.tab.chores'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);

      // Swiping away is leaving, and clears it exactly like a tab tap does
      // (test/app/snackbar_tab_switch_test.dart covers the tap path).
      await dragPage(tester, -500);
      expect(find.byType(SnackBar), findsNothing);

      handle.dispose();
    },
  );
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `flutter test test/app/shell_navigation_test.dart test/app/app_shell_test.dart`
Expected: FAIL — `find.byType(PageView)` finds nothing (the shell still
renders an `IndexedStack`), so every new test errors on a zero-widget finder.

- [ ] **Step 4: Convert the shell to a `PageView`**

In `lib/app/app_shell.dart`, replace the `AppShell` class doc comment's
first paragraph (lines 50-51):

```dart
/// Content lives in a [PageView] so the three tabs can be swiped between
/// (backlog D-1 / field feedback 2026-08-07 B3). Each page is wrapped in a
/// [_KeepAlivePage] so leaving a tab preserves its scroll position and
/// in-flight state instead of rebuilding it from scratch — the property the
/// [IndexedStack] this replaced was chosen for, and a binding requirement
/// (spec `docs/specs/ui-shopping.md`).
```

Then replace the whole of `_AppShellState` (lines 66-116) with:

```dart
class _AppShellState extends State<AppShell> {
  _AppTab _selected = _AppTab.chores;

  /// Drives the content [PageView].
  ///
  /// A tab TAP calls [PageController.jumpToPage], never `animateToPage`:
  /// Material 3 does not slide between bottom-navigation destinations, and
  /// an instant switch keeps every existing E2E flow and widget test seeing
  /// exactly the timing they saw before D-1 (spec
  /// `docs/specs/testing-strategy.md` §2.4). Only a user's own drag animates,
  /// and then it is `PageScrollPhysics`' standard settle — no custom
  /// animation code, so `docs/specs/design-language.md`'s Motion rule holds.
  final _pageController = PageController();

  /// Keyed so [_onPageChanged] can reach the nested [ScaffoldMessenger]'s
  /// state directly (it has no `BuildContext` of its own to look up via
  /// `ScaffoldMessenger.of`).
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // A nested ScaffoldMessenger so tab screens' `ScaffoldMessenger.of
      // (context)` lookups resolve to it instead of the root one:
      // ScaffoldMessenger only ever presents in the topmost Scaffold among
      // its registered descendants, so without this the root messenger
      // would present tab-screen snackbars in THIS Scaffold (the one below,
      // owning `bottomNavigationBar`) — flush against `_BottomTabBar` with
      // no room to breathe. Nesting it here makes each tab's own inner
      // Scaffold the topmost one instead, so its snackbars present above
      // the tab bar with margin (see `lib/app/snackbars.dart`).
      body: ScaffoldMessenger(
        key: _messengerKey,
        child: PageView(
          controller: _pageController,
          onPageChanged: _onPageChanged,
          // `allowImplicitScrolling` is deliberately left at its default
          // (false) and must stay there: it widens the viewport's cache
          // extent so the neighbouring page is laid out INSIDE the
          // semantics clip, which would leak that tab's
          // `Semantics(identifier: ...)` nodes into every
          // `find.bySemanticsIdentifier` and every Maestro `assertVisible`
          // while another tab is on screen. Covered by
          // test/app/shell_navigation_test.dart.
          children: [
            for (final tab in _AppTab.values)
              _KeepAlivePage(child: _screenFor(tab)),
          ],
        ),
      ),
      bottomNavigationBar: _BottomTabBar(
        selected: _selected,
        onSelected: _onTabSelected,
      ),
    );
  }

  /// The screen shown on [tab]'s page.
  Widget _screenFor(_AppTab tab) {
    switch (tab) {
      case _AppTab.chores:
        return const ChoresListScreen();
      case _AppTab.shopping:
        return const ShoppingListScreen();
      case _AppTab.settings:
        return const SettingsScreen();
    }
  }

  /// Switches the visible tab. Re-tapping the current tab is NOT a switch
  /// and deliberately falls through to nothing here (Task 2 of backlog D-4
  /// gives it scroll-to-top).
  void _onTabSelected(_AppTab tab) {
    if (tab == _selected) {
      return;
    }
    _pageController.jumpToPage(tab.index);
  }

  /// The single source of truth for "the user left a tab" — reached both by
  /// [_onTabSelected]'s jump and by a finger-driven page settle.
  ///
  /// Clears any snackbar shown on the tab being left (field feedback B1,
  /// `docs/feedback/2026-08-01-field-feedback.md`): a completion/skip toast
  /// is contextual to the tab the action happened on, so it shouldn't
  /// linger — or, worse, have its UNDO tapped — once the user has moved on
  /// to something else. Independent of the `persist: false` fix in
  /// `lib/app/snackbars.dart` (which stops toasts from sticking around
  /// forever on their OWN tab); this handles leaving the tab before that
  /// duration elapses. Re-tapping the tab you are already on is not leaving
  /// it, never reaches here, and so keeps its snackbar.
  void _onPageChanged(int index) {
    _messengerKey.currentState?.clearSnackBars();
    setState(() => _selected = _AppTab.values[index]);
  }
}

/// One page of the shell's [PageView], kept alive when it scrolls off
/// screen.
///
/// `PageView` builds its pages lazily and discards them once they are far
/// enough away; [AutomaticKeepAliveClientMixin] opts each page out of that,
/// which is what preserves a tab's scroll position and in-flight state
/// across a switch (spec `docs/specs/ui-shopping.md`). Implemented as a
/// wrapper here rather than mixed into the three tab screens so the whole
/// of D-1 stays inside this file.
///
/// A kept-alive page is held outside the sliver's laid-out child list, so it
/// is neither painted nor visited for semantics while off screen — see the
/// note on `allowImplicitScrolling` above.
class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child});

  /// The tab screen this page shows.
  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
```

Finally, update the now-inaccurate rationale in
`lib/features/shopping/shopping_list_screen.dart` (line 43, inside
`_cartExpanded`'s doc comment) — comment text only, no code change:

```dart
  /// This screen stays mounted for the tab's entire lifetime once first
  /// visited (each page of the `PageView` in `lib/app/app_shell.dart` is
  /// kept alive), so this field survives every such rebuild. Reset to
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/app/shell_navigation_test.dart test/app/app_shell_test.dart`
Expected: PASS (4 + 2 tests).

- [ ] **Step 6: Run the regression gate for everything that switches tabs**

Run:
```bash
flutter test test/app test/features/shopping test/features/settings test/features/chores test/features/onboarding
```
Expected: PASS. This is the real check on the container swap — 20 test files
tap `shell.tab.*`. Pay particular attention to `test/app/sticky_snackbar_test
.dart` and `test/app/snackbar_tab_switch_test.dart`: both switch tabs while a
snackbar is showing, and both keep their `IndexedStack` narrative comments on
purpose (they record a ruled-out theory, not current structure).

- [ ] **Step 7: Analyze and commit**

```bash
flutter analyze --fatal-infos --fatal-warnings
git add lib/app/app_shell.dart lib/features/shopping/shopping_list_screen.dart test/app/app_shell_test.dart test/app/shell_navigation_test.dart
git commit -m "Swipe left/right between tabs (D-1): IndexedStack -> keep-alive PageView"
```

---

## Task 2: Re-tap the active tab to scroll its list to the top (D-4 / C6)

**Files:**
- Modify: `lib/app/app_shell.dart` (`_AppShellState`, `_KeepAlivePage`)
- Test: `test/app/shell_navigation_test.dart` (append)

**Interfaces:**
- Consumes: `_KeepAlivePage` and `_onTabSelected` from Task 1.
- Produces: `_AppShellState._scrollControllers` (`Map<_AppTab,
  ScrollController>`) and `_KeepAlivePage({required ScrollController
  scrollController, required Widget child})`. No public API; nothing in
  `lib/features/` changes.

- [ ] **Step 1: Write the failing test**

Append to `test/app/shell_navigation_test.dart` (inside `main()`), and add
`import 'package:chore_app/features/settings/settings_screen.dart';` to the
import block:

```dart
  testChoreApp(
    're-tapping the tab you are already on scrolls its list back to the top '
    '(conventions audit C6 / backlog D-4)',
    today: today,
    (tester, database) async {
      // The shared surface is 2400 px tall so forms lay out without
      // scrolling; shrink it here so the Settings list actually overflows
      // and has somewhere to scroll to. `pump_app.dart` already registered
      // the tear-down that restores it.
      tester.view.physicalSize = const Size(400, 700);
      await tester.pumpAndSettle();

      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('shell.tab.settings'));
      await tester.pumpAndSettle();

      // `.first` guards against a future nested scrollable inside the
      // Settings subtree turning this into an ambiguous finder.
      final position = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(SettingsScreen),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      expect(position.maxScrollExtent, greaterThan(0));

      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));

      await tester.tap(find.bySemanticsIdentifier('shell.tab.settings'));
      await tester.pumpAndSettle();

      expect(position.pixels, 0);

      handle.dispose();
    },
  );

  testChoreApp(
    'each tab gets its own scroll controller: scrolling one tab and '
    "re-tapping another leaves the first tab's position alone",
    today: today,
    (tester, database) async {
      tester.view.physicalSize = const Size(400, 700);
      await tester.pumpAndSettle();

      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('shell.tab.settings'));
      await tester.pumpAndSettle();

      final position = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(SettingsScreen),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      final scrolled = position.pixels;
      expect(scrolled, greaterThan(0));

      // Leave, re-tap the OTHER tab twice (a switch, then a scroll-to-top
      // on that tab), then come back.
      await tester.tap(find.bySemanticsIdentifier('shell.tab.chores'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('shell.tab.chores'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('shell.tab.settings'));
      await tester.pumpAndSettle();

      expect(position.pixels, scrolled);

      handle.dispose();
    },
  );
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/app/shell_navigation_test.dart`
Expected: FAIL — the first new test fails on `expect(position.pixels, 0)`
(re-tapping is a no-op after Task 1, so the list stays where it was). The
second passes already; it is there to lock the per-tab isolation in.

- [ ] **Step 3: Give each page its own `PrimaryScrollController` and wire the re-tap**

In `lib/app/app_shell.dart`, add the controller map to `_AppShellState`,
directly under `_pageController`:

```dart
  /// One scroll controller per tab, published into that tab's subtree by
  /// [_KeepAlivePage] via [PrimaryScrollController].
  ///
  /// The three tab screens' scroll views are all uncontrolled and vertical
  /// (`ListView`/`CustomScrollView` with no `controller:` and no `primary:`),
  /// so `ScrollView.effectivePrimary` makes them attach to whatever
  /// `PrimaryScrollController` is in scope — which is how the shell reaches
  /// a tab's scroll position for D-4 without any feature file exposing one.
  /// Every scrollable INSIDE a tab that must not attach (the members list,
  /// the categories reorder list, every bottom sheet) lives on a pushed
  /// route or an overlay, i.e. a sibling of this shell under the `Navigator`
  /// rather than a descendant of a page.
  late final Map<_AppTab, ScrollController> _scrollControllers = {
    for (final tab in _AppTab.values) tab: ScrollController(),
  };
```

Extend `dispose`:

```dart
  @override
  void dispose() {
    _pageController.dispose();
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }
```

Pass each controller into its page, in `build`:

```dart
          children: [
            for (final tab in _AppTab.values)
              _KeepAlivePage(
                scrollController: _scrollControllers[tab]!,
                child: _screenFor(tab),
              ),
          ],
```

Replace `_onTabSelected` with:

```dart
  /// Switches the visible tab — or, when [tab] is already the visible one,
  /// scrolls that tab's list back to the top (conventions audit C6 /
  /// backlog D-4): the convention every list-based mobile app has taught
  /// the user.
  ///
  /// `animateTo` rather than `jumpTo` because landing at the top from far
  /// down a list without motion is disorienting, and it is a first-party
  /// `ScrollController` API reached only from a user tap — not custom
  /// animation code (spec `docs/specs/design-language.md`, Motion).
  /// `animateTo` also iterates `positions` internally, so unlike `.offset`
  /// it is safe even if a tab ever ends up with two attached scroll views;
  /// `hasClients` covers the zero case (a tab with nothing scrollable in it
  /// yet).
  void _onTabSelected(_AppTab tab) {
    if (tab == _selected) {
      final controller = _scrollControllers[tab]!;
      if (controller.hasClients) {
        unawaited(
          controller.animateTo(
            0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          ),
        );
      }
      return;
    }
    _pageController.jumpToPage(tab.index);
  }
```

Add `import 'dart:async';` at the top of `app_shell.dart` (above the
`package:` imports) for `unawaited` — this is the file's only new import in
the whole plan, and it does not collide with the two imports
`2026-08-08-notification-permission-recovery.md` Task 2 adds.

Finally, give `_KeepAlivePage` the controller and publish it:

```dart
class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.scrollController, required this.child});

  /// Published to [child]'s subtree as its [PrimaryScrollController], so the
  /// tab screen's uncontrolled vertical scroll view attaches to it.
  final ScrollController scrollController;

  /// The tab screen this page shows.
  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return PrimaryScrollController(
      controller: widget.scrollController,
      child: widget.child,
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/app/shell_navigation_test.dart test/app/app_shell_test.dart`
Expected: PASS (6 + 2 tests).

- [ ] **Step 5: Re-run the tab-screen suites**

Run: `flutter test test/features/chores test/features/shopping test/features/settings`
Expected: PASS. The controllers now own those lists' scroll positions, so
this is the check that nothing scroll-related regressed — in particular the
pull-to-refresh tests (`chores.refresh` / `shopping.refresh`) and the
`ScrollViewKeyboardDismissBehavior.onDrag` behavior.

- [ ] **Step 6: Analyze and commit**

```bash
flutter analyze --fatal-infos --fatal-warnings
git add lib/app/app_shell.dart test/app/shell_navigation_test.dart
git commit -m "Re-tap a tab to scroll its list to the top (D-4/C6)"
```

---

## Task 3: Android back returns to the first tab (D-6)

**Files:**
- Modify: `lib/app/app_shell.dart` (`_AppShellState.build`)
- Test: `test/app/shell_navigation_test.dart` (append)

**Interfaces:**
- Consumes: `_onTabSelected` and `_selected` from Tasks 1-2.
- Produces: nothing new; `build` returns `PopScope(child: Scaffold(...))`
  instead of a bare `Scaffold`.

- [ ] **Step 1: Write the failing tests**

Add `import 'package:flutter/services.dart';` to
`test/app/shell_navigation_test.dart`'s import block, then add this helper
just below `dragPage` inside `main()`:

```dart
  /// Delivers the platform's `popRoute` message — what the Android system
  /// back gesture/button actually sends the engine.
  Future<void> pressSystemBack(WidgetTester tester) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
      (_) {},
    );
    await tester.pumpAndSettle();
  }
```

and append these two tests:

```dart
  testChoreApp(
    'system back on a non-first tab returns to Chores instead of leaving the '
    'app (backlog D-6)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('shell.tab.settings'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsIdentifier('settings.categories'), findsOneWidget);

      await pressSystemBack(tester);

      expect(find.bySemanticsIdentifier('chores.add'), findsOneWidget);
      expect(find.bySemanticsIdentifier('settings.categories'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'system back on the first tab is not intercepted — it leaves the app '
    '(Material: back exits from the start destination)',
    today: today,
    (tester, database) async {
      final platformCalls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          platformCalls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final handle = tester.ensureSemantics();

      // Go away and come back, so the tab really is "first" rather than
      // merely "never left".
      await tester.tap(find.bySemanticsIdentifier('shell.tab.shopping'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('shell.tab.chores'));
      await tester.pumpAndSettle();

      await pressSystemBack(tester);

      expect(find.bySemanticsIdentifier('chores.add'), findsOneWidget);
      expect(
        platformCalls.map((call) => call.method),
        contains('SystemNavigator.pop'),
      );

      handle.dispose();
    },
  );
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/app/shell_navigation_test.dart`
Expected: FAIL — the first new test fails because back is not intercepted at
all, so Settings stays selected and `chores.add` is not found. (The second
already passes; it is the guard that Task 3 doesn't over-reach and swallow
back on the first tab too.)

- [ ] **Step 3: Wrap the shell in a `PopScope`**

In `_AppShellState.build`, wrap the returned `Scaffold`:

```dart
  @override
  Widget build(BuildContext context) {
    // Backlog D-6: Material's rule is that back returns to the start
    // destination before it leaves the app, and today a back press on any
    // tab quits outright. `canPop` is true only on the first tab, so the
    // first-tab case is left entirely alone — the framework bubbles it and
    // calls `SystemNavigator.pop()` exactly as before. (Side effect: with
    // `canPop: false` Android's predictive-back preview is suppressed on the
    // other two tabs, which is the documented cost of intercepting a pop.)
    return PopScope(
      canPop: _selected == _AppTab.chores,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        _onTabSelected(_AppTab.chores);
      },
      child: Scaffold(
        // ...everything from Task 1/2's build, unchanged...
      ),
    );
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/app/shell_navigation_test.dart test/app/app_shell_test.dart`
Expected: PASS (8 + 2 tests).

- [ ] **Step 5: Check the chore form's own `PopScope` still wins**

Run: `flutter test test/features/chores/chore_form_discard_test.dart test/features/chores`
Expected: PASS. `chore_form_screen.dart:251` has its own `PopScope` for the
unsaved-changes guard (conventions audit C4); it lives on a **pushed** route,
so its route's pop is resolved before the shell's ever sees anything. This
step proves that rather than assuming it.

- [ ] **Step 6: Analyze and commit**

```bash
flutter analyze --fatal-infos --fatal-warnings
git add lib/app/app_shell.dart test/app/shell_navigation_test.dart
git commit -m "Android back on a non-first tab returns to Chores (D-6)"
```

---

## Task 4: E2E coverage for the swipe, plus the flow-authoring convention

**Files:**
- Create: `e2e/flows/shell/tab_swipe.yaml`
- Modify: `e2e/README.md` (add convention 9, after convention 8's block)

**Interfaces:**
- Consumes: `e2e/common/onboard_fresh.yaml`, and the ids `shell.tab.chores`,
  `chores.add`, `shopping.empty`, `settings.categories` — all already shipped.
- Produces: nothing other code depends on.

- [ ] **Step 1: Write the flow**

Create `e2e/flows/shell/tab_swipe.yaml`:

```yaml
# Shell navigation: swipe left/right between the three tabs (backlog D-1,
# field feedback 2026-08-07 B3).
#
# The suite's FIRST flow to use `swipe:` — see README convention 9. Two
# things are deliberate here:
#   * both endpoints sit well inside the screen (20%/80%), so the gesture
#     can never be mistaken for iOS's left-edge interactive-pop or an
#     Android system edge gesture (same danger class as README convention 3);
#   * the shopping list is left EMPTY. Once
#     docs/plans/2026-08-08-shopping-gestures.md lands, a horizontal drag
#     starting on a shopping ROW is claimed by that row's Dismissible, not
#     by the page (spec docs/specs/ui-shopping.md). Swiping over an empty
#     list keeps this flow correct whichever order the two land in.
#
# Android back (D-6) is intentionally NOT covered here: README convention 7
# bans Maestro's bare `back`, and `pressKey: Back` is Android-only while
# e2e/flows/config.yaml runs every flow on both platforms. It is covered in
# test/app/shell_navigation_test.dart via the real `popRoute` platform
# message instead.
appId: ${APP_ID}
tags:
  - happy
---
- launchApp:
    clearState: true
# First-frame settle (README convention 8).
- extendedWaitUntil:
    visible:
      id: "welcome.create"
    timeout: 60000
- runFlow: ../../common/onboard_fresh.yaml
- assertVisible:
    id: "chores.add"
# Chores -> Shopping.
- swipe:
    start: "80%, 45%"
    end: "20%, 45%"
- assertVisible:
    id: "shopping.empty"
# Shopping -> Settings.
- swipe:
    start: "80%, 45%"
    end: "20%, 45%"
- assertVisible:
    id: "settings.categories"
# Swiping past the last tab does nothing (no wrap-around).
- swipe:
    start: "80%, 45%"
    end: "20%, 45%"
- assertVisible:
    id: "settings.categories"
# ...and back again, one tab at a time.
- swipe:
    start: "20%, 45%"
    end: "80%, 45%"
- assertVisible:
    id: "shopping.empty"
- swipe:
    start: "20%, 45%"
    end: "80%, 45%"
- assertVisible:
    id: "chores.add"
```

- [ ] **Step 2: Add the authoring convention**

In `e2e/README.md`, append to the numbered convention list (after
convention 8's "content matters" bullet block):

```markdown
9. **A swipe never gets a wait — it gets an `assertVisible` on an element
   that only exists on the destination.** The shell's tab `PageView`
   (backlog D-1) settles with standard `PageScrollPhysics`, so the frame
   the swipe lands on is not predictable; `assertVisible` polls, a sleep
   does not (spec `docs/specs/testing-strategy.md` §2.5). Keep both swipe
   endpoints well inside the screen (20%/80% is the suite's default): a
   gesture starting at a screen edge is an iOS interactive-pop or an
   Android system edge gesture, not your swipe — the same failure class as
   convention 3's `hideKeyboard`. And remember that a horizontal drag
   starting on a shopping ITEM row belongs to that row's `Dismissible`, not
   to the page (spec `docs/specs/ui-shopping.md`), so flows that swipe on
   the Shopping tab must do it over an empty list or over the quick-add
   row / a category header.

   **The trap that will silently poison this whole suite:
   `PageView.allowImplicitScrolling`.** It is `false` in
   `lib/app/app_shell.dart` and must stay `false`. Setting it true (the
   obvious-looking "fix" for the one-frame spinner on a tab's first visit)
   widens the viewport's cache extent so the NEIGHBOURING tab is laid out
   inside the viewport's semantics clip — unlike a kept-alive page, which
   is excluded. Its `Semantics(identifier: ...)` nodes then join the
   accessibility tree while a different tab is on screen, so `assertVisible`
   starts passing for ids that are not on screen and `assertNotVisible`
   starts failing for ids that are correctly hidden. The failures look like
   flakes and point nowhere near the shell. Guarded by
   `test/app/shell_navigation_test.dart` and spec
   `docs/specs/ui-foundation-chores.md`, "App shell navigation" item 2.
```

- [ ] **Step 3: Run the flow**

Do **not** run this locally — the E2E gate for this project is GitHub CI
(local emulator runs are noise). Push the branch and read the Android job,
then the iOS job. Expected: `tab_swipe` passes on both. If it fails, start
from the uploaded `~/.maestro/tests` screenshots and hierarchy JSON
(`e2e/README.md`, end of the Maestro-version section) — never from theory.

- [ ] **Step 4: Commit**

```bash
git add e2e/flows/shell/tab_swipe.yaml e2e/README.md
git commit -m "E2E: swipe between tabs, and the swipe-authoring convention"
```

---

## Task 5: Update the binding specs

**Files:**
- Modify: `docs/specs/ui-foundation-chores.md` (widget-test matrix item 1 at
  `:150-151`; new section appended before "All tests use in-memory
  AppDatabase…")
- Modify: `docs/specs/ui-shopping.md` (§"Behaviors & constraints", the
  `IndexedStack` bullet at `:63-64`)

**Interfaces:**
- Consumes: the behavior shipped in Tasks 1-4.
- Produces: the binding contract future work is reviewed against.

- [ ] **Step 1: Replace the `IndexedStack` claim in the chores spec's test matrix**

In `docs/specs/ui-foundation-chores.md`, replace item 1 of "## Widget test
matrix (minimum)":

```markdown
1. Shell: three tabs render; switching tabs swaps content and preserves
   state per tab (keep-alive `PageView` — see "App shell navigation" below).
```

- [ ] **Step 2: Add the binding shell-navigation section**

In the same file, insert this section immediately **before** the closing
paragraph "All tests use in-memory AppDatabase + fixed clock via provider
overrides…":

```markdown
## App shell navigation (added 2026-08-08 — backlog D-1 / D-4 / D-6)

Binding for `lib/app/app_shell.dart`.

1. **Content is a `PageView`**, one page per tab in `_AppTab.values` order,
   each page kept alive (`AutomaticKeepAliveClientMixin`) so leaving a tab
   preserves its scroll position and in-flight state. Horizontal swipe moves
   one tab at a time; there is no wrap-around.
2. **`allowImplicitScrolling` must stay `false`.** Setting it true lays the
   neighbouring page out inside the viewport's semantics clip, leaking that
   tab's `Semantics(identifier: ...)` nodes into `find.bySemanticsIdentifier`
   and Maestro's `assertVisible` while another tab is on screen. Regression
   test: `test/app/shell_navigation_test.dart`.
3. **A tab TAP switches instantly (`jumpToPage`); only a user's drag
   animates.** Material 3 does not slide between bottom-navigation
   destinations, and an instant tap keeps every E2E flow deterministic
   (`docs/specs/testing-strategy.md` §2.4). Never change this to
   `animateToPage` without re-timing the suite.
4. **Re-tapping the active tab scrolls that tab's list to the top**
   (conventions audit C6). The shell owns one `ScrollController` per tab and
   publishes it through `PrimaryScrollController`; the tab screens' scroll
   views stay uncontrolled and inherit it. A screen that ever needs its own
   `controller:` must instead accept one, or D-4 silently stops working for
   that tab.
5. **Re-tapping the active tab does NOT clear its snackbar.** Clearing is
   tied to *leaving* a tab (field feedback B1) and lives in `onPageChanged`,
   which a re-tap never reaches.
6. **System back on a non-first tab returns to the Chores tab**; on the
   Chores tab it is not intercepted and the app exits (Material's
   start-destination rule). No "press back again" confirmation.
7. **The hand-rolled `_BottomTabBar` and every `shell.tab.*` id are
   unchanged** by all of the above (`docs/specs/theme-v2.md` §4.5).
```

- [ ] **Step 3: Rewrite the shopping spec's bullet**

In `docs/specs/ui-shopping.md`, §"Behaviors & constraints", replace:

```markdown
- The tab must keep its scroll position when switching tabs (IndexedStack
  already guarantees this — don't break it).
```

with:

```markdown
- The tab must keep its scroll position when switching tabs. Guaranteed by
  the shell's per-page keep-alive (`docs/specs/ui-foundation-chores.md`,
  "App shell navigation") — don't break it, and don't give this screen's
  `ListView` its own `controller:`, which would also detach it from the
  re-tap-to-scroll-to-top handle the shell publishes.
- **A horizontal drag that starts on an item row belongs to that row, not to
  the tab `PageView`.** The row's `Dismissible` is deeper in the tree, so it
  wins the gesture arena: swipe-left deletes, and swipe-right does nothing
  (the row declines the disallowed direction after already winning). This is
  the same model Gmail and WhatsApp ship — a row's horizontal gesture beats
  the pager — and it is a deliberate, accepted trade-off, not a defect
  (decision D-S2, `docs/plans/2026-08-08-shell-navigation.md`).
- **The accepted cost, stated plainly:** Shopping is the MIDDLE tab and its
  rows cover most of the screen, so *paging away from this tab by swipe
  mostly won't work*. It works only from the app bar, the pinned quick-add
  row, category headers, the cart-section header, the empty state and the
  bottom padding; the tab bar is always available and is the reliable route.
- **The escape hatch, if this annoys in the field:** remove the `Dismissible`
  from `ShoppingItemTile` and keep D-3's long-press → Delete menu. That
  restores page-swiping everywhere at the cost of exactly one gesture, and
  delete still has a tap-reachable path — which is the reason D-3 exists.
  Do NOT instead try to give the `PageView` priority over rows: that needs a
  custom `RawGestureDetector` and makes the swipe undiscoverable (rejected
  in decision D-S2).
```

- [ ] **Step 4: Commit**

```bash
git add docs/specs/ui-foundation-chores.md docs/specs/ui-shopping.md
git commit -m "Spec the shell's swipe/re-tap/back navigation contract"
```

---

## Self-review notes

- **Ticket coverage.** D-1 → Task 1 (+ E2E Task 4). D-4/C6 → Task 2. D-6 →
  Task 3. Gesture collision with `2026-08-08-shopping-gestures.md` → Analysis
  §"Gesture collision" + decision D-S2 + Task 5 Step 3. Accommodating
  `2026-08-08-notification-permission-recovery.md` → Global Constraints
  (`_BottomTabBar`/`_TabContent` byte-identical) + §"Coordination with
  in-flight plans" + the decision to put new tests in a new file. Animation
  vs. the no-custom-animation rule and its E2E consequences → Analysis
  §"Animation, and what it means for E2E" + Task 5 Step 2 items 2-3 + E2E
  convention 9.
- **Order.** Each task is independently reviewable and leaves the app green:
  Task 1 ships the swipe; Task 2 adds the re-tap; Task 3 adds back; Tasks 4-5
  add coverage and contracts. Task 2's second test and Task 3's second test
  are written to pass immediately — they are guards against over-reach, and
  their tasks' Step 2 says so explicitly rather than pretending they fail.
- **Not in scope, deliberately:** the shopping list's `Dismissible` (its own
  plan), the Settings-tab attention badge (its own plan), and D-5's offline
  indicator.
