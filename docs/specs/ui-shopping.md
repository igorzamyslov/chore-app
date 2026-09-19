# Spec: Shopping List UI

*The Shopping tab. Builds on the foundation from ui-foundation-chores.md
(providers, `semantic()`, `categoryIcon()`, theme) — reuse, don't duplicate.*

## Amendment 2026-09-19 — row gestures (field report, v0.10.1)

> **This amendment REVERSES backlog D-2 and D-3 and supersedes every
> statement about row gestures below.** Where the older text and this block
> disagree, this block wins; the older text is kept (struck through or
> marked) so the reversal is visible rather than tidied away.
>
> **What happened.** Igor used v0.10.1 on a real phone and reported, in his
> words: *"in shopping cart: remove swipe action (it prevents swiping the
> screen left/right); click on the item should also tick it; long click
> should open the item menu; current long click menu is useless anyway and
> can be removed."* That is not a new discovery — it is the cost this spec
> already recorded as accepted in §"Behaviors & constraints", together with
> the escape hatch to take if it ever annoyed in the field. It annoyed. The
> hatch is taken.
>
> **The new gesture map**, complete:
>
> | Gesture on a row | Does |
> |---|---|
> | Tap the 48dp check ring | Toggle checked |
> | Tap anywhere else on the row | Toggle checked — the same action |
> | Long-press anywhere on the row | Open the **edit sheet** |
> | Horizontal drag | Nothing. It belongs to the shell's tab `PageView`. |
>
> Both sections behave identically, as before: an expanded "In the cart"
> row ticks, long-presses and pages exactly like an aisle row.
>
> **Why the edit sheet is "the item menu".** Igor asked for long-press to
> open the item menu AND for the current long-press menu to be removed,
> which reads as a contradiction only until you notice that the one-row
> `{Delete}` sheet D-3 shipped was never the item's menu — the edit sheet
> was, and it was on tap. Tap is now spent on ticking, so the edit sheet
> moves to long-press and the one-row sheet is deleted outright
> (`shopping_item_action_sheet.dart`, and with it the
> `shopping.menu.delete` id). Every action it offered is a strict subset of
> the edit sheet's, so nothing became unreachable.
>
> **What this costs, stated as plainly as the old cost was.** D-3's stated
> reason for existing was accessibility: swipe-to-delete needed a
> tap-reachable equivalent, because a calibrated horizontal drag is exactly
> what a user on Switch Control or with a motor condition cannot perform.
> That reason DISSOLVES with the swipe — there is no longer a
> gesture-only action to back up, and delete is reached by a long-press,
> which Switch Control and TalkBack/VoiceOver both expose as an explicit
> action rather than as a timed gesture. The residual cost is real but
> smaller: **long-press is less discoverable than tap**, so a user who
> never tries it will not find rename/quantity/category. Accepted, because
> ticking is the thing done dozens of times per shop and editing is rare,
> and the alternative — keeping edit on tap — is what produced the report.
>
> **Do not re-derive the rejected option.** Giving the `PageView` priority
> over rows while keeping the swipe was rejected in decision D-S2 and is
> still rejected: it needs a custom `RawGestureDetector` and makes the
> swipe undiscoverable. The answer is that the row claims no horizontal
> gesture at all.
>
> **Regression guard.** `e2e/flows/shell/tab_swipe.yaml` now pages over a
> POPULATED shopping list, not only an empty one. The empty-list version
> was a deliberate workaround for the `Dismissible`, and that workaround is
> why this cost was never observed in CI.

## Placement

| What | Where |
|---|---|
| Screens/widgets | `lib/features/shopping/…` (files < ~300 lines) |
| Providers | extend `lib/app/providers.dart` (shoppingItemsProvider, shoppingCategoriesProvider, ShoppingRepository provider) |
| Widget tests | `test/features/shopping/…` |

## Screen layout (top to bottom)

