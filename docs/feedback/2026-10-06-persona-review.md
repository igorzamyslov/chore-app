# Persona review + technical review — 2026-10-06 (v0.14.0+21)

Five independent read-only reviews of the app as it ships, consolidated.
Four were persona walkthroughs (each reviewer reconstructed every screen
and string from `lib/l10n/app_en.arb`, the feature code, the specs and the
E2E flows, and traced the code path for each step); the fifth was a
technical review of sync, data integrity, robustness and CI. Nothing was
run on a device, so visual/density claims are marked as unverified in the
raw reports. The orchestrator re-verified every P1 and the technical P2s
against the source before they were carried here.

Raw reports with full traces and all `path:line` evidence are in
[`2026-10-06-personas/`](2026-10-06-personas/):
`maria-admin.md` (household organiser), `leon-teen.md` (reluctant 14-year-old
joiner), `tom-shopping.md` (shopper, German UI, poor reception),
`priya-privacy.md` (privacy-minded flat-share power user, a11y) and
`technical-review.md`.

**No decisions are taken in this document.** Unlike the 2026-08-01 round, the
right column is a proposal, not a verdict — Igor decides. Items already in
`docs/backlog.md` / `docs/future-improvements.md` are not re-listed as new;
they appear in §9 as "+1" with the persona-specific cost.

Priority = impact on a family actually using the app. Effort XS/S/M/L as in
`docs/backlog.md`.

## 0. Headline

Three findings would each, on their own, justify a patch release:

1. **A hard-delete tombstone can erase a completion another phone already
   synced** (A1). Edit/pause/delete a chore on phone B while phone A
   completed its pending occurrence → the server row and A's `done` row are
   both deleted. History silently lost.
2. **Every server read is capped at 1,000 rows and nothing pages** (A2). A
   second phone joining a household with a year of history gets a truncated
   snapshot, the cursor advances past the gap, and the newest rows (the
   current pending occurrences) are the ones dropped.
3. **Editing who a chore is assigned to does not change the open turn**
   (C1). The organiser's most common maintenance action — "Anna is ill, take
   her off the bins" — visibly does nothing, and nothing says so.

Behind those, two clusters recur across all four personas: **the app's
honesty about its own state** (what left the phone, whether a push actually
landed, what "removed from the server" really does, error snackbars that
look like success), and **the joiner's first ten minutes** (welcome screen
steers to "create", sign-in before the code, one-tap claim, no household
name, no install link).

## 1. Matrix

