# Famdo 0.14.0+21 — persona walkthrough: Leon, 14, reluctant participant

Method: read-only reconstruction from source. Every UI string below was read from `lib/l10n/app_en.arb`
(DE copy spot-checked in `app_de.arb`); every behaviour was traced through the code named in the citation.
Nothing was run on a device, so anything that depends on real rendering, OS mail clients, notification
delivery or ripple behaviour is marked "could not verify". Paths are relative to the repo root.

Severity: P1 = misleads / blocks / loses work. P2 = real friction on a common path. P3 = polish.
Effort: XS / S / M / L.

---------------------------------------------------------------------------------------------------

## Walkthrough summary (what Leon actually sees)

1. **Install + welcome.** Mum's share text is "Join my household on Famdo — enter the code {code} when you
   sign in." (`app_en.arb:1129`) with no install link or store hint. First launch shows the welcome gate:
   logo, "Share chores and a shopping list with your household.", then two cards
   (`lib/features/onboarding/welcome_screen.dart:209-228`). The **raised, accent-outlined, first** card is
   "Set up a new household / Keep it on this device — you can sync later."; the quiet second card is
   "Join my family's household / Sign in and use an invite code from a family member's device."
   Small print: "No account needed — everything stays on your device unless you sign in." (`:230-239`).
2. **Join.** Tapping join pushes `WelcomeJoinPage`. Step 1 is an email field under a long paragraph
   ("Signing in stores your email and your household's data … on the sync server", `app_en.arb:1399`),
   button "Send sign-in link", then "Check your email at {email} for your sign-in link."
   (`welcome_join_page.dart:202-248`). It is a magic link only (`auth_gateway.dart:106-111`,
   `signInWithOtp` + `emailRedirectTo`; no typed-code path anywhere in `lib/`). Only after the link
   returns does he reach "Enter your invite code" (`join_flow_steps.dart:101-103`), then
   "Which profile is yours?" with one row per unclaimed member, "Are you {name}?", plus "I'm new here"
   (`join_flow_steps.dart:171-193`), then a spinner and the Chores tab.
3. **Daily open.** Chores tab, unfiltered: sync banner (if any) / catch-up banner / digest pre-prompt,
   a progress card ("2 of 9 done today", "7 still to go", ring), then sections Overdue / Today / Tomorrow /
   This week / This month / Later, each tile = complete ring, title, assignee avatar + first name, category,
   due chip (hidden under Today/Tomorrow), optional note line (`chore_occurrence_tile.dart:118-177`).
   Collapsed "Done today (N)" and "Paused (N)" at the very bottom.
4. **Complete.** Tap the ring: writes immediately, medium haptic, snackbar "Done" or
   "Done — next due {text}" with UNDO for 4 s (`chores_list_screen.dart:250-288, 404-471`,
   `snackbars.dart:60`). Long-press (or the kebab) opens Skip / Edit / Pause / Delete
   (`chore_action_sheet.dart:45-121`; "Mark done for…" only if linked and >1 member).

---------------------------------------------------------------------------------------------------

## A. Pain points

### A1. [P1] The first screen steers a joiner into "Set up a new household"
- **Leon:** "Mum sent a code, the big button says set up, so I'll tap the big button."
- **What happens:** `welcome.create` is `emphasized: true` (raised shadow, `primaryOutline` border) and sits first;
  `welcome.join` is the plain secondary card (`welcome_screen.dart:209-228`, `_WelcomeCard` styling `:397-400`).
  The onboarding spec makes this binding ("Primary card: Set up a new household", `docs/specs/onboarding-v2.md` §1)
  because the design optimised for the household *creator*. A joiner who taps create types a name, lands in a
  solo local household with "No chores yet / Add your first chore with +" (`app_en.arb:290-294`), and the only way
  out is Settings → Account → "Join an existing household — Use an invite code from another device — this replaces
  your local data" (`app_en.arb:1652-1656`) followed by the archive/import steps
  ("Bring over your open chores? … Everything else is replaced", `app_en.arb:1720-1732`). That reads as a
  destructive path for someone who has only just started. Likelihood is moderate (the join card's subtitle does
  mention an invite code), but the cost is a dead-end first run, which for this persona is the whole relationship.
- **Suggest (S):** make the card order/emphasis symmetric, or add a one-time "Got an invite code?" entry as the
  top row of the create card/form. Better (M): a single "Enter invite code" field on the welcome screen that
  routes straight to the join flow and defers sign-in until the code is validated.

