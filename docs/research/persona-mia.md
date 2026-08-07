# Persona walkthrough: Mia, in the shop, one hand, bad signal

*Read-only research. No files under `lib/`, `test/`, or config were changed.
Every claim below cites `path:line`; anything I couldn't confirm from source
is marked "unverified" rather than guessed.*

## Who Mia is, and what she's optimizing for

Mia shops one-handed — phone in her right hand, basket in her left — on
flaky signal, in a hurry, while her partner edits the same list from home.
She needs the list to be true *right now*, needs checks to register
instantly and forgive mis-taps, needs everything to keep working with no
signal and catch up silently, and needs to know whether what she's looking
at is current without ever thinking about "sync." She lives entirely in the
Shopping tab and reaches only where a right thumb naturally falls.

## Surface-by-surface

### Quick-add

| Interaction | Mia expects | Actually happens (source) | Verdict |
|---|---|---|---|
| Type + submit | Item appears under the right category instantly, field clears, keyboard stays up for the next one | `_addOrRestore` inserts, clears `_controller`, calls `_focusNode.requestFocus()` (`lib/features/shopping/shopping_quick_add_row.dart:279-291`); matches spec `docs/specs/ui-shopping.md` item 1 | OK |
| Empty submit | Nothing happens, no error | `_addOrRestore` returns immediately if `name.isEmpty` (`shopping_quick_add_row.dart:244-246`) | OK |
| Keyboard covering the list while typing | She can still see enough of the list to know what's already there | Quick-add row is a fixed `Column` child above `Expanded` (`lib/features/shopping/shopping_list_screen.dart:61-64`); default `resizeToAvoidBottomInset` shrinks the `Expanded` list, so the input row itself is never covered, but visible list rows shrink to whatever room is left above the keyboard | OK — the row itself is never hidden, but this wasn't verified visually (no build/run performed) |
| Typing fast while walking | Suggestions feel instant | `_onTextChanged` calls `_updateSuggestions()` on **every keystroke**, with no debounce (`shopping_quick_add_row.dart:185-187`); each call does a full, unfiltered scan of every history row ever created for the household, active or soft-deleted, with no `LIMIT` (`lib/data/repositories/shopping_repository.dart:167-177, 320-336`) | LIMIT (undocumented) — cheap at today's "family scale" (`docs/specs/sync-backend.md:88`), but nothing bounds it as history grows; not measured, so impact is inferred, not proven |

### Suggestions & their ranking

| Interaction | Mia expects | Actually happens (source) | Verdict |
|---|---|---|---|
| Focus the empty field | Top-5 "usual buys" | `suggestions(householdId, '', limit: 5)` on focus/tap (`shopping_quick_add_row.dart:207-225`), ranked frequency-then-recency (`shopping_repository.dart:167-222`) | OK |
| Tap a suggestion | Adds immediately with its own category, list re-ranks cleanly | `_selectSuggestion` → `_addOrRestore(..., isSuggestionTap: true)` (`shopping_quick_add_row.dart:229-235`); each chip is `key: ValueKey(suggestion.name)` (`lib/features/shopping/shopping_suggestions_list.dart:53`) — this is the C3 fix (field feedback 2026-08-07) confirmed live in code, so the "wrong chip gets the tap animation" bug is actually gone | OK |
| Return to the tab mid-typing, keep scrolling | Suggestions get out of her way while she works the list | Dismissed on tab-tap tile, on check/uncheck, and on a genuine drag scroll (`ScrollStartNotification` with non-null `dragDetails`) (`shopping_list_screen.dart:73-104`) — this is the Round 2 Bug 3 fix, confirmed live | OK |
| Explicitly-deleted item never comes back; a bought-then-cleared staple does | Matches | `_namesToExcludeFromFocusSuggestions` implements exactly this rule (`shopping_repository.dart:224-263`) — Round 2 Bug 1 fix, confirmed live | OK |

### Duplicate prevention (B3)

| Interaction | Mia expects | Actually happens (source) | Verdict |
|---|---|---|---|
| Re-add an unchecked item already on the list | No new row, told so | `findActiveByNormalizedName` finds it, snackbar `shoppingAddAlreadyOnList` (`shopping_quick_add_row.dart:259-262`) | OK |
| Re-add a checked item | Restored to the list instead of duplicated | `setChecked(..., checked: false)` + snackbar `shoppingAddMovedBack` (`shopping_quick_add_row.dart:263-268`) | OK |
| Duplicate check is scoped **only to this device's local database** | — | `findActiveByNormalizedName` reads `_historyRows`, a plain local `db.select` (`shopping_repository.dart:271-283, 320-336`) — no server round trip. See "Conflicts" below for the cross-device consequence | SURPRISE (traced under Conflicts) |

