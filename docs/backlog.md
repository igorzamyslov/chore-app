# Consolidated open work — 2026-08-08 (from v0.4.1+7)

*Every outstanding item in the project, in one place, each sized to be handed
to an agent as a self-contained ticket. Compiled by cross-checking
`future-improvements.md`, `app-lifecycle.md`, `next-session-plan.md`,
`research/triage.md`, all four `feedback/` docs and `specs/polish-round-1.md`
against the actual source — not against what the docs claim. Anything those
documents listed that is in fact implemented has been dropped here.*

**Closed since they were written, verified in code:** the entire
`2026-08-01-ux-audit.md` (A1–A6, B1–B3), all of `polish-round-1.md` (A1–A3,
B1–B2, C1–C3), app-lifecycle G1/G2/G3/G4/G5/G7/G9, triage Tier 1 in full,
the `2026-08-07` field-feedback C1/C2/C3 and A1/B2, and every
`next-session-plan.md` backlog bullet except `Recurrence` equality.
Also closed: **A-5 (acting-member pinning + Mark done for…, 2026-08-08)**.

Effort key: XS ≈ under an hour · S ≈ half a day · M ≈ 1–3 days ·
L ≈ a week · XL ≈ multi-week.

## Decisions taken 2026-08-08 (Igor)

- **D-B1 — Android backup: `allowBackup="false"`.** The app's answer to
  "don't lose my data" is sync plus the JSON export, which is exactly what
  the reset copy already tells users. Uninstall means gone. A real backup
  story is **G-3** (restore from a backup file), not the OS's. This settles
  **A-3** and closes `app-lifecycle.md` G8(a).
- **D-B2 — Distribution: open-source only, permanently.** GitHub Releases
  and F-Droid; no Play/App Store accounts, ever. Consequences:
  - **H-2 (tip-jar IAP) is closed as won't-do.** The Ko-fi/PayPal donate row
    already shipped is the final answer. `DESIGN.md` §5's prohibition on
    linking out applies only inside store-distributed apps, so it no longer
    binds — that section should be updated to say so rather than left to
    contradict the shipped code.
  - **Account deletion (C-2 / F11) is GDPR-driven, not store-mandated.**
    Still genuinely required once accounts exist, but it is not a launch
    gate and does not need to precede the first public release.

## Plan-level decisions taken 2026-08-08 (delegated by Igor)

*Igor delegated the plans' open product decisions, asking that they follow
best practice for UI/UX, architecture and security. Each plan's own
recommendation was accepted unless noted. Two were overruled, both because
the local recommendation contradicted something else in the app.*

**Accepted as recommended**

