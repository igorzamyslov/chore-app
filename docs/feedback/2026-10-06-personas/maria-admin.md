# Persona walkthrough: Maria, 41, the household organiser (Famdo 0.14.0+21)

Method: read-only. Every screen and string reconstructed from source (`lib/l10n/app_en.arb`, `lib/features/**`, `lib/application/**`, specs). Paths are relative to the repo root. Nothing was run on a device, so anything about pixel layout is marked "arithmetic only" or "could not verify".

Severity: P1 = blocks / misleads / loses work. P2 = real friction on a common path. P3 = polish / QoL.
Size: XS / S / M / L.

---

## 0. Walkthrough trace (what Maria sees, in order)

**Step 1 - first launch.** `WelcomeScreen` shows the app tile, "Famdo", the tagline "Share chores and a shopping list with your household.", a raised card "Set up a new household / Keep it on this device - you can sync later.", a quieter card "Join my family's household" (only when Supabase is configured, `welcome_screen.dart:~190-225`) and small print "No account needed - everything stays on your device unless you sign in." (`welcome_screen.dart:233`). Tapping Set up opens one field, "Your name" (`:301`), and a "Get started" button; Enter submits. `HouseholdCreateService.create` makes the household, one admin member, seeds categories and marks the name banner as handled in one transaction (`lib/application/household_create_service.dart:60-73`). She lands on an empty Chores tab: "No chores yet / Add your first chore with +" (`chores_list_screen.dart:919,928`). Good, fast. Note she is never asked for a household name: it is hardcoded to `'My household'` (`lib/data/repositories/household_repository.dart:139`).

**Step 2 - chores.** FAB (+) opens `ChoreFormScreen` (`chore_form_screen.dart`). Top to bottom: Title, Notes, category chips (with an inline "Edit categories" entry), a "Repeat" switch, then (when on) one fill-in-the-blank sentence "Repeat every [1] [Week] on", weekday circles, "COUNTING FROM" with two radio cards ("On fixed days - e.g. every Tuesday" / "After last completion - 3 days after last done"), and a preview line "Every week on Tue, Fri. Next Tue, Oct 7, then Fri ... " (`repeat_controls.dart:111-221`, `recurrence_sentence.dart:154-233`). Then Start date, "Remind me about this chore" switch (default 18:00, hint "This chore won't be counted in the daily summary"), then assignment "Fixed | Rotation | Anyone", and a pinned Save bar (`chore_form_screen.dart:417-431`).
- Feed the cat: Repeat on, tap the unit hole, pick Day. Works; the "Counting from" card is irrelevant for a daily chore but harmless.
- Bins Tue+Fri: Week, tap Tue and Fri chips (a week rule can never be emptied, `:507-523`). Preview confirms the dates. Good.
- Bed sheets "first weekend": Month, mode "A weekday", pick "1st" + "Saturday". A literal "first weekend" (Sat or Sun) is not expressible; she will settle for the first Saturday. Not worth a finding.
- Plumber one-off: Repeat off, set Start date. Fine.
- Rotation across 3: Rotation, tap three chips, they become a reorderable list "1. Anna 2. Ben 3. Cleo" with drag handles (`assignment_fields.dart:215-231`). Order = turn order; first row gets the first turn (`docs/specs/occurrence-lifecycle.md` createChore). No on-screen text says that.
- Reminder: switch on, time card, hint. Save silently pops the form (`chore_form_screen.dart:683`).

**Step 3 - family.** Settings -> Household group: [Account block] -> Members -> Categories -> Chore history. Members screen: first row is the household name with a pencil (rename sheet), then member rows (avatar + name only), FAB to add (`manage_members_screen.dart:38-67`). Add sheet: Name, live avatar preview, 12-colour swatch grid (taken colours badged, hint "Your color is how you show up on every chore..."), Save. There is no role control; the household is deliberately flat (`docs/specs/household-lifecycle.md` D-L2). Inviting: in a local household the Members screen has no Invite row (`manage_members_screen.dart:32-33,40,46`); she must sign in by email in the Account block, tap "Put my household online" ("Makes your household available on your other devices."), and only then do "Invite a member" / "Invite" appear. The invite sheet shows an 8-char code + Share ("Join my household on Famdo - enter the code {code} when you sign in.").

**Step 4 - living with it.** Tile: ring to complete, title, assignee avatar + first name, category dot, due chip (hidden under Today/Tomorrow), note line. Tap on the body does nothing; long-press or the kebab opens Skip / Edit / Pause / Delete (+ "Mark done for..." only when linked and signed in, `chores_list_screen.dart:328-333`). Complete / Skip / Pause give snackbars with Undo; Delete gives only a confirm dialog.

