# Persona walkthrough: Ben (the reluctant participant)

*Read-only research. No files were modified; no build/test/analyze was run.
Every claim below cites `path:line`; anything I could not verify from source
is marked "unverified."*

## Who Ben is, and what he's optimising for

Ben didn't choose Famdo — his partner did, and sent him a code. He wants to
open the app, see what he owes, tap it once, and leave; anything that isn't
that is friction he resents. He never opens Settings voluntarily, so a
feature that lives only there does not exist for him. He doesn't read
dialogs — he taps the biggest/highlighted button and assumes it's
reversible. He forgets the app exists for weeks, then opens it to a
backlog, and he hates the feeling of being scored or blamed by software.
Everything below is read against that lens, not against "is this correct."

## Surface: being invited (join flow)

| Interaction | Ben expects | Actually happens (source) | Verdict |
|---|---|---|---|
| Tap "Join my family's household" | Type a code, done | Email + magic-link sign-in first (`welcome_join_page.dart:169-236`), *then* a membership probe — if he already has a membership elsewhere it offers reconnect instead of code entry (`:150-163, 243-264`) — *then* code entry (`:269-297`), *then* a chooser step | SURPRISE — sign-in is a whole extra step before the code Ben was actually handed |
| Type the invite code | If wrong, tells him what's wrong | Code is auto-uppercased/trimmed (`welcome_join_page.dart:270`); a mistyped code, an *expired* code, and a code his partner already *revoked* by generating a new one all produce the identical string `joinHouseholdCodeError`: "That code isn't valid or has expired. Please check it and try again." (`app_en.arb:1203`; server-side, all three fail the same `_valid_invite` check, `supabase/migrations/20260731120000_initial_schema.sql:314-333`) | UNCLEAR — Ben can't tell "I mistyped" from "this code is dead," so he can't decide what to do next |
| "Which profile is yours?" chooser | Obviously pick himself | Plain list: "Are you {name}?" rows + a fixed "I'm new here" row (`join_flow_steps.dart:155-181`, copy `app_en.arb:1211-1226`) — no subtitle, no warning. If his partner used a nickname or he doesn't recognize the row, nothing stops him tapping "I'm new here" and creating a duplicate member | TRAP-adjacent — a genuinely easy way to fork himself into two people, with zero guard |
| Kill the app mid-join | Have to start over | Every rebuild re-derives the step from live auth/membership state rather than a cached step (`welcome_join_page.dart:109-117`, doc comment `:10-17`) — resumes exactly where he left off | OK |
| Land in the household as the invited person | Assume he's just "a member" | Confirmed: `join_as_new_member`/`claim_member` never grant `role='admin'` (`supabase/migrations/20260731120000_initial_schema.sql:399`, `:356-379`) — but **no code anywhere, client or server, actually checks that role for anything.** `households_update`/`members_update` RLS policies only require `is_household_member(...)` (`supabase/migrations/20260731120000_initial_schema.sql:183-199`); no `MemberRole` check exists in `manage_members_screen.dart`, `account_section.dart`, or `household_rename_sheet.dart` (grepped, zero hits) | SURPRISE — Ben has exactly the same power as the admin who invited him: he can rename the household, and regenerating an invite silently revokes his partner's live code, with no gate saying "only admins should do this" |

## Surface: chores tab