| Plan | Decision |
| --- | --- |
| A-2 | A day rolling over while the user watches says **nothing** — the UI just becomes correct. A date boundary is not an event. |
| A-2 | The Settings "Last synced N minutes ago" text is **out of scope** — it needs a ticker, which reopens the pending-timer hazard. Filed as **A-2b** below. |
| A-5 | Where the switcher stood when pinned: a **non-interactive avatar** of the claimed member. Keeps the identity affordance and avoids layout shift between local and linked. **Constraint:** no ink, ripple or splash — it must not read as tappable. |
| A-5 | "Mark done for…" is **pinned-households only**. Local-only keeps the switcher; two mechanisms for one job is worse than one. |
| A-5 | The confirmation snackbar **names the credited member** ("Done — credited to Anna"). Attribution is the entire point of the ticket, and confirming a non-default action is standard. |
| B-1 | Catch-up is explained by a **self-hiding banner**, not a snackbar. Four seconds is too thin to de-escalate something that reads as an accusation. |
| B-5 | The digest pre-prompt banner **never re-arms**. The honest toggle sub-line and the tab dot are already persistent signals; a returning banner is nagging. |
| C-2 | The delete-account confirm **points at the JSON export first**. Portability before erasure is the right pairing, and GDPR treats them as siblings. |
| C-2 | After leaving a household the device **stays signed in**. Leaving a household is not leaving the account — you may want to join another. |
| D-2 | Swipe is **one direction, delete only** (`endToStart`). Matches platform convention, doesn't duplicate the existing check ring, smallest collision surface with the `PageView`. |
| D-3 | The one-row long-press menu **ships**. It is the tap-reachable equivalent of the swipe for anyone who can't perform a calibrated drag — an accessibility floor, not a duplicate. |
| F-1 | Ship **"Done" only**; "Snooze to tomorrow" becomes its own ticket. Its semantics are genuinely undefined for the overdue case and would block the unambiguous half. |
| G-1 | Placement: a **Settings row**, not a fourth tab. |
| G-1 | Window: **fixed 30 days**, clamped to the household's start. |
| G-1 | `skipped` and `missed` are **never shown**. Counting them against a person is the accusation T2.1 exists to remove. |
| G-1 | Share list uses **roster order**, never sorted by count. This is the line between describing work and ranking people. |
| D-5 | Sync-health thresholds: **`pullStaleAfter` 5 min, `dirtyStaleAfter` 3 min.** A healthy device polls every 60s, so 5 min is five missed cycles — past a tunnel or a lift, but well before real divergence goes unmentioned. Faster (2/1) fires on ordinary mobile hiccups and teaches people to ignore the banner; slower (15/10) misses the mid-shop case the feature exists for. Both must be named constants in one place, with the values and rationale in `sync-freshness.md` §2.5. |
| D-5 | The sync-health banner uses **`secondaryContainer`, not `errorContainer`**, and stays non-dismissible. For a local-first app, being briefly unreachable is a normal condition, not an error — red here would be alarmist and would dilute red everywhere else. |
| Shell | Tapping a tab uses **`jumpToPage`, not `animateToPage`.** Material's horizontal page-slide belongs to `TabBar`/`TabBarView`, not bottom navigation: animating Chores → Settings would visibly slide Shopping past in between. Destinations swap; they do not travel. An animated drag and an instant tap are two different interactions correctly rendered, not an inconsistency. (E2E timing stability is a secondary benefit, not the reason.) |
| Shell | **Shopping rows own the horizontal gesture**; swiping to page away from the shopping tab mostly won't work, since rows cover most of it. Accepted as the established pattern (Gmail, WhatsApp). Must be documented in `ui-shopping.md`, not just the plan, along with the escape hatch: dropping the `Dismissible` and keeping D-3's long-press delete restores paging everywhere at the cost of one gesture. |
| Shell | Back on the first tab **exits immediately** — no "press back again" toast. That idiom is dated, predictive back has effectively retired it, and intercepting the final back now reads as the app refusing to close. |

**Accepted, with an added obligation**

- **A-1 — the digest counts your chores plus unassigned "anyone" chores.**
  Strictly-mine would leave a household that assigns everything to "anyone"
  in permanent silence, which is a worse failure than slight over-inclusion.
  **But** `DESIGN.md` §3 currently says unassigned chores are *opt-in*, so
  this deviates from a written decision. It was written for the pre-sync,
  single-device era. The plan must therefore include a task amending
  `DESIGN.md` §3 — the deviation gets recorded, not silently absorbed.

**Overruled**

- **C-2 — delete account DOES get its own second confirmation**, rather than
  riding the shared exit sheet alone. The app already double-confirms
  *Reset app data*, which is purely local and recoverable by re-syncing.
  Account deletion is irreversible server-side erasure. Guarding the weaker
  action more heavily than the stronger one is exactly backwards, and
  irreversible destructive actions are the canonical case for a deliberate
  second step. Reuse the reset flow's two-step shape so the app has one
  consistent grammar for "this cannot be undone".

- **E — the privacy disclosure wording is changed.** The recommended
  sentence said the data goes "on our server", which is wrong for a
  self-hostable, open-source, F-Droid-distributed app, and it omitted the
  thing that actually reassures a first-time reader: that not signing in
  keeps everything local. Use instead:

  > "Signing in stores your email and your household's data — chores,
  > shopping list, members — on the sync server, so your devices stay in
  > step. Without an account, everything stays on this device."

  Keep it to those two sentences; it must stay a disclosure, not a policy.