**Step 5 - settings maintenance.** Rename household (Members -> first row). Categories: tap row -> sheet -> Delete shows an exact impact count ("This deletes 'Pets'. 3 chores use it and will become uncategorized.", `category_delete_dialog.dart:32-43`). Export data -> OS share sheet with `famdo-export-<date>.json`. "Last synced N minutes ago" appears only under the signed-in tile (`account_section.dart:176`).

---

## 1. Pain points

### P1-A. Editing who a chore is assigned to does not change the turn that is open right now
- Persona: "I took Anna off the bins because she's ill, saved, and the list still says Anna. Did it save at all?"
- What happens: `ChoreService.updateChore` returns early unless `recurrence` or `startDate` changed (`lib/application/chore_service.dart:364-366`); the repository only rewrites the `chore_assignees` rows (`lib/data/repositories/chore_repository.dart:230-256`). The tile reads the occurrence's own `assignedMember` (`chore_occurrence_tile.dart:248,266`), so the old person stays on the card until the chore is next completed or skipped. Same for Fixed Anna -> Ben and for Anyone -> Fixed. The form gives no hint. The contrast is sharp: deleting a member *does* unassign their open turns, and the dialog says so (`memberDeleteDialogBody`). This is deliberate and tested (`docs/plans/2026-08-08-rotation-reorder.md` points 2-3; `docs/specs/occurrence-lifecycle.md` updateChore), but nothing on screen tells Maria. The only workaround is to nudge the start date (which regenerates the occurrence, `chore_service.dart:368-393`).
- Suggestion (S): when assignment mode/assignees change and the current holder is no longer a valid assignee, re-resolve the open occurrence with `_regeneratedAssignee` (it already exists, `:613-632`). If that is too bold, show a one-line snackbar/confirm: "Today's turn stays with Anna. Reassign it now?"

### P2-B. Tapping a chore does nothing; everything lives behind the kebab or a long-press
- Persona: "I tapped 'Take out bins' to change the days and nothing happened."
- What happens: the tile's `InkWell` has only `onLongPress` (`chore_occurrence_tile.dart:120-121`); the complete ring and kebab are the only taps. The tile also never shows the repeat rule or whether a reminder is set (the paused row does show the rule, `chore_paused_section.dart:97-112`; the pending tile deliberately doesn't, comment `:76-81`), so tapping is also the natural way to "check what I set". Shopping rows open their edit sheet on tap, so the app is inconsistent. Already noted once in `docs/research/persona-anna.md` but not in backlog/future-improvements and still true.
- Suggestion (XS): `onTap: onOpenMenu` or open the edit form directly; or add a recurrence sentence to the metadata row on tap-to-expand (S).

### P2-C. A paused chore can be neither edited nor deleted until it is resumed
- Persona: "I paused the sheets for the holiday and now I want to move them to Sunday. I have to un-pause it first?"
- What happens: `_PausedRow` is a bare `ListTile` with only a trailing Resume button, no `onTap`, no long-press, no menu (`chore_paused_section.dart:85-124`). Resume regenerates a pending occurrence (`chore_service.dart:257-310`, spec "unpauseChore"), so editing a parked chore means un-parking it first and then finding it in the list. Deleting a paused chore is the same detour.
- Suggestion (S): tap/long-press on a paused row opens the same action sheet (Edit / Resume / Delete), or at minimum Edit.

### P2-D. "Invite" silently kills the code Maria already sent, and the old code can never be shown again
- Persona: "I wanted to read the code out to my son and now my husband's code doesn't work."
- What happens: `runInviteFlow` calls `revokeActiveInvites` then `createInvite` every time (`lib/features/settings/invite_flow.dart:28-30`). The explanation ("Share this code - it replaces any earlier code and expires in 7 days.", `invite_code_sheet.dart:46`) appears only after the old code has already been revoked. There is one live code per household, not per person, and no screen shows the current code. The sheet also does not tell her to create everyone's profile first; a joiner picks from existing unclaimed profiles ("Which profile is yours?") or "I'm new here" (`join_flow_steps.dart:171-194`), so an invitee who is not pre-created becomes a second profile and Maria's pre-made one stays unclaimed.
- Suggestion (S): a confirm before the first re-invite ("This replaces the code you shared on ..."), or keep and re-display the active code until it expires; add one line to the sheet: "Add everyone under Members first. They pick their own profile."

