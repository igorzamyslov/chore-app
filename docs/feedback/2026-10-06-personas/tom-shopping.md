# Persona walkthrough: Tom, 43, the one who shops (Famdo 0.14.0+21)

Method: every screen and string reconstructed from source, nothing run on a device. Paths are relative to the repo root. "Could not verify" marks things that need a real phone or a live two-device test.

Screen model (so findings make sense):
- Shopping tab = AppBar title only, then `SyncHealthBanner` (self-hiding), then the quick-add pill, then one `ListView`: category header + card per category run (uncategorized first), then a collapsed "In the cart (N)" tile holding `Put all back` and `Clear checked` (`lib/features/shopping/shopping_list_screen.dart:161-163,406-423`, `shopping_checked_section.dart:98-121`).
- Row gestures: tap anywhere = tick, long-press = edit sheet (name, quantity/note, category chips, Delete, Save), horizontal drag = nothing (`shopping_item_tile.dart:81-82`, `shopping_edit_sheet.dart:90-146`).

---

## Walkthrough notes per flow

1. **Join.** Welcome gate "Join my family's household" (de: join with invite code), sign-in is an emailed link, then code, then "Which profile is yours?" / "I'm new here" (`app_en.arb:368-372,1415,1670-1712`). The default tab on a fresh install is Chores (`docs/specs/last-tab-restore.md` §1 "Default"), so Tom has to spot the cart icon in the 72dp bottom bar (`lib/app/app_shell.dart:350`). Afterwards the app reopens on Shopping by itself (last-tab restore), which is exactly right for him. No finding beyond "email sign-in is a prerequisite he may not expect".
2. **Add.** Type, tap `+` or keyboard Done. Field clears and refocuses; top-5 suggestion chips appear on empty focus (`shopping_quick_add_row.dart:227-301`, `shopping_repository.dart:167-222`). Duplicates are caught (see "works well").
3. **In store.** See findings PP1/PP2.
4. **After checkout.** `Clear checked` (no confirm, 4s Undo snackbar) or auto-clear of items checked more than 24h ago at the next cold start (`lib/app/providers.dart:825-828`, `shopping_repository.dart:522-553`). Cleared rows are soft-deleted, stay in history, and feed the suggestions, so staples come back as chips (`shopping_repository.dart:154-159`).
5. **Several stores.** Only categories exist as an axis.
6. **Edit/delete.** Long-press, then sheet. Delete is one button, no confirm, Undo snackbar (`shopping_delete.dart:32-51`).
7. **Two people.** Whole-row last-push-wins (PP1).
8. **German.** Mostly natural du-form; two real issues (PP6, Q2).

---

## Pain points

### PP1. Last-PUSH-wins on whole rows lets Tom's stale offline edit erase his partner's newer edit  (P1)
> "I cleared the list in the store and when I got home the milk she re-added was gone again."

What happens:
- Conflict rule: a pulled row never overwrites a locally dirty row; the dirty row then wins on the server and "server updated_at = push time" (`docs/specs/sync-backend.md:138-143`, `lib/data/repositories/sync_repository.dart:275-281`).
- The push sends the whole row, including `checked_at`, `deleted_at`, `name`, `quantity_note`, `category_id` (`lib/data/sync/row_mappers.dart:236-247`, `sync_engine.dart:697-706`). Which device wrote LAST is decided by when each device manages to push, not when the human acted.
- Concrete trap: Tom ticks "Milch" and presses Clear checked with no reception (row = deleted, dirty). At home his partner sees "Milch" (checked or deleted on her side), re-adds or un-checks it ("Moved back to the list"). Tom's phone reconnects later and pushes its older deleted row, which replaces her newer change. Her request disappears with no message on either phone.
- Brand-new items are separate rows (new UUID), so "we also need batteries" never conflicts. The risk is limited to edits of the same item: tick/untick, clear, rename, quantity, category.
- Could not verify on a live pair; derived from spec + engine code. The spec says it is accepted "at family scale" (sync-backend.md:140-143), so this is a +1 with a Tom-specific consequence, not a spec violation.

Suggestion (M): make the server decide by the client's own edit time for the contended fields. Cheapest form: on push, send the local `updated_at` as `client_updated_at` and let the upsert apply only if it is newer than the stored one. Cheaper and mostly sufficient (S): when a pull finds the server row newer than a dirty local row AND `deleted_at`/`checked_at` differ, prefer the server value for those two fields.