### A2. [P2] Sign-in comes before the code, is magic-link only, and the page leads with a data-policy paragraph
- **Leon:** "I wanted to type the code mum sent, not read about servers and go check my email."
- **What happens:** `WelcomeJoinPage._buildBody` shows the email step whenever `currentAuthUserProvider` is null
  (`welcome_join_page.dart:147-150`); the invite code is asked only after sign-in (`:187-196`). The first thing on
  the page is `settingsAccountIntro` (`:211`, `app_en.arb:1399`), 40+ words about server storage, reused from
  Settings. The user has to leave the app, find the email, and tap the link on the same phone. There is no typed
  one-time code alternative (`grep verifyOtp|otp` in `lib/` only hits the `signInWithOtp` call that sends the
  link), and the copy gives no "check spam / open it on this phone" hint (`app_en.arb:1415`). The kill-and-relaunch
  mid-flow case *is* handled well (`welcome_screen.dart:71-77, 118-138`). Whether the `famdo://auth-callback`
  link survives every mail client's in-app browser: could not verify (`AndroidManifest.xml:59`).
- **Suggest (M):** accept the code first (it is validated by `listClaimableMembers`, which needs auth today, so this
  needs a server change or a deferred validation); minimum (XS): move the policy paragraph below the button as small
  print and add one line "Open the link on this phone". Optional (M): 6-digit email OTP as an alternative to the link.

### A3. [P2] "Which one is me": one tap commits the claim, and the screen does not say which household it is
- **Leon:** "It listed four names and tapped one by accident — now I'm Mia?"
- **What happens:** each row calls `onClaim` -> `_runJoin(ClaimMemberChoice(...))` immediately with no confirm
  (`join_flow_steps.dart:176-185`, `welcome_join_page.dart:155-161, 362-370`). The rows carry only an avatar
  (colour + initials) and "Are you {name}?"; `ClaimableMember` has just `memberId/name/color`
  (`household_gateway.dart:33-45`), so there is no hint such as "has 3 chores assigned" and no household name
  anywhere on the join page (AppBar is the static "Join my family's household", `welcome_join_page.dart:128`).
  "I'm new here" sits last and creates a second "Leon" next to mum's pre-created one, leaving her chores assigned
  to a ghost (could not verify how mum would merge them; I found no merge feature). Undoing a wrong claim means a
  household member removing a *claimed* profile, which needs a connection (`app_en.arb:1229`).
- **Suggest (S):** a one-line confirm ("Join {household} as {name}?"), show the household name in the page header,
  and sort/emphasise by likely match (name equals the email/OS name). (M) show assigned-chore count per profile.

### A4. [P2] The default Chores view is the whole household; "mine" is an unlabelled icon, and it disagrees with his notification
- **Leon:** "I opened it and there are nine things with other people's faces on them. Where's mine?"
- **What happens:** the filter starts as `null` ("All") (`chores_list_screen.dart:52-63`; the stored filter only
  persists what he later chose, `last-tab-restore.md` §5). Filtering lives behind a `person_outline` icon
  (tooltip "Filter by member") next to a `label_outline` icon (`:150-163`, `chores_filter_bar.dart:32-37`); the menu
  lists "All members" and names with no "(you)" marker and no "Me" shortcut (`:43-62`). Tiles are ordered by due
  date then title, not by assignee (`chore_repository.dart:584-586`), so his rows interleave with everyone's.
  Worse, the filter hides *unassigned* chores (`chores_list_screen.dart:595`: `assignedMember?.id != memberFilter`),
  while his digest counts "your chores plus unassigned 'anyone' chores" (`docs/specs/notifications.md` N1,
  `docs/backlog.md` A-1). So "3 chores today" in the notification can disagree with a filtered list of 2.
  The progress card does honestly say "Filtered — not the whole household" (`app_en.arb:339`).
- **Suggest (S):** in pinned mode (`memberIdentityModeProvider == pinned`, `providers.dart:1100-1160`) default the
  filter to the claimed member on first open, or add an inline "Mine / Everyone" toggle row under the progress card.
  Mark "You" in the member menu. Make the member filter include unassigned chores (or label them "Anyone") so the
  digest count and the list agree.