### P2-E. The path to "invite my family" is hidden behind email sign-in and a button that talks about "other devices"
- Persona: "Where do I invite my husband? Members has nothing."
- What happens: in a local household the Members screen shows no Invite row (`manage_members_screen.dart:40,46`). The Account block's intro talks about syncing "devices" ("Signing in stores your email and your household's data ... so your devices stay in step", `settingsAccountIntro`), and "Put my household online" says "Makes your household available on your other devices." (`settingsAccountAdoptIntro`); neither mentions family or invites. Directly under it sits "Join an existing household - ... this replaces your local data." (`account_section.dart:96-97`). The welcome-gate redesign fixed the second-phone case, but the organiser's equivalent (first phone -> invite others) has no signpost.
- Suggestion (S): show a disabled-looking "Invite" row on Members while local with the subtitle "Sign in first to invite your family", and reword the adopt row ("Put my household online so your family can join").

### P2-F. In a local household, the app-bar "who's acting" avatar silently re-scopes credit, the daily summary and reminders, and the confirmation never names who got credit
- Persona: "I ticked off my son's chore as him last night. This morning my summary is full of his chores."
- What happens: in local/signed-out mode the avatar switches `settings.actingMemberId`, which persists (`acting_member_sheet.dart:115-122`). `_complete` credits that member (`chores_list_screen.dart:256-257`), and the digest/reminder recipient is the acting member (`lib/app/providers.dart:1262-1268` recompute on change, `:1401-1416` `recipientMemberId`, `lib/domain/digest_projection.dart:217-222`, `reminder_planner.dart:311-316`). The normal snackbar says only "Done - next due Fri" (`chores_list_screen.dart:439-457`); only the "Mark done for..." path names the credited member (`:424-438`), and that row is offered only when linked and signed in (`:328-333`). The sheet title "Who's doing chores right now?" does not mention the digest.
- Suggestion (S): offer "Mark done for..." in local households too (it needs no auth), and have the sheet say "Credit and your daily summary follow this person." (XS copy).

### P2-G. "Last synced just now" measures the last *pull*, not whether Maria's own edits arrived
- Persona: "It says synced just now, but my husband still doesn't see the chore I added."
- What happens: the line reads `syncLastPulledAt` (`last_synced_line.dart:17-19,86-97`). The 60 s poll pushes and then *always* pulls even when the push failed (`lib/application/sync_engine.dart:346-372`), so a persistently-rejected push leaves the line fresh. The unhealthy banner exists, but needs dirty rows for 3 min (`lib/domain/sync_health.dart` defaults) and is rendered only on the Chores/Shopping lists. Settings has no pending-changes count and no "Sync now" (the line is plain `Text` inside a ListTile subtitle; pull-to-refresh exists only on the lists, `chores_list_screen.dart:196-215`).
- Suggestion (S): append "3 changes waiting to send" when any synced row is dirty (the dirty watch already exists), and make the line tappable to run `refreshNow()`.

### P2-H. Reminder form does not say who gets reminded, and the hint is easy to misread
- Persona: "I set a 17:30 reminder for the bins on my son's turn. Whose phone rings? Mine?"
- What happens: per-chore reminders and the digest are scoped to the device's acting member plus unassigned chores (`reminder_planner.dart:311-316`, spec `notifications-n2.md` §2.2). So a reminder on a chore assigned to the 9-year-old rings nobody if he has no phone, and never rings Maria's. The only copy is "This chore won't be counted in the daily summary" (`reminder_row.dart:130-138`), which is also incomplete: the chore is only left out of that one day's count and returns as overdue the next day (spec §2.4). The row is stateless and shows nothing about notification permission (`reminder_row.dart:35-157`).
- Suggestion (XS copy, M to really fix): "Reminds whoever the chore is assigned to, on their phone." Backlog G-9 (digest scope toggle) is the real fix: +1 below.

---

## 2. Missing features

### P2-I. No way to hand today's turn to someone else (sick / away) without completing or deleting it
- Persona: "Anna's ill. I just want Ben to take her turn this week. I can't find that."
- What happens: the action sheet offers only Mark done for..., Skip, Edit, Pause, Delete (`chore_action_sheet.dart:10-27`). Skip "sticks": a skipped rotation turn stays with the same person (`chore_service.dart:556-562`), so Anna gets it again next cycle. Editing the rotation doesn't move the open turn (P1-A). Pause stops the chore for everyone and has no resume date (`pauseChore(String choreId)` only, `chore_service.dart:~218`; resume is manual, `chore_paused_section.dart:119-122`). Mark done for... credits someone but also completes it. "Covering" a turn (done by someone else) is handled well afterwards (the coverer skips the next turn, `lib/domain/rotation.dart:15-20,41-43`), but that is after the fact.
- Suggestion (M): a "Reassign this turn..." row (pick a member; writes `assigned_member_id` on the pending occurrence, rotation continues from there) plus optionally "Pause until <date>". Even S if limited to the reassign row.