| Interaction | Ben expects | Actually happens (source) | Verdict |
|---|---|---|---|
| Day-progress card at the top | A nice "you're doing fine" widget | `ChoreProgressCard` (`chore_progress_card.dart:35-122`): `M` = still-pending occurrences due today **or overdue**, plus occurrences done today; `N` = done-only (never skipped, `:19-22`). Deliberately household-wide, unfiltered (`chores_list_screen.dart:62-66`). Per spec this is intentional (`docs/specs/theme-v2.md:185-194`) | SURPRISE — after a lapse, `M` swallows every stale overdue occurrence as if it were "today's" plate; a returning Ben can see "0 of 12 done today" with a 0% ring the moment he opens the app, and the ratio also reflects a partner's backlog, not just his |
| Tap the leading circle | Marks it done, that's it | Immediate write, haptic, then a 5s undo snackbar (`chores_list_screen.dart:179-204`) | OK |
| Long-press / ⋮ menu | Some options | Bottom sheet: **Skip, Edit, Pause, Delete** in that order, Delete alone in error-red (`chore_action_sheet.dart:41-93`) | OK, well-signaled |
| Skip | "I don't want to do this" | No confirmation, immediate + undo snackbar (`chores_list_screen.dart:212-219`); for a rotation chore the SAME person is due again next cycle ("skip sticks") — correct by design, but nothing on-screen says so | UNCLEAR |
| Pause | Some visible "paused" marker | `_openMenu`'s `pause` case calls `pauseChore` with **no snackbar at all** (`chores_list_screen.dart:226-227`); the tile just vanishes because paused chores have no pending occurrence (`chore_service.dart:184-193`, `chore_repository.dart` filter `pausedAt.isNull()`) | TRAP-adjacent — zero feedback; the only way back is knowing to open the collapsed "Paused (N)" section |
| Delete a chore | A confirm, then it's gone | 3 taps (menu → Delete → confirm). Dialog: "Delete chore? This deletes '{title}'. Its history is kept, but its pending occurrence is removed." (`app_localizations_en.dart:95-100`). `softDeleteChore` really does soft-delete the chore and only hard-deletes the *pending* occurrence (`chore_repository.dart:229-249`) | **TRAP** — see "Traps" below; "history is kept" is true in the DB and false in the UI |
| Filter hides everything | "Did my chores disappear?" | Distinct filtered-empty state with "Show everything" (`chores_list_screen.dart:625-667`, trigger `:396-417`) | OK (already fixed per 2026-08-01 UX audit) |
| Dismiss the name/digest banners | Can find the setting again easily | Both are one-way flags; dismissing marks it permanently (`onboarding_name_banner.dart:96-103`, `digest_preprompt_banner.dart:91-93`) — the only way back is Settings, which Ben never opens | MISSING (for this persona specifically) |
| Acting-member switcher (app-bar avatar) | Not really his concern | Shown unconditionally, even for a linked/signed-in household (`chores_list_screen.dart:78`) — the decided fix (hide it when linked+signed-in, replace with a "Mark done for…" sheet row) is **not implemented**: no "Mark done for" string exists anywhere in `lib/l10n` (grepped) | **TRAP**, currently live (see below) |

## Surface: chore form

| Interaction | Ben expects | Actually happens (source) | Verdict |
|---|---|---|---|
| Open by accident, type something, hit back | Loses it silently | `PopScope(canPop: !_isDirty, ...)` (`chore_form_screen.dart:251-261`) triggers a confirm dialog (`chore_form_discard_dialog.dart:18-46`) the moment ANY field differs from its snapshot; dismissing the dialog defaults to "keep editing" | OK — better than expected |
| Save with empty title | Error, and don't lose the rest | Inline error, save aborts early, nothing else clears (`chore_form_screen.dart:426-495`) | OK |
| Toggle "repeat" on | Sensible defaults | interval 1, weekly, schedule-anchored (`chore_form_screen.dart:49-57`) — reasonable | OK |
| Anchor choice ("fixed schedule" vs "after last completion") | Obvious from the label | Distinguished only by a subtitle sentence a non-reader will skip (`repeat_section.dart:135-252`); picking wrong changes whether the chore drifts with actual completion dates | SURPRISE (already logged, G3) |
| Assignee picker missing a person | Have to leave the form | Inline "add member" chip present (`assignment_fields.dart:101-108`) | OK, shipped |

## Surface: shopping tab

