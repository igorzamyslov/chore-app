# Consolidated open work — 2026-08-08 (from v0.4.1+7)

*Every outstanding item in the project, in one place, each sized to be handed
to an agent as a self-contained ticket. Compiled by cross-checking
`future-improvements.md`, `app-lifecycle.md`, `next-session-plan.md`,
`research/triage.md`, all four `feedback/` docs and `specs/polish-round-1.md`
against the actual source — not against what the docs claim. Anything those
documents listed that is in fact implemented has been dropped here.*

**Closed since they were written, verified in code:** the entire
`2026-08-01-ux-audit.md` (A1–A6, B1–B3), all of `polish-round-1.md` (A1–A3,
B1–B2, C1–C3), app-lifecycle G1/G2/G3/G4/G5/G7/G9, triage Tier 1 in full
(and T2.2 from Tier 2), the `2026-08-07` field-feedback C1/C2/C3 and A1/B2,
and every `next-session-plan.md` backlog bullet except `Recurrence`
equality.
Also closed: **A-5 (acting-member pinning + Mark done for…, 2026-08-08)**.
Also closed: **B-2 (category delete states its impact count, 2026-08-08)**.

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

**New rows found while executing wave 4 (2026-08-17)**

| ID | Title | Notes | Effort |
| --- | --- | --- | --- |
| **A-6** | `e2e.yml`'s `ios` job is intermittently red on `main` — **trigger settled 2026-08-28, flake still open** | Observed at `625ea72` (run `31800958022`): 2 of 14 flows failed — `language_override` and `done_today_reopen` — both on `Assertion is false: id: welcome.create is visible`; `android` passed the same run. **Not a code regression:** `625ea72` added only `db.yml` plus `supabase/tests/**`, and the previous main commit passed. **The cause originally recorded here — "the app was not in fresh-install state", i.e. a state-isolation/`clearState` flake — is WRONG.** Corrected 2026-08-28 from that run's Maestro debug artifact, retrieved hours before its 14-day expiry: (1) the failure-step accessibility hierarchy contains the status bar and an app window titled "Famdo" and **nothing inside it** — no welcome gate and *no tab shell either*, so there was no leaked household to see; the screenshot is a blank white frame. (2) Not a slow runner: the wait for `welcome.create` was 4.8–9.0 s in all 12 passing flows and a full 60 s in both failures — bimodal, so a larger timeout buys nothing. (3) Not a hang or crash: XCTest runs in-process and logged the app's main thread responding ("MT responded in time"), capturing a snapshot in 0.01 s with zero Flutter nodes in it. **Real cause: the Flutter view permanently fails to present on a fresh install, ~3% of flows / ~17% of runs (1 red in the 6 main runs where `ios` ran; 4 green since).** Probable contributing factor, also from the log: Maestro implements `clearState: true` on **iOS as uninstall + reinstall** (new bundle container, fully cold start, 14 times per run, discarding the warm-up launch), where on Android it clears data and leaves the app installed. **Trigger decision (done):** `ios` stays off automatic PR runs — widening it while the flake is live would make ~1 PR run in 6 falsely red — and a `workflow_dispatch` trigger was added so any branch can be verified on iOS pre-merge, on demand, with attribution. Reasoning is in `e2e.yml`'s `ios` comment. **Still open:** the blank-frame flake itself, and the flows' inability to retry a launch that presents nothing. `ios` must not be made a required check until both the flake is fixed and the trigger widened | S |
| **A-7** | `dart format` silently uses the wrong config in a git worktree | Worktrees have no `.dart_tool/`, so `dart format` cannot resolve `include: package:very_good_analysis/analysis_options.yaml`, prints a "Package resolution error" to **stderr**, and falls back to the default `trailing_commas: automate` instead of the project's `preserve`. Bare `dart format .` then reflows ~93 of 255 files, joining multi-line calls and stripping trailing commas. **The reason this is a real hazard and not a nuisance: `preserve` is *stable* on already-reflowed code, so `dart format --set-exit-if-changed` PASSES on the churn and `ci.yml` cannot detect it.** It cost real time in wave 4 — one agent put 85 out-of-scope files into its branch, including two files other agents were concurrently editing. Workaround used: copy `.dart_tool/package_config.json` from the primary checkout into each worktree (it is gitignored, so it can never be committed); `flutter pub get --enforce-lockfile` also produces it. A durable fix would be a committed formatter config that does not depend on package resolution, or a lefthook check that fails on the warning | XS–S |

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