### P2-J. Members screen shows no status: who has joined, who is "me", who has no phone
- Persona: "I sent the code an hour ago. Did my husband join? Which of these is my own profile?"
- What happens: a member row is avatar + name, nothing else (`manage_members_screen.dart:139-151`); the claimed state (`members.userId`) is read only inside the edit sheet to decide whether Delete is allowed (`member_edit_sheet.dart:147-178`). Joining a profile is one tap with no confirmation ("Are you Anna?" -> straight into `_runJoin`, `welcome_join_page.dart:158`), and a wrong claim can only be undone by removing the profile entirely (`remove_member` "unclaims AND soft-deletes", `supabase/migrations/20260808120000_membership_exit.sql:170-175`), or by the person using Leave and a fresh code.
- Suggestion (S): subtitle on member rows ("Uses Famdo on their own phone" / "No phone - you mark their chores"), a "You" tag on the claimed row, and a confirm step in the join chooser (XS).

### P3-K. No role or permission model for the organiser
- Persona: "I run the household, but my 14-year-old can rename it, delete chores, or remove his sister."
- What happens: `members.role` exists but is "vestigial" by decision D-L2/D1 (`docs/specs/household-lifecycle.md` D-L2; RPC comment `membership_exit.sql:172-173`; no role control in `member_edit_sheet.dart`). Every member can edit anything. This is a recorded product decision, so it is a +1 for revisiting only if the app targets families with older kids; at minimum, show Maria that this is how it works.
- Suggestion (L to build; XS to disclose). I would not build it unprompted.

### P3-L. No duplicate-chore action or starter chores
- Persona: "I'm typing six chores from scratch, and three of them are 'weekly, assigned to a kid'."
- What happens: no copy/duplicate/template anywhere in `lib/features/chores` or `lib/features/stats` (searched for restore/duplicate/copy/template: no hits). The empty state is only "Add your first chore with +" (`chores_list_screen.dart:928`). Each new chore also resets the repeat toggle, assignment mode and start date (`chore_form_screen.dart:58,71,163`).
- Suggestion (S): "Duplicate" row in the action sheet (prefills the form, empty title); optional "Suggested chores" chips on the empty state (M).

### P3-M. Categories: no counts on the list and no "move to another category" on delete
- Persona: "I want to merge Kitchen into Cleaning. I'd have to re-tag every chore by hand."
- What happens: category rows show icon + name only (`manage_categories_screen.dart:211-231`). Delete is well-guarded with an exact count (`category_delete_dialog.dart:32-43`; counts the same rows the delete detaches, `category_repository.dart:203-261`), but the only outcome offered is "will become uncategorized", with no undo. Palette is 12 colours and a fixed icon set (backlog F17).
- Suggestion (S): count as a subtitle; in the delete dialog offer "Move them to <category>".

---

## 3. Quality of life

### P3-N. Household name is never asked, is hardcoded English, and renaming is buried
- What happens: `createLocalHousehold` always names it `'My household'` (`household_repository.dart:139`); seeded chore/shopping categories are literal English strings too (`category_repository.dart:69-87`), so a German-UI household sees English names. Rename lives only as the first row of Settings -> Members (`manage_members_screen.dart:42-43,76-95`); the Settings row is just labelled "Members". When linked, the name appears in the Account subtitle "Synced with My household" (`account_section.dart:168`).
- Suggestion (XS): localise the default name and seeds at creation time; (S) show the household name as a tappable Settings row.

### P3-O. Saving an edit is silent, even when the schedule changed and an occurrence was regenerated
- What happens: the form just pops (`chore_form_screen.dart:683`). If recurrence/startDate changed, the pending occurrence is deleted and re-inserted (`chore_service.dart:368-393`), so the tile may jump sections (and an overdue one is floored to today). The pre-save preview is good, but there is no after-save confirmation ("Saved - next due Mon").
- Suggestion (XS): snackbar with the next due date, reusing `futureDueText`.

### P3-P. Assignment control is unexplained and switching modes wipes her picks
- What happens: segments "Fixed | Rotation | Anyone" have no helper text (`assignment_fields.dart:77-92`); the rotation list shows order numbers but not whose turn is current, and the edit form never shows the current holder. `_onAssignmentModeChanged` clears `_selectedMemberIds` (`chore_form_screen.dart:566-572`): Rotation -> Fixed -> Rotation loses the ordered list she just built.
- Suggestion (XS): one helper line per mode ("Takes turns in this order, starting at 1."), keep the rotation list in memory when toggling modes.

