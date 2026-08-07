# Future improvements

*The single backlog. Items live here once they are understood and
deliberately deferred — not dropped. Anything still being decided stays in
its feedback doc until it has a decision. Updated 2026-08-07 (post-v0.4.0).*

## Interaction / conventions

| # | Item | Source | Effort |
| --- | --- | --- | --- |
| F1 | **Swipe left/right between tabs.** The shell uses an `IndexedStack` to preserve each tab's scroll position and in-flight state; a `PageView` must keep that (per-page keep-alive), keep every `shell.tab.*` id, and keep the hand-rolled bar's semantics workaround | field feedback 2026-08-07 B3 | M |
| F2 | **Swipe-to-delete on shopping items, with undo.** Swipe without undo is worse than no swipe, so the two ship together | conventions audit C2 + C10 | S |
| F3 | **Long-press context menu on shopping items** — chores have one, shopping does not | conventions audit C5 | S |
| F4 | **Re-tap a tab to scroll its list to top** | conventions audit C6 | S |
| F5 | **Offline / can't-reach-server indicator.** A linked device that cannot reach Supabase currently looks identical to a healthy one | conventions audit C9 | M |

## Platform integration (each needs a decision before starting)

| # | Item | Why it matters | Effort |
| --- | --- | --- | --- |
| F6 | **Notification actions** — mark a chore done straight from the daily digest. Needs a background isolate handler and its own tests | strong fit for a chores app | M |
| F7 | **Share-to-app** — "add to shopping list" from any app's share sheet | would change how the shopping half feels day to day | L |
| F8 | **Home-screen widget** for the shopping list | same | XL |

## Household lifecycle (the P4 cluster)

| # | Item | Notes |
| --- | --- | --- |
| F9 | **Leave a household** (as distinct from Disconnect, which only unlinks this device) | server-side membership change |
| F10 | **Remove a claimed member** — today only unclaimed profiles can be deleted | needs a rule for their history |
| F11 | **Delete account** (GDPR erasure) — spec'd in `sync-backend.md` §2 as `delete_account()` + an edge function; no UI yet | |
| F12 | **Restore from a backup file** — export exists, import does not | |
| F13 | **Orphan household cleanup** — households whose last claimed member left | server-side |

## Product

| # | Item | Notes |
| --- | --- | --- |
| F14 | **Repeat-form structural redesign** (G3 stage 2) — the wording was fixed, the structure was not | |
| F15 | **Custom avatars** (photo or colour-as-border) | user request, round 1 |
| F16 | **Finer-grained notifications** (N2: per-chore reminders, evening re-reminder) | |
| F17 | **More category icons and colours** | user request, round 1 |
| F18 | **Search in long lists** — low value at family scale | conventions audit C14 |
| F19 | **Stats — "who actually does the chores"** | from DESIGN.md backlog |
| F20 | **Multiple shopping lists** | from DESIGN.md backlog |

## Distribution

| # | Item | Notes |
| --- | --- | --- |
| F21 | **F-Droid / IzzyOnDroid submission** — metadata exists under `fastlane/`; v0.4.0 is a suitable candidate build | awaiting Igor's go-ahead |
| F22 | **Tip-jar IAP** — needs store accounts, paid-apps agreements, tax/banking | user-side prerequisites |

## Known trade-offs (deliberate, revisit only with evidence)

- **Last-push-wins conflict resolution.** Two devices editing the same row:
  the later push wins, even if the other edit was newer in real time. A
  documented family-scale trade-off (`sync-backend.md` §3). It gets worse
  the longer a device stays signed out — which is why the signed-out state
  now says so out loud (field feedback 2026-08-07 A1).
- **No background sync while the app is closed.** Needs platform
  background-task work and a battery story (`sync-freshness.md` §3).
- **`chore_assignees` has no tombstones**, so a removed assignee does not
  replicate as a deletion (`sync-backend.md` §8.5).