### PP2. Tom gets no positive confirmation that his edits are safe or that partner's adds arrived  (P2)
> "I'm at the dairy shelf. Did her 'butter' ever reach my phone? Did my ticks go through?"

What happens:
- When sync is healthy the shopping screen shows nothing at all (`sync_health_banner.dart:39-41`). The only signal is a banner after 5 minutes without a successful pull or 3 minutes of unpushed rows (`lib/domain/sync_health.dart:34,42,100-105`). The grace is deliberate, but it means a store with weak signal looks identical to "all good" for the first 3-5 minutes.
- Copy is good but passive: en "...Your changes are saved - try pulling down to refresh." (`app_en.arb:1554`), de at `app_de.arb:333`. Pull-to-refresh failure snackbar is honest too (`app_en.arb:1546`, `shopping_list_screen.dart:317-349`).
- "Last synced" exists only in Settings, Account (`docs/specs/sync-freshness.md` §2.4), two taps away.
- Arrival of partner's items is invisible: `addedBy` is written at `shopping_quick_add_row.dart:283` and never read in any UI (grep of `lib/features` finds only that write). No "new" marker, no "added by Anna", no tab badge, no notification (notifications are chore digests only; `docs/specs/notifications-n2.md:986` rules out shopping reminders).
- Realtime plus 60s poll mean it usually arrives within a second or a minute, but Tom cannot tell "nothing new" from "nothing arrived".

Suggestion (S): a quiet app-bar line or glyph on the Shopping tab, e.g. "Synced 2 min ago" / "3 changes waiting to send", fed by data that already exists (`syncLastPulledAt`, `watchAnyDirty`). Add (XS) a small "Anna" label or avatar dot on rows added by someone else, using the existing `addedBy`.

### PP3. The add field is at the very top of the screen, the hardest place for a one-handed thumb  (P2)
> "I'm holding the trolley with my left hand. The add field is up at the top; I have to re-grip every time."

What happens: the layout is `Column[banner, quick-add, Expanded(list)]` (`shopping_list_screen.dart:161-163`), and the suggestion chips also open below the field at the top (`shopping_quick_add_row.dart:176-180`). Ticking is cheap (whole-row target), but "we also need batteries" means a stretch to the top edge of a 6"+ phone. With the keyboard open there is, on top of that, up to 5 chips plus the field above a shrunken list.
Suggestion (M): offer the quick-add at the bottom (above the tab bar, `docs/design` mock puts it at top, so this is a design call), or at minimum a setting. The cheaper XS alternative: leave position, but make the pill taller (it is 48dp, `shopping_quick_add_row.dart:142-143`).

### PP4. Undoing an accidental tick means expanding the collapsed cart and finding the item  (P2)
> "I tapped the wrong row and it vanished. Where did it go?"

What happens: a tick holds the row 350 ms and then moves it into "In the cart (N)", which starts collapsed (`shopping_list_screen.dart:31,57`, `shopping_checked_section.dart:92`). There is no snackbar or Undo for a tick (`_setChecked` only fires a haptic, `shopping_list_screen.dart:267-280`). Tapping anywhere on the row ticks, so a stray touch is plausible. To undo: tap the cart header, scroll, find the item by name (cart rows are sorted by category then name, not by recency), tap it. The backlog fix for G1 optimised "stays open once expanded" but not first discovery.
Suggestion (S): an "Undo" snackbar for a single tick (reuse `showAppSnackbar` as delete does). Or (XS) show the 1-2 most recently ticked items beneath the cart header even when collapsed.

### PP5. "Put all back" has no undo and sits next to "Clear checked"; the clear Undo lasts 4 seconds  (P2)
> "My thumb hit the wrong text button. Now my whole cart is back on the list, or the list is gone and the toast vanished while I looked up."

What happens:
- Both `TextButton`s live inside the collapsed cart header's `Wrap`, side by side (`shopping_checked_section.dart:106-119`).
- `Clear checked` shows an Undo snackbar (`shopping_list_screen.dart:285-301`) but it auto-closes after 4 s (`lib/app/snackbars.dart:60`), and any later snackbar (e.g. "Already on the list" from a quick-add) replaces it immediately (`snackbars.dart:46-48` `clearSnackBars`).
- `Put all back` calls `uncheckAll` with no feedback or undo (`shopping_list_screen.dart:236,303-306`). It is the exact action meant for "failed checkout", but also an easy mis-tap that silently re-shuffles the whole cart.
Suggestion (XS): 8 s for bulk-action snackbars, plus a snackbar with Undo on Put all back (needs the captured id list, same pattern as `_clearChecked`). Optional (S): confirm only when N > ~10.