### A5. [P2] The catch-up banner explains a mechanism, not what changed for him — and it covers less than it implies
- **Leon (back after 3 days):** "'Moved forward'? Forward to when? Why is it still red?"
- **What happens:** the banner reads "We moved 3 overdue chores forward to their most recent due dates, so nothing
  piled up." (`app_en.arb:411`, shown by `catch_up_banner.dart:52-55`). It is deliberately blame-free (no "missed",
  per its ARB description) — good — but "moved forward" is ambiguous in English (earlier or later?); DE "auf ihre
  neueste Fälligkeit verschoben" is no clearer (`app_de.arb:100`). It is not tappable and does not say which chores
  or that they now sit on today's slot. Scope is narrower than the sentence: `catchUpOverdue` only touches
  *schedule-anchored recurring* chores that have a later slot ≤ today (`chore_service.dart:177-197`;
  `occurrence-lifecycle.md` §catchUpOverdue). A weekly chore three days late, any one-off, and any
  completion-anchored chore are left as ordinary overdue tiles that keep ageing, turning error-red from 7 days
  (`due_tone.dart:11,29-41`). So he can see six overdue tiles under a banner that says three things were fixed.
  The banner is in-memory and returns on any later catch-up run (by design, `occurrence-lifecycle.md`).
- **Suggest (XS):** reword to the outcome: "Your repeating chores jumped ahead to their latest slot — you didn't
  miss anything extra." (S) make the banner tap scroll to / highlight the affected tiles.

### A6. [P2] Reminders have no off switch on this device, and the form label implies they are personal
- **Leon:** "I turned the summary off and my phone still buzzes about bins, and I never asked for that."
- **What happens:** the Settings notification group has digest toggle, evening toggle and quiet hours
  (`settings_screen.dart:117-206`); only `digestEnabled` is read by the planner and only for the digest
  (`digest_plan_builder.dart:239`). `planReminders` takes no enabled flag (`reminder_planner.dart:294-302`), so a
  chore with a reminder rings on the assignee's phone regardless. The reminder is a property of the shared chore:
  the form says "Remind me about this chore" (`app_en.arb:928`) but who gets pinged is "unassigned or assigned to
  the acting member" (`notifications-n2.md` §2.2), so mum ticking that box on Leon's chore pings *Leon*, not her.
  Leon has no per-chore way to mute a reminder except editing the household chore. Separately, after he taps
  "Not now" on the pre-prompt, a permanent 8dp dot sits on the Settings tab until he grants permission or turns
  the digest off (`app_shell.dart:331-335, 450-478`); the spec calls this "persistent signal, not nagging"
  (`notifications.md` "Saying so when the digest cannot be delivered"), which a reluctant teen will read as nagging.
- **Suggest (S):** a device-level "Chore reminders" master toggle (and honour the channel switch in OS settings);
  reword the form label to "Remind whoever is assigned"; clear the dot after N days or after a first visit to the
  digest row.

### A7. [P2] Any member can edit, pause, delete or reopen anything, and nobody is told
- **Leon:** "If I delete the bins chore, does anyone even know?"
- **What happens:** the long-press sheet offers Skip/Edit/Pause/Delete to every member with no role check
  (`chore_action_sheet.dart:45-121`; delete = confirm dialog then `softDeleteChore`, no undo,
  `chores_list_screen.dart:357-367`). `members.role` is "vestigial", no role gating by decision D1
  (`docs/specs/household-lifecycle.md:88,452`), and "remove member" works for any member (`:237`). Pause removes the
  pending occurrence for everyone and its undo is a 4 s snackbar (`:378-395`). History does keep deleted chores
  (`stats.md` §2.1) but there is no activity feed or notification to mum. This is a household-trust problem more than
  a Leon problem, but he is the persona who will test it.
- **Suggest (M):** a light "recent changes" list for admins; or make Delete/Pause admin-only for a household with
  >=2 claimed members. XS interim: a heads-up line in the delete dialog ("Everyone in the household will see this").

### A8. [P3] Gaming surface: early completion is allowed and credited; skip and catch-up leave no trace
- **Leon:** "I'll just tick the whole 'Later' section now, then skip the rest."
- **What happens:** the complete ring is on every tile in every section (`chore_occurrence_tile.dart:135-142`) and
  `completeOccurrence` has no due-date guard: it closes with `closedOn = today` (`chore_service.dart` `_closeAndAdvance`
  ~`:456-500`). Schedule-anchored chores then jump to the first slot strictly after `max(due, today)`
  (`recurrence_engine.dart:136-155`); that is deliberate (`docs/feedback/2026-08-01-field-feedback.md` B3 notes
  completing early is expected). The credit lands in the progress card (`chore_progress_card.dart:69-78`) and in
  Chore history (`stats.md` §2.1). Skip and `missed` never appear next to a name (`stats.md` §0 rule 1), so
  "skip everything" has zero footprint after midnight. Both are documented stances; the consequence is that nothing
  separates Leon's honest "done" from a pre-tick or a skip.
