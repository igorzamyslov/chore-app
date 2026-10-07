# Persona walkthrough: Priya (36, privacy-minded power user, flat-share), Famdo 0.14.0+21

Method: every screen and string reconstructed from source (no app run, no network trace). Paths are relative to the repo root. Where I could not verify at runtime I say so. "arb" = `lib/l10n/app_en.arb`. German strings were spot-checked in `lib/l10n/app_de.arb`.

Severity: P1 = misleads / loses work / privacy-claim mismatch. P2 = real friction on a common path. P3 = polish. Effort: XS/S/M/L.

---

## Flow notes (what I traced)

1. **First launch, offline.** `lib/main.dart:33-43` only calls `Supabase.initialize` (no sign-in, no request I can find). The sync engine is `NoopSyncEngine` unless a transport exists AND the device is linked AND a user is signed in (`lib/app/providers.dart:~513-531`). The error uploader gate needs configured + signed in + linked + switch on (`lib/application/error_reporter.dart:66-70`). No analytics or HTTP packages in `pubspec.yaml`; fonts are bundled. By code reading, nothing phones home before she signs in and links. Not confirmed with a traffic capture. The `INTERNET` permission is declared unconditionally (`AndroidManifest.xml:131`).
   The welcome screen does say it: "No account needed — everything stays on your device unless you sign in." (`welcome_screen.dart`, arb `welcomeOffline`).
2. **Link up.** Sign-in is a magic-link email only, no OTP code (`lib/application/auth_gateway.dart:107-112`, `emailRedirectTo: famdo://auth-callback`). The intro above the email field is `settingsAccountIntro` (arb:1399). After sign-in she sees "Put my household online" (adopt) and "Join an existing household" rows. Once linked she sees Invite a member, Leave the household, Disconnect from the online household, Delete my account (`account_section.dart:98-110`).
3. **Terminology, 4. Lifecycle, 5. New phone, 6. A11y, 7. Error visibility**: findings below.

---

## Pain points

### PP1 (P1): PRIVACY.md contradicts the app in four places
> "I read the policy before I installed. Half of it is already wrong."

- Line 14 says "The app contains **no analytics, no crash reporting**…". Since 0.13 the app records every caught and uncaught error (`main.dart:49-62`, `FlutterError.onError` / `PlatformDispatcher.onError`) and uploads them when signed in and linked (`error_reporter.dart`). It is conditional, but the sentence is unconditional.
- Lines 62-65 say account deletion "ships with the sync feature's final phase. Until then, contact the backend operator". Delete account is shipped: `_DeleteAccountRow` (`account_section.dart:666`), RPC in `supabase/migrations/20260808120000_membership_exit.sql:62-81`. `docs/future-improvements.md` F11 ("no UI yet") is stale in the same way. PRIVACY.md was last edited in 46c9a7e (the 0.13 error-reporting commit), which did not fix this.
- Line 36 says "That is the complete list" of server data. It omits category names (a synced table, `sync_engine.dart:36`). It omits that error reports carry your `user_id` (server default), `household_id` and UUIDs (`error_reporter.dart:155-158`, spec §3.1), so they are pseudonymous, not anonymous. It also omits the local archive files (see PP3).
- It never states the server region or who the operator is beyond "the app's author". `docs/supabase-setup-checklist.md:~48` explicitly says to note the region "for the privacy docs"; it did not make it in.

**Suggestion (S):** one editing pass on PRIVACY.md. Replace "no crash reporting" with "error reports only if signed in, opt-out in About". Rewrite the Deleting section to point at Settings → Household → Delete my account. Add categories, the id linkage, archives, region and operator.

### PP2 (P1): Last-member "removed from the server" is only a soft delete
> "You told me the shared copy and its history are removed from the server. Is it?"

`householdLeaveConfirmBodyLastMember` (arb:1474) and `accountDeleteConfirmBodyLastMember` (arb:1498) say "the shared copy and its history are removed from the server". The RPC only stamps `households.deleted_at` (`_cascade_if_orphaned`, migration `20260808120000_membership_exit.sql:138-165`). The comment states "Child rows are deliberately left alone" and spec §2.4 says the same. Chores, completion history, shopping items and member names stay in the database, hidden by RLS. There is no purge job: the only `cron.schedule` in the migrations is the error-report prune (`20261004120000_client_errors.sql:76`). For a GDPR-minded person this is the exact sentence that matters, and it is not true in the sense she will read it.