### P3-Q. Weekday circles likely wrap on 360-375dp phones (arithmetic only)
- What happens: 7 toggles x 48dp + 6 x 4dp spacing = 360dp (`weekday_chips.dart:34-48,88-90`), but the form body has 16dp gutters (`chore_form_screen.dart:317`), so 328dp is available at 360dp width and 343dp at 375dp: Sunday would wrap alone. Tue and Thu both show "T", Sat and Sun both "S" (`weekdayNarrowName`, comment at `recurrence_builder.dart:210-212` admits the ambiguity; the a11y label is fine, the visual is not). Could not verify on a device.
- Suggestion (XS): size toggles with `Expanded` in a `Row`, or use 3-letter names.

### Nits (not counted)
- `settingsResetConfirm1Body` uses ASCII " -- " ("...no cloud backup -- this can't be undone"), `lib/l10n/app_en.arb:1909`, while the rest of the copy uses em dashes.
- Done-today row for a skipped chore prints "by <assignee>" (`chore_done_section.dart:139-144,181-182`), implying the assignee skipped it when anyone may have.
- Tile shows only the first word of a name (`chore_occurrence_tile.dart:352-355`) and avatars the first two characters (`member_avatar.dart:64-73`), so "Anna M." and "Anna S." look alike (unique colours rescue the avatar).
- A rename done by the 14-year-old applies household-wide (no per-viewer display name); the rename path itself works (`member_edit_sheet.dart:421-427`).

---

## 4. What already works well (do not break)

1. **Repeat form as a sentence with a live preview.** "Repeat every [2] [weeks] on" + weekday chips + "Next Tue, Oct 7, then Fri..." lets Maria verify Tue+Fri without leaving the form (`repeat_controls.dart:130-146,188-220`). `docs/future-improvements.md` F14 still lists the structural redesign as open, but G-2 shipped it, so that row is stale.
2. **Destructive actions state their blast radius.** Category delete gives exact counts (`category_delete_dialog.dart:32-43`), member delete explains rotation/fixed/anyone consequences (`memberDeleteDialogBody`), chore delete says history is kept and where to find it (`choresDeleteDialogBody`).
3. **Undo where it counts.** Complete, skip, pause all show a snackbar with Undo (`chores_list_screen.dart:378-395,459-470`); Done-today rows have Reopen with a LIFO guard.
4. **Never lose input.** Dirty-form guard with a real snapshot diff (`chore_form_screen.dart:108-136,303-313`); Save is pinned above the keyboard (`:417-431`).
5. **Rotation fairness is thoughtful.** Rotation order is editable by drag (`assignment_fields.dart:215-231`), the person who covers a turn never gets the next one (`rotation.dart:15-20`), and missed turns don't pass on (`occurrence-lifecycle.md` catchUpOverdue) with a visible catch-up banner.
6. **Honest local-first onboarding.** One field, no account, offline reassurance in the small print (`welcome_screen.dart:233,301`); member colours are unique and explained (`memberEditColorUniqueHint`, `member_edit_sheet.dart:306-327`); the add-member chip works from inside the chore form.

## 5. Known-backlog +1 (Maria would prioritise)

- **G-3 Restore from a backup file** (`docs/backlog.md` G-3). Export is a raw JSON of every table including soft-deleted rows (`lib/application/data_export.dart:33-42,62-77`) with no explanation on the row (`export_row.dart:41-46`) and no way back in. For the person who "fixes mistakes", an export that can't be imported looks like a backup but isn't. Top of her list.
- **G-9 Digest scope toggle / F16 per-person notifications.** See P2-H: Maria wants the summary to include the kids' chores she supervises.
- **Undo on chore delete** (conventions audit C10, `docs/feedback/2026-08-06-conventions-audit.md:36`). Chore delete is still the one chore action with no undo snackbar (`chores_list_screen.dart:357-367`) and there is no way to re-create from Chore history; she loses the whole schedule/rotation setup.
- **F17 More category icons and colours.**
- **F5/D-5 offline indicator** shipped, but only on the two lists (see P2-G for the Settings gap).

## 6. Could not verify

- Real-device wrapping of the weekday circles (P3-Q) and any visual density claims.
- Whether the Settings -> Account local-mode copy reads as intended in German (`app_de.arb` not reviewed line by line).
- Server-side enforcement of invite expiry (7 days, per copy only); I did not read the RPC.