| ID | Item | Who hit it | Prio | Effort | Proposal |
|----|------|-----------|------|--------|----------|
| A1 | Occurrence tombstone matches on `id` only → deletes a completed row on server and on the other device | tech | **P1** | S | Guard `markDeleted` and `applyPulledOccurrenceDeletion` with `status = pending`; add the race as an engine test |
| A2 | No paging anywhere; PostgREST `max_rows` 1000 truncates join/download and the first pull, cursor skips the rest forever | tech | **P1** | S | `.order('updated_at').range()` loop in `downloadHousehold` and `pullTable`; `test_live` case with 1,001 rows |
| C1 | Changing assignee/rotation leaves today's turn with the old person; UI silent | Maria | **P1** | S | Re-resolve the open occurrence when its holder is no longer a valid assignee (helper exists), or at least a snackbar offering to reassign |
| B1 | PRIVACY.md wrong in four places (no crash reporting; account deletion "not shipped"; "complete list" omits categories, id linkage, archive files; no region/operator) | Priya | **P1** | S | One editing pass; also fix stale F11 row in future-improvements |
| B2 | Last-member Leave / Delete account says "the shared copy and its history are removed from the server"; RPC only soft-deletes `households`, children stay, no purge job | Priya | **P1** | S copy / M purge | Reword to "hidden and scheduled for deletion" + pg_cron hard-delete N days after `deleted_at` |
| B3 | "Saved to a backup file on this device" → app-private dir, unreachable, overwritten by a same-day join, survives Reset app data, no importer | Priya | **P1** | M | Offer the share sheet after archiving; delete archives on reset; until an importer exists reword to "a copy is kept inside the app" |
| A3 | `_pushAll` is all-or-nothing: one rejected row blocks every later table forever; "Last synced" reads the pull cursor so Settings says "just now" | tech, Maria, Priya | P2 | S | Per-table try/continue + row quarantine via `AppLog`; append "N changes waiting to send" to the Settings line; tap = `refreshNow()` |
| A4 | Ghost-repair survivor key mixes device (`…Z`) and server (`…+00:00`) stamps; concurrent catch-up on two phones can tombstone both pending rows → chore vanishes | tech | P2 | S | Survivor key `dueDate desc, id desc`; normalise timestamps at the boundary; later deterministic occurrence ids |
| A5 | `pendingOccurrenceOf` uses `getSingleOrNull` → two pending rows throw inside bootstrap → startup error screen | tech | P2 | XS | Order + `limit(1)`; run ghost repair before catch-up |
| A6 | Pull-cursor race: `now()` is transaction start, a push that began before `server_now()` and committed after the read is below the cursor forever | tech | P2 | XS | Store `serverNow − 30 s` as cursor (apply is idempotent) |
| A7 | Sync-health banner compares server cursor with device clock; a phone 5 min ahead shows the outage banner permanently | tech | P2 | XS | Stamp a device-clock `lastPullCompletedAt` and feed that to `computeSyncHealth` |
| A8 | Dirty local chore + pulled assignee rows merge into a union with duplicate `position`s → rotation order differs per device | tech | P2 | S | Treat the assignee set as one LWW value with the chore row; tie-break by `memberId` |
| A9 | Whole-row last-push-wins: offline "Clear checked" pushed later erases partner's re-add; same for tick/untick | Tom, Priya, Leon | P2 (+1 on known trade-off) | S–M | Field-level rule for `checked_at`/`deleted_at` (server value wins when newer), or `client_updated_at` on push |
| B4 | Two strings send users to "Settings → Account", which no longer exists (also DE) | Priya | P2 | XS | "Settings → Household" |
| B5 | Sign-out / paused-sync copy omits that re-login overwrites newer remote edits (2026-08-07 A1 promised it would say so) | Priya | P2 | XS | Add one sentence |
| B6 | "Put my household online" uploads everything on one tap; subtitle says only "other devices" | Priya, Maria | P2 | XS–S | One confirm sheet: what goes up, where, how to undo; reword subtitle to mention inviting family |
| B7 | Every snackbar, including all error paths, shows a green check for 4 s | Priya, Leon | P2 | XS–S | `showAppError` variant: error icon, longer/persistent, optional Retry |
| B8 | Error reports default-on, not in the sign-in disclosure; pre-sign-in buffer uploads on first link; no way to view the queue | Priya | P2 | S | One line + inline switch under the sign-in intro; later a read-only pending list |
| B9 | Reminder row says "Remind me…" / "won't be counted in the daily summary"; it actually rings the assignee's phone only, and the chore returns as overdue next day | Maria, Leon | P2 | XS copy | "Reminds whoever is assigned, on their phone" |
| C2 | No way to hand today's turn to someone else; Skip sticks to the same person, Pause has no resume date | Maria | P2 | M (S for reassign only) | "Reassign this turn…" row writing `assigned_member_id` on the pending occurrence; optional "Pause until" |
| C3 | Tapping a chore tile does nothing (`onLongPress` only); shopping rows open on tap → inconsistent, undiscoverable | Maria, Leon, Priya | P2 | XS–S | `onTap` opens the action sheet or a read-only detail sheet (full note, rule, history) |
| C4 | Paused chores can be neither edited nor deleted without resuming first | Maria | P2 | S | Same action sheet on paused rows |
| C5 | In a local household the app-bar acting-member switcher also re-scopes digest and reminders; "Done" snackbar never names who got credit; "Mark done for…" only when linked | Maria | P2 | S | Offer "Mark done for…" locally too; sheet copy "Credit and your daily summary follow this person" |
| D1 | Welcome screen raises "Set up a new household" and demotes "Join"; a joiner holding a code lands in a solo household, exit is "replaces your local data" | Leon | P2 | S | Symmetric cards, or an "Enter invite code" entry on the welcome screen |
| D2 | Sign-in before the code, magic link only, no OTP fallback, no expired-link handling, one generic send-failure message (also for rate limit), no resend cooldown; join-page handler swallows errors without `AppLog` | Leon, Priya | P2 | M | Code first (needs server change) or at least the policy paragraph below the button + "open on this phone"; OTP fallback; map `AuthException`; 60 s cooldown |
| D3 | "Are you {name}?" claims on one tap, no confirm, household name never shown; "I'm new here" duplicates a pre-created profile | Leon, Maria | P2 | S | Confirm line "Join {household} as {name}?", show household name, hint in the invite sheet "add everyone under Members first" |
| D4 | Members list is avatar + name: no "you", no "has joined", no "no phone", no "moved out" | Maria, Priya | P2 | S | Subtitle per row from `userId` state |
| D5 | Each Invite silently revokes the code already shared; no way to re-show the active code; no expiry date shown; every `PostgrestException` on join reads as "typo" | Maria, Priya | P2 | S | Re-display active code until expiry; confirm before revoking; distinguish invalid/expired from outage |
| D6 | In a local household Members has no Invite row; the path is Account intro ("devices") → "Put my household online" | Maria | P2 | S | Disabled Invite row with "Sign in first to invite your family" |
| D7 | Invite share text has no install link or store name | Leon | P2 | S | Append a landing/release URL |
| D8 | A member who leaves stays in every rotation; nobody is told; Delete account keeps the display name; Adopt row after leaving is a dead end | Priya | P2 | M | "Moved out" state (skip in rotation, chip), rename-on-exit option, hide Adopt after leaving |
| D9 | Four exit rows (Sign out / Leave / Disconnect / Delete account) with no subtitles; "profile" vs "member", "phone" vs "device" mixed; account/member/household never defined | Priya | P2 | S | One-line subtitles; pick terms; a short "how accounts work" sheet from the sign-in intro |
| D10 | Household name hardcoded English `'My household'`, never asked; chore and shopping category seeds are English literals, synced as-is → German households see "Dairy", "Bakery" headers | Maria, Priya, Tom | P2 | S | Localise defaults at creation (locale into `seedDefaults`); ask for the name or make it a Settings row |
| D11 | No in-app link to the privacy notes, source repo or the sync server host | Priya | P2 | S | Three About rows |
| D12 | Export row has no sublabel; file includes `settings` (sync ids, `pendingJoinCode`); no import | Priya, Maria | P2 | XS now | Sublabel stating format and "cannot import yet"; exclude `settings`; importer stays G-3 |
| E1 | Chores list opens unfiltered; "mine" is an unlabelled icon with no "you"; member filter hides unassigned chores while the digest counts them → notification and list disagree | Leon | P2 | S | Default filter to the claimed member when pinned; "You" marker; include unassigned in the member filter |
| E2 | Catch-up banner "moved forward" is ambiguous and covers only schedule-anchored chores with ≥2 missed slots; weekly/one-off overdue tiles stay red under a banner saying things were fixed | Leon | P2 | XS | Outcome wording; optionally tap → highlight affected tiles |
| E3 | No device-level off switch for per-chore reminders (only the digest toggle); after "Not now" a permanent dot sits on the Settings tab | Leon | P2 | S | "Chore reminders" master toggle; clear the dot after N days |
| E7 | Chore history share window is clamped to the household's start, not the member's join date → new member shows 0 % beside 90 % | Leon | P2 | S | Clamp per member ("since {date}"), or show counts only |
| E8 | Digest body is only a count ("2 chores today · 1 overdue"); reminders are non-actionable | Leon | P2 (+1 G-6) | S / M | List up to 3 chore names in the digest body; ship slice 7 |
| F1 | Shopping shows nothing while sync is healthy; `addedBy` is written but never shown; "Last synced" is two taps away | Tom, Leon | P2 | S | Quiet "Synced 2 min ago / 3 waiting" line on the Shopping app bar; "Anna" dot on rows added by others |
| F2 | Quick-add pill is at the very top; hardest one-handed reach, chips also open there | Tom | P2 | M (design call) | Bottom-anchored add, or a setting |
| F3 | A tick has no Undo; the row moves into the collapsed cart, sorted by category not recency | Tom | P2 | S | Undo snackbar on single tick, or show the last ticked items under the collapsed header |
| F4 | "Put all back" has no undo and sits beside "Clear checked"; the clear Undo lasts 4 s and any other snackbar replaces it | Tom | P2 | XS | 8 s for bulk snackbars; Undo on Put all back |
| F9 | No "what to buy where": categories are the only axis, cannot be collapsed or filtered | Tom | P2 (interim for G-8) | S | Tap header to collapse; category filter reusing the chores filter widget and `ui_state` |
| G1 | Screen reader: "Complete" / "More actions" tooltips repeat without the chore name; shopping check ring has no label; Settings headers lack `header: true`; tab bar has no index | Priya | P2 | S | Label with the item name; `header: true`; "tab 1 of 3" |
| E4 | Any member can edit/pause/delete/reopen anything, silently; `role` is vestigial by decision D1 | Leon, Maria | P3 (decision exists) | XS disclose / L | At least a line in the delete dialog; revisit only if older kids are a target |
| E5 | Progress card counts the whole overdue pile as "today" ("0 of 7 done today"); "nice work" tone | Leon | P3 | XS | Exclude overdue or relabel "7 to catch up" |
| E6 | Undo 4 s; Reopen is silent and works on others' completions; "Skipped · by {assignee}" blames whoever was assigned; early completion indistinguishable from on-time | Leon | P3 | S | "Done early" tag; drop "by" on skipped rows; confirm when reopening someone else's |
| E9 | No receipt beyond today ("prove I did it Tuesday") | Leon | P3 | S | "Done recently" (3 days) for the current member only — no cross-person view |
| E10 | Offline tick shows no per-item pending state | Leon, Tom | P3 | S | Clock glyph on `syncDirty` rows |
| C6 | Saving a chore edit is silent even when the occurrence was regenerated and jumped sections | Maria | P3 | XS | "Saved — next due Mon" snackbar reusing `futureDueText` |
| C7 | Switching assignment mode wipes the picked members/order; no helper text; current holder not shown in the form | Maria | P3 | XS | Keep the list in memory; one helper line per mode |
| C8 | Weekday toggles 7×48 + 6×4 = 360 dp vs 328 dp available at 360 dp width → Sunday wraps (arithmetic only); Tue/Thu both "T", Sat/Sun both "S" | Maria | P3 | XS | `Expanded` in a `Row`; 2–3-letter names |
| C9 | No duplicate chore / starter chores | Maria | P3 | S | "Duplicate" in the action sheet |
| C10 | Category rows show no counts; delete offers only "become uncategorized", no "move to…" | Maria | P3 | S | Count subtitle; move target in the dialog |
| F6 | No category or quantity at add time; new names sort first under Uncategorized; long-press edit is undiscoverable | Tom | P3 | S | Optional category chip beside the field; parse "2 Milch" into quantity |
| F7 | Duplicate check is lowercase-exact only; rename bypasses it; concurrent offline adds never merge; comma lists become one item | Tom | P3 | S | Fold diacritics/plurals; run the check on rename |
| F8 | Shopping text 15 / 12.5 / 10.5 sp; no keep-screen-on | Tom | P3 | XS / S | `titleMedium` for names; wakelock toggle on the Shopping tab |
| F10 | No remaining-count anywhere (only the cart count) | Tom | P3 | XS | App-bar subtitle "7 left" |
| F11 | Suggestion history can't be pruned; typos suggested forever; `_historyRows` loads the whole table per keystroke | Tom, tech | P3 | S | Long-press chip → Forget; grouped SQL query |
| F12 | No `textCapitalization` on the add and edit fields → "milch" next to "Milch" | Tom | P3 | XS | `TextCapitalization.sentences` |
| F13 | DE: "Im Einkaufswagen" vs "Erledigte leeren" mixed metaphor; en/em dash inconsistency; stiff banner sentence | Tom | P3 | XS | "Einkaufswagen leeren" |
| F14 | Edit sheet saves a stale snapshot of all fields; dismiss discards silently | Tom | P3 | S | Save on dismiss when name non-empty |
| G2 | Bottom bar fixed 72 dp, no text-scale clamp → fits at 2.0, overflows ≈2.25× (iOS a11y sizes); chore notes one ellipsised line and no tap to read | Priya | P3 | XS | `minHeight`/clamp; `maxLines: 2` under large text |
| D13 | Reset dialog doesn't point at Export (Delete account does); linked variant doesn't say the account stays; ASCII `--` | Priya, Maria | P3 | XS | Mirror the Delete-account copy |
| H1 | `db.yml` path filter misses `lib/data/repositories/sync_repository.dart` (where LWW apply, tombstones and ghost repair live) → pgTAP/test_live skipped on exactly those PRs | tech | P3 | XS | Add it and `tables.dart` |
| H2 | `release.yml` never checks tag == `pubspec.yaml` version / versionCode monotonic | tech | P3 | XS | One grep step; assert `versionCode` from the existing aapt dump |
| H3 | Migration tests cover `N→13` and single steps `13→14…16→17`, never `N→17` | tech | P3 | S | Parametrised `1..16 → 17` test |
| H4 | `household_invites` / `households` have full-column UPDATE grants (members can rewrite `code`, `expires_at`); invite codes from `random()` not a CSPRNG | tech, Priya | P3 | XS | Column-scope like `members`; `gen_random_bytes` |
| H5 | Notification-action background isolate never attaches `AppLog` → its failures never reach the error buffer | tech | P3 | XS | Attach `DatabaseErrorLogSink` in `_run` |
| H6 | No retention for soft-deleted rows locally or server-side; shopping history grows at purchase rate (the table most likely to cross A2's cap first) | tech | P3 | S | Cap history per normalised name or compact >1 year |
| H7 | `watchActiveChores` is N+1 per emission and does not watch `chore_assignees` | tech | P3 | S | Joined query or `readsFrom` |
| H8 | `ErrorScrubber` scrubs the message but not `context` values; `FormatException` appends raw source unquoted | tech | P3 | XS | Run the rules over context; special-case `FormatException` |
| H9 | `start()` fires push→pull and the realtime `subscribed` pull concurrently; no in-flight guard; every push triggers two pulls; interleaved pulls can move the cursor backwards | tech | P3 (precondition for A4) | XS | Single in-flight `Future`; ignore own realtime echo ≈1 s |

## 2. Sync integrity (A)

The technical review's conclusion: the conflict model has outgrown "LWW per
row". Tombstones (A1), ghost repair (A4), assignee sets (A8) and catch-up
(A4) are each a small hand-rolled merge rule on top of LWW with no shared
statement of invariants. Proposal: write them down in `sync-backend.md`
§8.7 — "a tombstone only kills pending rows", "assignees are one value",
"ids should be deterministic", "the survivor key must be identical on both
devices" — before fixing any of them.

A1 is the only confirmed history-loss path and A5 the only confirmed crash
path; both are tiny and testable in the existing engine/service suites. A2
is plausible within a year of normal use for any household (≈1,300
occurrence rows/year for 3 daily + 4 weekly chores; shopping history grows
faster). Note that `supabase/config.toml` governs only the local stack; the
hosted project's cap is a dashboard setting with the same 1000 default, so
paging is needed regardless.

A9 is the known last-push-wins trade-off; it is listed because Tom's
walkthrough produced the first concrete everyday scenario (offline Clear
checked in the store vs partner re-adding at home) and because the
field-level fix for just `checked_at`/`deleted_at` is much smaller than
replacing LWW.

Things the technical review checked and found fine, so nobody re-reviews
them: the RLS matrix for every table and verb; the revocation probe cannot
false-positive on auth loss; no secrets in the repo; Android release gates
assert on the APK; iOS backup exclusion pinned by a test; DE localisation is
complete (362/362 keys, `gen_l10n` would fail the build on a missing key);
notification scheduling (one-shot, serialised writes, DST-safe midnight);
local FK enforcement; rotation cover logic from #60.

## 3. Honesty of copy and docs (B)

Four personas independently reached the same theme: the app is very
careful about *not alarming* (neutral banner colour, no "offline", no
blame), and that care has tipped into *under-informing*. The specific
sentences that are no longer true against the code are B1, B2, B3, B4, B5;
the states that look like success but are not are B7 (green check on every
error) and A3 ("Last synced just now" while pushes are rejected). B2 is the
one a GDPR-minded user will actually test.

## 4. Chores for the organiser (C)

C1 is deliberate (`docs/plans/2026-08-08-rotation-reorder.md` points 2–3)
and tested, but the decision was about not *reordering* a rotation mid-
stream; removing the current holder from the chore entirely is a different
case the UI should either handle or explain. C2 (reassign a turn) is the
feature Maria reaches for most often and does not exist; Skip, Pause, Edit
and Mark-done-for are each a wrong tool for "Anna is ill this week". C3 is
the single most-cited interaction gap (three personas): the tile's only
gesture is long-press.

## 5. Joining and members (D)

The join funnel in order: share text with no install hint (D7) → welcome
screen emphasising Create (D1) → policy paragraph + email + leave the app
for a magic link, no OTP, generic errors (D2) → code → one-tap claim with no
household name (D3) → Members list that never shows who has joined (D4) →
inviting the next person revokes the previous code (D5). Each step is
individually small; together they are the whole first impression for every
non-organiser. D10 (English defaults synced to German households) is the
only item three personas hit from three different directions.

## 6. Daily use for a member (E), shopping (F), accessibility (G)

See the matrix; the raw reports carry the full traces. The single most
valuable shopping change by Tom's own ranking is F1 + F3 + F4 together
("did it sync, did my tick land, can I undo") — all three reuse data and
helpers that already exist (`syncLastPulledAt`, `watchAnyDirty`,
`showAppSnackbar` with action). For Leon, E1 (default to "mine", include
unassigned so the digest and the list agree) changes the two-second open
that the persona exists for.

## 7. Engineering hygiene (H)

H1 and H2 are CI gaps that each remove a false green; H9 is the
precondition that makes A4 reachable. The architecture note from the
technical review: layering is real and the seams are narrow and
consistently faked; the drift is in timestamps meaning three things in one
column (device stamp, server stamp, two formats), in all-or-nothing network
steps, and in three files over 1,000 lines (`providers.dart` 1,874,
`chores_list_screen.dart` 1,045, `account_section.dart` 1,000).

## 8. What already works well (do not break)

Converging across reviewers:

- Repeat form as one sentence with a live "Next Tue, Oct 7, then Fri…" preview.
- Destructive dialogs state their blast radius with exact counts (category,
  member, chore delete) and the common confirms were checked against the
  code and found truthful (Disconnect, non-last Leave, Delete account,
  claimed-member removal, Reset).
- Undo on complete/skip/pause/clear/delete-item; dirty-form guard; Save
  pinned above the keyboard; LIFO reopen.
- Identity pinned on a joined phone; tap-anywhere tick with 350 ms hold and
  haptic after the write; duplicates and "typed something already in the
  cart" handled; top-5 staples on focus; reopens on the last tab.
- Blame-free stance held consistently: no "missed" in copy, skipped/missed
  never counted, roster order in stats, neutral sync banner.
- Authored dark theme with a measured contrast floor; due state carried by
  text and edge, not colour alone; settings rows restack above 1.3×.
- Offline-first is real: engine, uploader and join card gated on config +
  link + sign-in; `allowBackup=false` + iOS exclusion; error scrubbing
  deliberately lossy; resumable join after a process kill.

## 9. Known-backlog +1 (already tracked; persona cost in one line)

- **G-3 / F12 restore from backup** — Maria and Priya both: an export that
  cannot be imported looks like a backup and isn't; B3's archive is the same
  gap seen from the join side. Top of both lists.
- **G-6 slice 7 reminder Done/Snooze** and **F-1 Snooze to tomorrow** — Leon
  ignores anything he cannot act on from the shade.
- **G-9 digest scope toggle / F16** — Maria wants the kids' chores in her
  summary; Leon's digest count disagrees with his filtered list (E1).
- **G-8 several lists / G-7 search** — Tom's three stores; F9 is the cheap
  interim.
- **F-2 share-to-app / F-3 widget** — the partner's "oat milk, sourdough"
  message is exactly Tom's input and today becomes one item.
- **Undo on chore delete (conventions audit C10)** — still the one chore
  action with no undo; it loses the whole schedule/rotation setup.
- **G-10 fork a removed member's copy / G-11 account in several
  households** — Priya's flat-share lifecycle hits both.
- **G-13 12 sp labels below 4.5:1 (light)**, **G-14 widget tests cannot
  measure text** — why G2 would not be caught by CI.
- **Last-push-wins** and **no background sync while closed** — A9, E10.
- **D-2/D-3 swipe reversal** — explains why there is no row gesture on
  either list; the discoverability cost (F6) landed where predicted.
- **F17 more icons/colours.**

## 10. Stale documentation found on the way

- `docs/future-improvements.md` F14 (repeat-form redesign) — shipped as G-2;
  the row should close.
- `docs/future-improvements.md` F11 (delete account "no UI yet") — shipped;
  stale in the same way as PRIVACY.md.
- `PRIVACY.md` — see B1.
- `app_en.arb` descriptions and code comments still say "Account section"
  for what is now the Household group (harmless, but B4's two user-facing
  leftovers came from it).

## 11. Suggested order of work (proposal)

1. **A1 + A5** (S + XS): the confirmed history-loss and crash paths.
2. **C1 + C2-reassign-only** (S + S): the organiser's broken core action and
   the missing one next to it.
3. **B1 + B2 copy + B4 + B5 + B7** (all XS–S): one honesty pass over docs,
   confirm bodies and the error snackbar.
4. **A2 paging + A3 per-table push and "N waiting"** (S + S): before the
   second-device story is relied on.
5. **Join funnel D1 + D3 + D4 + D7 + D10** (S each): the first ten minutes
   for everyone who is not the organiser.
6. **Shopping F1 + F3 + F4 + F12** (S + S + XS + XS): the in-store loop.
7. **A4 + H9, A6, A7, A8** (S + XS, XS, XS, S): the remaining desync modes.
8. **H1, H2, H5** (3 × XS): CI/observability hygiene.
9. Then write `sync-backend.md` §8.7 invariants before the next sync feature.