**Wave 2 — trust gaps.** B-1, B-3, B-4, B-6 are mutually independent.
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

- **Two plans both claim schema v10.** ~~B-3 adds `settings.pendingJoinCode`;
  G-1 adds a `(status, closed_on)` index. Current schema is v9.~~ **Resolved
  for G-1.** v10 went to `settings.membershipRevoked`
  (`docs/specs/household-lifecycle.md` §3.5), so G-1's index landed as
  **v11** with a v10 → v11 migration test. ~~B-3 must now take **v12**.~~
  **Closed 2026-08-17:** B-3 took **v12** (`settings.pendingJoinCode`),
  placed inside the `settings` `else` branch as `if (from < 12)` because
  `settings` did not exist before v2 and a v1 → v12 jump already builds the
  table at full width via `createTable`. **The next migration is v13.**
  Whichever lands next must keep claiming the next free number: two
  migrations sharing a version is a corrupt upgrade path, not a conflict git
  will surface. Assign the number at MERGE time, never from plan text —
  B-3's own plan still said v9 → v10 when it was executed.
- **A-4 before E-2.** Both rewrite `reset_flow.dart`: A-4 adds sign-out and
  digest-cancel to `_confirmAndReset`, E-2 extracts that method. Extracting
  first silently drops the sign-out.
- **Shell (D-1/D-4/D-6) before B-5.** Both touch `_TabContent`/`_BottomTabBar`.
- **A-1 before F-1.** F-1 assumed the digest's shape rather than reading
  A-1's rolling 7-day horizon; compatible, but needs a rebase.
- **A-5 before G-1.** The stats screen makes `completedBy` authoritative;
  shipping it over unfixed misattribution enshrines wrong data.