- **Suggest (S):** keep the behaviour, but show a "Done early" tag on the Done-today row when `closedOn < dueDate`,
  and surface skips to *mum only* in a household digest (not in a ranking). Not worth a confirm dialog for Leon.

### A9. [P3] Undo is short-lived, and Reopen is silent and unrestricted by person
- **Leon:** "I tapped the wrong circle on the bus and the Undo was gone before I looked up."
- **What happens:** snackbar Undo lasts 4 s (`snackbars.dart:60`). After that the only way back is the collapsed
  "Done today (N)" tile at the *bottom* of the list, below Paused, with a text "Reopen" on the latest row of each
  chore (`chores_list_screen.dart:764-775`, `chore_done_section.dart:93-118, 188-196`); and only same-day
  (`chore_service.dart` reopen guard `closedOn != today`). Reopen produces no snackbar (`:473-477`) and works on
  rows completed by *other* members, wiping their credit. After midnight a mis-tap is permanent through the UI.
- **Suggest (S):** a "Done today" shortcut chip at the top of the list when N>0; show "Reopened — you can mark it
  done again" snackbar; label rows "by Mum" and ask confirm when reopening someone else's.

### A10. [P2] Chore history: the share is raw counts across people, and a new member starts at an unfair zero
- **Leon:** "I've been here three days and it says Mum 92%, me 0%."
- **What happens:** the card lists every roster member in creation order with "{count} · {percent}" side by side
  (`stats_share_card.dart:71-75, 146`). The ranking rules are honoured (no sort, `stats.md` §0), but percent of
  total done across people is still the leaderboard's information. The 30-day window is clamped to the *household's*
  start, not the member's join date (`stats_service.dart:103-116`; `stats.md` §2.2), and zero rows are kept on
  purpose (`stats.md` §3.1), so a freshly joined member reads as 0%. It is also assignment-blind: someone with two
  chores assigned who did both shows a few percent. It lives in Settings → Household → Chore history
  (`stats.md` §1), so Leon will only meet it if mum shows him.
- **Suggest (S):** clamp each member's window to their own creation date and say so ("since {date}"); (S) drop the
  percent and show only counts, or show done/assigned. (XS) hide zero rows for members younger than the window.

---------------------------------------------------------------------------------------------------

## B. Missing features

### B1. [P2] The invite text has no way to get the app
- **Leon:** "Mum texted a code. For what? Where do I get this?"
- **What happens:** share text is "Join my household on Famdo — enter the code {code} when you sign in."
  (`app_en.arb:1129`); the sheet adds "expires in 7 days" and that any new invite revokes the previous one
  (`:1121`; `20260731120000_initial_schema.sql:121`). No link, no store name. Distribution is "GitHub Releases and
  F-Droid; no Play/App Store accounts, ever" (`docs/backlog.md:40`, D-B2), so on iOS I could not verify how a 14-year-old
  installs it at all (could not verify; `README.md` has no install section).
- **Suggest (S):** append an install/URL line to the share text (a landing page, or the release URL); (XS) mention
  the revoke-on-new-invite risk in the sheet ("giving Dad a code invalidates this one", partially said already).

### B2. [P2] Notifications are mostly non-actionable
- **Leon:** "I ignore anything I can't swipe away and be done with."
- **What happens:** per-chore reminders are scheduled "non-actionable and with no payload"; Done/Snooze are slice 7
  and not built (`notification_scheduler.dart:706-709`; `docs/backlog.md` G-6). The digest's Done button appears
  only when exactly one chore is counted (`notifications.md` N2 "Gate, evaluated PER SLOT"). The digest body is
  only a count, title "Famdo": "2 chores today · 1 overdue" (`app_en.arb:84`; `notification_scheduler.dart:673`).
  Tapping opens the Chores tab, unfiltered (A4). The per-chore reminder title is the chore name with body
  "Due today" / "Still open" (`app_en.arb:50-53`), which is the best-written one.