### PP6. German household sees English category headers (PRODUCE, DAIRY, MEAT & FISH...)  (P2)
> "Everything else is German but my aisles say 'Dairy' and 'Bakery'."

What happens: the default shopping categories are hard-coded English literals (`lib/data/repositories/category_repository.dart:79-88`), inserted without any locale by `seedDefaults` (`category_repository.dart:105-107`, called from `household_create_service.dart:59` and `lib/app/providers.dart:809`) and synced as plain rows, so every member sees whatever language the creator's code literal had, i.e. always English. Only "Uncategorized" is localised (`app_de.arb:201` "Ohne Kategorie"). Same for the chore defaults. Tom can rename each of the 8 in Settings, Categories, but nobody told him to, and the Manage screen is a different tab. grep found no localisation of seeds and nothing in `docs/backlog.md` about it.
Suggestion (S): pass the creating device's locale into `seedDefaults` and use a small de/en seed table; for existing households offer nothing (renaming remains manual). Backlog entry for a one-time "rename defaults" prompt is optional (M).

### PP7. A new item has no category unless typed before; assigning one is long-press, sheet, chip, Save  (P3)
> "Batteries ended up at the top under 'Uncategorized'. To file it under hardware I need four taps."

What happens: the quick-add has no category or quantity control (`shopping_quick_add_row.dart:108-124`). A repeat item inherits the last category used for that name (`:270-284`), a brand-new one is uncategorized and sorts FIRST (`shopping_repository.dart:106-113`, spec `docs/specs/ui-shopping.md` layout item 2). Setting category or quantity needs the long-press-only edit sheet (`shopping_edit_sheet.dart:103-121`), which has no visible hint anywhere (grep of `app_en.arb` for long-press wording finds none; known cost accepted in the 2026-09-19 amendment).
Suggestion (S): tapping the suggestion chip already carries its category; add an optional category chip row (or a small icon button) next to the field for new names. Also +1 below on discoverability.

### PP8. Duplicate detection is exact-after-lowercasing only; renames and concurrent offline adds bypass it  (P3)
> "'Milch', 'milch' and 'Milch 1 l' all ended up on the list."

