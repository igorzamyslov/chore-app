# Shopping-list gestures (D-2 swipe-to-delete + D-3 long-press menu) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give shopping-item rows the two established mobile conventions they're
missing — swipe-to-delete (backlog D-2 / conventions audit C2) and a
long-press context menu (backlog D-3 / C5) — by reusing the delete-with-undo
path that already shipped, not inventing a second one.

**Architecture:** `ShoppingItemTile` gains a `Dismissible` wrapper
(single-direction, `endToStart`) and an `onLongPress` callback, mirroring
`ChoreOccurrenceTile`'s existing `onLongPress` precedent exactly. Both new
entry points — swipe and the new one-row action sheet — call a single
extracted function, `deleteShoppingItemWithUndo`, which is also what the
edit sheet's existing Delete button is refactored to call. One delete path,
three doors into it.

**Tech Stack:** Flutter/Riverpod/drift, no new dependencies. `Dismissible` is
a stock Material widget (framework already ships it; the codebase just never
used it before — see conventions audit C2, "`Dismissible`: 0 hits").

## Global Constraints

- Every user-visible string goes through gen_l10n (`app_en.arb` template +
  `app_de.arb`, German du-form) — no inline English. This plan adds **zero**
  new l10n keys: both new entry points reuse `commonDelete`,
  `shoppingDeletedSnackbar`, and `shoppingDeletedUndo`, which already exist.
- Every interactive widget gets a stable id via `semantic()`; E2E selects
  only by id or `(?s)`-substring text.
- Widget tests are integration-style: real in-memory `AppDatabase` + fixed
  clock, overriding ONLY `appDatabaseProvider` and `clockProvider`. Never
  mock repositories or services.
- Strict lints (very_good_analysis, `--fatal-infos`); public members need
  doc comments.
- TDD: write-failing-test → run → implement → run → commit.
- Shopping-item delete never confirms (design-language.md rule 3: cheap,
  low-stakes; undo instead of a dialog) — neither new entry point may add a
  confirmation dialog.
- Specs in `docs/specs/` are binding contracts — `docs/specs/ui-shopping.md`
  gets a task to document both new gestures.
- Files in `lib/features/shopping/` stay under ~300 lines (spec
  `docs/specs/ui-shopping.md` "Placement" table) — this plan adds two new
  small files rather than growing `shopping_item_tile.dart` or
  `shopping_list_screen.dart` past that.

---

## Analysis

### What's already there (verified against source, not assumed)

- `deleteItem`/`restoreItem` on `ShoppingRepository`
  (`lib/data/repositories/shopping_repository.dart:422-449`) are a plain
  soft-delete / clear-`deleted_at` pair — no other column touched, so undo
  after either a swipe or a menu delete is byte-identical to undo after the
  edit sheet's delete today.
- The undo snackbar itself
  (`lib/features/shopping/shopping_edit_sheet.dart:175-196`) is inline in
  `_ShoppingEditSheetState._delete()` — there is exactly one copy of this
  logic in the codebase today, and it is NOT reusable as-is (private method
  on a private State class). It must be extracted before a second caller
  (the swipe) can reuse it, or the ticket's own "don't invent a second undo"
  constraint would be violated by construction.
- `ChoreOccurrenceTile` (`lib/features/chores/chore_occurrence_tile.dart:113-116`)
  already wires `InkWell(onLongPress: onOpenMenu, ...)`, and
  `chores_list_screen.dart:225-259`'s `_openMenu` shows
  `showChoreActionSheet` then switches on the returned enum. This is the
  exact shape to copy for D-3.
- `IndexedStack` is still the tab shell today
  (`lib/app/app_shell.dart:88`, confirmed via grep — no `PageView` anywhere
  in the file). D-1's swipe-between-tabs conversion has not been started:
  `docs/plans/2026-08-08-shell-navigation.md`, which the ticket brief names,
  does not exist in the repo (`find docs/plans` confirms). So there is no
  gesture conflict to reproduce or test against today — see "Gesture
  collision with D-1" below for how this plan stays valid regardless.

### D-2 approaches considered

1. **`Dismissible`, single direction (`endToStart`), delete only.**
   Standard "swipe left to delete" (Gmail, Reminders, most Android list
   apps). One recognizer direction, one action.