| Interaction | Ben expects | Actually happens (source) | Verdict |
|---|---|---|---|
| Add an item already on the list | Nothing / duplicate | Snackbar-disclosed: unchecked-duplicate → "Already on the list"; checked-duplicate → unchecked + "Moved back to the list" (`shopping_quick_add_row.dart:239-305`) | OK |
| Tap a suggestion | Adds it, chip behaves | C3 bug (tap animates the *next* chip) is fixed via `ValueKey(name)` (`shopping_suggestions_list.dart:53`) | OK, shipped |
| Check an item off | Some confirmation | Haptic only, no snackbar (`shopping_list_screen.dart:151`) — deliberate, matches the "no custom animation" rule | OK |
| Delete an item (via edit sheet) | Confirm dialog | No dialog, immediate delete + undo snackbar (`shopping_edit_sheet.dart:175-196`) | OK |
| Swipe or long-press a shopping row | Standard list gestures | Neither exists (`Dismissible`/`onLongPress`: 0 hits across all shopping files) | LIMIT, already logged (F2/F3) |
| Tap "Clear checked" | A confirm, or at least an undo | **No confirm** (by design, `shopping_checked_section.dart:113-119`) and, unlike every other "delete-like" action in the app, **no undo snackbar for the clear itself** — the adjacent "Put all back" button only restores items *before* they're cleared, not after (`shopping_checked_section.dart:106-112`); recovery afterward means retyping each name from memory into quick-add and hoping the suggestion surfaces it | **TRAP** |

## Surface: settings (what Ben would find if he ever went in)

| Interaction | Ben expects | Actually happens (source) | Verdict |
|---|---|---|---|
| "Reset app data" | A hard confirm | 3 taps from Settings root; copy correctly branches on linked/unlinked (`reset_flow.dart:44-108`, `app_localizations_en.dart:989-1010`); truly a full-table irreversible wipe (`data_reset.dart:20-31`), no undo | **TRAP**, mitigated by two dialogs — but see below |
| "Sign out" | Logs him out, that's it | Keeps the sync link (`auth_gateway.dart:115` is a bare pass-through); confirm body is generic ("You can sign in again anytime with your email," `app_localizations_en.dart:816-820`) — doesn't mention sync pausing or the last-push-wins risk; a separate "Disconnect" action (decided in the 2026-08-07 feedback) does not exist in code | UNCLEAR (already logged, confirmed still open) |
| Delete a member | Only for people who make sense to delete | Delete option is *absent from the widget tree* (not just disabled) for claimed members and the last remaining member (`member_edit_sheet.dart:79-143`); dialog states the referential consequences in plain language (`app_localizations_en.dart:695-697`) | OK, well done |
| Regenerate the invite code | New code, old one... also works? | `runInviteFlow` unconditionally revokes then recreates (`invite_flow.dart:26-29`); disclosed only in small sheet body text ("it replaces any earlier code," `app_en.arb:653-654`), no standalone confirm before the revoke | SURPRISE |
| Export data | One tap, share sheet | Exactly that, no confirm (`export_row.dart:31-65`) | OK |

## Surface: app lifecycle (weeks away, then a cold open)

| Interaction | Ben expects | Actually happens (source) | Verdict |
|---|---|---|---|
| Open after 3 weeks | Just see today's list | Bootstrap chain runs `seedDefaults` → `catchUpOverdue(householdId)` → 24h shopping auto-clear, all before the shell renders (`providers.dart:487-525`). `catchUpOverdue` silently closes each stale pending occurrence as `missed` and reinserts one fresh pending occurrence per chore at the latest missed slot, in one transaction (`chore_service.dart:138-178`) | **UNCLEAR** — see "Top findings" |
| Understand *why* several chores flipped to "missed" | Some banner/summary | None exists. The only downstream effect of catch-up changing anything is a debounced digest recompute (`providers.dart:869-875`) — nothing user-visible explains what just happened | MISSING |
| Force-quit mid-write | Data corruption worry | All multi-write service methods run inside `database.transaction(...)` (`chore_service.dart` throughout) — SQLite/drift transaction atomicity should protect this; no explicit recovery UI either way | unverified beyond transaction wrapping, likely safe |

## Surface: notifications