What happens:
- `normalizeShoppingItemName` only trims, lowercases and collapses whitespace (`shopping_repository.dart:63-65`). "Milk"/"milk" (Tom's own example) IS caught (`shopping_quick_add_row.dart:249-268`). "Müsli"/"Musli", "Tomate"/"Tomaten", and "Milch" vs "2 l Milch" are not.
- The edit sheet's rename calls `updateItem` with no duplicate check (`shopping_edit_sheet.dart:151-171`, `shopping_repository.dart:384-401`).
- The check reads the LOCAL database only (`findActiveByNormalizedName`, `:271-283`); if Tom and his partner both add "Eier" while one is offline, two rows sync, and `applyPulledShoppingItem` does not merge by name (`sync_repository.dart:275-281`).
- Comma-lists ("Milch, Eier, Brot") become one item with a comma-name; there is no splitting.
Suggestion (S): fold diacritics and strip a trailing plural "n/en/s/e" for comparison only, plus run the same duplicate check on rename. Comma/newline split is covered by +1 on F7.

### PP9. Text is small for arm's length  (P3)
> "I have to hold the phone close to read the quantities."

What happens: item name 15sp (`theme.dart:207-210`, `shopping_item_tile.dart:102`), quantity note 12.5sp (`theme.dart:223-226`, `shopping_item_tile.dart:112`), category header 10.5sp uppercase (`theme.dart:238-241`, `shopping_category_header.dart:55`). The app follows the OS text scale (a 2.0 smoke test exists, `docs/specs/ui-shopping.md` test 7) but has no in-app size setting, and I found no keep-screen-on (grep for wakelock finds nothing; `pubspec.yaml` has no such package), so the screen can sleep between aisles.
Suggestion (XS): raise the shopping row name to `titleMedium` (15.5sp) and the quantity to `bodyMedium` (14sp). (S): optional "Large text for lists" setting, and a keep-screen-on toggle while the Shopping tab is foregrounded.

---

## Missing features

### MF1. No way to see "what to buy where"; categories are doing double duty  (P2)
> "Supermarket, drugstore, hardware: my one list shows everything everywhere."

What happens: the only grouping axis is the household-wide category; a "Baumarkt" or "Drogerie" category would work as a store bucket but then it loses the aisle meaning, is shared with the partner, cannot be collapsed or hidden, and the default set is food only (`category_repository.dart:79-88`; "Household" is the nearest). Chores have a remembered category filter (`lib/features/chores/chores_list_screen.dart:49-63`, `last-tab-restore.md` §5) but Shopping has no filter and no remembered state besides the last tab. Several lists is the parked XL design (`docs/design/2026-08-18-famdo-features.md` 1c, backlog G-8, "no list FK" in `shopping_items`).
Suggestion: (S) tap a category header to collapse it, and a "Show only" category filter reusing the chores filter widget with the same `ui_state` storage; this gets Tom 80% of the benefit without a schema change. (XL) the parked 1c design stays the real answer.

### MF2. No "how much is left" at a glance  (P3)
> "How many things are still on my list? I only see the 'in the cart' count."

What happens: the AppBar is the title only (`shopping_list_screen.dart:141-143`), the tab icon has no badge (the only badge is Settings', `app_shell.dart:331-337`), the cart header shows bought count but nothing shows remaining count.
Suggestion (XS): subtitle in the AppBar "7 left" / "Noch 7", derived from the same stream.

### MF3. Suggestion history cannot be pruned, and the empty-focus view shows only 5  (P3)
> "A typo I once added keeps being suggested."

What happens: suggestions come from every row ever added, including soft-deleted ones, ranked by count then recency (`shopping_repository.dart:167-222`), and the empty-focus list is capped at 5 (`shopping_quick_add_row.dart:218`). There is no UI to drop a suggestion, and reason 2 of the exclusion rule hides a name only if its latest row was removed unchecked (`:253-261`). Good for staples, but typos and one-offs persist forever. Also `_historyRows` loads the entire table for every keystroke and for each of the three queries per add (`:320-336`, `shopping_quick_add_row.dart:251,272`); family-scale, so could not verify that it matters on a real phone after years of weekly shops.
Suggestion (S): long-press a suggestion chip to "Forget" it. (XS) show 8 chips when the keyboard is closed.

### MF4. Quantity cannot be entered while adding  (P3)
> "Two cartons of milk: I have to add it, then edit it."

What happens: quantity lives only in the edit sheet (`shopping_edit_sheet.dart:103-111`). Typing "2x Milch" produces a name that does not match "Milch" for dedupe or suggestions (see PP8), so staples with counts split into separate history entries.
Suggestion (S): parse a leading/trailing count ("2 Milch", "Milch x2") into `quantityNote` on submit.

---

## Quality of life

### Q1. Typed names are not capitalised and autocorrect is left at defaults  (P3)
> "My list is half 'milch' and half 'Milch'."

`TextField` in quick-add sets no `textCapitalization` (`shopping_quick_add_row.dart:108-124`), nor does the edit sheet's name field (`shopping_edit_sheet.dart:92-100`). Rows show exactly what was typed, while suggestions show the most recent casing. German nouns are capitalised; lowercase entries look wrong next to chips. Autocorrect behaviour on German words could not be verified.
Suggestion (XS): `textCapitalization: TextCapitalization.sentences` on both fields.

### Q2. German copy: natural overall, two inconsistencies  (P3)
> "Why is it 'Einkaufswagen' here but 'Erledigte' there?"

- Checked items are "Im Einkaufswagen (N)" (`app_de.arb:203`) but the button next to it is "Erledigte leeren" (`:204`, en: "Clear checked"). Mixed metaphor (cart vs done) and "leeren" reads as clearing the list. Suggest "Abgehakte entfernen" or "Einkaufswagen leeren" (`:205` "Alles zurücklegen" fits the cart metaphor).
- Dash style differs between sync messages: em dash in `app_de.arb:332` ("Nichts ist verloren — verbinde...") vs en dash in `:333`.
- The banner `app_de.arb:333` ("Dieses Gerät hat den Rest des Haushalts schon eine Weile nicht erreicht...") is stiff; "Gerade keine Verbindung zum Haushalt. Deine Änderungen sind gespeichert – zieh die Liste nach unten, um es erneut zu versuchen." is shorter. All other shopping strings I checked (`app_de.arb:191-213`) are correct du-form ("Deine Einkaufsliste konnte nicht geladen werden", "Schon auf der Liste", "Zurück auf die Liste verschoben").
- Layout: cart header is a `Wrap` so it reflows at large text (`shopping_checked_section.dart:94-98`); the tab label "Einkaufsliste" is the longest tab label in a third-width cell; could not verify truncation at large scale.

### Q3. Success of an add is silent; the new row can be out of sight  (P3)
> "I typed batteries, field cleared. Did it work?"

Success is silent by design (`shopping_quick_add_row.dart:287-300`: clear, refocus, refresh chips). Uncategorized rows sort first so usually visible, but a staple that inherits a category lands in its alphabetical slot, possibly off screen under the open keyboard; there is no scroll-to or flash. Suggestion (XS): brief highlight and scroll-into-view of the new/affected row. Related (could not verify, inferred from the stream ordering at `shopping_repository.dart:106-113` and `_Body` rebuilding from the stream): when a partner's item arrives while Tom is about to tap, the rows below shift under his thumb.

### Q4. Edit sheet saves from a stale snapshot and discards silently on swipe-away  (P3)
> "I changed the quantity and swiped the sheet down by accident. Gone."

The sheet captures the item at long-press time and, on Save, writes name, quantity and category all together (`shopping_edit_sheet.dart:151-171`), so a partner's change to another field in the meantime is overwritten (PP1 flavour, same item only). Dismissing the sheet (drag handle, tap-outside) throws edits away with no prompt. Name field has no autofocus. Suggestion (XS): leave as is, or (S) save on dismiss when the name is non-empty.

---

## What already works well

1. **Tap anywhere to tick, with a 350 ms hold so you see the tick** and a haptic; row never claims horizontal drags, so the tab pager still works over a populated list (`shopping_item_tile.dart:81-82`, `shopping_list_screen.dart:31,101-129`, regression guard `e2e/flows/shell/tab_swipe.yaml`). The write is never delayed.
2. **Duplicates handled the way Tom wants:** "Milk"/"milk" is caught, and typing something that sits in the cart un-checks it with "Moved back to the list" instead of adding a second row (`shopping_quick_add_row.dart:259-268`).
3. **Staples are one tap:** focusing an empty field shows the five most-bought names not already on the list, each carrying its last category; cleared staples stay eligible, items deleted unchecked do not (`shopping_repository.dart:154-159,253-261`, `shopping_suggestions_list.dart`).
4. **Honest, calm sync language:** never says "offline", says changes are saved, names the recourse; pull-to-refresh actually reports failure; reconnect pulls automatically and a 60s poll backs it (`docs/specs/sync-freshness.md` §2.1-2.5, `sync_health_banner.dart`). Partner additions are separate rows, so concurrent adds never conflict.
5. **Safety nets without confirmations:** delete and bulk clear both have Undo; Undo of clear restores exactly the ids cleared (`shopping_list_screen.dart:222-235,285-301`, `shopping_delete.dart:32-51`). Items checked more than 24h ago self-clear at next start (`providers.dart:825-828`).
6. **Reopens on the tab he left**, so Tom lands on Shopping at the supermarket door (`docs/specs/last-tab-restore.md` §1).

---

## Known-backlog +1 (already tracked; why it hurts Tom)

- **F7 Share-to-app / split pasted text** (`docs/backlog.md` F-2): his partner's "oat milk, sourdough" message is exactly his input; today the comma line becomes one item.
- **F8 Home-screen widget** (F-3): the supermarket entry is "unlock, find app, tap Shopping"; a widget removes two steps and shows remaining count (MF2).
- **G-8 Several lists / 1c** (`docs/design/2026-08-18-famdo-features.md`): his three stores; MF1 offers a cheap interim.
- **G-7 Search with filters** (same design doc, 1e): filter by category/store is what MF1 needs; the 1e design gates the search icon at 15 rows, which a weekly family list will exceed.
- **D-2/D-3 reversal (long-press only edit/delete)** (`docs/backlog.md` D-2/D-3, `ui-shopping.md` amendment): discoverability cost lands on Tom: nothing tells him quantity/category/delete exist (PP7). The cost was predicted and accepted; the shell swipe is fixed, which suits one-handed use.
- **Banner thresholds 5 min / 3 min** (D-5): intentional and documented; PP2 only asks for a positive "all synced" state, not for tighter thresholds.
- **No confirm on Clear/Delete** is by rule (design-language rule 3); PP5 asks only for longer Undo and Undo on Put all back.

Not done / could not verify: any on-device behaviour (keyboard overlap with chips, reflow under thumb, German truncation at large text), live two-device conflict, performance of `_historyRows` with years of history.