### Grouping / aisles

| Interaction | Mia expects | Actually happens (source) | Verdict |
|---|---|---|---|
| Items grouped by category run, in repository order, uncategorized first | Matches | `watchActiveItems` orders unchecked-first, then `sort_order`, then name (`shopping_repository.dart:92-124`); `_groupedTiles` walks that order without re-sorting (`shopping_list_screen.dart:238-254`) | OK |
| Checking the last item in a category run | The header disappears cleanly | Same mechanism as below — instant, no transition | See "list reflow" below |

### The check control, its tap target, and mis-tap recovery

| Interaction | Mia expects | Actually happens (source) | Verdict |
|---|---|---|---|
| Tap target size | Big enough for a rushed, one-handed tap | `_CheckRing` is a 23dp ring inside a 48dp `SizedBox` (Material's minimum) (`lib/features/shopping/shopping_item_tile.dart:112-134`) | OK |
| Tapping the ring vs. tapping the row | Ring toggles check; anywhere else opens the edit sheet, not both | Ring wraps its own nested `InkWell`/`onTap` inside the row's outer `InkWell` (`shopping_item_tile.dart:53-65, 126-140`). By Flutter's default gesture-arena resolution, the innermost recognizer wins a plain tap, so the outer row's `onTap` (edit sheet) does not also fire — inferred from the widget structure and Flutter's documented tap-disambiguation, not confirmed by running the app | OK (inferred, not runtime-verified) |
| Instant write-through, no confirm | Matches — spec says optimistic UI is unnecessary since local writes are fast | `setChecked` writes immediately (`shopping_repository.dart:404-415`); haptic fires once write is confirmed (`shopping_list_screen.dart:139-152`) | OK |
| Mis-tap → tap again to undo | Works, but the list itself has already reflowed under her finger by the time she taps again | Checking an item removes it from the unchecked list on the very next frame (no animation — `ListView(children: children)`, a plain rebuild, `shopping_list_screen.dart:224-231`; consistent with the "no animations beyond defaults" rule, `docs/specs/ui-shopping.md:62`) — every row below the tapped one, and the whole category header if it was the run's last item, shifts up instantly | SURPRISE (inferred from code + design-language's no-animation rule; the actual mis-tap-on-reflow rate under rapid tapping was not runtime-verified) |

### Cart section, clear, put-all-back

| Interaction | Mia expects | Actually happens (source) | Verdict |
|---|---|---|---|
| Section stays open while she works inside it | Matches — this was a real, fixed bug (G1) | `_cartExpanded` is hoisted to `_ShoppingListScreenState` and fed back as `initiallyExpanded` on every rebuild (`shopping_list_screen.dart:33-46`, `shopping_checked_section.dart:20-37, 92`) | OK |
| "Put all back" for a bulk failed-checkout scenario | Exists | `onUncheckAll` → `ShoppingRepository.uncheckAll` (`shopping_list_screen.dart:159-162`, `shopping_repository.dart:469-490`) — the G1 fix, confirmed live | OK |
| "Clear checked" — no confirm dialog (per spec B4) | Matches — a confirm here would be the wrong friction | No dialog; `onClear` soft-deletes immediately (`shopping_list_screen.dart:154-157`, `shopping_repository.dart:451-467`) | OK |
| "Clear checked" mis-tap → some way back | She'd expect *some* undo, since deleting one item does get one | **No undo at all.** `_clearChecked`/`clearChecked` has no snackbar, no action (`shopping_list_screen.dart:154-157`); compare to the single-item delete flow, which shows an UNDO snackbar (`lib/features/shopping/shopping_edit_sheet.dart:186-195`). Recovery is only indirect: a cleared item stays eligible for focus-suggestions (since it was checked, not deleted-while-unchecked — `shopping_repository.dart:154-159, 224-263`), so she'd have to know to re-focus the field and tap it back, once per item, from memory | SURPRISE |
| "Put all back" and "Clear checked" are next to each other | Distinct enough not to mix up under a rushed tap | Both are plain `TextButton`s in the same `Wrap` right next to the header text (`shopping_checked_section.dart:98-121`) — no icon, spacing, or color differentiates a merely-inconvenient action from a bulk-destructive one | REACH / SURPRISE (see reachability section) |