- **Suggest (M):** ship slice 7 (Done + "Tomorrow" on reminders); (S) list up to 3 chore names in the digest body
  (BigText on Android) so the notification itself answers "what do I have to do".

### B3. [P3] No receipt: nowhere to show "I did my part" beyond today
- **Leon:** "Mum says I didn't do anything Tuesday. Prove it."
- **What happens:** the only place his completions appear is "Done today", which resets at midnight
  (`chore_service.dart` reopen guard; list is `closedTodayOccurrencesProvider`), or Settings → Chore history per chore
  (`chore_history_screen.dart:79-119`). There is no "my last 7 days", and a per-member view is a *permanent* non-goal
  (`stats.md` §0 rule 5, §7). That rule and this need conflict.
- **Suggest (S):** keep stats as is, but extend "Done today" to "Done recently" (last 3 days) for the current user's
  own device only (no cross-person view), which gives Leon a receipt without a leaderboard.

### B4. [P3] Offline tick-off gives no per-item sync status
- **Leon:** "I did it on the bus. Did mum see it? Am I going to get yelled at?"
- **What happens:** completion writes locally, haptic, snackbar "Done" (`chores_list_screen.dart:250-288`).
  Sync is "no background sync while the app is closed" (`docs/future-improvements.md` known trade-off), so ticking
  off and closing the app leaves the change dirty until the next open. The banner "This device hasn't reached the
  rest of the household in a while. Your changes are saved — try pulling down to refresh." only appears after
  5 min stale or 3 min dirty (`sync_health.dart:34-48`) and only if the app is open and has been polling
  (`sync-freshness.md` §2.5). Pull-to-refresh offline gives "Couldn't reach the household. Your changes are saved
  here and will sync later." (`app_en.arb:1546`). Copy is honest and non-red, which is good; what is missing is any
  item-level "waiting to send" cue.
- **Suggest (S):** a small clock glyph on rows whose `syncDirty` is true, plus a last-synced time on the chores
  app bar long-press.

---------------------------------------------------------------------------------------------------

## C. Quality of life

### C1. [P3] "Skipped by Leon" blames the assignee, and every confirmation has a green check
- **What happens:** a skipped row's label uses the assignee as stand-in closer ("by {name}"):
  `chore_done_section.dart:139-144, 181-183`; the code comment admits "closest available stand-in". If mum
  skips Leon's chore, his Done-today list says "Skipped · by Leon". Separately every snackbar, including
  "Skipped", "Paused" and the "This device doesn't know who you are yet" error, is prefixed with a green
  check_circle (`snackbars.dart:50-56`).
- **Suggest (XS):** drop the "by {name}" on skipped rows (or record `skipped_by`); (XS) make the icon an argument.

### C2. [P3] The progress card counts the whole overdue pile as "today"
- **What happens:** `M = pending due-or-overdue + done today` (`chore_progress_card.dart:69-78`;
  `chores_list_screen.dart:141-143`). Back after 3 days with 7 overdue it reads "0 of 7 done today / 7 still to go"
  with a 0% ring (`app_en.arb:311, 325`). It also rewards early completion (A8) and, with the empty state
  "No chores pending — nice work!" / "That's everything — nice work" (`app_en.arb:282, 335`), has a tone a 14-year-old
  may read as patronising.
- **Suggest (XS):** exclude overdue from M or relabel to "7 to catch up"; a setting to hide the card; (XS) drop "nice work".

### C3. [P3] Tapping a tile does nothing, notes are truncated, and there is no swipe
- **What happens:** the tile `InkWell` has only `onLongPress` (`chore_occurrence_tile.dart:120-121`); a tap on the
  body is dead (whether a ripple shows: could not verify). The note is a single ellipsised line (`:158-161, 369-392`),
  and the full note is only reachable via long-press -> Edit, opening the edit form. Complete/skip by swipe does not
  exist; shopping swipe was removed because it fought the tab pager (`docs/backlog.md:70,80`), so the same
  constraint applies here.
- **Suggest (S):** tap opens a small read-only detail sheet (title, full note, history, Done/Skip); that is the
  modern equivalent without taking horizontal gestures from the pager.

### C4. [P3] Done from a notification is local until the app opens; no feedback
- **What happens:** the background isolate has "no Supabase session" and completes only locally, then pings the main
  isolate if alive (`notification_action_handler.dart:55-80`; `notifications.md` N2). Mum's view stays stale until
  Leon opens the app. The notification is dismissed with no toast, no undo, and the on-device behaviour is a GATE
  item still marked unverified (`notifications.md` "What no test in this repo covers").