**Suggestion (S for wording, M for a fix):** either reword to "hidden from everyone and scheduled for deletion" plus a scheduled hard-delete (pg_cron, e.g. 30 days after `deleted_at`), or do the cascade delete in the RPC.

### PP3 (P1): "Saved to a backup file on this device" is a file she cannot reach or import
> "You say my old data is safe in a backup file. Where? And how do I open it?"

- Join and Reconnect write `famdo-archive-<date>.json` via `getApplicationDocumentsDirectory()` (`household_join_service.dart:236-241`, `household_archive.dart:86`). On Android that is the app-private directory. On iOS there is no `UIFileSharingEnabled` in `Info.plist`. The user cannot browse to it.
- The only mention is a 4-second snackbar with the file name (`settingsAccountJoinSuccessSnackbar`, arb:1660, shown via `snackbars.dart:50-67`). The confirm copy promises the backup (arb:1576, 1724).
- There is no importer (known G-3 / F12) and no share or "save to Files" action for the archive.
- The filename is date-only and written with `writeAsString` (`household_archive.dart:67,86`), so a second join the same day overwrites the first archive. After a join, the second archive would contain the joined household, not the original.
- Reset app data deletes DB rows only (`data_reset.dart`), so archives containing every member name and chore title survive "Reset app data". PRIVACY.md says reset "deletes the local database irreversibly" and that everything is "stored only in a local database".