### Edit sheet

| Interaction | Mia expects | Actually happens (source) | Verdict |
|---|---|---|---|
| Prefill, rename, quantity, category, save | Matches | `_ShoppingEditSheetState.initState`/`_save` (`lib/features/shopping/shopping_edit_sheet.dart:47-54, 153-173`) | OK |
| Empty-name error + recovery | Matches | `validateItemName` (`lib/features/shopping/shopping_edit_validation.dart:19-21`), inline error shown, no data lost | OK |
| Delete, no confirm | Matches (cheap, low-stakes per design-language) | `_delete` soft-deletes immediately (`shopping_edit_sheet.dart:175-196`) | OK |
| Delete → undo | Exists, and better than clear-checked's | Snackbar with an UNDO action calling `restoreItem` (`shopping_edit_sheet.dart:186-195`, `shopping_repository.dart:439-449`) | OK |

### Empty states

| Interaction | Mia expects | Actually happens (source) | Verdict |
|---|---|---|---|
| Fresh/all-checked list | Friendly empty message, quick-add stays | `_EmptyMessage` + `semantic('shopping.empty')` (`shopping_list_screen.dart:306-350`); quick-add row is a sibling, always rendered | OK |
| Pull-to-refresh must work even on an empty list | Not a dead/no-op affordance | Empty state is wrapped in a `CustomScrollView`/`SliverFillRemaining` specifically so `RefreshIndicator` still has a `Scrollable` (`shopping_list_screen.dart:283-304`) | OK |

## Liveness (traced in full below, "Worst-case staleness")

## Offline

| Interaction | Mia expects | Actually happens (source) | Verdict |
|---|---|---|---|
| Check items with no signal | Works, no error, no visible difference | Every write is a local Drift/SQLite write, always synchronous to the UI regardless of network (`shopping_repository.dart:404-415`); `syncDirty` set unconditionally, even offline (spec `docs/specs/sync-backend.md:326-328`) | OK |
| Signal returns, queued checks push automatically | She expects this to "just happen," soon | It happens, but **only when re-triggered** by a local write, an app resume, or a realtime resubscribe tick — see finding below; there is no periodic push-retry timer, only a periodic *pull* timer (`lib/application/sync_engine.dart:290-301` pulls only; pushes are armed solely by `db.tableUpdates()`, `sync_engine.dart:233-245`, and by app resume, `lib/app/providers.dart:937-939`) | SURPRISE |
| App tells her something failed while offline | She doesn't expect an error (this is meant to be invisible) but also doesn't expect *false reassurance* | Every engine failure (push or pull) is caught and silently logged, never surfaced (`sync_engine.dart:319-327, 408-412`, spec `docs/specs/sync-backend.md:369-371` — deliberate policy). Pull-to-refresh, however, is specified to break this silence with a failure snackbar (`docs/specs/sync-freshness.md:90-91`) — see Top Findings #1 for why that doesn't actually happen | BUG (spec vs. code mismatch) |
| App killed by the OS while in her pocket | No data loss | All writes are already durable in SQLite; on relaunch `SupabaseSyncEngine.start()` calls `pushDirty()` immediately, explicitly documented as recovering "rows left dirty from a prior session that never got pushed" (`sync_engine.dart:254-260`) | OK |

## Conflicts

| Scenario | Traced outcome (source) | Verdict |
|---|---|---|
| She checks "milk"; partner deletes it (same row, different field) elsewhere at the same time | Push is a **full-row upsert**, not a per-field patch (`lib/data/sync/row_mappers.dart:196-207`, used by `_pushShoppingItems`, `sync_engine.dart:539-550`). Whichever device's push lands on the server LAST wins the *entire* row. If her check reaches the server after the partner's delete, the item comes back for both of them with no signal to either party that a delete was reverted. Locally, `applyPulledShoppingItem` (`lib/data/repositories/sync_repository.dart:237-244`) keeps her dirty local row over an incoming pulled delete — so as long as her row stays dirty, her phone won't even show his delete; only after her own push clears the flag and a later pull runs does her phone see whatever the server currently has | SURPRISE — this is the documented last-push-wins trade-off (`docs/future-improvements.md:56-59`) applied to a specific, higher-stakes pairing (check vs. delete) that the trade-off note doesn't call out by name |
| She adds "bread"; partner adds "Bread" at the same time, both offline or both not yet synced to each other | `findActiveByNormalizedName`'s duplicate check is a **local-only** query (`shopping_repository.dart:271-283`) — neither device can see the other's not-yet-synced row. Both inserts succeed, get distinct ids, and both push successfully (`_pushShoppingItems`, `sync_engine.dart:539-550`, a plain per-id upsert, no name-based conflict target). Nothing in the pull-apply path merges by normalized name either. Result: two permanent, separate "bread" rows survive on both phones after both sync — B3's dedup never runs across devices, only within one | SURPRISE — genuinely different angle from the logged last-push-wins trade-off: this isn't a lost edit, it's a duplicate that nothing will ever clean up automatically |
| Both check the same item at nearly the same moment (same field, same semantic outcome) | Same last-push-wins full-row race as above, but since `checkedAt` non-null either way reads as "checked" to both users, the tiny timestamp difference is invisible in the UI | OK — benign in practice |