- **D-5 — the sync-health banner must name the user's recourse.** The plan
  proposed a non-tappable banner, which is right, but paired it with copy
  that states the problem and offers nothing to do about it. A notice that
  reports a fault and provides no action is the same dead end as the startup
  error screen in E-2. The copy therefore points at pull-to-refresh, which
  already exists on both list screens and (since `60c15ce`) genuinely
  reports failure. No button, no tap target: a control duplicating a gesture
  on the same screen is redundant, and routing to Settings would be worse,
  since Settings cannot fix connectivity either. The word "offline" stays
  out — the honest framing is "unsent changes / hasn't reached the household
  in a while", not a connectivity verdict the app cannot actually make.

**New backlog row from the above**

| ID | Title | Notes | Effort |
| --- | --- | --- | --- |
| **A-2b** | Settings "Last synced" text goes stale while open | Needs a periodic ticker; deliberately excluded from A-2 because a provider-armed timer trips `flutter_test`'s pending-timer check | S |
| **A-3b** | iOS: the database is in `Documents/`, which iCloud backs up by default | The iOS counterpart to A-3's `allowBackup="false"`. Needs per-file `NSURLIsExcludedFromBackupKey` at runtime, not a manifest flag — deliberately out of A-3's scope | S |

## Suggested execution order

*Every group-A/B/C/D/E/F/G item below now has a written plan under
`docs/plans/2026-08-08-*.md`. Order respects the hazards in the next
section; within a wave, items are independent and can run in parallel.*

**Wave 1 — release gates.** Nothing ships publicly before these.
1. **A-3** Android backup — one manifest line plus a CI assertion; smallest
   thing on the list and the only one that must be right *before* the first
   wide install rather than after.
2. **A-1** daily digest — highest-value fix in the whole backlog.
3. **A-2** day rollover.
4. **A-4** reset signs out — must precede E.
5. **A-5** acting member — must precede G-1.

**Wave 2 — trust gaps.** B-1, B-2, B-3, B-4, B-6 are mutually independent.
B-5 waits for the shell (wave 3).

**Wave 3 — conventions.** Shell (D-1/D-4/D-6) **first**, because two other
plans build on the file it rewrites. Then B-5's tab dot, D-2/D-3 shopping
gestures, and D-5 offline indicator in any order.

**Wave 4 — small fixes.** E, after A-4.

**Wave 5 — larger committed work.** C-1 (already planned, in progress in a
separate worktree) → C-2. G-1 after A-5, coordinating the schema version
with B-3. F-1 after A-1.

**Not planned, and deliberately so:** F-2, F-3, G-2, G-4, G-5, G-6, G-7, G-8
need a design conversation before a plan would be worth writing; H-1 is a
go/no-go, not code; H-2 is closed by D-B2.

## Execution hazards between plans

*Found while reviewing the plans against each other. None is visible from
inside a single plan, and the schema one is not a merge conflict a reviewer
would catch by eye.*

- **Two plans both claim schema v10.** B-3 adds `settings.pendingJoinCode`;
  G-1 adds a `(status, closed_on)` index. Current schema is v9. Whichever
  lands second must become **v11**, along with its migration test. Two
  migrations sharing a version number is a corrupt upgrade path, not a
  conflict git will surface.
- **A-4 before E-2.** Both rewrite `reset_flow.dart`: A-4 adds sign-out and
  digest-cancel to `_confirmAndReset`, E-2 extracts that method. Extracting
  first silently drops the sign-out.
- **Shell (D-1/D-4/D-6) before B-5.** Both touch `_TabContent`/`_BottomTabBar`.
- **A-1 before F-1.** F-1 assumed the digest's shape rather than reading
  A-1's rolling 7-day horizon; compatible, but needs a rebase.
- **A-5 before G-1.** The stats screen makes `completedBy` authoritative;
  shipping it over unfixed misattribution enshrines wrong data.