1. **Quick-add row**, pinned above the list: text field
   (`shopping.add.input`, hint 'Add item…') + submit icon button
   (`shopping.add.submit`). Submitting (button or keyboard action) trims;
   empty input does nothing (no error, no row). Non-empty →
   `ShoppingRepository.addItem` with `addedBy` = acting member, category
   null; field clears, focus stays for rapid entry.
2. **Unchecked items**, in repository order (category sort_order, then
   name), with a header row per category run: category icon + name in the
   category's color; uncategorized items come first under the header
   'Uncategorized'. Item tile (`shopping.item.<id>`): leading round
   checkbox (`shopping.item.<id>.check`), name, quantity note as subtitle
   when present.

   **Gestures (amended 2026-09-19 — see the Amendment above, which is the
   binding version):** tapping the tile ANYWHERE, checkbox included, toggles
   checked; long-pressing it opens the edit sheet; a horizontal drag belongs
   to the tab pager and does nothing to the row. Neither gesture confirms
   first — see "Edit sheet" and design-language rule 3. Both apply
   identically to checked rows in the "In the cart" section once it is
   expanded; there is no behavioral difference between the two sections.

   ~~Tapping the tile (not the checkbox) opens the edit sheet. Two more
   gestures on the same row (backlog D-2/D-3): swiping left deletes the item
   immediately, with the exact same undo snackbar as the edit sheet's Delete
   button; long-pressing opens a one-row menu (`shopping.menu.delete`)
   offering only Delete, as the tap-reachable equivalent of the swipe for
   anyone who cannot perform a calibrated horizontal drag.~~ — **reversed
   2026-09-19.**
3. **Checked section**: a collapsed-by-default `ExpansionTile` header
   'In the cart (N)' (`shopping.checked.header`), containing checked items
   (strikethrough style) with the same check control (tap = uncheck, item
   returns to its section live).
4. **Clear-checked**: `TextButton` 'Clear checked' (`shopping.clear`)
   visible only when N > 0, inside the checked section header row area.
   Asks confirmation dialog (`shopping.clear.confirm` / `shopping.clear.cancel`);
   confirm soft-deletes all checked via `clearChecked`.

Empty states:
- No active items at all: centered message ('Shopping list is empty') +
  `semantic('shopping.empty')`; quick-add row stays.
- All items checked: unchecked area shows the same empty message; checked
  section still visible.

## Edit sheet (modal bottom sheet)

Opened by tapping an item tile. Controls:
- name field (`shopping.edit.name`) — required; inline error 'Name is
  required' on empty save, recovery must work;
- quantity/note field (`shopping.edit.quantity`) — optional, cleared to
  NULL when saved blank;
- category chip row (`shopping.edit.category.<categoryId>` + 'None' chip
  `shopping.edit.category.none`) from active shopping categories;
- Save (`shopping.edit.save`) → `updateItem`, closes sheet;
- Delete (`shopping.edit.delete`, destructive style) → soft-delete
  immediately (no confirm — shopping items are cheap; matches the spec'd
  low-friction philosophy), closes sheet.

Delete has exactly ONE door — this button, reached by long-pressing the row
— and exactly ONE implementation behind it
(`lib/features/shopping/shopping_delete.dart`). It soft-deletes and raises
the 'Removed' / UNDO snackbar; it does not confirm first. A second door, or
a second copy of the undo, is a defect. *(Amended 2026-09-19. Was: "exactly
THREE doors — this button, swipe-left, and the long-press menu's Delete
row". Swipe-left and the one-row menu are both gone; the invariant that
mattered — one implementation, one undo, no confirmation — is unchanged, and
the door count fell out of it rather than being the point.)*

## Behaviors & constraints

- All data through providers; bucketing/grouping computed from the
  repository stream's existing order — do NOT re-sort client-side.
- Check/uncheck writes through immediately (optimistic UI unnecessary —
  local DB is fast); no animations beyond defaults.