- **Suggest (S):** when a background completion is not synced within a few minutes, show a one-line "Waiting to
  sync" in the sync banner; (XS) keep Done but also post a silent "Done ✓ {chore}" confirmation notification.

---------------------------------------------------------------------------------------------------

## What already works well

1. **Identity is pinned on a joined phone.** On a signed-in, linked device the app bar shows a non-interactive avatar
   (tooltip "You're signed in as {name}") and every tick credits the claimed member; the "who am I" switcher is gone
   (`acting_member_sheet.dart:48-56`, `providers.dart:1100-1160`). Leon never has to think about "acting as".
2. **Good completion feedback.** Haptic fires only after the write is confirmed, the snackbar says what happens next
   ("Done — next due Fri"), Undo reverts, and snackbars never stack (`chores_list_screen.dart:283-287, 404-471`,
   `snackbars.dart:35-69`).
3. **The dark theme is authored, not derived.** Hand-built dark ColorScheme with a measured contrast floor for member/
   category tones (dark floor 7.63) and due urgency carried by text ("Overdue · 2 days"), the section header, and a 3dp
   edge, never colour alone (`theme-v2.md` §1.1, §1.3; `chore_occurrence_tile.dart:184-191`, `due_tone.dart`). The
   known 4.5:1 label gap (G-13) is a light-theme issue only. Visual rendering: could not verify.
4. **Stance on blame is consistent.** Catch-up avoids "missed"/"failed" in copy (`app_en.arb:411` description);
   `skipped` and `missed` never count against anyone (`stats.md` §0); the share is in roster order with no medals,
   streaks or trends; the overdue digest is the only recurring "overdue" signal and per-chore reminders are silent on
   overdue (`notifications-n2.md` D8).
5. **Notifications are per-person and quiet by default.** The digest is scoped to the acting member and is silent when
   nothing is due; the evening re-reminder ships OFF; quiet hours defer instead of dropping
   (`notifications.md` N1; `notifications-n2.md` D6, D7, D12).
6. **Offline honesty.** The sync banner is neutral (secondaryContainer, not red), non-dismissible, never says "offline",
   and names the recourse (`sync_health_banner.dart:50-72`); pull-to-refresh only exists when there is something to
   pull (`chores_list_screen.dart:196-215`); the member filter now survives restarts (`last-tab-restore.md` §5).
7. **Resumable join.** Killing the app while checking mail resumes on the join page with the last accepted code
   prefilled (`welcome_screen.dart:71-77, 118-138`; `welcome_join_page.dart:97-106`).

---------------------------------------------------------------------------------------------------

## Known-backlog +1 (already tracked; one-line "hurts Leon because")

- **G-6 slice 7 (reminder Done/Snooze, `docs/backlog.md:336`)** — he ignores notifications he can't act on from the shade.
- **F-1 "Snooze to tomorrow" (`docs/backlog.md:72`)** — "not now" is his main move; today the only answer is to ignore it.
- **G-9 digest scope toggle (`docs/backlog.md:339`)** — the digest counts unassigned chores, so his number and his filtered list disagree (A4).
- **Known trade-off: no background sync while closed (`docs/future-improvements.md`)** — tick on the bus, close the app, mum sees it open.
- **Known trade-off: last-push-wins (`docs/future-improvements.md`)** — an offline tick can be overwritten by mum's concurrent edit with no notice.
- **D-2 swipe reversal (`docs/backlog.md:70,80`)** — explains why no swipe gestures on rows; a Leon-friendly gesture needs a pager-safe design.
- **Known constraint B-5 "banner never re-arms" (`docs/backlog.md:67`)** — good for him, but combined with the permanent Settings dot it is the only nag left.

## Could not verify

- On-device rendering (dark theme tone separation between the tinted tile grounds `#161E12 / #231C10 / #241812`
  and `surfaceContainerLow #211C18`; `theme-v2.md` §1.2 — the 3dp edge and chip likely carry the signal).
- Magic-link return via `famdo://auth-callback` from iOS Mail / Gmail in-app browser.
- Whether ripple feedback shows on a dead tap of a tile.
- How a duplicate "I'm new here" profile is merged or removed from mum's side.
- iOS distribution path for a joiner (the backlog states no store accounts).