- **`app_de.arb` escapes umlauts inconsistently.** Exactly one string,
  `syncRefreshError`, stores them as JSON `ä`-style escapes; the other
  65 German lines use literal `ä/ö/ü/ß`. Any plan whose edit anchors on that
  one line by its rendered text will fail to match. Found while editing D-5.
  Worth normalising that line to literal umlauts in the **E** wave so the
  file has one convention — a one-character-class change, and it removes the
  trap rather than documenting it.
- **Two plans edit `ui-shopping.md`.** The shell plan documents the
  gesture-collision trade-off there; D-2/D-3 documents the swipe and
  long-press behaviour. Trivial to reconcile, but they will conflict
  textually if applied blind.

---

## A. Release gates

*Nothing should ship publicly with these open.*

| ID | Title | What's wrong | Files | Effort |
| --- | --- | --- | --- | --- |
| **A-1** | **The daily digest is not daily** | **DONE 2026-08-08** (`docs/plans/2026-08-08-daily-digest-scheduling.md`): the digest is now armed as a rolling 7-day horizon of distinct ids, rewritten on every trigger, with counts projected per date and scoped to the acting member. **T2.3 closed with it** | `lib/domain/digest_planner.dart`, `lib/application/notification_scheduler.dart`, `lib/app/providers.dart:650-856`, `docs/specs/notifications.md` | M |
| **A-1b** | **The digest goes silent after 8 unopened days** | Follow-on to A-1, found in the v0.5.0 handover (§3.1). The rolling horizon is 7 days (ids 1001..1007), so an app left unopened longer than that is silent again — failing exactly the disengaged user a reminder exists to re-engage. **The non-obvious part:** horizon length buys no *accuracy*. The projection assumes the local DB doesn't change, which holds while the app is closed, so staleness is binary — right if nothing changed, stale if another device acted — and that applies equally at day 2. Day 28 is as accurate as day 8, so `digestHorizonDays`' "comfortably inside iOS's 64-notification cap" rationale is true but not load-bearing. The number to protect is the unbuilt per-chore reminders (G-6/F16), not 64. Planned 2026-08-14 | `lib/domain/digest_planner.dart`, `lib/application/notification_scheduler.dart` | S–M |
| **A-2** | **Date-derived UI never rolls over at midnight** | `clockProvider` never re-emits. `closedTodayOccurrencesProvider` captures `today` at build time and watches nothing that changes at midnight — an app left open overnight shows yesterday's completions under "Done today" forever, and the progress ring with it. Section buckets only refresh if catch-up happens to change something. `CatchUpController` already owns a DST-safe midnight timer; its only consumer is catch-up | `lib/app/providers.dart:545-552,820-884`, `lib/features/chores/chores_list_screen.dart:53` | S |
| **A-3** | **Android auto-backup unconfigured** | No `allowBackup`, no `dataExtractionRules`, no `fullBackupContent` anywhere under `android/`, so backup defaults on with no rules: a live SQLite file plus WAL sidecars copied uncoordinated, and the Supabase refresh token + pull cursor restored onto a second device. Under last-push-wins that is a data-clobbering configuration. Invisible in every emulator and E2E run — same blind-spot class as the v0.2.0 `INTERNET` miss. **Decided (D-B1): `allowBackup="false"`. Planned in `docs/plans/2026-08-08-android-backup.md`, ready to execute** | `android/app/src/main/AndroidManifest.xml`, `docs/app-lifecycle.md` G8 | XS–S |
| **A-3b** | **iOS: no backup exclusion on the local DB** | `chore_app.sqlite` (+ `-wal`/`-shm`) lives under `getApplicationDocumentsDirectory()` (`drift_flutter`'s native default, no iOS/Android branch), which iCloud/iTunes backs up by default — same torn-restore and cross-device session-clobber shape as A-3, but the fix is per-file (`NSURLIsExcludedFromBackupKey` at runtime), not a manifest flag, so it needs its own scoping pass. Deliberately excluded from A-3/D-B1, which is Android-only | `ios/Runner/Info.plist`, wherever the DB file is opened (`lib/data/db/app_database.dart`) | S |
| **A-4** | **"Reset app data" leaves the account signed in** | `resetAppData` wipes eight tables and nothing else; the Supabase session survives, so the user lands on the welcome screen still authenticated and *Join* skips the email step. The linked confirm copy says "You can reconnect by signing in again", describing a sign-out that never happens. Should also cancel the scheduled digest | `lib/application/data_reset.dart`, `lib/features/settings/reset_flow.dart` | S |

---

## B. Trust and safety gaps (triage Tier 2 — all verified still open)

| ID | Title | What's wrong | Files | Effort |
| --- | --- | --- | --- | --- |
| **B-1** | Catch-up after a lapse is invisible (T2.1) | `catchUpOverdue` silently converts a backlog to "missed" before the list renders, with no explanation. To a returning user it reads as an accusation | `lib/application/chore_service.dart:138-178`, `lib/features/chores/` | S |
| **B-2** | Category delete never says how much it affects (T2.2) | No "3 chores and 5 items" before an irreversible tap. Zero counting code in the dialog | `lib/features/settings/category_delete_dialog.dart` | S |
| **B-3** | Join wizard keeps no persisted state (T2.4) | Switching to Mail to tap the magic link can drop the user back to the welcome screen mid-join; the route is not restored across process death | `lib/features/onboarding/welcome_join_page.dart` | M |
| **B-4** | Rotation order can't be edited, only rebuilt (T2.5) | Re-tapping always re-appends; no reorder handle, while Categories next door has drag-reorder | `lib/features/chores/chore_form/assignment_fields.dart` | S |
| **B-5** | A denied notification permission is permanent in practice (T2.6) | The only nudge is a one-shot banner; recovery lives in Settings, which the user who most needs it never opens | `lib/features/chores/digest_preprompt_banner.dart`, `lib/features/settings/digest_section.dart` | S |
| **B-6** | Push has no periodic retry (T2.7) | `_armPoll` arms `pullSince` only. A write made as connectivity drops sits dirty until the next local write or app resume | `lib/application/sync_engine.dart:307-317` | S |

---

## C. Household lifecycle — the P4 cluster (F9/F10/F11/F13)

*Spec is complete (`docs/specs/household-lifecycle.md`, decisions D-L1…D-L5).
**Slices 1–3 shipped in v0.5.0**; slices 4–6 are planned and unexecuted.*

*Naming warning: "P4" means two different things in this project's docs — this
household-lifecycle cluster, and the group of smaller findings in
`docs/feedback/2026-08-08-prerelease-audit.md`. Check which one a document
means before acting on it.*

| ID | Title | State | Effort |
| --- | --- | --- | --- |
| **C-1** | **Slices 1–3: server RPCs + pgTAP, the two claim-state gaps, shared confirm sheet, revocation detection** | **DONE (v0.5.0)**. The D-L4 gate held: `delete from auth.users` works inside a `SECURITY DEFINER` RPC, so no edge function is needed. Migration `20260808120000_membership_exit.sql` is applied in production (confirmed 2026-08-14) | L |
| **C-2** | **Slices 4–6: remove a claimed member (F10), leave household (F9) + last-member cascade warning, delete account (F11)** | Needs a plan. Deliberately not planned yet — a refusal in slice 1 reshapes delete-account | L |
| **C-3** | Orphan household cleanup (F13) | **DONE with C-1** — the slice-1 migration's cascade (§2.4); listed here so it isn't tracked twice | — |
| **C-4** | **Reconnect wipes local data; Adopt fails after revocation** | **Reconnect is a LIVE data-loss bug in the released v0.5.0, not a latent one.** `ReconnectChoice` makes no RPC; `downloadHousehold` returns an EMPTY result rather than erroring when RLS hides the household; `join` then deletes the local household and inserts nothing. The archive is the only trace and there is no importer (G-3/F12 unbuilt). Exposure today is narrow but real: `remove_member` is in the applied production migration even though its client UI is still C-2, and revocation detection already ships — a removed member tapping *Reconnect* is the path. Fix: abort the replace before the transaction on an unconfirmed snapshot. **(b)** Adopt deterministically fails after a revocation-triggered unlink — `create_household` takes the LOCAL household id verbatim, which still exists server-side, so the insert PK-conflicts (`23505`) into a generic failure state. The sharper mechanism: `adopt`'s resume heuristic keys on "can I still read this household", true after Disconnect and false after revocation, so the one user it cannot rescue is the removed one. Join-by-code still works. **Must land BEFORE C-2**, ahead of that plan's Task 12. Planned 2026-08-14 (`docs/plans/2026-08-14-reconnect-adopt-hardening.md`) | `lib/application/household_gateway.dart`, `household_join_service.dart`, `household_link_service.dart` | M |
| — | *Withdrawn claim, kept as a record* | An earlier version of C-4 asserted that `findMyMembership`'s missing `members.deleted_at`/`households.deleted_at` predicates let a stale membership offer a destructive reconnect into a dead household. **That was wrong.** RLS already closes both doors: `is_household_member` requires the caller's own row to be active, and `_cascade_if_orphaned` never soft-deletes a household still holding a claimed active member. The predicates are still worth adding as labelled defence-in-depth, and C-4 does so with pgTAP proving the RLS behaviour — but nobody should re-derive a threat model from the absent predicates alone | — | — |

**Note on urgency:** F11/G6 (account deletion) is a *store requirement* on both
Apple and Google when accounts exist. Under the current open-source-only
distribution decision it is GDPR-driven rather than store-driven — see the
distribution question below.

---

## D. Established mobile conventions

| ID | Title | State | Files | Effort |
| --- | --- | --- | --- | --- |
| **D-1** | Swipe left/right between tabs (F1) | `IndexedStack` → `PageView` while keeping per-page keep-alive, every `shell.tab.*` id, and the hand-rolled bar's semantics workaround | `lib/app/app_shell.dart` | M |
| **D-2** | Swipe-to-delete on shopping items (F2) | Undo already shipped via the edit sheet; only the `Dismissible` gesture is missing (no `Dismissible` anywhere in `lib/`) | `lib/features/shopping/shopping_item_tile.dart` | S |
| **D-3** | Long-press context menu on shopping items (F3) | Chores have `onLongPress`; shopping doesn't. Pattern to copy already exists | `lib/features/shopping/shopping_item_tile.dart` | S |
| **D-4** | Re-tap a tab to scroll its list to top (F4) | `_onTabSelected` only clears snackbars and swaps the index | `lib/app/app_shell.dart` + both list screens | S |
| **D-5** | Offline / can't-reach-server indicator (F5) | Only a passive "Last synced" line in Settings exists; a linked device that cannot reach Supabase looks identical to a healthy one everywhere else. Worth promoting given A-1 and B-6 | `lib/application/sync_engine.dart`, `lib/features/settings/account_section.dart`, both list screens | M |
| **D-6** | Android back on a non-first tab exits the app | No `PopScope`; Material guidance is that back returns to the start destination first. Natural companion to D-1/D-4 | `lib/app/app_shell.dart` | XS |

---

## E. Small, unambiguous fixes

*Good candidates for one combined wave.*

| ID | Title | What's wrong | Files | Effort |
| --- | --- | --- | --- | --- |
| **E-1** | Notification channel name is hardcoded English | `'Daily summary'` / `'The once-a-day chores digest notification.'` are user-visible in system Settings → Notifications. Violates the all-strings-through-l10n rule. Android caches the channel name at creation, so a later change needs a new channel id — fix before the first wide install | `lib/application/notification_scheduler.dart:155-158` | XS |
| **E-2** | Startup error screen is a dead end | `_ErrorScaffold` renders the raw exception `toString()` with no retry and no way out; a database-open failure bricks the app permanently. The list screen's `_ErrorState` already has the retry pattern to copy | `lib/app/app.dart:79-102` | S |
| **E-3** | In-app privacy disclosure above the sign-in field | `PRIVACY.md` shipped, but the one-line "what's stored and where" sentence above the email field never did. The 2026-08-01 doc gates this on "before any public announcement of sync" | `lib/features/settings/account_section.dart`, `lib/features/onboarding/welcome_join_page.dart`, l10n | XS |
| **E-4** | `Recurrence` has no `==`/`hashCode` | Last unclosed bullet from the old backlog; add before something needs state comparison and gets it subtly wrong | `lib/domain/recurrence/recurrence.dart` | XS |
| **E-5** | `pubspec.yaml` still says "A new Flutter project." | Package metadata on an open-source release | `pubspec.yaml:2` | XS |

---

## F. Platform integrations (each needs its own decision before starting)

| ID | Title | Why it matters | Effort |
| --- | --- | --- | --- |
| **F-1** | Notification actions — mark a chore done from the digest (F6) | Strong fit for a chores app; needs a background isolate handler and its own tests | M |
| **F-2** | Share-to-app — "add to shopping list" from any share sheet (F7) | Would change how the shopping half feels day to day | L |
| **F-3** | Home-screen widget for the shopping list (F8) | Same, and multi-day native work per platform | XL |

---

## G. Product features

| ID | Title | Notes | Effort |
| --- | --- | --- | --- |
| **G-1** | Stats — "who actually does the chores" (F19) | **Promoted out of the backlog by decision D2**: the delete copy was softened on the promise that this gets built, at which point the stronger "its history is kept" copy comes back | L |
| **G-2** | Repeat-form structural redesign (F14) | G3 stage 2 — the wording was fixed, the structure was not | M |
| **G-3** | Restore from a backup file (F12) | Export exists, import does not. Explicitly a non-goal of the P4 spec, so it stands alone | M |
| **G-4** | Custom avatars — photo or colour-as-border (F15) | User request, round 1 | M |
| **G-5** | More category icons and colours (F17) | User request, round 1. Icon set unchanged at 15 entries | S |
| **G-6** | Finer-grained notifications — N2: per-chore reminders, evening re-reminder (F16) | Own spec; depends on A-1 landing first | L |
| **G-7** | Search in long lists (F18) | Low value at family scale | M |
| **G-8** | Multiple shopping lists (F20) | Schema is single-list today | XL |
| **G-9** | Digest scope toggle — a per-device "include unassigned chores in my digest" opt-in | The opt-in that `DESIGN.md` §3 originally promised, retired as a *default* by OPD-1 (`docs/plans/2026-08-08-daily-digest-scheduling.md`) rather than as a *capability*. Would be a per-device `settings` boolean feeding `projectDigestCounts`'s recipient predicate — genuinely small, but it is a new settings row, new l10n and new widget tests, and nobody has asked for it. Build it if a real household reports the over-inclusion as noise, not before | S |

---

## H. Distribution

| ID | Title | State | Effort |
| --- | --- | --- | --- |
| **H-1** | F-Droid / IzzyOnDroid submission (F21) | `fastlane/metadata/` is written, app id and name are real. Awaiting a go-ahead, not code | S |
| **H-2** | Tip-jar IAP (F22) | A Ko-fi/PayPal donate row shipped instead. **See the distribution question below** — `DESIGN.md` §5 records that linking out to Ko-fi/PayPal from inside the app is forbidden by both stores' policies, so the current row is fine for F-Droid/GitHub and is a policy violation the day the app enters a store | L |

---

## Known trade-offs (documented, revisit only with evidence)

- Last-push-wins conflict resolution, worse the longer a device stays signed out.
- No background sync while the app is closed.
- `chore_assignees` has no tombstones, so a removed assignee doesn't replicate
  as a deletion — and rotation drifts on the other device as a result.
- Delete-vs-check resurrection; cross-device duplicate names; the 60-second
  pull bound with realtime degraded.