- The tab must keep its scroll position when switching tabs. Guaranteed by
  the shell's per-page keep-alive (`docs/specs/ui-foundation-chores.md`,
  "App shell navigation") — don't break it, and don't give this screen's
  `ListView` its own `controller:`, which would also detach it from the
  re-tap-to-scroll-to-top handle the shell publishes.
- **A horizontal drag that starts on an item row belongs to the tab
  `PageView`** (amended 2026-09-19). The row claims no horizontal gesture,
  so paging works from every pixel of this tab. Keep it that way: no
  `Dismissible`, no `GestureDetector` with horizontal drag callbacks, no
  `HorizontalDragGestureRecognizer` on a row. Anything deeper in the tree
  than the pager wins the arena, and this tab's rows cover most of the
  screen.
- Do NOT solve a future row-swipe wish by giving the `PageView` priority
  over rows: that needs a custom `RawGestureDetector` and makes the row
  gesture undiscoverable (rejected in decision D-S2,
  `docs/plans/2026-08-08-shell-navigation.md`, and still rejected).
- ~~The row's `Dismissible` is deeper in the tree, so it wins the gesture
  arena: swipe-left deletes, and swipe-right does nothing. The accepted
  cost: Shopping is the MIDDLE tab and its rows cover most of the screen,
  so paging away from this tab by swipe mostly won't work. The escape
  hatch, if this annoys in the field: remove the `Dismissible` from
  `ShoppingItemTile` and keep D-3's long-press → Delete menu.~~ —
  **the hatch was taken on 2026-09-19.** Recording it rather than deleting
  it, because the prediction was accurate and the record is the evidence
  that the cost was understood before it was paid, not rationalised after.

## Widget test matrix (minimum)

1. Quick add: type + submit → tile appears under 'Uncategorized'; input
   clears; empty submit adds nothing.
2. Check: tapping check moves item to checked section (and header count
   updates); uncheck moves it back under its category header.
3. Grouping: items across 2 categories + uncategorized render 3 headers in
   sort_order with correct icons/names; names sorted within each.
4. Clear checked: button hidden at N=0; confirm flow removes checked items
   only; cancel keeps them.
5. Edit sheet: prefill, rename, quantity set + cleared-to-null round-trip,
   category change moves the tile under the new header; empty-name error +
   recovery; delete removes the tile.
6. Empty states: fresh list; all-checked state.
7. Dark mode + text scale 2.0 smoke (no exceptions/overflows).
8. Row drag pages the shell (`row_swipe_pages_test.dart`): dragging left
   from a populated row lands on Settings, dragging right lands on Chores,
   and in neither case is the item deleted (asserted against the database —
   the pager leaves the other tab out of the semantics tree, so the row's
   absence proves nothing); applies the same way to a checked item in the
   expanded cart section.
9. Row tap ticks (`row_tap_toggles_test.dart`): tapping the row body moves
   the item into the cart WITHOUT opening the edit sheet, tapping a checked
   row unticks it, and the row tap fires the same single selection-click
   haptic the ring does.
10. Row long-press opens the edit sheet (`long_press_menu_test.dart`): the
   name/quantity/category/Delete/Save controls are all present,
   `shopping.menu.delete` is gone, Delete there removes the item with the
   one shared undo snackbar, a long-press does not also tick the item,
   dismissing without a choice leaves the item untouched, and it behaves the
   same on a checked row.

*(Items 8 and 9 were "Swipe-to-delete" and "Long-press menu" before the
2026-09-19 amendment.)* Item 8 is deliberately widget-level as well as
E2E-level: `e2e/flows/shell/tab_swipe.yaml` covers paging over a populated
list on a real device, and the widget test covers the same arena outcome
fast enough to run on every commit. The one thing NEITHER can see is how the
gesture feels under a thumb on a physical phone, which is where the report
came from in the first place.

Same integration-style setup as chores tests: real in-memory AppDatabase,
provider overrides for db + clock only, no mocks.

Done criteria: format clean, analyze --fatal-infos --fatal-warnings clean,
all tests green. No new dependencies.