## Worst-case staleness

Concrete trace of the longest realistic gap between "partner adds coffee at
home" and "Mia sees it," given the current triggers. Assumptions: she's
standing in the aisle with the app open and foregrounded (not backgrounded),
signed in, linked household.

**Best case (realtime healthy):** partner's insert lands on the server →
Postgres broadcasts a `postgres_changes` event → her `RealtimeChannel`
delivers it → `notify()` fires → the engine's realtime listener calls
`pullSince()` (`lib/application/sync_engine.dart:252-254, 639-643`) — typically
sub-second, bounded by network round trip.

**Worst case (the actual field-reported scenario, `docs/specs/sync-freshness.md:35-37`):**
her socket quietly died (Wi-Fi→cell handover exactly when she walked into
the store is the textbook trigger named in the spec) and hasn't
resubscribed yet at the moment the write happens.

1. T+0s — partner's write lands on the server; broadcast to a dead socket
   reaches nobody.
2. Nothing pulls until the FIRST of:
   - the channel auto-reconnects and re-subscribes, which emits a
     `subscribed` tick that itself triggers `pullSince()`
     (`sync_engine.dart:692-698`) — timing is entirely up to the Supabase
     client's own retry/backoff and her phone's radio, not bounded by any
     app code, so in principle this could take anywhere from ~1s to well
     over a minute on a bad connection;
   - the foreground safety-net poll, `Timer.periodic(pollInterval)` with
     `pollInterval` defaulting to 60 seconds (`sync_engine.dart:193,
     213-216, 294-301`), armed independently of realtime health — if the
     write happens right after a tick, the next one is up to **60 seconds**
     away;
   - she locks/unlocks her phone or backgrounds/foregrounds the app, which
     fires `SyncEngineController.triggerOnResume()` → `pushDirty()` → pull
     (`lib/main.dart:83-91`, `lib/app/providers.dart:937-939`) — immediate,
     but requires an incidental lifecycle event she has no reason to
     trigger deliberately;
   - she pulls-to-refresh herself (`lib/features/shopping/shopping_list_screen.dart:110-125`)
     — immediate if she thinks to do it (and if it's actually reachable
     given Top Finding #1 below).
3. **Bound, assuming she just keeps standing there with the screen on and
   doesn't touch anything:** the 60-second poll is the true backstop, so
   the worst realistic wait — while basic connectivity exists but realtime
   specifically is degraded — is just under **60 seconds**.
4. **If she's genuinely offline** (airplane mode / dead zone, not just a
   degraded socket), the poll's own `pullSince()` call fails too and is
   silently swallowed (`sync_engine.dart:408-412`) — at that point staleness
   is not time-bounded at all; it waits for real connectivity to return
   *and* one of the triggers above to fire again afterward. There is no
   connectivity-change listener anywhere in the app (`connectivity`/
   `internet_connection` packages: zero hits in `pubspec.yaml` and `lib/`)
   — recovery is entirely incidental to whatever she or the OS does next.

## One-handed reachability

Every control Mia might need mid-shop, and whether a right thumb on a 6.7"
phone reaches it one-handed without a grip shift.