- ~~**`app_de.arb` escapes umlauts inconsistently.**~~ **Closed 2026-08-17**
  (commit `102d4c3`): `syncRefreshError` was the only `\u`-escaped line in
  either `.arb` file and now uses literal `ä/ö/ü/ß` like the other 65 German
  lines. `flutter gen-l10n` reproduces the generated localizations
  byte-for-byte, so this was purely a source-convention change. Two notes for
  whoever meets this again: the JSON parser decodes both forms identically, so
  a tool that reads the file *decoded* (as most editors and edit tools do)
  cannot see the difference and will report "no change to make" — the fix
  needs a byte-level replacement. And a plan written before this landed may
  still assert the escapes are present; the offline-indicator plan did, citing
  `xxd`, and its executor correctly refused the instruction after checking
  that `xxd` now shows literal UTF-8 (`c3 84`).
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
| **A-1b** | **The digest goes silent after 8 unopened days** | **DONE 2026-08-14** (`docs/plans/2026-08-14-digest-horizon-ceiling.md`): the horizon is now segmented -- 14 daily slots then 10 at weekly spacing -- so the same 24 ids reach day 83 instead of day 23. A test pins `digestHorizonSlots <= 32`, reserving 40 of iOS's 64 for the unbuilt per-chore reminders (G-6/F16). Was: Follow-on to A-1, found in the v0.5.0 handover (§3.1). The rolling horizon is 7 days (ids 1001..1007), so an app left unopened longer than that is silent again — failing exactly the disengaged user a reminder exists to re-engage. **The non-obvious part:** horizon length buys no *accuracy*. The projection assumes the local DB doesn't change, which holds while the app is closed, so staleness is binary — right if nothing changed, stale if another device acted — and that applies equally at day 2. Day 28 is as accurate as day 8, so `digestHorizonDays`' "comfortably inside iOS's 64-notification cap" rationale is true but not load-bearing. The number to protect is the unbuilt per-chore reminders (G-6/F16), not 64. Planned 2026-08-14 | `lib/domain/digest_planner.dart`, `lib/application/notification_scheduler.dart` | S–M |
| **A-2** | **Date-derived UI never rolls over at midnight** | `clockProvider` never re-emits. `closedTodayOccurrencesProvider` captures `today` at build time and watches nothing that changes at midnight — an app left open overnight shows yesterday's completions under "Done today" forever, and the progress ring with it. Section buckets only refresh if catch-up happens to change something. `CatchUpController` already owns a DST-safe midnight timer; its only consumer is catch-up | `lib/app/providers.dart:545-552,820-884`, `lib/features/chores/chores_list_screen.dart:53` | S |
| **A-3** | **Android auto-backup unconfigured** | No `allowBackup`, no `dataExtractionRules`, no `fullBackupContent` anywhere under `android/`, so backup defaults on with no rules: a live SQLite file plus WAL sidecars copied uncoordinated, and the Supabase refresh token + pull cursor restored onto a second device. Under last-push-wins that is a data-clobbering configuration. Invisible in every emulator and E2E run — same blind-spot class as the v0.2.0 `INTERNET` miss. **Decided (D-B1): `allowBackup="false"`. Planned in `docs/plans/2026-08-08-android-backup.md`, ready to execute** | `android/app/src/main/AndroidManifest.xml`, `docs/app-lifecycle.md` G8 | XS–S |
| **A-3b** | **iOS: no backup exclusion on the local DB** | `chore_app.sqlite` (+ `-wal`/`-shm`) lives under `getApplicationDocumentsDirectory()` (`drift_flutter`'s native default, no iOS/Android branch), which iCloud/iTunes backs up by default — same torn-restore and cross-device session-clobber shape as A-3, but the fix is per-file (`NSURLIsExcludedFromBackupKey` at runtime), not a manifest flag, so it needs its own scoping pass. Deliberately excluded from A-3/D-B1, which is Android-only | `ios/Runner/Info.plist`, wherever the DB file is opened (`lib/data/db/app_database.dart`) | S |
| **A-4** | **"Reset app data" leaves the account signed in** | **DONE 2026-08-14** (`docs/plans/2026-08-08-reset-signs-out.md`): reset now cancels the digest and ends the Supabase session before the wipe, both best-effort and never blocking it (`on Object`, since a plugin `LateInitializationError` is an Error, not an Exception). Was: `resetAppData` wipes eight tables and nothing else; the Supabase session survives, so the user lands on the welcome screen still authenticated and *Join* skips the email step. The linked confirm copy says "You can reconnect by signing in again", describing a sign-out that never happens. Should also cancel the scheduled digest | `lib/application/data_reset.dart`, `lib/features/settings/reset_flow.dart` | S |

---

## B. Trust and safety gaps (triage Tier 2 — all verified still open)

| ID | Title | What's wrong | Files | Effort |
| --- | --- | --- | --- | --- |
| **B-1** | Catch-up after a lapse is invisible (T2.1) | **DONE 2026-08-17** (`docs/plans/2026-08-08-catchup-visibility.md`): `catchUpOverdue` now returns the number of chores it moved, and a self-hiding banner says so in plain terms — a banner, not a snackbar, since four seconds is too thin to de-escalate something that reads as an accusation. The copy closes on the at-most-one-overdue-occurrence-per-chore invariant, which is the fact that actually de-escalates; neither locale contains "missed" or "failed". Also collected the three loose banners into a `_BannerRegion` with a documented ordering contract. **Not E2E-coverable:** `E2E_TODAY` freezes the clock so an in-flow chore can never become overdue — carried by a widget test seeding a two-week backlog before the first frame. Was: `catchUpOverdue` silently converts a backlog to "missed" before the list renders, with no explanation. To a returning user it reads as an accusation | `lib/application/chore_service.dart:138-178`, `lib/features/chores/` | S |
| **B-3** | Join wizard keeps no persisted state (T2.4) | **DONE 2026-08-17** (`docs/plans/2026-08-08-join-wizard-state.md`): the join subpage is pushed back open when a signed-in user lands on the welcome screen with no household (which can only mean an interrupted join), and the last server-accepted code is prefilled from a new `settings.pendingJoinCode`. Landed as schema **v12**, not the plan's stale v10 — see the execution hazard above. Two plan instructions were refused as bugs: the auto-resume had no route guard (a sign-in while the user was already on the join page pushed a second copy over the first, and the single post-join pop then left them on a stale page instead of their new household), and the prefill read `settingsProvider.valueOrNull`, whose first state is always `AsyncLoading`, so it would have prefilled nothing in exactly the cold-start ordering the feature exists for. Was: Switching to Mail to tap the magic link can drop the user back to the welcome screen mid-join; the route is not restored across process death | `lib/features/onboarding/welcome_join_page.dart` | M |
| **B-4** | Rotation order can't be edited, only rebuilt (T2.5) | **DONE 2026-08-14** (`docs/plans/2026-08-08-rotation-reorder.md`): rotation assignees render as a reorderable list (drag handle, avatar, order label, remove button); order is edited directly rather than rebuilt by deselect-then-reselect. Was: Re-tapping always re-appends; no reorder handle, while Categories next door has drag-reorder | `lib/features/chores/chore_form/assignment_fields.dart` | S |
| **B-5** | A denied notification permission is permanent in practice (T2.6) | **DONE 2026-08-17** (`docs/plans/2026-08-08-notification-permission-recovery.md`): two ambient signals now carry the recovery. The Settings digest row grows a factual sub-line when the toggle is ON but the OS permission is denied, so the switch's ON position can no longer imply a delivery that is not happening; and the Settings tab carries a small dot, making the recovery path visible from every tab. Both are live projections of provider state with no dismiss action and no one-shot flag, so they clear by themselves once the permission is granted on app resume or the digest is switched off. A fresh install stays silent — the dot additionally requires `digestPrepromptShownAt != null`, because a permission never *requested* reads identically to a denied one on iOS and Android 13+. `permissionDenied` is presentation only and never writes back to stored `digestEnabled`, which stays the record of what the user WANTS. Was: The only nudge is a one-shot banner; recovery lives in Settings, which the user who most needs it never opens | `lib/features/chores/digest_preprompt_banner.dart`, `lib/features/settings/digest_section.dart` | S |
| **B-6** | Push has no periodic retry (T2.7) | **DONE 2026-08-14** (`docs/plans/2026-08-08-push-retry.md`): the foreground poll now pushes then ALWAYS pulls, so a persistently-rejected row can no longer turn the 60s freshness bound into a silent pull blackout. Was: `_armPoll` arms `pullSince` only. A write made as connectivity drops sits dirty until the next local write or app resume | `lib/application/sync_engine.dart:307-317` | S |

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
| **C-2** | **Slices 4–6: remove a claimed member (F10), leave household (F9) + last-member cascade warning, delete account (F11)** | **PARTIALLY DONE 2026-08-18** (`docs/plans/2026-08-08-household-lifecycle-slices-4-6.md`) — the earlier "needs a plan" note here was stale. **Landed:** the `exit_confirm_sheet` overflow fix on BOTH axes (the handover flagged only the vertical `isScrollControlled`/bare-`Column` case; the horizontal one is Cancel plus a label as long as "Konto löschen" not fitting 288 logical pixels at 2× text scale, now an `OverflowBar` matching `AlertDialog.actions`) — this satisfies the one hard ordering constraint the handover named, ahead of slices 5–6; the three exit RPCs on `HouseholdGateway` (`removeMember` has a caller, `leaveHousehold`/`deleteAccount` are inert tested plumbing so 5–6 has a concrete entry point); `MemberService.deleteMember` routing by claim state with `ClaimedMemberRemovalFailure`; and `syncRefreshErrorRevoked` on both list screens, so a revoked device stops being promised a sync that cannot happen. **STILL OPEN: slices 5–6's user-facing surfaces** — leave-household, the last-member cascade warning (D-L5), and delete account. Nothing half-built shipped: there is no leave/delete UI, and F10's new service path is still gated off by `member_edit_sheet`'s `_canDelete` (`userId != null` ⇒ no Delete button), so **F10 is not yet reachable by a user.** **Two things for whoever resumes.** (1) Unhiding Delete for claimed members means handling `ClaimedMemberRemovalFailure` INLINE — it needs the network, changed nothing, and the person is still in the household; the call-site comment in `member_edit_sheet` now says so explicitly. (2) The revoked-refresh snackbar is a NARROW RACE, not the primary surface: `syncEngineProvider` is gated on `settings.syncHouseholdId` and the engine's own startup/60s probe usually detects revocation first, calling `clearSyncLink()` and turning the provider into a `NoopSyncEngine` whose `refreshNow()` returns true — so a later pull-to-refresh reports success silently. That is covered by the revocation notice (§3.5), not this string. Two tests failed on exactly this and were fixed in the tests, not the implementation. Also: **next migration is v13**, and the two-step confirm already exists as `confirmTwoStepDestructiveAction` (`lib/features/settings/destructive_confirm.dart`) — compose a step pair, do not copy a dialog builder | L |
| **C-3** | Orphan household cleanup (F13) | **DONE with C-1** — the slice-1 migration's cascade (§2.4); listed here so it isn't tracked twice | — |
| **C-4** | **Reconnect wipes local data; Adopt fails after revocation** | **DONE 2026-08-14** (`docs/plans/2026-08-14-reconnect-adopt-hardening.md`): `join`/`joinFresh` now refuse an unconfirmed snapshot BEFORE the transaction opens, so the destructive replace cannot run on an empty download; adopt's PK-conflict after a revocation is a terminal explanatory state instead of an impossible retry. **CAVEAT: the four pgTAP assertions are written but NEVER EXECUTED** -- no workflow stands up Supabase. A/B/C are characterization tests, labelled as such in the file; **D** (`create_household` on a taken id raises `23505`) is a NEW contract the client's `HouseholdIdTakenFailure` branch depends on, and its deliberate-red check is outstanding. Was: **Reconnect is a LIVE data-loss bug in the released v0.5.0, not a latent one.** `ReconnectChoice` makes no RPC; `downloadHousehold` returns an EMPTY result rather than erroring when RLS hides the household; `join` then deletes the local household and inserts nothing. The archive is the only trace and there is no importer (G-3/F12 unbuilt). Exposure today is narrow but real: `remove_member` is in the applied production migration even though its client UI is still C-2, and revocation detection already ships — a removed member tapping *Reconnect* is the path. Fix: abort the replace before the transaction on an unconfirmed snapshot. **(b)** Adopt deterministically fails after a revocation-triggered unlink — `create_household` takes the LOCAL household id verbatim, which still exists server-side, so the insert PK-conflicts (`23505`) into a generic failure state. The sharper mechanism: `adopt`'s resume heuristic keys on "can I still read this household", true after Disconnect and false after revocation, so the one user it cannot rescue is the removed one. Join-by-code still works. **Must land BEFORE C-2**, ahead of that plan's Task 12. Planned 2026-08-14 (`docs/plans/2026-08-14-reconnect-adopt-hardening.md`) | `lib/application/household_gateway.dart`, `household_join_service.dart`, `household_link_service.dart` | M |
| — | *Withdrawn claim, kept as a record* | An earlier version of C-4 asserted that `findMyMembership`'s missing `members.deleted_at`/`households.deleted_at` predicates let a stale membership offer a destructive reconnect into a dead household. **That was wrong.** RLS already closes both doors: `is_household_member` requires the caller's own row to be active, and `_cascade_if_orphaned` never soft-deletes a household still holding a claimed active member. The predicates are still worth adding as labelled defence-in-depth, and C-4 does so with pgTAP proving the RLS behaviour — but nobody should re-derive a threat model from the absent predicates alone | — | — |

**Note on urgency:** F11/G6 (account deletion) is a *store requirement* on both
Apple and Google when accounts exist. Under the current open-source-only
distribution decision it is GDPR-driven rather than store-driven — see the
distribution question below.

---

## D. Established mobile conventions

| ID | Title | State | Files | Effort |
| --- | --- | --- | --- | --- |
| **D-1** | Swipe left/right between tabs (F1) | **DONE 2026-08-14** (`docs/plans/2026-08-08-shell-navigation.md`): `IndexedStack` -> keep-alive `PageView`; every `shell.tab.*` id preserved byte-identical. Was: `IndexedStack` → `PageView` while keeping per-page keep-alive, every `shell.tab.*` id, and the hand-rolled bar's semantics workaround | `lib/app/app_shell.dart` | M |
| **D-2** | Swipe-to-delete on shopping items (F2) | **DONE 2026-08-17** (`docs/plans/2026-08-08-shopping-gestures.md`): one direction only (`endToStart`, delete), wrapping the existing `semantic()` id so every `shopping.item.<id>` selector is preserved, and reaching the same `deleteShoppingItemWithUndo` the edit sheet already used. The RED run made decision D-S2's cost concrete: with no `Dismissible`, a right-drag over a row was claimed by the shell's `PageView` and paged back to Chores, so the right-swipe test is now a regression guard on the gesture-arena outcome rather than on the `direction:` argument. **iOS UNVERIFIED** — see A-6; `e2e.yml`'s `ios` job never runs on a PR, and iOS additionally has a left-edge interactive-pop recognizer that could compete with an `endToStart` drag started near the leading edge. Was: Undo already shipped via the edit sheet; only the `Dismissible` gesture is missing (no `Dismissible` anywhere in `lib/`) | `lib/features/shopping/shopping_item_tile.dart` | S |
| **D-3** | Long-press context menu on shopping items (F3) | **DONE 2026-08-17** (`docs/plans/2026-08-08-shopping-gestures.md`): `onLongPress` on the row's existing `InkWell` opening a delete action sheet — the tap-reachable equivalent of D-2's swipe for anyone who cannot perform a calibrated drag, which is why it ships alongside rather than instead. Both new gestures also unfocus the quick-add field, matching what check/uncheck and a scroll drag already did. Was: Chores have `onLongPress`; shopping doesn't. Pattern to copy already exists | `lib/features/shopping/shopping_item_tile.dart` | S |
| **D-4** | Re-tap a tab to scroll its list to top (F4) | **DONE 2026-08-14** (`docs/plans/2026-08-08-shell-navigation.md`): re-tapping the active tab scrolls its list to top. Was: `_onTabSelected` only clears snackbars and swaps the index | `lib/app/app_shell.dart` + both list screens | S |
| **D-5** | Offline / can't-reach-server indicator (F5) | **DONE 2026-08-17** (`docs/plans/2026-08-08-offline-indicator.md`): both list screens carry a non-dismissible `secondaryContainer` banner naming pull-to-refresh, with no tap target and without the word "offline". Thresholds are named constants (`pullStaleAfter` 5 min, `dirtyStaleAfter` 3 min) with their rationale in `sync-freshness.md` §2.5. **Two plan design defects were found and fixed, either of which would have shipped a broken feature:** the plan measured pull staleness from `syncLastPulledAt` alone, which is legitimately hours old the instant the engine returns, so the banner would have flashed on nearly every cold start and every resume after >5 min away — the exact cry-wolf failure the thresholds exist to prevent; staleness is now floored by an `observingSince` stamp. And the plan left recomputation to Riverpod's dependency graph, which would have made the feature **inert in its central case**, since an unreachable device persists nothing and a second local write re-emits an *equal* `AsyncData` that Riverpod correctly treats as no change, so no threshold could ever be observed as crossed; a one-shot self-invalidating 60s timer now drives it, armed only after the unlinked early-returns so it never trips `flutter_test`'s pending-timer check. **E2E cannot cover this** — the suite runs permanently unlinked; recorded in `sync-freshness.md` §4. Was: Only a passive "Last synced" line in Settings exists; a linked device that cannot reach Supabase looks identical to a healthy one everywhere else. Worth promoting given A-1 and B-6 | `lib/application/sync_engine.dart`, `lib/features/settings/account_section.dart`, both list screens | M |
| **D-6** | Android back on a non-first tab exits the app | **DONE 2026-08-14** (`docs/plans/2026-08-08-shell-navigation.md`): `PopScope` returns to the first tab; back THERE exits immediately, no confirm toast. Was: No `PopScope`; Material guidance is that back returns to the start destination first. Natural companion to D-1/D-4 | `lib/app/app_shell.dart` | XS |

---

## E. Small, unambiguous fixes

*Good candidates for one combined wave.*

| ID | Title | What's wrong | Files | Effort |
| --- | --- | --- | --- | --- |
| **E-1** | Notification channel name is hardcoded English | **DONE 2026-08-17** (`docs/plans/2026-08-08-small-fixes-wave.md`): the channel copy goes through l10n, on a new id `digest_v2`, with the legacy `digest` channel deleted in `ensureInitialized` so upgrading users do not accumulate a dead English-named row. The channel LABEL stays frozen at its creation locale and that is accepted and recorded at the call site — Android offers no rename, and a per-language id would accumulate one dead row per language tried while discarding the user's own sound/importance customisation each time; title and body, which is what the user actually reads, re-resolve on every reschedule. **Also fixed a defect the plan did not name:** the scheduler resolved its locale from the OS while the UI honours the in-app override, so German-on-an-English-phone already got English digest notifications. Was: `'Daily summary'` / `'The once-a-day chores digest notification.'` are user-visible in system Settings → Notifications. Violates the all-strings-through-l10n rule. Android caches the channel name at creation, so a later change needs a new channel id — fix before the first wide install | `lib/application/notification_scheduler.dart:155-158` | XS |
| **E-2** | Startup error screen is a dead end | **DONE 2026-08-17** (`docs/plans/2026-08-08-small-fixes-wave.md`): the startup error screen has a retry and an escape hatch, and the two-step destructive confirm is extracted as `confirmTwoStepDestructiveAction` in `lib/features/settings/destructive_confirm.dart`. **The hazard this row carried was real:** the plan instructed a wholesale replacement of `reset_flow.dart` whose replacement silently dropped A-4's sign-out and digest-cancel. It was refused; the extraction preserves the load-bearing ordering (digest-cancel → sign-out → wipe → invalidate) with both best-effort steps under `on Object`, never `on Exception`. Was: `_ErrorScaffold` renders the raw exception `toString()` with no retry and no way out; a database-open failure bricks the app permanently. The list screen's `_ErrorState` already has the retry pattern to copy | `lib/app/app.dart:79-102` | S |
| **E-3** | In-app privacy disclosure above the sign-in field | **DONE 2026-08-17** (`docs/plans/2026-08-08-small-fixes-wave.md`): the two-sentence disclosure sits above the email field on both surfaces, using the overruled wording that says data goes to "the sync server" rather than "our server" (wrong for a self-hostable, F-Droid-distributed app) and states that without an account everything stays on the device. Was: `PRIVACY.md` shipped, but the one-line "what's stored and where" sentence above the email field never did. The 2026-08-01 doc gates this on "before any public announcement of sync" | `lib/features/settings/account_section.dart`, `lib/features/onboarding/welcome_join_page.dart`, l10n | XS |
| **E-4** | `Recurrence` has no `==`/`hashCode` | **DONE 2026-08-17** (`docs/plans/2026-08-08-small-fixes-wave.md`): value equality added, and the sweep for behaviour changes found exactly one production caller — `_sameRecurrence` in `chore_service.dart`, which compared `jsonEncode(toJson())` strings and whose own doc comment admitted it existed only because `Recurrence` had no `==`. Removed. No `Set<Recurrence>`, no `Map<Recurrence, _>`, and no Riverpod `select` projecting a `Recurrence`. Was: Last unclosed bullet from the old backlog; add before something needs state comparison and gets it subtly wrong | `lib/domain/recurrence/recurrence.dart` | XS |
| **E-5** | `pubspec.yaml` still says "A new Flutter project." | **DONE 2026-08-17** (`docs/plans/2026-08-08-small-fixes-wave.md`). Was: Package metadata on an open-source release | `pubspec.yaml:2` | XS |

---

## F. Platform integrations (each needs its own decision before starting)

| ID | Title | Why it matters | Effort |
| --- | --- | --- | --- |
| **F-1** | Notification actions — mark a chore done from the digest (F6) | **DONE 2026-08-17** (`docs/plans/2026-08-08-notification-actions.md`), tasks 1-9 of 10. "Done" only, as recorded. The plan was first retargeted at the segmented digest, because the original planned to recover the actioned occurrence from `NotificationResponse.id` — impossible, since ids are slot-relative and the background path substitutes `-1` outright — and because its isolate-side acting-member chain was only `actingMemberProvider`'s *unpinned* branch and would have re-introduced the A-5 misattribution for every linked household. Occurrence and member now travel in a versioned JSON payload. `completeOccurrence`'s `completedBy` widened to `required String?`: in-app a null identity is still REFUSED with a snackbar, from a notification it is recorded as null, since dropping the tap discards an explicit "I did this" and guessing is what A-5 closed. **Task 10's first gate is now CLOSED: the background isolate CAN open the database — confirmed on a real Android device against v0.7.0 (build 10), 2026-08-18, by tapping "Done" and seeing the chore marked done in the app.** That was the premise Tasks 7-9 rested on, so the explicit-file-path fallback is not needed. **Still unverified:** whether the isolate survives long enough to rewrite the horizon (the check is a ONE-OFF chore actioned with the app away, then no notification claiming it overdue at the next slot — its fallback is to accept the truncation, NOT to call `cancelDigest()`, which would trade one wrong notification for up to 83 days of silence), and iOS end to end. `AppDelegate.swift` is compiled by NO PR job; it parses clean under `swiftc -parse` and matches the plugin's documented setup, and that is the whole of its verification. **The release APK still needs an assertion that `ActionBroadcastReceiver` is present** — its absence looks exactly like a working app until someone taps the button. Was: Strong fit for a chores app; needs a background isolate handler and its own tests | M |
| **F-2** | Share-to-app — "add to shopping list" from any share sheet (F7) | Would change how the shopping half feels day to day | L |
| **F-3** | Home-screen widget for the shopping list (F8) | Same, and multi-day native work per platform | XL |

---

## G. Product features

| ID | Title | Notes | Effort |
| --- | --- | --- | --- |
| **G-1** | Stats — "who actually does the chores" (F19) | **SHIPPED** as `docs/specs/stats.md` (Settings → Chore history). D2 step 2 closed with it: the stronger "its history is kept — you'll find it under Settings › Chore history" delete copy is restored and now true. Landed the `(status, closed_on)` index as schema **v11**, not v10 — see the execution hazard below, which v10 (`settings.membershipRevoked`) had already claimed | L |
| **G-2** | Repeat-form structural redesign (F14) | G3 stage 2 — the wording was fixed, the structure was not | M |
| **G-3** | Restore from a backup file (F12) | Export exists, import does not. Explicitly a non-goal of the P4 spec, so it stands alone | M |
| **G-4** | Custom avatars — photo or colour-as-border (F15) | User request, round 1 | M |
| **G-5** | More category icons and colours (F17) | User request, round 1. Icon set unchanged at 15 entries | S |
| **G-6** | Finer-grained notifications — N2: per-chore reminders, evening re-reminder (F16) | Own spec; depends on A-1 landing first | L |
| **G-7** | Search in long lists (F18) | Low value at family scale | M |
| **G-8** | Multiple shopping lists (F20) | Schema is single-list today | XL |
| **G-9** | Digest scope toggle — a per-device "include unassigned chores in my digest" opt-in | The opt-in that `DESIGN.md` §3 originally promised, retired as a *default* by OPD-1 (`docs/plans/2026-08-08-daily-digest-scheduling.md`) rather than as a *capability*. Would be a per-device `settings` boolean feeding `projectDigestCounts`'s recipient predicate — genuinely small, but it is a new settings row, new l10n and new widget tests, and nobody has asked for it. Build it if a real household reports the over-inclusion as noise, not before | S |
| **G-10** | Fork a removed member's local copy into a new online household | From **OPD-1** of `docs/plans/2026-08-14-reconnect-adopt-hardening.md` (option 2, deliberately not built there). **Not a bug fix**: keeping the local copy after a removal is already the D-L3 default, so nothing is missing — turning that copy into an *independent online household* is a new capability. **Carry this finding, it is the whole reason this is not a small task:** after a revocation the local rows are copies of the original household's SERVER rows and share their ids, so minting a fresh **household** id alone is insufficient. `create_household` inserts the acting member *by id* and PK-conflicts too, and `uploadHouseholdData` would then be silently skipped for members (`ignoreDuplicates: true`) or RLS-rejected for the other tables. The smallest correct version re-keys **every** local row carrying an id or FK, in one local transaction: `households`, `members`, `categories`, `chores`, `chore_assignees` (composite `chore_id, member_id`), `chore_occurrences` (`id`, `chore_id`, `assignedMemberId`, `completedBy`), `shopping_items` (`id`, `categoryId`, `addedBy`), plus `settings.actingMemberId`. A missed FK is silently orphaned history. Must NOT be improvised inside an adopt-failure branch. Entry point: the terminal adopt state added by that plan's Task 6. Build on evidence of demand | S–M |
| **G-11** | Reconnect chooser for an account in several households | From **OPD-2** of `docs/plans/2026-08-14-reconnect-adopt-hardening.md` (option b). An account can legitimately claim a member in several households (`delete_account`'s own comment in `20260808120000_membership_exit.sql` relies on it). Today `findMyMembership` returns one deterministic answer — most recent membership first, by `members.created_at` descending — and the offer always names the household so the user can decline. But it can still be the wrong one, and tapping it runs a destructive local replace. The fix is to return a list and make the reconnect row a picker: a gateway signature change plus one new UI surface, l10n and tests | S |
| **G-12** | `cancelDigest()` is unserialized against `applyDigestPlans` | Carried from the v0.5.0 handover §4 as "no concurrent caller today". **F-1 changed that**: a notification action rewrites the horizon from a background isolate, so a wipe racing an action is now reachable in principle. Bounded — the worst case is the one §4 already accepts for a mid-apply process kill, a single duplicate morning notification — and documented at the call site, but no longer hypothetical. Note the fix is NOT to have the action call `cancelDigest()`: that trades one wrong notification for up to 83 days of silence | S |

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