**Suggestion (M):** after archiving, offer the OS share sheet (reuse `ExportDataTile`'s `SharePlus` call), and delete archives in `confirmAndResetAppData`. XS: until an importer exists, reword to "a copy is kept inside the app" and add the archive to PRIVACY.md.

### PP4 (P2): Error reports are default-on, not in the sign-in disclosure, and she cannot see what is queued
> "The app told me nothing leaves my phone, and then you tell me about error uploads in a switch at the bottom of Settings?"

- Default on (`Settings.errorReportsEnabled`, spec §6). `settingsAccountIntro` (arb:1399) lists email + household data only; the spec decided this on purpose (spec header). The switch lives in About (`about_section.dart:57-76`), the last group.
- Errors recorded while she was still local-only are uploaded the moment she signs in and links (spec §4.3, `error_reporter.dart:flush`). She believed she was offline when they were recorded.
- While local-only the About switch shows ON with subtitle "Only when signed in" (arb:1872). That is accurate but reads as an active uploader on first launch. The real gate is signed in AND linked.
- No in-app view of the local buffer (spec §9 "no in-app UI showing errors"; "Share diagnostics" deferred). She cannot inspect what would be sent. The scrubber is good (`error_scrubber.dart`), but unverifiable by the user.

**Suggestion (S):** one extra line under the sign-in intro ("also sends technical error reports; switch in About") with the switch inline, and ask once at first sign-in. M: a read-only "Pending error reports" list with a Clear button.

### PP5 (P2): Magic-link sign-in has dead ends and weak error copy
> "My flatmate opened the email on her laptop and nothing happened. Then it said 'try again' four times."

- Link only; `docs/supabase-setup-checklist.md:67-69` says "Open the email ON THE PHONE". No 6-digit code fallback, though Supabase supports it. `famdo://` does not open from a laptop.
- No handling of an expired or used link. `grep` finds no `AuthException` handling in the UI. The form stays at "Check your email at {email}" (arb `settingsAccountCheckEmail`). Could not verify at runtime how supabase_flutter surfaces a bad deep link.
- A failed send shows one generic snackbar "Couldn't send the sign-in link. Please try again." (arb:1526) for every failure, rate limit included. "Send again" is enabled immediately (`account_section.dart`, `_SignedOutFormState`). The checklist says the built-in Supabase mailer is used (`docs/supabase-setup-checklist.md:53`), which is rate-limited. I could not verify the production limit.
- The welcome-join copy of this handler swallows with `on Exception {` and no `AppLog.error` (`welcome_join_page.dart:257`), unlike the Settings copy (`account_section.dart`, `ui.accountSendMagicLink`), so those failures never reach the buffer.

**Suggestion (M):** add an OTP-code field beside the link, map `AuthException` codes (rate limit, expired) to specific copy, add a 60-second resend cooldown.

### PP6 (P2): When a push is rejected she sees a generic banner and a contradictory "Last synced"
> "It says last synced just now, but my flatmate has not seen my change for an hour."

- `_pushAll` pushes table by table in FK order and aborts on the first failing table (`sync_engine.dart:399-408`). One rejected `members` row blocks chores and shopping pushes. The poll then still pulls (`_pollTick`, `sync_engine.dart:368-374`), which advances `syncLastPulledAt`.
- `LastSyncedLine` reads that cursor (`last_synced_line.dart`), so Settings can say "Last synced just now" while nothing she wrote is leaving the phone.
- After 3 dirty minutes the banner appears (`syncHealthBannerMessage`, arb:1554: "hasn't reached the rest of the household in a while… try pulling down to refresh"). Pulling down runs `refreshNow()`, which fails on the same push, and shows `syncRefreshError` "Couldn't reach the household… will sync later" (arb:1546). That is wrong for a server rejection (it reached the server) and "will sync later" is optimism for a permanently rejected row.
- A signed-out-but-linked device gets no banner on the lists by design (`providers.dart:564-570`, spec sync-freshness §2.5 gating). The only signal is in Settings. The Settings-tab dot is only for the notification permission (`app_shell.dart:331-334`).
- The real cause goes only to the operator's table. Spec: "any in-app UI showing errors… out of scope".

**Suggestion (S-M):** show "N changes waiting to upload since HH:MM" next to "Last synced" (the dirty count and `dirtySince` already exist). Give the banner and snackbar two variants (offline vs server rejected). Add a Settings-tab dot for the signed-out-linked state.

### PP7 (P2): Error snackbars look like success and disappear in 4 seconds
> "I tapped 'Delete account', confirmed twice, saw a green tick, and had no idea it failed."

`showAppSnackbar` always draws `Icons.check_circle` in `inversePrimary` and a fixed 4 s duration (`snackbars.dart:52,60`). All error paths use it: `accountDeleteError`, `householdLeaveError`, `settingsResetError`, `settingsExportError`, `syncRefreshError`. Screen reader and large-text users get 4 seconds to read a sentence like "Couldn't delete your account. This needs a connection — nothing was changed. Try again." (arb `accountDeleteError`). It is also the only place the archive file name appears (PP3).

**Suggestion (XS-S):** a `showAppError` variant with `Icons.error_outline` in `colorScheme.error`, a longer duration (or `persist` plus Dismiss), and an optional Retry action.

### PP8 (P2): Two messages point to "Settings → Account", which does not exist
> "'Use Leave the household in Settings → Account.' I looked. There is no Account."

`memberEditDeleteBlockedSelf` (arb:1191) and `syncRefreshErrorRevoked` (arb:1550), also in German ("Einstellungen → Konto"). The Settings groups are Household / Preferences / Data / About (`settings_screen.dart`, `settingsHouseholdSectionTitle`); the Account group was merged into Household (field feedback B2). Code comments and arb descriptions still say "Account section". The strings are the only user-visible leftovers.

**Suggestion (XS):** replace with "Settings → Household". The arb description at arb:1463 says the leave label is quoted verbatim, so keep both in sync.

### PP9 (P2): Sign-out and paused-sync copy omit that re-login can overwrite flatmates' newer edits
> "'Changes are kept and sent once you sign in.' Even if Sam has changed the same chore since?"

`settingsAccountSignOutConfirmBody` (arb:1538) and `settingsAccountPausedNotice` (arb:1435) say only that changes "will be sent". The conflict rule is last-push-wins, and the re-login push beats newer remote edits (`docs/feedback/2026-08-07-field-feedback.md` A1; `docs/future-improvements.md` "Known trade-offs" says the signed-out state "now says so out loud"). It does not say so. This is a documented trade-off, but the user-facing sentence under-warns, and the A1 decision text promised it would.

**Suggestion (XS):** add "If someone else edited the same item meanwhile, your version replaces theirs."

### PP10 (P2): "Put my household online" is a one-tap upload with a subtitle that undersells it
> "One tap uploaded every name and every completion since January. The row said 'available on your other devices'."

`_AdoptRow` (`account_section.dart:842-935`) runs `HouseholdLinkService.adopt` straight from `onTap`; no confirm. The subtitle (arb:1584) does not say what is uploaded (members, chores, full completion history, notes) or where. The intro that does say it is shown before sign-in, on the signed-out form. Given PP2, upload is effectively one-way.

**Suggestion (XS-S):** a one-step confirm sheet listing what is uploaded, to which server, and how to undo it (Delete my account / Leave).

---

## Missing features

### MF1 (P2): Terminology and mental model are never stated, and four near-identical exit rows have no hints
> "Sign out, Disconnect, Leave, Delete my account. Which one stops syncing but keeps my flatmates' copy?"

- Linked state shows `Sign out` (button in the email row), `Leave the household`, `Disconnect from the online household`, `Delete my account` (`account_section.dart:98-110`). The Leave and Disconnect rows are bare `ListTile`s with no subtitle (`_LeaveRow` :536, `_DisconnectRow` :459). The difference only appears in the confirm dialogs.
- Nowhere in the app or PRIVACY.md is "account = your email login on the sync server; member/profile = a person in the household; household = the shared data" defined. The UI mixes: "profile" (arb:1191, `joinHouseholdChooserTitle`), "member" (`settingsAccountInvite`), "Delete {name}?" vs "Couldn't remove {name}" (arb:1199 and `memberRemoveError`), "this phone" (leave, delete, revoked, exit sheet) vs "this device" (`settingsAccountPausedNotice`, `syncRefreshErrorRevoked`).
- "Sync — coming soon" (`settingsAccountComingSoonTitle`, arb:1562) is shown on a build without Supabase, where it is not coming.
- Confirm copy checked against code and found truthful: Disconnect (`HouseholdLinkService.disconnect` is local only), Leave non-last (`household_exit_service.dart:leaveHousehold` unclaims, keeps profile), Delete account (RPC erases `auth.users`), member removal bodies (`member_service.dart:150-190`: rotation, fixed and unassigned rules match arb), Reset (linked vs unlinked bodies). The inaccurate ones are PP2, PP3, PP8, PP9.

**Suggestion (S):** one-line subtitles on Leave and Disconnect ("Stops syncing and removes you from the household" / "Stops syncing on this phone only"), pick "profile" vs "member" and "phone" vs "device", add a short "How accounts and households work" sheet reachable from the sign-in intro.

### MF2 (P2): Flatmate leaves: stays in rotation, nobody can tell, and she cannot erase her name
> "Sam moved out in March and is still on the rota. Nothing told us."

- Leave only unclaims; the profile stays active (`household_exit_service.dart:leaveHousehold`, spec §2.2). Chores keep rotating to the departed profile until someone deletes it.
- The Members list is avatar + name only (`manage_members_screen.dart:_MemberRow`), with no marker for "has an account / is you / left". Others learn only on trying "Delete".
- The household gets no notice that a member left (no server message in the leave RPC).
- "Delete account" keeps her real display name in every household and on the server ("Your profile stays…", arb:1498; PRIVACY.md lines 62-63). The only erasure of her name is to rename her own profile first. Neither exit offers that.
- After leaving as a non-last member, the household she left is still "hers" locally. `_AdoptRow` is shown ("Put my household online") and, once tapped, goes to the terminal "already online" state (arb `settingsAccountAdoptBlockedTitle`). The way forward (G-10 fork) is unbuilt.

**Suggestion (M):** a "moved out" state (keep history, skip in rotation, show a "Moved out" chip). Add a Members-list indicator for linked / you / moved out. Add "rename my profile to…" in the leave and delete sheets. Hide the Adopt row after leaving a household that still exists.

### MF3 (P2): No in-app route to the policy, source or operator
> "Open source, local-first, and I cannot find the privacy policy or the repo from inside the app."

`grep -ri 'privacy|github.com' lib/` returns nothing user-facing. About has Version, Error reports, Licenses (Flutter licence page) and Donate (`settings_screen.dart` About group; `about_section.dart`). The arb description at arb:1399 says "PRIVACY.md is that", but nothing links to it. The backend can only be changed at build time (`supabase_config.dart:34-48`; PRIVACY.md "Who operates the backend"). So she cannot tell, in the app, whose server "the sync server" is.

**Suggestion (S):** About rows for Privacy notes, Source code, and a read-only "Sync server: <host>" line. M later: a custom-server field.

### MF4 (P2): New phone: no restore, and no guidance for local-only users
> "I export, I switch phones, and there is nothing to import into."

Export writes a JSON file via the share sheet (`export_row.dart:46-64`; raw `SELECT *` of 8 tables incl. soft-deleted rows, `data_export.dart:63-72`). There is no import (known G-3). Signed-in users can recover by Reconnect (`_ReconnectRow`, welcome reconnect card). Local-only users have no route short of first signing in on the old phone and adopting (PP10). Nothing in the app says "moving phones: sign in on the old one first". The Export row carries no sublabel (`export_row.dart:41-45`), so format and contents are unexplained. The file includes the `settings` table, so it carries `syncHouseholdId` and any `pendingJoinCode` (`tables.dart:313`); `pendingJoinCode` is an unused invite code but still a token. PRIVACY.md says settings never leave the device.

**Suggestion (XS now, M later):** sublabel "JSON file with your members, chores, history and shopping list; the app cannot import it yet" plus a "Switching phones?" hint. Exclude `settings` from the export, or at least scrub sync ids and join code. Importer is G-3.

---

## Quality of life

### Q1 (P2): Screen-reader labels are missing where lists repeat
> "TalkBack says 'Complete, button' twenty times."

- Chore rows: the tooltips are the generic "Complete" and "More actions" (`chore_occurrence_tile.dart:139,170`; arb:178,182), with no chore name. The tile itself has `onLongPress` only (`:121`) and no tap or semantic action. Title and metadata are separate nodes from the buttons.
- Shopping rows: `_CheckRing` is `Semantics(container, button, checked)` with no label (`shopping_item_tile.dart:152-159`); the item name is a sibling Text. Could not verify on a device how the nodes merge.
- Settings group headers are a `Semantics(label)` with no `header: true` (`settings_group.dart:46-52`), so they cannot be jumped to on a ~25-row screen.
- The hand-rolled bar (`app_shell.dart:361-364`) sets `button` and `selected` but no "tab 1 of 3" position that `NavigationBar` would give.

**Suggestion (S):** label with the chore or item name (`Semantics(label: 'Complete $title')`), add `header: true`, and add an index hint to the tab bar.

### Q2 (P3): Large text: fine at 2.0 by design, unverified above, and notes are not readable in the list
- Spec makes 2.0 a release gate (`docs/specs/theme-v2.md` §5). The bottom bar is a fixed `SizedBox(height: 72)` (`app_shell.dart:350`). By my arithmetic (30 + 2 + labelMedium 12sp × scale × 1.33) it fits at 2.0 (≈64dp) and overflows above about 2.25×, i.e. iOS accessibility sizes. No `TextScaler` clamp exists (`grep textScaler` finds only the avatar clamp, ring and swatch exceptions). I did not run it.
- Chore notes are one ellipsized line (`chore_occurrence_tile.dart:383-387`), so larger text shows less of the note and the row does nothing on tap to read the rest.
- Positive: `SettingsRow` stacks values under labels above 1.3× (`settings_group.dart:155`); the exit sheet and delete dialogs scroll.

**Suggestion (XS):** `maxLines: 2` for notes under large text or tap-to-expand; cap the bar's text scale or use `minHeight`.

### Q3 (P3): Hard-coded English household name, family wording
`createLocalHousehold` names every household `'My household'` in English (`household_repository.dart:139`), stored and synced. The welcome flow asks only for "Your name" (`welcomeCreateNameLabel`). So Priya's flatmate sees "Synced with My household", "Leave My household?" and "Reconnect to My household", also on a German phone. Rename exists (Members → household name row) but is undiscovered. The join card says "Join my family's household" and "from a family member's device" (arb `welcomeJoinTitle`, `welcomeJoinSubtitle`), and the invite share text says "Join my household".

**Suggestion (XS):** ask for the household name during onboarding, or localise the default; say "household" not "family" in the join card.

### Q4 (P3): Invite code and join error details
- `runInviteFlow` revokes every active invite before creating a new one (`invite_flow.dart:29`). The sheet says so ("replaces any earlier code and expires in 7 days", arb:1121), but a flatmate mid-join with the old code gets an opaque failure. The sheet shows no expiry date.
- `joinCodeErrorMessage` maps every `PostgrestException` (5xx, permission, outage included) to "That code doesn't work. Double-check it for typos" (`join_flow_steps.dart:50-54`; arb:1682). Only non-Postgrest errors get the "check your connection" copy.
- Code is 8 chars from a 32-symbol alphabet using Postgres `random()` (`20260731120000_initial_schema.sql:~304`), valid 7 days, and I found no attempt limiting in the migrations (platform rate limits could not be verified). Probably fine at that entropy, but worth noting for a security-minded user.

**Suggestion (XS-S):** distinguish "invalid or expired" from other failures, show expiry ("valid until Sat 12th"), consider `gen_random_bytes` for the code.

### Q5 (P3): Reset app data does not point at Export or at server-side deletion
`settingsResetConfirm1Body` (arb:1909) says "There is no cloud backup -- this can't be undone" and, unlike delete-account (D-L7), never mentions Export. The linked variant (`settingsResetConfirm1BodyLinked`) says the household stays online and does not say her account and email also stay on the server, or that Delete my account is the way to erase them. PRIVACY.md's "Deleting your data" lists only Reset for local (PRIVACY.md:60). Copy also uses ASCII `--` where the rest of the app uses an em dash.

**Suggestion (XS):** add "Export first" to Reset's first dialog and one clause naming Delete my account in the linked body.

---

## What already works well

1. **Offline-first is real and says so.** Welcome screen states "No account needed" (`welcomeOffline`); the sync engine, error uploader and join card are all gated on config, link and sign-in; `allowBackup="false"` plus the iOS backup exclusion (`AndroidManifest.xml:29`, backlog A-3b); Inter font bundled, no analytics dependency.
2. **Honest destructive confirms for the common cases.** Disconnect, non-last Leave, Delete account (choice sheet then a final dialog that names the outcome, with an export pointer), and claimed-member removal ("it keeps everything it already has, as its own local copy", arb `memberRemoveDialogBodyClaimed`) all match what the code does. The "also delete this phone's copy" checkbox is unchecked by default, so it never silently wipes.
3. **Departed people's work is preserved.** Soft-deleted members still show in Chore history if they have completions (`stats_service.dart:128-144`); rotation, fixed and unassigned rewrites on member delete match the copy (`member_service.dart:150-190`).
4. **Revocation and signed-out states are explicit.** A removed device gets a revoked notice with a keep-or-wipe choice (`membership_revoked_notice.dart`); signed-out-but-linked gets its own paused notice and a Disconnect (`account_section.dart:_SignedOutLinkedSection`); the join wizard resumes after a process kill (`welcome_screen.dart` auto-resume).
5. **Error scrubbing is deliberately lossy.** `ErrorScrubber` drops Postgrest `details`, cuts sqlite "Causing statement", and redacts emails, quoted spans and long numbers (`error_scrubber.dart:60-120`). The server grants insert-only plus 90-day prune with cascade on account delete (`client_errors.sql`).
6. **Large-text care in the places that need it.** `SettingsRow` restacks at >1.3× (`settings_group.dart:155`); the exit sheet uses `OverflowBar` and scroll; the delete dialog is `scrollable`; avatars scale with text up to 1.6×; due state uses border plus chip text, not colour alone (`chore_occurrence_tile.dart:108-112`); a language override with a System default exists (`language_section.dart`).

---

## Known-backlog +1 (hurts Priya because…)

- **G-3 / F12 restore from backup:** an export she cannot import is a one-way door; the archive in PP3 is the same gap.
- **G-10 fork a removed member's local copy:** after leaving, her only forward path is Reset or a manual workaround.
- **G-11 account in several households:** a flat-share veteran (two flats over time) hits the single-reconnect chooser.
- **G-13 12sp category labels below 4.5:1 in light theme:** category names on chore tiles are 12sp in `categoryTone` (`chore_occurrence_tile.dart:_CategoryDotName`), the worst case for low vision.
- **G-14 widget tests cannot measure text metrics:** this is why Q2's overflow above 2.0 would not be caught by CI.
- **F5 / D-5 offline indicator (shipped):** the banner exists, but PP6 shows it is generic and cannot tell offline from rejected.
- **Last-push-wins trade-off (`future-improvements.md`):** PP9; the copy promise that it is "said out loud" is not met.
- **A1.1 signed-out honesty (shipped):** works, but only inside Settings; no ambient hint on the lists.
- **`docs/specs/client-error-reporting.md` §9 (no in-app error UI):** PP4 and PP6 are the user-side cost of that decision.