| Control | Position in layout | Reach |
|---|---|---|
| Quick-add text field + submit button | Pinned `Column` child directly under the `AppBar`, top of screen (`shopping_list_screen.dart:61-63`, `shopping_quick_add_row.dart:81-175`) | REACH — near-top, a stretch on a large phone; the submit button sits at the row's right edge, marginally easier via an edge-slide than a dead-center top target |
| Focus-suggestion / type-ahead chips | Rendered immediately below the quick-add row (`shopping_quick_add_row.dart:176-181`) | REACH — same top band as the input |
| Category header | Not interactive | N/A |
| Check ring (per item) | Wherever its row scrolls to; the very first unchecked row sits just under the quick-add row | REACH for the top-most row, OK once scrolled past it — and this is the control she uses most, all trip |
| Row tap → edit sheet | Same position as the check ring | Same as above |
| "In the cart" header (expand/collapse) | Wherever it scrolls to — typically lower in the list, since it follows all unchecked items | OK |
| "Put all back" / "Clear checked" | Inside the cart header row, two small adjacent `TextButton`s (`shopping_checked_section.dart:106-119`) | OK for vertical position once scrolled there, but a precision risk: two visually-similar small targets side by side, one merely inconvenient and one bulk-destructive, with no color/icon separation |
| Edit sheet Save / Delete | Bottom of a modal sheet, `Save` (FilledButton, right) / `Delete` (TextButton, left) (`shopping_edit_sheet.dart:126-147`) | REACH — bottom-of-screen is the easiest one-handed zone on any phone |
| Pull-to-refresh | A drag gesture starting from wherever the list's current top edge is, not a fixed tap target (`shopping_list_screen.dart:117-125`) | OK — doesn't have the fixed-corner problem, but needs the list scrolled to its top first |
| Bottom tab bar | Bottom of screen (`lib/app/app_shell.dart`) | REACH — though she says she'd rather never need it |
| AppBar | Title only, no action icons for the Shopping tab (`shopping_list_screen.dart:57-60`) | N/A — nothing lives in the unreachable top corners here, which is a quiet correctness: unlike the Chores tab's filter icons, Shopping has nothing up there to miss |

## Interruptions

- **Phone call / brief background:** `AppLifecycleState` moves away from
  `resumed`; the engine's `pauseBackgroundWork()` only cancels the 60s poll
  — the write-listener and realtime subscription stay armed at the OS's
  discretion (`sync_engine.dart:277-282`, `lib/main.dart:93-98`). Local
  writes are unaffected either way (SQLite doesn't care about app
  lifecycle). On return, `resumed` fires an immediate push+pull
  (`main.dart:83-91`). An open edit sheet / scroll position survive a call
  through ordinary Flutter navigation/state persistence — not
  shopping-specific, not independently verified by running the app.
- **10-minute background:** poll paused the whole time (no wasted network
  wakeups, `sync-freshness.md §2.2` intent, confirmed above); on resume, one
  immediate push+pull catches her up in one round trip rather than 10
  missed poll ticks.
- **OS kill while backgrounded:** see Offline table above — no data loss,
  `start()`'s own `pushDirty()` recovers anything left dirty
  (`sync_engine.dart:254-260`).
- **Notifications:** the only notification in the app is the once-daily
  digest, defaulting to 08:00 local time (`digestMinutes` default `480`,
  `lib/data/db/tables.dart:210`) — there is no per-chore or shopping-related
  notification (finer-grained notifications are backlog item F16,
  `docs/future-improvements.md:41`). In practice this almost never
  interrupts a shopping trip unless she happens to shop right at her
  configured digest time. OK, not a gap for this persona today.

## Top findings

Ranked by how much they cost someone actually standing in an aisle.

1. **Pull-to-refresh gives false reassurance when it fails.** Spec
   `docs/specs/sync-freshness.md:90-91` requires refresh failure to surface
   "a snackbar with the existing sync-error copy." But the refresh handler
   is a bare `() => ref.read(syncEngineProvider).pushDirty()`
   (`shopping_list_screen.dart:122`, identically in
   `lib/features/chores/chores_list_screen.dart:141`), and `pushDirty()`
   catches every error internally and always completes normally
   (`sync_engine.dart:308-330`) — it can never propagate a failure to the
   `RefreshIndicator`. There is also no "sync error" copy anywhere in
   `lib/l10n/app_en.arb`/`app_de.arb` to show even if it could. The one
   affordance Mia has to force a freshness check — pull down, watch it spin,
   watch it stop — looks identical whether it worked or she's fully
   offline. This directly undermines her single biggest stated need: "know
   whether what I'm looking at is current, without thinking about sync."
