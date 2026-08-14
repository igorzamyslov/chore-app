# Spec: Shopping List UI

*The Shopping tab. Builds on the foundation from ui-foundation-chores.md
(providers, `semantic()`, `categoryIcon()`, theme) — reuse, don't duplicate.*

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
   when present. Tapping the tile (not the checkbox) opens the edit sheet.
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

Same integration-style setup as chores tests: real in-memory AppDatabase,
provider overrides for db + clock only, no mocks.

Done criteria: format clean, analyze --fatal-infos --fatal-warnings clean,
all tests green. No new dependencies.