2. **`Dismissible`, both directions** (`DismissDirection.horizontal`):
   swipe-left = delete, swipe-right = toggle checked/unchecked.
   Rejected — checking/unchecking already has a dedicated 48dp leading
   control (design-language rule 2: "the most frequent action gets the
   biggest target"); duplicating it onto a swipe adds a second way to do
   the same thing for no gain, and doubles the horizontal-gesture surface
   that will one day compete with D-1's `PageView`.
3. **A custom `GestureDetector` instead of `Dismissible`**, to get finer
   control over drag-start thresholds for the eventual `PageView` conflict.
   Rejected as premature — `PageView` doesn't exist yet, so there is nothing
   concrete to tune against, and it would mean hand-rolling the resize/fade
   dismiss animation `Dismissible` already gives for free, for no present
   benefit.

**Chosen: option 1.** It's the smallest change, matches the dominant
platform convention, and keeps exactly one horizontal gesture direction in
play (see below).

### D-3 approaches considered

1. **Menu = `{Edit, Delete}`, mirroring `chore_action_sheet.dart` exactly.**
   Rejected — the ticket's own bar ("a menu that just duplicates the sheet
   is not worth shipping") applies directly: tapping a shopping row already
   opens the edit sheet in one step (no menu detour, unlike chores, where
   the row's `InkWell` has no `onTap` at all and the action sheet is the
   *only* way to reach Edit). Adding an "Edit" row that does exactly what a
   plain tap already does is pure duplication.
2. **Menu = `{Toggle checked, Delete}`.** Also rejected on inspection: the
   leading 48dp check ring is already a fully accessible toggle (explicit
   `Semantics(checked: ..., button: true)`,
   `lib/features/shopping/shopping_item_tile.dart:126-131`), so duplicating
   it into a modal sheet makes an already-one-tap action slower, not more
   accessible.
3. **Menu = `{Delete}` only.** The one action D-2 adds that has *no* tap-only
   equivalent is delete-via-swipe: swiping is a calibrated horizontal drag
   past a distance threshold, which is materially harder or impossible for
   users on Switch Control, single-tap scanning, or anyone with a motor
   condition that makes a clean horizontal drag unreliable. A long-press
   (already available as the row's *only* other unclaimed gesture — tap
   opens edit, the check ring handles its own taps) followed by a single
   tap on one menu row is a strictly easier motion. This gives the menu a
   real, non-duplicated job: it's the tap-reachable equivalent of the swipe,
   not a second way to do what a tap already does.

**Chosen: option 3.** A one-row sheet is intentionally sparse — see Open
product decisions below for whether that's the right long-term call.

### Gesture collision with D-1 (swipe-between-tabs)

D-1 doesn't exist in code today (`IndexedStack`, confirmed above), so there
is no live conflict to build against, and this plan **does not touch
`lib/app/app_shell.dart`** (out of its file map). Restricting the new
`Dismissible` to a single direction (`DismissDirection.endToStart`) is the
mitigation this plan actually ships: it's the smallest surface a future
horizontal `PageView` recognizer could ever compete with (one direction, not
two), and it costs nothing today since `IndexedStack` has no horizontal
recognizer to compete with in the first place.

Whichever order D-1 and this plan land in, the two are independent at the
code level (different files, no shared state), so neither blocks the other
and neither can regress the other by omission. What isn't guaranteed is
*good UX* the day both exist simultaneously: a horizontal drag starting over
an item row would put `Dismissible`'s `HorizontalDragGestureRecognizer` and
`PageView`'s own recognizer into the same gesture arena, and Flutter does
not document a stable winner for two independent recognizers on the same
axis with no shared `GestureArenaTeam`. This is a real, known Flutter
footgun class (nested horizontal-drag surfaces), not a hypothetical.

This plan's answer, since it cannot safely modify `app_shell.dart`: **flag it
as an explicit follow-up for whichever of D-1/D-2 lands second**, with a
concrete lever already in hand if manual testing shows tab-swipes eating row
swipes — `Dismissible` exposes `onUpdate: (DismissUpdateDetails details)`,
which fires continuously during a drag and reports `details.progress` and
`details.direction`. Whoever writes D-1's plan can have `ShoppingItemTile`
publish "a dismiss is in progress" (e.g. via a small `ValueNotifier<bool>`
or provider) and have the shell's `PageView` set
`physics: NeverScrollableScrollPhysics()` while it's true. This plan does
not implement that wiring itself (it would require editing
`app_shell.dart`), but the hook (`onUpdate`) is free — Task 2 below wires
`Dismissible` in a way that adding `onUpdate` later is a one-line change,
not a rewrite. **This must be verified on a real device/simulator once both
land**, not assumed correct from either plan in isolation.

### E2E vs widget-test coverage

**Neither D-2 nor D-3 gets new Maestro coverage.** The ticket brief is
explicit that Maestro handles swipe gestures awkwardly, and delete's actual
*outcome* (soft-delete + undo) is already E2E-exercised via the edit sheet's
Delete button, which this plan leaves untouched as a trigger. Adding a
parallel E2E flow that swipes or long-presses to reach the identical
already-covered outcome would only test gesture *dispatch*, which the
widget-test layer below covers directly and far more cheaply. All new
coverage in this plan is widget-test only
(`test/features/shopping/swipe_delete_test.dart`,
`test/features/shopping/long_press_menu_test.dart`).

---

## Open product decisions

### OD-1: Swipe direction and what it does

**Options:**
1. **(Recommended, implemented below) Single direction, delete only —
   `DismissDirection.endToStart` (swipe left).** Matches the dominant
   platform convention (Gmail, Reminders, most Android list-delete
   patterns); doesn't duplicate the existing check-ring control; keeps the
   smallest possible collision surface with D-1's future `PageView`.
2. Bidirectional — left = delete, right = toggle checked/unchecked.
   Rejected in Analysis above: duplicates the dedicated 48dp check control
   for no gain, doubles the future gesture-collision surface.
3. Single direction, but `startToEnd` (swipe right) instead of left.
   Functionally identical to option 1, purely a mirror-image convention
   choice; left is the more common pattern across the apps most users have
   already learned, so there's no reason to prefer this over option 1.

This plan implements **option 1**. If Igor prefers option 2 or 3, the only
change is the `direction:` argument and the background's alignment in Task
2 — cheap to flip later.

### OD-2: Is a one-row long-press menu worth shipping, or should D-3 wait
for a second menu item to justify the sheet?

**Options:**
1. **(Recommended, implemented below) Ship the one-row `{Delete}` menu now.**
   It closes the literal C5/D-3 gap ("shopping items have nothing on
   long-press") and gives the one action D-2 adds — delete via a
   calibrated drag — a tap-reachable equivalent for users who can't
   perform that drag reliably (see Analysis, D-3 option 3). A single-row
   bottom sheet is a known, unremarkable pattern (many apps show one-item
   action sheets); it isn't empty, it's focused.
2. **Skip D-3 entirely for now, revisit once a second menu item exists**
   (e.g. a future "duplicate item" or multi-list "move to list" feature).
   Rejected as the default here because it leaves the backlog item (D-3)
   and the conventions-audit finding (C5) open indefinitely on a
   speculative future feature with no spec and no committed timeline.
3. **Make long-press an alias for tap** (`onLongPress: onTap`, opening the
   edit sheet directly, no new sheet at all). Cheapest possible fix to "long
   press does nothing," but doesn't give delete a non-gesture equivalent
   (this plan's actual justification for D-3), and doesn't read as "a
   context menu" the way the backlog item names it.

This plan implements **option 1**.

---

## File map

| File | Change |
| --- | --- |
| `lib/features/shopping/shopping_delete.dart` | **New.** Extracts `deleteShoppingItemWithUndo` — the one shared delete-with-undo function. |
| `lib/features/shopping/shopping_item_action_sheet.dart` | **New.** `showShoppingItemActionSheet` + `ShoppingItemMenuAction` enum, mirroring `chore_action_sheet.dart`. |
| `lib/features/shopping/shopping_edit_sheet.dart` | Modify `_delete()` to call the shared helper instead of inlining it. |
| `lib/features/shopping/shopping_item_tile.dart` | Add `Dismissible` wrapper + `onLongPress`/`onSwipeDelete` callbacks. |
| `lib/features/shopping/shopping_list_screen.dart` | Thread the two new callbacks from `_ShoppingListScreenState` through `_Body._tileFor` to the tile; add `_openMenu`. |
| `docs/specs/ui-shopping.md` | Document both gestures; extend the widget test matrix; note the E2E-scope decision. |
| `test/features/shopping/swipe_delete_test.dart` | **New.** Widget coverage for D-2. |
| `test/features/shopping/long_press_menu_test.dart` | **New.** Widget coverage for D-3. |

---

## Task 1: Extract the shared delete-with-undo helper

**Files:**
- Create: `lib/features/shopping/shopping_delete.dart`
- Modify: `lib/features/shopping/shopping_edit_sheet.dart:175-196`
- Test: `test/features/shopping/delete_undo_test.dart` (existing — used here as a regression guard, unchanged)

**Interfaces:**
- Produces: `Future<void> deleteShoppingItemWithUndo(BuildContext context, WidgetRef ref, {required String itemId})` — Tasks 2 and 3 both call this.

- [ ] **Step 1: Run the existing regression guard to confirm today's baseline passes**

Run: `flutter test test/features/shopping/delete_undo_test.dart`
Expected: PASS (3 tests) — this is the behavior Task 1 must not change.

- [ ] **Step 2: Create the shared helper**

```dart
// lib/features/shopping/shopping_delete.dart
/// The single shared delete-with-undo action for one shopping item.
library;

import 'dart:async';

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/snackbars.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Soft-deletes the item [itemId] and shows the standard 'Removed' undo
/// snackbar (spec `docs/specs/polish-round-1.md` C3), whose UNDO action
/// restores it by clearing `deleted_at` — a plain
/// [ShoppingRepository.restoreItem] call, since soft delete never touches
/// any other column.
///
/// This is the ONE place that logic lives (backlog D-2: "the swipe must
/// reuse that existing undo, not invent a second one"). The edit sheet's
/// Delete button, swipe-to-delete
/// (`lib/features/shopping/shopping_item_tile.dart`), and the long-press
/// menu's Delete row (`lib/features/shopping/shopping_item_action_sheet.dart`)
/// all call this same function, so there is exactly one delete-with-undo
/// behavior to reason about across all three entry points.
Future<void> deleteShoppingItemWithUndo(
  BuildContext context,
  WidgetRef ref, {
  required String itemId,
}) async {
  final repository = ref.read(shoppingRepositoryProvider);
  await repository.deleteItem(itemId);
  if (!context.mounted) {
    return;
  }
  final l10n = AppLocalizations.of(context);
  showAppSnackbar(
    context,
    message: l10n.shoppingDeletedSnackbar,
    action: SnackBarAction(
      label: l10n.shoppingDeletedUndo,
      onPressed: () => unawaited(repository.restoreItem(itemId)),
    ),
  );
}
```

- [ ] **Step 3: Point the edit sheet's Delete button at the shared helper**

Replace `_delete()` in `lib/features/shopping/shopping_edit_sheet.dart`
(currently lines 175-196) with:

```dart
  Future<void> _delete() async {
    final itemId = widget.item.item.id;
    // Shown (and the sheet popped) before the row disappears from view, so
    // the undo mirrors the chores undo tone (spec
    // `docs/specs/polish-round-1.md` C3) — see `shopping_delete.dart` for
    // the shared logic this now delegates to (also used by swipe-to-delete
    // and the long-press menu's Delete row).
    await deleteShoppingItemWithUndo(context, ref, itemId: itemId);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }
```

Add the import at the top of `shopping_edit_sheet.dart` (alongside the
existing `shopping_repository.dart` import):

```dart
import 'package:chore_app/features/shopping/shopping_delete.dart';
```

- [ ] **Step 4: Run the regression guard again — behavior must be byte-identical**

Run: `flutter test test/features/shopping/delete_undo_test.dart`
Expected: PASS (same 3 tests, unchanged assertions).

- [ ] **Step 5: Run the full shopping suite to catch anything else touching `_delete`**

Run: `flutter test test/features/shopping/`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/shopping/shopping_delete.dart lib/features/shopping/shopping_edit_sheet.dart
git commit -m "refactor(shopping): extract shared delete-with-undo helper"
```

---

## Task 2: Swipe-to-delete on the shopping item tile

**Files:**
- Modify: `lib/features/shopping/shopping_item_tile.dart` (whole file — see below)
- Modify: `lib/features/shopping/shopping_list_screen.dart:214-329` (`_Body` + `_tileFor`)
- Test: Create `test/features/shopping/swipe_delete_test.dart`

**Interfaces:**
- Consumes: `deleteShoppingItemWithUndo` (Task 1).
- Produces: `ShoppingItemTile` gains two new required parameters,
  `onLongPress: VoidCallback` (wired in Task 3) and
  `onSwipeDelete: VoidCallback` (wired in this task) — Task 3's tests
  construct `ShoppingItemTile` with both, so their exact names/types matter.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/shopping/swipe_delete_test.dart
/// Widget coverage for swipe-to-delete on a shopping item row (backlog
/// D-2 / conventions audit C2): a single-direction (`endToStart`, i.e.
/// swipe-left) `Dismissible` that reuses the exact delete-with-undo path
/// the edit sheet's Delete button already ships (spec
/// `docs/specs/polish-round-1.md` C3) — see `shopping_delete.dart`.
library;

import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'shopping_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  Future<void> expandCartSection(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testChoreApp(
    'swiping an unchecked item left removes it and shows the same undo '
    'snackbar as the edit sheet delete',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final item = await ShoppingRepository(
        database,
      ).addItem(householdId, name: 'Milk');
      await tester.pumpAndSettle();

      await openShoppingTab(tester);
      await tester.drag(
        find.bySemanticsIdentifier('shopping.item.${item.id}'),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle();

      expect(find.text('Milk'), findsNothing);
      expect(find.bySemanticsIdentifier('shopping.empty'), findsOneWidget);
      expect(find.text('Removed'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'UNDO after a swipe restores the item by clearing deleted_at',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final item = await ShoppingRepository(
        database,
      ).addItem(householdId, name: 'Milk');
      await tester.pumpAndSettle();

      await openShoppingTab(tester);
      await tester.drag(
        find.bySemanticsIdentifier('shopping.item.${item.id}'),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(find.text('Milk'), findsOneWidget);

      final restored = await (database.select(
        database.shoppingItems,
      )..where((tbl) => tbl.id.equals(item.id))).getSingle();
      expect(restored.deletedAt, isNull);

      handle.dispose();
    },
  );

  testChoreApp(
    'swiping right (startToEnd) does nothing — delete is left-swipe only',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final item = await ShoppingRepository(
        database,
      ).addItem(householdId, name: 'Milk');
      await tester.pumpAndSettle();

      await openShoppingTab(tester);
      await tester.drag(
        find.bySemanticsIdentifier('shopping.item.${item.id}'),
        const Offset(500, 0),
      );
      await tester.pumpAndSettle();

      expect(find.text('Milk'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'swiping a checked item in the expanded cart section deletes it the '
    'same way as an unchecked item',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final item = await ShoppingRepository(
        database,
      ).addItem(householdId, name: 'Milk');
      await ShoppingRepository(database).setChecked(item.id, checked: true);
      await tester.pumpAndSettle();

      await openShoppingTab(tester);
      await expandCartSection(tester, 'In the cart (1)');
      await tester.drag(
        find.bySemanticsIdentifier('shopping.item.${item.id}'),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle();

      expect(find.text('Milk'), findsNothing);
      expect(find.text('Removed'), findsOneWidget);

      handle.dispose();
    },
  );
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/shopping/swipe_delete_test.dart`
Expected: FAIL — `ShoppingItemTile` has no swipe behavior yet, so the drag
is a no-op and `find.text('Milk')` still finds the item after the first
test's drag.

- [ ] **Step 3: Add `Dismissible` + `onLongPress` to the tile**

Replace the whole of `lib/features/shopping/shopping_item_tile.dart` with:

```dart
/// A single shopping item's list row.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:flutter/material.dart';

/// A row for one active [ShoppingItemWithCategory].
///
/// Leading check control (tap toggles checked/unchecked via
/// [onCheckedChanged], writing through immediately): a 23dp ring inside a
/// 48dp tap target (spec `docs/specs/theme-v2.md` §4.3) -- an `outline` 2px
/// border when unchecked, filled `primary` with an `onPrimary` check when
/// checked. Tapping anywhere else on the row opens the edit sheet via
/// [onTap]. The same row renders both the unchecked list and the checked
/// section -- checked items render with strikethrough, muted text (color is
/// never the only signal for the checked state, per
/// `docs/specs/design-language.md`).
///
/// Two more gestures (backlog D-2/D-3, conventions audit C2/C5): swiping
/// left ([DismissDirection.endToStart] only -- see the module doc comment
/// on `shopping_delete.dart` for why this is single-direction) fires
/// [onSwipeDelete]; long-pressing anywhere on the row fires [onLongPress].
/// Both ultimately call the SAME `deleteShoppingItemWithUndo` the edit
/// sheet's own Delete button uses -- there is exactly one delete-with-undo
/// behavior in the app, reached three ways.
///
/// This widget is deliberately bare (no card of its own): callers group rows
/// from the same category into one shared card (see `ShoppingListScreen`'s
/// aisle cards and `ShoppingCheckedSection`'s cart card), hairline-separated,
/// rather than each row carrying its own card as before this wave.
class ShoppingItemTile extends StatelessWidget {
  /// Creates a row for [item].
  const ShoppingItemTile({
    required this.item,
    required this.onCheckedChanged,
    required this.onTap,
    required this.onLongPress,
    required this.onSwipeDelete,
    super.key,
  });

  /// The item (and its joined category) to display.
  final ShoppingItemWithCategory item;

  /// Called with the new checked value when the leading check control is
  /// tapped.
  final ValueChanged<bool> onCheckedChanged;

  /// Called when the row is tapped anywhere but the check control.
  final VoidCallback onTap;

  /// Called when the row is long-pressed, to open the delete action sheet
  /// (backlog D-3) -- the tap-reachable equivalent of [onSwipeDelete] for
  /// anyone who can't perform a calibrated horizontal drag.
  final VoidCallback onLongPress;

  /// Called once the swipe-to-delete gesture's own dismiss animation
  /// completes (backlog D-2). The caller does the actual delete + undo
  /// snackbar (`deleteShoppingItemWithUndo`) -- this widget only reports
  /// that the gesture happened, matching how [onTap]/[onLongPress] report
  /// gestures without owning their side effects.
  final VoidCallback onSwipeDelete;

  @override
  Widget build(BuildContext context) {
    final shoppingItem = item.item;
    final checked = shoppingItem.checkedAt != null;
    final theme = Theme.of(context);
    final quantityNote = shoppingItem.quantityNote;
    final mutedColor = theme.colorScheme.onSurfaceVariant;

    return Dismissible(
      key: ValueKey('shopping.item.${shoppingItem.id}.dismissible'),
      // Single direction (OD-1, docs/plans/2026-08-08-shopping-gestures.md):
      // delete-only, swipe left -- never both directions, so this never
      // duplicates the dedicated check-ring control and stays the smallest
      // possible collision surface against a future PageView tab shell
      // (backlog D-1, not yet implemented).
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onSwipeDelete(),
      background: _SwipeDeleteBackground(),
      child: semantic(
        'shopping.item.${shoppingItem.id}',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  _CheckRing(
                    identifier: 'shopping.item.${shoppingItem.id}.check',
                    checked: checked,
                    onChanged: onCheckedChanged,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            shoppingItem.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              decoration: checked
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: checked ? mutedColor : null,
                            ),
                          ),
                          if (quantityNote != null && quantityNote.isNotEmpty)
                            Text(
                              quantityNote,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: mutedColor,
                                decoration: checked
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The swipe-to-delete background: an `errorContainer` ground with a
/// trailing delete glyph in `error`, revealed as the row is dragged left --
/// the same error-container/error pairing the overdue chore tile already
/// uses (`lib/features/chores/chore_occurrence_tile.dart`), so this doesn't
/// introduce a new color pairing. Purely a transient drag-in-progress
/// affordance, not a persistent status color, so it doesn't conflict with
/// design-language.md's "category color is an accent, not a background"
/// rule (a different subject: persistent per-item state, not a one-off
/// gesture reveal).
class _SwipeDeleteBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.errorContainer,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Icon(Icons.delete_outline, color: colorScheme.error),
    );
  }
}

/// The 23dp check ring inside a 48dp tap target (spec
/// `docs/specs/theme-v2.md` §4.3/§5): hand-rolled (rather than a Material
/// [Checkbox], which has no supported way to render at this exact visual
/// size) but carries the same accessibility contract via an explicit
/// `Semantics.checked` flag, so it still announces as a toggle to assistive
/// technology.
class _CheckRing extends StatelessWidget {
  const _CheckRing({
    required this.identifier,
    required this.checked,
    required this.onChanged,
  });

  final String identifier;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      identifier: identifier,
      container: true,
      button: true,
      checked: checked,
      onTap: () => onChanged(!checked),
      child: SizedBox(
        width: 48,
        height: 48,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => onChanged(!checked),
            child: Center(
              child: Container(
                width: 23,
                height: 23,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: checked ? colorScheme.primary : null,
                  border: checked
                      ? null
                      : Border.all(color: colorScheme.outline, width: 2),
                ),
                child: checked
                    ? Icon(Icons.check, size: 16, color: colorScheme.onPrimary)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Wire the two new callbacks through `shopping_list_screen.dart`**

In `lib/features/shopping/shopping_list_screen.dart`, add the import:

```dart
import 'package:chore_app/features/shopping/shopping_delete.dart';
```

Change `_Body`'s constructor and fields (currently lines 214-231) to accept
the two new callbacks:

```dart
class _Body extends StatelessWidget {
  const _Body({
    required this.items,
    required this.cartExpanded,
    required this.onCartExpansionChanged,
    required this.onCheckedChanged,
    required this.onTapItem,
    required this.onLongPressItem,
    required this.onSwipeDeleteItem,
    required this.onClear,
    required this.onUncheckAll,
  });

  final List<ShoppingItemWithCategory> items;
  final bool cartExpanded;
  final ValueChanged<bool> onCartExpansionChanged;
  final void Function(String id, {required bool checked}) onCheckedChanged;
  final ValueChanged<ShoppingItemWithCategory> onTapItem;
  final ValueChanged<ShoppingItemWithCategory> onLongPressItem;
  final ValueChanged<String> onSwipeDeleteItem;
  final VoidCallback onClear;
  final VoidCallback onUncheckAll;
```

Update `_tileFor` (currently lines 321-329):

```dart
  Widget _tileFor(ShoppingItemWithCategory item) {
    return ShoppingItemTile(
      key: ValueKey(item.item.id),
      item: item,
      onCheckedChanged: (value) =>
          onCheckedChanged(item.item.id, checked: value),
      onTap: () => onTapItem(item),
      onLongPress: () => onLongPressItem(item),
      onSwipeDelete: () => onSwipeDeleteItem(item.item.id),
    );
  }
```

In `_ShoppingListScreenState.build`, update the `_Body(...)` construction
(currently lines 93-123) to pass the two new callbacks — for this task,
`onLongPressItem` is a placeholder that will be replaced in Task 3, so wire
it directly here already anticipating Task 3's `_openMenu` (Task 3 adds the
method body; declaring the call now avoids touching this block twice):

```dart
                  final body = _Body(
                    items: items,
                    cartExpanded: _cartExpanded,
                    onCartExpansionChanged: (value) =>
                        setState(() => _cartExpanded = value),
                    onCheckedChanged: (id, {required checked}) {
                      // Bug 3: checking/unchecking an item is also "working
                      // the list" — dismiss the suggestions the same way.
                      FocusManager.instance.primaryFocus?.unfocus();
                      unawaited(_setChecked(ref, id, checked: checked));
                    },
                    onTapItem: (item) {
                      FocusManager.instance.primaryFocus?.unfocus();
                      unawaited(showShoppingEditSheet(context, item: item));
                    },
                    onLongPressItem: (item) => unawaited(_openMenu(item)),
                    onSwipeDeleteItem: (id) => unawaited(
                      deleteShoppingItemWithUndo(context, ref, itemId: id),
                    ),
                    onClear: () => unawaited(
                      _clearChecked(
                        ref,
                        [
                          for (final item in items)
                            if (item.item.checkedAt != null) item.item.id,
                        ],
                      ),
                    ),
                    onUncheckAll: () => _uncheckAll(ref),
                  );
```

This references `_openMenu`, which does not exist yet — Task 3 adds it.
Until Task 3 lands, this file will not compile; that's expected and
resolved within this same plan (Tasks 2 and 3 are meant to land together as
one PR-sized unit if executed back-to-back, or Task 2's commit can stub
`_openMenu` as `Future<void> _openMenu(BuildContext context, ShoppingItemWithCategory item) async {}` if Task 2 must compile standalone).

- [ ] **Step 5: Add the compiling stub for `_openMenu` so Task 2 builds on its own**

Add to `_ShoppingListScreenState` (e.g. directly below `_uncheckAll`):

```dart
  // Replaced in full by Task 3 (docs/plans/2026-08-08-shopping-gestures.md)
  // -- this stub only exists so Task 2 compiles and its tests can run
  // standalone. Takes no explicit `context`/`ref` params, matching
  // `chores_list_screen.dart`'s `_openMenu(OccurrenceWithChore occurrence)`
  // precedent exactly -- both use the State's own ambient `context`/`ref`.
  Future<void> _openMenu(ShoppingItemWithCategory item) async {}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `flutter test test/features/shopping/swipe_delete_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 7: Run the full shopping suite for regressions**

Run: `flutter test test/features/shopping/`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/features/shopping/shopping_item_tile.dart lib/features/shopping/shopping_list_screen.dart test/features/shopping/swipe_delete_test.dart
git commit -m "feat(shopping): swipe left to delete an item (D-2)"
```

---

## Task 3: Long-press action sheet on the shopping item tile

**Files:**
- Create: `lib/features/shopping/shopping_item_action_sheet.dart`
- Modify: `lib/features/shopping/shopping_list_screen.dart` (replace the `_openMenu` stub from Task 2)
- Test: Create `test/features/shopping/long_press_menu_test.dart`

**Interfaces:**
- Consumes: `ShoppingItemTile.onLongPress` (Task 2), `deleteShoppingItemWithUndo` (Task 1).
- Produces: `enum ShoppingItemMenuAction { delete }`,
  `Future<ShoppingItemMenuAction?> showShoppingItemActionSheet(BuildContext context)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/shopping/long_press_menu_test.dart
/// Widget coverage for the shopping item long-press action sheet (backlog
/// D-3 / conventions audit C5) -- a one-row `{Delete}` menu, the
/// tap-reachable equivalent of swipe-to-delete (D-2) for anyone who can't
/// perform a calibrated horizontal drag. See "OD-2" in
/// `docs/plans/2026-08-08-shopping-gestures.md` for why the menu has
/// exactly one row.
library;

import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'shopping_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'long-pressing an item opens a menu with a Delete row; tapping it '
    'deletes with the same undo snackbar as the edit sheet',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await ShoppingRepository(database).addItem(householdId, name: 'Milk');
      await tester.pumpAndSettle();

      await openShoppingTab(tester);
      await tester.longPress(find.text('Milk'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('shopping.menu.delete'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('shopping.menu.delete'));
      await tester.pumpAndSettle();

      expect(find.text('Milk'), findsNothing);
      expect(find.text('Removed'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'dismissing the menu without picking an action leaves the item alone',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await ShoppingRepository(database).addItem(householdId, name: 'Milk');
      await tester.pumpAndSettle();

      await openShoppingTab(tester);
      await tester.longPress(find.text('Milk'));
      await tester.pumpAndSettle();

      // Tap outside the sheet to dismiss it without choosing a row.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.text('Milk'), findsOneWidget);
      expect(find.text('Removed'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'long-pressing a checked item in the expanded cart section also opens '
    'the delete menu',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final item = await ShoppingRepository(
        database,
      ).addItem(householdId, name: 'Milk');
      await ShoppingRepository(database).setChecked(item.id, checked: true);
      await tester.pumpAndSettle();

      await openShoppingTab(tester);
      await tester.tap(find.text('In the cart (1)'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Milk'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('shopping.menu.delete'), findsOneWidget);

      handle.dispose();
    },
  );
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/shopping/long_press_menu_test.dart`
Expected: FAIL — `_openMenu` is still Task 2's empty stub, so no sheet
opens and `shopping.menu.delete` is never found.

- [ ] **Step 3: Create the action sheet**

```dart
// lib/features/shopping/shopping_item_action_sheet.dart
/// The long-press action sheet for a shopping item tile (backlog D-3).
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The action a user picked from [showShoppingItemActionSheet], or `null`
/// if they dismissed it without picking one.
enum ShoppingItemMenuAction {
  /// Delete the item, with the same undo snackbar as every other shopping
  /// delete path (`shopping_delete.dart`).
  delete,
}

/// Shows the tile-level long-press sheet, currently offering only Delete --
/// see "OD-2" in `docs/plans/2026-08-08-shopping-gestures.md` for why this
/// menu is deliberately one row rather than mirroring the chore action
/// sheet's four: renaming/category already has a one-tap path (the row's
/// own [InkWell.onTap]) and checking/unchecking already has a dedicated
/// 48dp control, so duplicating either here would fail the "not worth
/// shipping if it just duplicates the sheet" bar. Delete is the one action
/// introduced by a gesture (swipe, D-2) with no other tap-only path, so
/// this sheet is that path.
///
/// Resolves to the chosen [ShoppingItemMenuAction] (or `null` if dismissed).
/// Row shape (22dp icon, ≥48dp height, drag handle from the app-wide
/// `BottomSheetThemeData`) matches `chore_action_sheet.dart` exactly.
Future<ShoppingItemMenuAction?> showShoppingItemActionSheet(
  BuildContext context,
) {
  return showModalBottomSheet<ShoppingItemMenuAction>(
    context: context,
    builder: (sheetContext) {
      final errorColor = Theme.of(sheetContext).colorScheme.error;
      final l10n = AppLocalizations.of(sheetContext);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            semantic(
              'shopping.menu.delete',
              child: ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: errorColor,
                  size: 22,
                ),
                title: Text(l10n.commonDelete, style: TextStyle(color: errorColor)),
                onTap: () {
                  Navigator.pop(sheetContext, ShoppingItemMenuAction.delete);
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}
```

- [ ] **Step 4: Replace the Task-2 stub with the real `_openMenu`**

In `lib/features/shopping/shopping_list_screen.dart`, add the import:

```dart
import 'package:chore_app/features/shopping/shopping_item_action_sheet.dart';
```

Replace the stub added in Task 2, Step 5 with:

```dart
  /// Opens the long-press action sheet for [item] and acts on the chosen
  /// [ShoppingItemMenuAction] (backlog D-3) -- currently just Delete,
  /// reusing the same `deleteShoppingItemWithUndo` every other delete path
  /// calls (see `shopping_delete.dart`). Takes no explicit `context`/`ref`
  /// params -- uses the State's own ambient values, matching
  /// `chores_list_screen.dart`'s `_openMenu(OccurrenceWithChore occurrence)`
  /// precedent exactly.
  Future<void> _openMenu(ShoppingItemWithCategory item) async {
    final action = await showShoppingItemActionSheet(context);
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case ShoppingItemMenuAction.delete:
        await deleteShoppingItemWithUndo(
          context,
          ref,
          itemId: item.item.id,
        );
    }
  }
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/features/shopping/long_press_menu_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Run the full shopping suite for regressions**

Run: `flutter test test/features/shopping/`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/features/shopping/shopping_item_action_sheet.dart lib/features/shopping/shopping_list_screen.dart test/features/shopping/long_press_menu_test.dart
git commit -m "feat(shopping): long-press delete menu (D-3)"
```

---

## Task 4: Document both gestures in the binding spec

**Files:**
- Modify: `docs/specs/ui-shopping.md`

**Interfaces:**
- Consumes: nothing new — documents Tasks 1-3's shipped behavior.

- [ ] **Step 1: Add the gestures to the item tile's description**

In `docs/specs/ui-shopping.md`, in the "Screen layout" section's item 2
(currently describing the item tile), add a new paragraph directly after
the existing "Tapping the tile (not the checkbox) opens the edit sheet."
sentence:

```markdown
   Two more gestures on the same row (backlog D-2/D-3): swiping left
   deletes the item immediately, using the exact same undo snackbar as the
   edit sheet's Delete button (see below) -- swipe right does nothing.
   Long-pressing the row opens a one-row menu (`shopping.menu.delete`)
   offering Delete, as the tap-reachable equivalent of the swipe for anyone
   who can't perform a horizontal drag gesture reliably. Both apply
   identically to checked items in the "In the cart" section once it's
   expanded -- there is no behavioral difference between the two sections.
```

- [ ] **Step 2: Extend the widget test matrix**

In `docs/specs/ui-shopping.md`'s "Widget test matrix (minimum)" list,
append after the existing item 7 ("Dark mode + text scale 2.0 smoke..."):

```markdown
8. Swipe-to-delete: swiping an item left removes it and shows the undo
   snackbar; UNDO restores it; swiping right does nothing; applies the same
   way to a checked item in the expanded cart section.
9. Long-press menu: long-pressing an item opens a one-row Delete menu;
   tapping Delete removes it with the same undo snackbar; dismissing the
   menu without a choice leaves the item untouched; applies the same way to
   a checked item.
```

- [ ] **Step 3: Note the E2E-scope decision**

Directly below the widget test matrix's numbered list, before the "Same
integration-style setup..." sentence, add:

```markdown
Items 8 and 9 are widget-test only, deliberately: Maestro handles swipe
gestures awkwardly, and the actual delete-with-undo outcome both gestures
produce is already E2E-covered via the edit sheet's Delete button, which
neither gesture changes.
```

- [ ] **Step 4: Commit**

```bash
git add docs/specs/ui-shopping.md
git commit -m "docs(shopping): spec swipe-to-delete and long-press menu"
```

---

## Task 5: Full regression pass

**Files:** none (verification only)

- [ ] **Step 1: Run the full shopping test directory**

Run: `flutter test test/features/shopping/`
Expected: PASS, every file including the two new ones from Tasks 2-3.

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze --fatal-infos --fatal-warnings`
Expected: no issues — in particular, confirm `_SwipeDeleteBackground`'s
missing doc comment on its constructor isn't flagged (it has none to flag,
being a default unnamed constructor on a private class, which
very_good_analysis does not require docs for) and that every new public
member (`deleteShoppingItemWithUndo`, `ShoppingItemMenuAction`,
`showShoppingItemActionSheet`, `ShoppingItemTile.onLongPress`,
`ShoppingItemTile.onSwipeDelete`) has a doc comment (all provided above).

- [ ] **Step 3: Run the full test suite**

Run: `flutter test`
Expected: PASS — confirms nothing outside `test/features/shopping/`
depended on `ShoppingItemTile`'s old three-parameter constructor or
`_ShoppingEditSheetState._delete`'s old inline body.

- [ ] **Step 4: Format check**

Run: `dart format --output=none --set-exit-if-changed lib/features/shopping/ test/features/shopping/ docs/specs/ui-shopping.md`
Expected: no changes needed (or run `dart format` without the flags to fix,
then re-stage).