2. **The 60-second poll bound is real, and it's a pull-only bound.** Traced
   in full above: when realtime is degraded (the exact "walked into the
   store" scenario the freshness spec was written for), up to 60 seconds
   can pass before she sees her partner's addition, even with the app open
   and on-screen the entire time.
3. **Push has no periodic retry at all — only pull does.** `_armPoll` calls
   `pullSince()` on a timer; nothing calls `pushDirty()` on a timer
   (`sync_engine.dart:290-301`). A push only fires from a fresh local write,
   an app resume, or the initial `start()`. If she checks an item right as
   connectivity drops and then goes quiet (stops touching the phone) before
   it returns, that check can sit unpushed indefinitely — recovered only by
   her next tap, or by locking/unlocking her phone. In practice her own
   continued shopping activity usually re-arms it, but the mechanism itself
   has no independent backstop the way pulls do.
4. **Checking an item while it's deleted elsewhere can resurrect it, with
   no signal to anyone.** Full-row upsert + last-push-wins
   (`row_mappers.dart:196-207`, `sync_repository.dart:237-244`) means a
   check that pushes after a delete un-deletes the item for both parties.
   This is the documented last-push-wins trade-off, but applied to a
   specific pairing (delete vs. check) worth naming: a delete looking
   "gone" is not actually safe from being silently reversed by someone
   else's concurrent, unrelated action.
5. **Two devices can each add the same name and get two permanent
   duplicates.** B3's duplicate prevention is a local-only query
   (`shopping_repository.dart:271-283`); nothing in push or pull dedupes by
   normalized name across devices. "Bread" from her partner and "bread"
   from Mia, added minutes apart before either has synced, is not a
   conflict the app ever resolves — it's two rows, forever, until a human
   notices and deletes one.
6. **"Clear checked" has no undo; single-item delete does.** Comparing
   `shopping_edit_sheet.dart:186-195` (delete → snackbar with UNDO) against
   `shopping_list_screen.dart:154-157`/`shopping_repository.dart:451-467`
   (clear → nothing) shows an inconsistent safety net on exactly the action
   with the biggest blast radius — and it sits in a `Wrap` right next to
   "Put all back," another small `TextButton` with no visual distinction
   (`shopping_checked_section.dart:106-119`). A rushed one-handed tap in the
   wrong spot loses the whole cart with only an indirect, per-item,
   remember-the-name recovery path.
7. **"Last synced" — the one honest freshness cue that exists — isn't in
   the Shopping tab.** It lives in Settings → Account
   (`lib/features/settings/account_section.dart:95-145`), several taps and
   a tab switch away from where Mia explicitly says she never wants to be
   sent. This is the same underlying gap as the already-logged C9/F5
   offline-indicator item (`docs/future-improvements.md:15`), but the
   persona-specific twist is concrete: the fix already exists in the
   codebase, it's just unreachable from the one tab she lives in.
8. **List reflow with no animation is a plausible mis-tap trap.** Checking
   an item removes its row from the unchecked list on the next rebuild with
   no transition (`shopping_list_screen.dart:224-231`, consistent with the
   deliberate no-custom-animation rule). Rows below shift up instantly;
   rapid one-handed tapping down a list risks the second tap landing on
   whatever slid into that position. Inferred from the code and the
   project's own design-language rule, not confirmed by interacting with a
   running build.
9. **No swipe-to-delete or long-press on shopping items** (already logged
   as F2/F3, `docs/future-improvements.md:12-13`). Worth restating the
   persona-specific cost: for Mia, removing an "actually don't need this"
   item means opening a full bottom sheet (tap → sheet renders → tap
   Delete) instead of one one-handed swipe — a proportionally bigger tax on
   someone shopping fast than on someone browsing at leisure.
10. **Suggestion queries are unbounded and undebounced.** Every keystroke
    triggers a full scan of the household's entire shopping history, active
    and soft-deleted, with no `LIMIT` (`shopping_repository.dart:167-177,
    320-336`) and no debounce on the text listener
    (`shopping_quick_add_row.dart:185-187`). Harmless at today's
    "family-scale" row counts the whole sync design assumes
    (`docs/specs/sync-backend.md:88`), but nothing bounds it as a
    household's history grows over years — exactly where "in a hurry"
    typing needs to stay instant. Flagged as an architectural gap, not a
    measured slowdown.

## What she'd tell a friend

"It's genuinely fast and forgiving one-handed — I check things off without
looking, it works with no signal, and nothing I do locally ever gets lost.
But I don't fully trust that what's on my screen right now is what's really
on the list, and the one button that's supposed to prove it — pull to
refresh — will happily spin and stop even when it did nothing at all."