| Interaction | Ben expects | Actually happens (source) | Verdict |
|---|---|---|---|
| First chore created | Maybe get nagged for permission immediately | Confirmed NO automatic `requestPermission()` anywhere (`notification_scheduler.dart:213-231`, iOS init passes all three permission flags `false` at `:76-80`); the OS dialog only ever fires from an explicit tap (digest pre-prompt banner or Settings) | OK |
| Deny the permission | Stop being asked | OS remembers; app re-checks on resume via `DigestRescheduleController.refreshPermissionState` (`providers.dart:712-717`, hooked at `main.dart:85`) and reflects it only in the Settings hint row | UNCLEAR for Ben specifically — see "Top findings" |
| Tap the digest notification | Opens something relevant | No tap handler registered anywhere (grepped `NotificationResponse`/`payload:` — 0 hits); default OS launch onto the chores tab, matching spec | OK/LIMIT (documented N1 scope) |

## Surface: effects on others

| Question | Answer (source) |
|---|---|
| Can Ben tell the household "I'm on holiday" / "already did this" / "not mine"? | **MISSING.** No such concept anywhere in `sync_engine.dart` or the household services. `pauseChore` exists but pauses the *chore for the whole household*, not a per-person away-status (`chore_service.dart:184-253`, comment calling it "a vacation" is about the chore, not the person). |
| Does anyone get told when Ben's chore quietly goes overdue → missed? | No push exists (N3, server-scheduled cross-user events, is explicitly out of scope for v1 per `docs/specs/notifications.md:13`). Other members only learn by opening the app and seeing the occurrence/assignee themselves. |

## Traps (ranked by ease of hitting + how hard to undo)

1. **"Clear checked" has no undo** — 1 tap from the Shopping tab, no confirm, and it's the *only* delete-like action in the whole app with no undo snackbar of its own (`shopping_checked_section.dart:113-119`). Everything else that removes data (chore skip/complete, single shopping-item delete) gives you 5 seconds or a snackbar; this one doesn't.
2. **Delete chore's "history is kept" promise is unverifiable** — 3 taps from any tile (⋮ → Delete → confirm, `chore_action_sheet.dart` + `chore_delete_dialog.dart`). The dialog text is literally reassuring ("Its history is kept"), which is true in SQLite (`chore_repository.dart:229-249`) and false in the app: no screen anywhere reads a deleted chore's history (zero `*history*` files in `lib/`, no restore method in `chore_repository.dart`/`chore_service.dart`). A reassuring dialog that can't be acted on is worse than a blunt one.
3. **Pause gives zero feedback** — 2 taps (⋮ → Pause), no snackbar (`chores_list_screen.dart:226-227`). The tile just disappears; Ben's most likely read is "did I just delete that?" and his most likely fix is adding a duplicate via the FAB rather than finding "Resume" in the collapsed Paused section.
4. **The acting-member switcher is still live for synced households** — 1 tap from the chores-tab app bar, present even when Ben is a linked/signed-in member (`chores_list_screen.dart:78`; the decided fix hiding it is unshipped). If tapped out of curiosity and left on someone else, every subsequent completion credits that person, silently, with no way to retroactively fix a closed occurrence's `completedBy`.
5. **Reset app data** — 3 taps total (row + 2 dialogs), both dialogs use a highlighted affirmative button ("Continue" then "Delete everything," `reset_flow.dart:101-140`) with no typed confirmation phrase. Correctly labeled and honestly worded, but a double-tap-through is exactly Ben's pattern for "seeing what a button does," and the barrier is two taps, not a typed word.
6. **Regenerating the invite code silently kills the old one** — 1-2 taps from Account/Members (`invite_flow.dart:26-29`), disclosed only in small sheet body copy, no separate "the old code stops working" confirm.

## Top findings (ranked)

1. **Catch-up after a lapse is invisible.** After weeks away, `catchUpOverdue` (`chore_service.dart:138-178`) silently converts a backlog into "missed" occurrences before the list even renders (`providers.dart:487-525`), and nothing — no banner, no toast, no summary screen — tells Ben this happened or why several chores suddenly say "missed." For someone who resents being blamed by the app, silently-appearing "missed" rows read as an accusation with no explanation.
2. **The day-progress ring can show Ben a discouraging score on the exact day he re-opens the app.** `M` intentionally folds "overdue" into "today's" denominator (`chore_progress_card.dart:19-25`, spec'd in `theme-v2.md:185-194`) and is household-wide, not per-person (`chores_list_screen.dart:62-66`). A backlog from a 3-week absence turns a feature meant to feel encouraging into a visible "0%" the moment he opens the app — for exactly the usage pattern this persona defines.
3. **Delete's "history is kept" claim is not something the user can ever see.** The dialog is factually true about the database and functionally false about the app: no history view exists anywhere in `lib/`, and there's no restore path. This is worse than an honest "this can't be undone," because it invites Ben to tap through under the belief he's kept a safety net he doesn't have.
4. **"Clear checked" is the one destructive-ish action in the app without an undo.** Every comparable action (chore skip/complete, single-item shopping delete) got a snackbar; the bulk shopping clear didn't, despite being one tap away with no confirm.
5. **Ben has admin-equivalent power with zero signal that it's unusual.** No role check exists client-side (`manage_members_screen.dart`, `account_section.dart`, `household_rename_sheet.dart` — grepped, no `MemberRole` gating) or server-side (`households_update`/`members_update` RLS only require membership, `supabase/migrations/20260731120000_initial_schema.sql:183-199`). Renaming the household or regenerating the family's one invite code looks and feels identical whether Ben or his admin partner does it.
6. **The acting-member switcher is still a live footgun for synced households.** The decided fix (hide it, replace with a rare "Mark done for…" action) hasn't shipped — no "Mark done for" string exists anywhere in the localization files. Today, a curious tap can leave completions silently misattributed with no way to fix a closed occurrence afterward.
7. **Pause is the quietest action in the app.** Every other state-changing tap (complete, skip, delete, shopping check/delete) gives *some* feedback; pause gives none, and its recovery mechanism (a collapsed section) is opposite to how Ben behaves (he won't expand a section he doesn't know exists).
8. **A denied notification permission is effectively permanent for this persona.** The recovery path is a Settings hint row (`digest_section.dart`), and the one proactive nudge to fix it (the digest pre-prompt banner) is a one-shot dismiss (`digest_preprompt_banner.dart:91-93`). Combined with "Ben never opens Settings," a single accidental OS-permission denial silences the digest forever for him specifically, even though the feature is designed to be recoverable.
9. **The join-flow error message can't tell Ben what actually went wrong.** A mistyped code, an expired code, and a code his partner already revoked all produce the identical "invalid or expired" string (`app_en.arb:1203`), on the one screen where Ben is most anxious about getting it right on his first real interaction with the app.
10. **No way to signal context to the household.** Ben has no "I'm away," "I already did this in person," or "this isn't mine" affordance — the closest primitive, `pauseChore`, pauses the chore for everyone, not his own participation in it. This absence is exactly what makes finding #1 sting more: when the app doesn't know Ben's context, its only tool is silently marking things "missed."
11. **Regenerating an invite silently revokes a code someone might still need**, disclosed only in body copy nobody reads on a screen whose whole point is copy-pasting a code correctly.

## What would make Ben quit

1. **Opening the app after a break to an unexplained wall of "missed" chores and a rock-bottom progress ring**, with no message anywhere saying "you were away, here's what changed." To this persona, that reads as the app scoring and blaming him with no chance to explain himself.
2. **Discovering the app silently mis-attributed or un-recoverably lost something** — a chore deleted "to tidy up" that supposedly kept its history but shows it nowhere, or a chore completed while the acting-member switcher was pointed at someone else. Either one breaks the baseline trust that the app is tracking things correctly, which is the only reason he tolerates it at all.
3. **A bad first impression at the one moment he's paying attention** — the invite-code screen. If entering the code his partner sent him fails with a generic, unhelpful error (typo vs. expired vs. already-revoked, all identical), he has no way to self-correct and may simply give up before ever seeing a chore.
