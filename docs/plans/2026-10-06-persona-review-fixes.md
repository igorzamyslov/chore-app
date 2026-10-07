# Persona-review fixes — implementation plan (v0.15.0+22)

> **For agentic workers:** this plan is executed workstream-by-workstream by
> isolated subagents (one git worktree each), merged by the orchestrator into
> the integration branch `claude/app-personas-feedback-1a67fd`, shipped as one
> PR. Each workstream below is a self-contained brief: findings covered, exact
> behaviour, copy, files, tests, docs. The findings themselves (with
> `path:line` evidence) are in `docs/feedback/2026-10-06-persona-review.md`
> and the raw reports under `docs/feedback/2026-10-06-personas/`. Read the
> rows you are assigned before touching code.

**Goal:** address every finding of the 2026-10-06 persona + technical review
(except the items explicitly deferred in §0) in one release.

**Architecture:** no new layers. Sync fixes live in `sync_engine.dart` /
`sync_repository.dart` / `household_gateway.dart`; behaviour changes go through
the existing services (`ChoreService`, `MemberService`, `HouseholdExitService`);
UI changes stay inside `lib/features/**`; every string through gen_l10n (EN
template with `@` description + DE du-form); server changes are new files
under `supabase/migrations/` and are applied to prod by the orchestrator.

**Tech stack:** Flutter 3.44.8 pinned, Riverpod 2, drift (schema v17 → v19),
Supabase (Postgres 17, pgcrypto + pg_cron present), gen_l10n, Maestro 2.7.0.

## Global constraints (apply to every workstream)

- **Worktree hygiene** (README): in a fresh worktree run
  `flutter pub get --enforce-lockfile` FIRST, then `tool/check_formatter_config.sh`
  must print that the config resolves, BEFORE any `dart format`. Prefix every
  flutter/dart command with `env -u GIT_DIR -u GIT_INDEX_FILE`.
- **Never run the full `flutter test` suite locally** (CI does; locally it can
  deadlock on drift streams). Run only the test files you touched or added,
  each with `timeout 300`. Never run more than one flutter process at a time.
- Gates you must pass before committing: `dart format` (changed files),
  `flutter analyze --fatal-infos --fatal-warnings`, your touched tests green,
  `flutter gen-l10n` run after any ARB edit (generated `lib/l10n/app_localizations*.dart`
  are committed), `dart run build_runner build --delete-conflicting-outputs`
  after any drift table change (`app_database.g.dart` is committed).
- Commit with `--no-verify` (hooks are slow; CI runs the same gates). Several
  small commits per workstream, conventional messages, **no Co-Authored-By**.
- **Copy rules:** every user-visible string is an ARB key with a `@` description
  saying where it appears and why it is worded so; DE is du-form; em dashes
  `—`, never `--`. Any EN string you change: grep `test/` and `e2e/` for the old
  text and update those asserts. Prefer asserting by semantic id.
- **Semantic ids:** every new interactive widget gets `semantic('<area>.<name>', child: …)`.
- **Tests:** widget tests use the real in-memory `AppDatabase` + fixed clock
  via the two provider overrides (see `test/test_utils/pump_app.dart`); never
  mock repos. Never `await` a drift stream outside the widget pump. For
  bare-`ProviderContainer` tests never `await container.read(bootstrapProvider.future)`
  — poll `.hasValue` with pump loops.
- **Specs are binding contracts.** When you change behaviour a spec describes,
  amend that spec in the same commit (add a dated "Amendment 2026-10-06" block;
  do not silently rewrite history).
- **Do not** touch files outside your workstream's list unless a compile
  error forces it; say so in your report if you did.
- Report back: what you changed, what you verified (commands + results), what
  you could not verify, any deviation from this brief.

## 0. Deferred (not in this release)

Role/permission model (E4 beyond disclosure; decision D1 stands) · reminder
notification Done/Snooze actions (slice 7; needs a phone) · several shopping
lists (G-8, XL) · email OTP fallback (D2; needs dashboard email-template edit)
· bottom-anchored quick-add (F2) · keep-screen-on toggle (F8 part; new
dependency) · in-app error-report viewer (B8 part) · import of JSON export
(G-3).

## 1. Schema and migration ownership

Local drift schema: **W5 ships v18** (settings columns `choreRemindersEnabled`
BOOL default true, `syncLeftAt` TEXT nullable). **W3 ships v19** (chores column
`pausedUntil` TEXT nullable, plain date `yyyy-MM-dd`). Nobody else bumps the
schema. Server: **W5 ships `20261006120000_join_funnel.sql`** (peek_invite RPC,
leave_household soft-deletes own profile). **W3 ships
`20261006130000_chore_paused_until.sql`** (`chores.paused_until date null`).
**W6 ships `20261006140000_privacy_and_grants.sql`** (purge job, column-scoped
grants, CSPRNG invite codes). Every migration file must also be covered by
`supabase/tests/*.sql` (pgTAP) where a policy or RPC changes.

## 2. Shared interfaces introduced by this plan

- `SyncRepository.watchDirtyRowCount() → Stream<int>` (W1): count of
  `syncDirty == true` rows across the seven synced tables + pending tombstones.
- `syncPendingCountProvider` (`lib/app/providers.dart`, W1): `StreamProvider<int>`
  over the above, `0` while unlinked.
- `syncLastPullCompletedAtProvider` (W1): `StateProvider<DateTime?>` set by the
  engine from `clock.now()` on every successful pull (device clock).
- `RefreshOutcome` enum (W1): `ok`, `offline`, `rejected`; returned by
  `SyncEngine.refreshNow()` instead of throwing. UI maps `offline` →
  existing `syncRefreshError`, `rejected` → new `syncRefreshErrorRejected`.
- `showAppSnackbar(..., {Duration duration = const Duration(seconds: 4)})` (W2
  adds the parameter).
- `showAppErrorSnackbar(BuildContext, {required String message, VoidCallback? onRetry})`
  (W6 adds; `lib/app/snackbars.dart`).
- `ChoreRepository.detachMemberFromChores(String memberId)` (W5 extracts from
  `MemberService.deleteMember`; W5 also calls it after a pull soft-deletes a
  member).
- `Settings.choreRemindersEnabled` (W5 adds column; W4 reads it).

---

## W1 — Sync integrity (findings A1, A2, A3, A4, A5, A6, A7, A8, H9; copy for the rejected-push state)

**Model:** Fable. **Files:** `lib/application/sync_engine.dart`,
`lib/data/repositories/sync_repository.dart`, `lib/data/repositories/chore_repository.dart`
(`pendingOccurrenceOf` only), `lib/application/household_gateway.dart`
(`downloadHousehold` paging), `lib/data/sync/row_mappers.dart` (timestamp
normalisation), `lib/domain/sync_health.dart`, `lib/app/providers.dart`
(the three providers in §2), `lib/features/settings/last_synced_line.dart`,
`lib/features/sync/sync_health_banner.dart`, `lib/features/chores/chores_list_screen.dart`
and `lib/features/shopping/shopping_list_screen.dart` (only the pull-to-refresh
error mapping), `lib/l10n/*.arb`, `test/application/sync_engine_test.dart`,
`test/application/fake_sync_transport.dart`, `test/domain/sync_health_test.dart`,
`test/application/refresh_now_test.dart`, `test/data/repositories/*sync*`,
`docs/specs/sync-backend.md`, `docs/specs/sync-freshness.md`.

### W1.1 Tombstones only kill pending occurrences (A1)
- `SupabaseSyncTransport.markDeleted` is called for `chore_occurrences` with
  match `{'id': id, 'status': 'pending'}` (the `.match()` map already supports
  extra columns). `applyPulledOccurrenceDeletion(id)` adds
  `tbl.status.equalsValue(OccurrenceStatus.pending)` to its WHERE.
- Tests (engine, real in-memory DB + `FakeSyncTransport`): (a) local `done`
  row, pulled tombstone for its id → row survives; (b) push of a tombstone
  calls `markDeleted` with the status match (assert on the fake's recorded
  call); (c) the full race from the finding: A completes O and pushes, B
  tombstones O and pushes, A pulls → A still has O as `done`.
- `FakeSyncTransport.markDeleted` must honour the status match when it mutates
  its in-memory server rows.

### W1.2 Tolerant `pendingOccurrenceOf` (A5)
- Order by `dueDate` desc, `updatedAt` desc, `limit(1)`; `catchUpOverdue`
  calls `SyncRepository.repairGhostOccurrences(householdId)` (make it callable
  outside the pull transaction; it already only touches pending rows) before
  iterating chores. Test: two pending rows → catch-up completes, one survives.

### W1.3 Convergent ghost-repair key + timestamp normalisation (A4)
- Survivor key: `dueDate` desc, then `id` desc. `updatedAt` leaves the key.
- `*FromRow` mappers in `row_mappers.dart` normalise every `*_at` string via
  `DateTime.parse(s).toUtc().toIso8601String()` so local and pulled stamps
  share one format. Test: a `…+00:00` input round-trips to `…Z`.
- Document the invariant in `sync-backend.md` §8.7 (new): *"Survivor selection
  uses only fields both devices see identically (`dueDate`, `id`)."*

### W1.4 Assignee set is one LWW value (A8)
- In `_pullSinceInner`, if the local chore row is dirty, skip the pulled
  `chore_assignees` rows and tombstones for that chore. If it is clean,
  replace the whole local set for that chore with the pulled rows (delete
  then insert, inside the pull transaction). `_currentAssigneeIds` orders by
  `position`, then `memberId`. Test: dirty local chore + pulled assignees →
  local set unchanged; clean chore → exact pulled set, positions 0..n-1.

### W1.5 One pull in flight; ignore own realtime echo (H9)
- `Future<void>? _inFlightPull`; `pullSince()` returns the running future if
  present. After our own push completes, ignore `householdChanges` events for
  1 s (`_ignoreRealtimeUntil`). Test: two concurrent `pullSince()` calls hit
  the transport once.

### W1.6 Paging (A2)
- `const int syncPageSize = 1000;` (`lib/application/sync_engine.dart`, doc
  comment explaining PostgREST `max_rows`). `pullTable` and every per-table
  read in `downloadHousehold` loop: `.order('updated_at', ascending: true).order('id').range(offset, offset + syncPageSize - 1)`
  until a page shorter than `syncPageSize`. `SyncTransport.pullTable` gains
  `{required int offset, required int limit}`; `FakeSyncTransport` implements
  paging over its row list. Tests: 1,001 fake rows → all applied; cursor
  unchanged on a thrown mid-page error.

### W1.7 Per-table push with quarantine; honest "Last synced" (A3)
- `_pushAll` wraps each table push in its own try/catch and continues;
  collects failures. On a batch failure whose `PostgrestException.code`
  starts with `22`, `23` or `42`, retry that table row-by-row; a row that
  still fails is left dirty, skipped for this tick, and recorded once via
  `AppLog.error('sync.rejected', e, s, context: {'table': t, 'id': id})`
  (dedupe by id in-memory so the log is not spammed every 60 s).
- `refreshNow()` returns `RefreshOutcome` (§2): `rejected` if any table hit a
  22/23/42 class error, `offline` on any other failure, else `ok`. Update
  `refresh_now_test.dart` and the two pull-to-refresh call sites: `rejected` →
  `syncRefreshErrorRejected` = "The household server rejected a change from
  this phone, so it hasn't gone through. Check for an app update; your other
  changes keep syncing." DE: "Der Haushalts-Server hat eine Änderung von diesem
  Handy abgelehnt, sie ist also nicht angekommen. Prüfe, ob es ein App-Update
  gibt; deine anderen Änderungen werden weiter synchronisiert."
- `SyncRepository.watchDirtyRowCount()` + `syncPendingCountProvider` (§2).
- `last_synced_line.dart`: when the count is > 0 append a second line
  `syncPendingChanges` = "{count, plural, one{1 change waiting to send} other{{count} changes waiting to send}}"
  (DE: "{count, plural, one{1 Änderung wartet aufs Senden} other{{count} Änderungen warten aufs Senden}}").
  The whole tile is tappable (semantic id `settings.account.syncNow`) and runs
  `refreshNow()`, showing the outcome snackbar. Widget test for both lines.
- Spec: `sync-backend.md` §8.3 amendment (per-table posture, quarantine),
  `sync-freshness.md` §2.4 amendment (pending line + tap).

### W1.8 Cursor overlap (A6)
- Store `serverNow - const Duration(seconds: 30)` as `syncLastPulledAt`.
  Comment why (`now()` = transaction start). Test with the fake transport
  returning a row stamped 10 s before the `serverNow` it handed out → pulled
  on the next incremental pull.

### W1.9 Health on the device clock (A7)
- Engine sets `syncLastPullCompletedAtProvider` (§2) from `clock.now()` after
  each successful pull. `syncHealthStatusProvider` passes that as
  `lastPulledAt` to `computeSyncHealth` (fall back to the persisted cursor only
  when the in-memory value is null, i.e. before the first pull of this
  session). Test: device clock 10 min ahead, pull just completed → healthy.

---

## W5 — Join funnel, members, honesty copy (D1, D3, D4, D5, D6, D7, D8, D9, D10, D11, D12, D13, B4, B5, B6, B8; schema v18; migration `20261006120000_join_funnel.sql`)

**Model:** Opus. **Files:** `lib/features/onboarding/*`, `lib/features/settings/account_section.dart`,
`manage_members_screen.dart`, `member_edit_sheet.dart`, `invite_flow.dart`,
`invite_code_sheet.dart`, `join_flow_steps.dart`, `join_household_sheet.dart`,
`exit_confirm_sheet.dart`, `about_section.dart`, `export_row.dart`, `reset_flow.dart`,
`settings_screen.dart`, `lib/application/household_gateway.dart`,
`household_exit_service.dart`, `household_create_service.dart`, `member_service.dart`,
`lib/data/repositories/household_repository.dart`, `category_repository.dart`,
`chore_repository.dart` (`detachMemberFromChores`), `sync_repository.dart`
(`applyPulledMember` post-hook only), `lib/data/db/tables.dart`, `app_database.dart`,
`lib/application/data_export.dart`, `lib/l10n/*.arb`, `supabase/migrations/20261006120000_join_funnel.sql`,
`supabase/tests/`, tests under `test/features/onboarding`, `test/features/settings`,
`test/application/`, `test/data/db/schema_migration_test.dart`, `e2e/common/onboard_fresh.yaml`
(if the welcome ids change — they must NOT), `docs/specs/onboarding-v2.md`,
`members-management.md`, `household-lifecycle.md`.

### W5.1 Welcome screen (D1)
- Both cards render with `emphasized: false` (same elevation/outline). Order
  stays Create, Join. `welcomeJoinSubtitle` → "Got an invite code? Sign in and
  enter it here." (DE: "Hast du einen Einladungscode? Melde dich an und gib
  ihn hier ein."). Ids `welcome.create` / `welcome.join` unchanged.
- Amend `onboarding-v2.md` §1 ("Primary card") with the reason (Leon A1).

### W5.2 Claim confirm + household name (D3)
- New RPC `peek_invite(p_code text) returns text` (security definer, pinned
  `search_path`, `authenticated` only): returns the household `name` for an
  active, unexpired, unrevoked code; raises `'invalid code'` otherwise.
  Gateway: `Future<String> peekInviteHouseholdName(String code)`; fake gateway
  returns a fixed name. pgTAP test: valid code returns name; revoked/expired
  raise; anon cannot execute.
- Join page: after the code is accepted, the AppBar title becomes the
  household name; the chooser header reads `joinHouseholdChooserTitle` with
  the name interpolated: "Which one is you in {household}?" (DE: "Wer bist du
  in {household}?"). Tapping a row opens a confirm dialog
  `joinClaimConfirmTitle` "Join {household} as {name}?" (DE: "{household} als
  {name} beitreten?"), body `joinClaimConfirmBody` "You'll see and mark the
  chores assigned to {name}. Pick another name if this isn't you." (DE: "Du
  siehst und erledigst die Aufgaben, die {name} zugeteilt sind. Wähle einen
  anderen Namen, wenn das nicht du bist."), actions Cancel / Join. Only Join
  calls `_runJoin`. Semantic ids `join.claim.confirm`, `join.claim.cancel`.
- Invite sheet gains the line `settingsMembersInviteHint` "Add everyone under
  Members first — they'll pick their own name when they join." (DE: "Leg
  vorher alle unter Mitglieder an — beim Beitreten wählen sie ihren eigenen
  Namen.").
- Widget tests: confirm dialog appears and Cancel does not claim; Join claims.

### W5.3 Member rows show status (D4)
- `_MemberRow` subtitle, only when the household is linked
  (`settings.syncHouseholdId != null`): claimed by the signed-in user →
  `memberStatusYou` "You" (DE "Du"); other claimed → `memberStatusLinked`
  "Uses Famdo on their own phone" (DE "Nutzt Famdo auf dem eigenen Handy");
  unclaimed → `memberStatusUnclaimed` "No phone yet — you can mark their
  chores" (DE "Noch kein Handy — du kannst ihre Aufgaben abhaken"). Local
  household: no subtitle. Widget test for the three states.

### W5.4 Invite code lifecycle (D5)
- Gateway `Future<ActiveInvite?> activeInvite(String householdId)` reading
  `household_invites` (SELECT is granted) where `revoked_at is null and expires_at > now()`
  → `{code, expiresAt}`. `runInviteFlow`: if one exists, show the sheet with
  THAT code and `settingsMembersInviteValidUntil` "Valid until {date}" (DE
  "Gültig bis {date}", `DateFormat.yMMMd`), plus a text button
  `settingsMembersInviteNewCode` "New code" (DE "Neuer Code") which first
  confirms `settingsMembersInviteReplaceTitle` "Replace the shared code?" /
  body "Anyone still joining with the old code will need this new one." (DE:
  "Geteilten Code ersetzen?" / "Wer noch mit dem alten Code beitritt, braucht
  dann den neuen.") and only then revokes + creates. No active code → create
  directly as today.
- `joinCodeErrorMessage`: `PostgrestException` whose message contains
  `invalid` or `expired` → existing typo copy; any other `PostgrestException`
  → `joinCodeErrorServer` "Couldn't check the code right now — try again in a
  moment." (DE "Der Code konnte gerade nicht geprüft werden — versuch es
  gleich noch mal."). Unit test for both.

### W5.5 Invite path signposting (D6, D7, B6)
- Local household Members screen: a disabled `SettingsRow`-style row
  `settingsMembersInviteLocalTitle` "Invite" with subtitle
  `settingsMembersInviteLocalSubtitle` "Sign in first to invite your family"
  (DE "Melde dich zuerst an, um deine Familie einzuladen"), semantic id
  `settings.members.inviteLocal`, no `onTap`.
- `settingsAccountAdoptIntro` → "Put it online so your family can join with an
  invite code. Also keeps your other phones in step." (DE: "Stell ihn online,
  damit deine Familie per Einladungscode beitreten kann. Hält auch deine
  anderen Handys auf dem gleichen Stand.")
- Adopt is no longer one tap: a confirm sheet `settingsAccountAdoptConfirmTitle`
  "Put '{household}' online?" with body `settingsAccountAdoptConfirmBody`
  "This uploads your members, chores, completion history, notes and shopping
  list to the sync server, under your account. You can take it down again
  with Delete my account or Leave the household." (DE: "Das lädt deine
  Mitglieder, Aufgaben, den Erledigt-Verlauf, Notizen und die Einkaufsliste
  auf den Sync-Server hoch, unter deinem Konto. Rückgängig machst du es mit
  Konto löschen oder Haushalt verlassen."), buttons Cancel / Put online.
  Semantic ids `settings.account.adopt.confirm`, `settings.account.adopt.cancel`.
- Invite share text `settingsMembersInviteShareText` appends a second
  sentence: "Get the app: https://github.com/igorzamyslov/chore-app/releases/latest"
  (DE: "Die App gibt's hier: …same URL…").

### W5.6 Leaving really leaves (D8)
- Migration: `leave_household` additionally sets `deleted_at = now()` on the
  caller's member row (so the family stops seeing them in rotations; history
  stays — soft-deleted members are already shown in Chore history). Keep the
  orphan cascade. pgTAP: after leave the row has `deleted_at`.
- Client: extract the assignment rewrite from `MemberService.deleteMember`
  into `ChoreRepository.detachMemberFromChores(memberId)` (rotation: remove
  from lists, reassign open turns to the next member; fixed: unassign; same
  rules as today — move, don't change). `MemberService.deleteMember` calls it.
  In `SyncRepository.applyPulledMember`, when the pulled row has `deletedAt`
  and the existing local row did not, call `detachMemberFromChores` after the
  write. Test: pulled soft-delete → that member no longer appears in any
  `chore_assignees` row or pending occurrence.
- Rename-on-exit: the Leave and Delete-account confirm sheets gain an optional
  field `householdExitNameLabel` "Your name in the household's history" (DE
  "Dein Name im Verlauf des Haushalts") prefilled with the current name; if
  changed, rename the profile (existing member update path) BEFORE the RPC.
- Schema v18: `Settings.syncLeftAt` TEXT nullable (set to now on a successful
  non-last leave) and `Settings.choreRemindersEnabled` BOOL default true (for
  W4). Migration in `app_database.dart` `if (from < 18)`; fixture + case in
  `schema_migration_test.dart`. Account section: hide the Adopt row while
  `syncLeftAt != null`; show instead a plain text `settingsAccountLeftNotice`
  "You left this household's online copy. What's on this phone stays yours; to
  share it again, start a new household from it later." (DE: "Du hast die
  Online-Kopie dieses Haushalts verlassen. Was auf diesem Handy ist, bleibt
  deins; um es wieder zu teilen, kannst du später einen neuen Haushalt daraus
  machen."). Reset app data clears `syncLeftAt`.
- Amend `household-lifecycle.md` §2.2 (leave now soft-deletes the profile; the
  reclaim-via-invite path is gone — joining again means "I'm new here" or an
  unclaimed profile).

### W5.7 Terminology and consequence copy (D9, B4, B5, D13)
- `memberEditDeleteBlockedSelf` and `syncRefreshErrorRevoked`: "Settings →
  Account" → "Settings → Household" (EN + DE "Einstellungen → Haushalt").
- Leave row subtitle `settingsAccountLeaveSubtitle` "Removes you from the
  household. Your chores and history stay with them." (DE "Entfernt dich aus
  dem Haushalt. Deine Aufgaben und dein Verlauf bleiben dort."). Disconnect
  row subtitle `settingsAccountDisconnectSubtitle` "Stops syncing on this phone
  only — the household stays online for everyone else." (DE "Stoppt die
  Synchronisierung nur auf diesem Handy — für alle anderen bleibt der Haushalt
  online.").
- Replace "this device" with "this phone" in `settingsAccountPausedNotice`
  and `syncRefreshErrorRevoked` (EN) / "dieses Gerät" → "dieses Handy" (DE).
- `settingsAccountSignOutConfirmBody` and `settingsAccountPausedNotice` gain:
  "If someone else edits the same item meanwhile, your version replaces
  theirs when you sign back in." (DE "Ändert jemand anderes inzwischen
  dasselbe, ersetzt deine Version seine, sobald du dich wieder anmeldest.")
- Reset confirm 1 body: replace ` -- ` with ` — ` and prepend "Export your
  data first if you want a copy. " (DE "Exportiere vorher deine Daten, wenn du
  eine Kopie behalten willst. "). Linked variant appends "Your account and
  email stay on the server — Delete my account removes them." (DE "Dein Konto
  und deine E-Mail bleiben auf dem Server — Konto löschen entfernt sie.")
- Sign-in intro (B8): append "Technical error reports are sent too — you can
  switch them off under About." (DE "Technische Fehlerberichte werden ebenfalls
  gesendet — unter Über die App kannst du sie abschalten.")
- A "How accounts work" link under the sign-in intro (`settings.account.howItWorks`)
  opening a bottom sheet with three short paragraphs: Account (your email login
  on the sync server), Member (a person in the household; may or may not have
  an account), Household (the shared chores and list; lives on your phone, and
  on the server once put online). EN + DE.

### W5.8 Localised defaults and household name (D10)
- `householdDefaultName` ARB key "My household" / "Mein Haushalt";
  `HouseholdCreateService.create` takes `householdName` and the welcome flow
  passes `l10n.householdDefaultName`. `CategoryRepository.seedDefaults(householdId, {required Locale locale})`
  with a DE table (Küche, Bad, Wohnbereich, Wäsche, Haustiere, Garten,
  Instandhaltung, Besorgungen; Obst & Gemüse, Milchprodukte, Fleisch & Fisch,
  Backwaren, Tiefkühl, Getränke, Haushalt, Sonstiges) — map 1:1 to the EN
  seeds in order; any other locale falls back to EN. Both call sites pass the
  app locale.
- Settings → Household group: first row becomes `settingsHouseholdNameRow`
  "Household name" with the current name as value, tapping opens the existing
  rename sheet (semantic id `settings.household.name`). Keep the Members row.

### W5.9 About and export (D11, D12)
- About rows: `settingsAboutPrivacy` "Privacy notes" → `https://github.com/igorzamyslov/chore-app/blob/main/PRIVACY.md`;
  `settingsAboutSource` "Source code" → `https://github.com/igorzamyslov/chore-app`;
  when `supabaseConfigured`, a non-tappable row `settingsAboutSyncServer`
  "Sync server" with value = host of the configured URL.
- Export row sublabel `settingsExportSubtitle` "JSON file with your members,
  chores, history and shopping list. The app can't import it yet." (DE
  "JSON-Datei mit Mitgliedern, Aufgaben, Verlauf und Einkaufsliste. Die App kann
  sie noch nicht importieren."). `buildExportDocument` excludes the `settings`
  table; update `data_export_test.dart` and PRIVACY-facing comment.

---

## W2 — Shopping (A9, F1, F3, F4, F6, F7, F8, F9, F10, F11, F12, F13, F14, E10-shopping, H6-query)

**Model:** Sonnet. **Files:** `lib/features/shopping/**`, `lib/data/repositories/shopping_repository.dart`,
`lib/data/repositories/sync_repository.dart` (`applyPulledShoppingItem` only),
`lib/app/snackbars.dart` (add `duration`), `lib/l10n/*.arb`, `test/features/shopping/**`,
`test/data/repositories/shopping_repository_test.dart`, `test/application/sync_engine_test.dart`
(A9 case), `e2e/flows/shopping/add_check_clear.yaml` (update if copy asserts
break), `docs/specs/ui-shopping.md`, `docs/specs/sync-backend.md` (new §8.8).

- **A9:** in `applyPulledShoppingItem`, when the local row is dirty AND the
  pulled `updatedAt` (normalised) is later than the local `updatedAt`: write
  the pulled `checkedAt` and `deletedAt` onto the local row, keep local
  `name`/`quantityNote`/`categoryId`, keep `syncDirty = true`. Engine test for
  the Tom scenario (offline clear vs re-add → item stays on the list). Spec
  §8.8 "Shopping field-level merge" with the rationale.
- **F1 + F10:** app bar gets a one-line subtitle widget `ShoppingStatusLine`:
  "{remaining} left" (`shoppingRemainingCount`, plural; DE "Noch {count}"),
  and when linked: " · " + either `shoppingSyncedAgo` "synced {relative}" (reuse
  the relative formatter from `last_synced_line.dart` — extract it to
  `lib/features/settings/relative_time.dart` if it is private) or
  `syncPendingChanges` from W1 when `syncPendingCountProvider` > 0. Rows added
  by a member other than the acting/claimed member show a 16 dp
  `MemberAvatar` of `addedBy` after the name (tooltip = member name).
- **F3:** ticking shows `shoppingCheckedSnackbar` "In the cart" (DE "Im
  Einkaufswagen") with Undo (unchecks). Latest-wins behaviour is fine.
- **F4:** `showAppSnackbar` gets `duration` (default 4 s). Clear-checked and
  Put-all-back use 8 s. Put all back shows `shoppingPutBackSnackbar`
  "{count, plural, one{Put 1 item back} other{Put {count} items back}}" (DE
  "{count, plural, one{1 Artikel zurückgelegt} other{{count} Artikel
  zurückgelegt}}") with Undo re-checking the captured ids.
- **F6 (quantity parse):** on submit, `parseQuantity(raw) → (name, quantityNote?)`
  recognising `^(\d+)\s*[x×]?\s+(.+)$` and `^(.+?)\s+[x×]\s*(\d+)$` → name
  trimmed, note = the number. Unit tests. Used by quick-add only.
- **F7:** `normalizeShoppingItemName` folds diacritics (ä→a, ö→o, ü→u, ß→ss,
  é→e etc. via a small map) after lowercasing/collapsing. Rename in the edit
  sheet runs the same duplicate check; a hit shows inline error
  `shoppingEditDuplicateError` "Already on the list" (reuse existing key if
  present). Quick-add splits input on `,` and newline into several items
  (each trimmed, empty dropped, duplicates handled per item); snackbar when
  >1 added: `shoppingAddedCount` "{count} items added" (DE "{count} Artikel
  hinzugefügt").
- **F8:** item name `titleMedium`, quantity `bodyMedium`.
- **F9:** tapping a category header toggles that category's collapse; state
  persisted in `ui_state` under key `shopping.collapsed.<categoryId>`; header
  shows a chevron and the count when collapsed. Semantic id
  `shopping.category.<id>.toggle`. Widget test.
- **F11:** long-press a suggestion chip → menu "Forget this suggestion"
  (`shoppingSuggestionForget`, DE "Vorschlag vergessen"); stores the normalised
  name in `ui_state` key `shopping.forgottenSuggestions` (JSON list);
  suggestions filter it. `_historyRows` becomes one grouped SQL query
  (`group by normalized name` with count and max(created_at)). Tests.
- **F12:** `textCapitalization: TextCapitalization.sentences` on the quick-add
  and edit name fields.
- **F13 (DE):** "Erledigte leeren" → "Einkaufswagen leeren"; make dash usage
  consistent (em dash) in the sync strings; shorten the DE banner to "Gerade
  keine Verbindung zum Haushalt. Deine Änderungen sind gespeichert — zieh die
  Liste nach unten, um es erneut zu versuchen."
- **F14:** edit sheet: if dismissed (drag/tap-outside) with a non-empty,
  changed name or changed fields → save (same path as Save). Test.
- **E10 (shopping):** when linked and the row is `syncDirty`, show a 14 dp
  `Icons.schedule` glyph with tooltip `syncPendingItemTooltip` "Waiting to
  send" (DE "Wartet aufs Senden") at the row's trailing edge.

---

## W3 — Chores for the organiser (C1, C2, C3, C4, C5, C6, C7, C8, C9, C10, E4-disclosure; schema v19; migration `20261006130000_chore_paused_until.sql`)

**Model:** Opus. **Files:** `lib/application/chore_service.dart`,
`lib/data/repositories/chore_repository.dart`, `lib/data/db/tables.dart`,
`app_database.dart`, `lib/data/sync/row_mappers.dart` (`paused_until`),
`lib/features/chores/**`, `lib/features/settings/manage_categories_screen.dart`,
`category_delete_dialog.dart`, `lib/data/repositories/category_repository.dart`,
`lib/l10n/*.arb`, tests under `test/application/chore_service*`,
`test/application/chore_update_regeneration_test.dart`, `test/features/chores/**`,
`test/features/settings/*categor*`, `test/data/db/schema_migration_test.dart`,
`supabase/migrations/20261006130000_chore_paused_until.sql`,
`e2e/flows/chores/*.yaml` (only if a copy assert breaks), `docs/specs/occurrence-lifecycle.md`,
`ui-foundation-chores.md`, `docs/plans/2026-08-08-rotation-reorder.md` (add a
superseded note).

- **C1:** in `ChoreService.updateChore`, after the repository update and when
  neither recurrence nor startDate changed: load the pending occurrence; if
  its `assignedMemberId` is not valid for the new assignment (fixed: ≠ the
  fixed member; rotation: not in the list; anyone: always valid), set it via
  `_regeneratedAssignee` (rotation: first member in the new order whose turn
  it would be given `latestClosed`). Return a small result
  `ChoreUpdateResult {DateTime? nextDue, String? reassignedToName}` so the
  form can show `choreSavedSnackbar` "Saved" / `choreSavedNextDue` "Saved —
  next due {date}" / `choreSavedReassigned` "Saved — today's turn is now
  {name}'s" (DE: "Gespeichert" / "Gespeichert — als Nächstes fällig {date}" /
  "Gespeichert — heute ist jetzt {name} dran"). (C6 covered.) Tests: fixed
  Anna→Ben moves the pending occurrence; rotation removal moves it; anyone
  leaves it. Amend `occurrence-lifecycle.md` updateChore; add "superseded
  2026-10-06 for the holder-removed case" to the rotation-reorder plan.
- **C2 reassign:** action sheet row `choresMenuReassign` "Reassign this turn…"
  (DE "Diese Runde übergeben …") → member picker sheet (same layout as
  `mark_done_for_sheet.dart`, title `choresReassignTitle` "Who takes this
  turn?" / DE "Wer übernimmt diese Runde?"), writes `assignedMemberId` on the
  pending occurrence (`ChoreService.reassignOccurrence(occurrenceId, memberId)`,
  marks dirty), snackbar `choresReassignedSnackbar` "Reassigned to {name}" (DE
  "An {name} übergeben") with Undo. Rotation after completion is unchanged
  (the cover rule from #60 applies: whoever completes it is treated as the
  cover if they are not the original turn-holder — document in the spec what
  the next turn is after a reassign: the next member after the *reassigned*
  holder in order). Tests.
- **C2 pause until:** schema v19 `Chores.pausedUntil` TEXT nullable (plain
  date); server migration `alter table public.chores add column paused_until date null;`
  + row mappers both ways (`paused_until`). Pause action opens a small sheet:
  "Until I resume it" / "Until a date…" (date picker, min tomorrow). Paused
  row subtitle `choresPausedUntil` "Paused until {date}" (DE "Pausiert bis
  {date}"). `catchUpOverdue` (which already runs at bootstrap and day change)
  first unpauses every chore whose `pausedUntil <= today` via `unpauseChore`.
  Tests: auto-resume on day change; migration fixture v18→v19.
- **C3:** tile `onTap: onOpenMenu` (same sheet as long-press). Keep
  long-press. Widget test: tap opens the sheet.
- **C4:** paused rows: `onTap`/`onLongPress` open the action sheet with
  Resume / Edit / Delete only. Test.
- **C5:** "Mark done for…" shown whenever the household has > 1 member (drop
  the linked-and-signed-in gate; keep the > 1 member gate). The ordinary Done
  snackbar names the credited member whenever the household has > 1 member:
  `choresDoneCredited` "Done — credited to {name}" / with next due
  `choresDoneCreditedNextDue` "Done — credited to {name}, next due {date}" (DE
  "Erledigt — gutgeschrieben für {name}" / "… , als Nächstes fällig {date}").
  Acting-member sheet gets a second line `choresActingMemberHint` "Credit and
  your daily summary follow this person." (DE "Gutschrift und deine
  Tagesübersicht richten sich nach dieser Person."). Update
  `undo_snackbar_test.dart` and any E2E `(?s).*Done.*` asserts (they should
  still match as substrings).
- **C7:** `_onAssignmentModeChanged` keeps per-mode selections in state
  (`_fixedMemberId`, `_rotationMemberIds`) and restores them when switching
  back. Helper text under the segmented control: Fixed → "Always the same
  person." / Rotation → "Takes turns in this order, starting at 1." / Anyone →
  "Whoever gets to it." (DE "Immer dieselbe Person." / "Reihum in dieser
  Reihenfolge, beginnend bei 1." / "Wer zuerst dazu kommt."). Test.
- **C8:** weekday toggles laid out with `Expanded` inside a `Row` (no fixed 48
  dp width); labels use the first two letters of `DateFormat.E(locale)` (Mo Tu
  We …). Semantic labels keep the full day name.
- **C9:** action sheet row `choresMenuDuplicate` "Duplicate" (DE "Duplizieren")
  opens the form prefilled with every field of the chore (title identical) in
  create mode. Test: saving creates a second chore.
- **C10:** category rows show subtitle `categoryUsageCount`
  "{count, plural, =0{Not used yet} one{Used by 1 chore} other{Used by {count} chores}}"
  (shopping kind: "… item(s)"; DE accordingly). Delete dialog gains a
  dropdown `categoryDeleteMoveTo` "Move them to" (DE "Verschieben nach")
  defaulting to "Uncategorized" and listing the other categories of the same
  kind; `CategoryRepository.deleteCategory(id, {String? moveToCategoryId})`.
  Test both paths.
- **E4 disclosure:** chore delete dialog body appends "Everyone in the
  household will see this." (DE "Alle im Haushalt sehen das.") when the
  household has > 1 member.

---

## W4 — Daily use for a member (E1, E2, E3, E5, E6, E7, E8-digest-names, E9, E10-chores, B9)

**Model:** Sonnet. **Files:** `lib/features/chores/chores_list_screen.dart`,
`chores_filter_bar.dart`, `catch_up_banner.dart`, `chore_progress_card.dart`,
`chore_done_section.dart`, `chore_occurrence_tile.dart`, `chore_form/reminder_row.dart`,
`lib/features/settings/settings_screen.dart` (+ notifications group),
`lib/domain/reminder_planner.dart`, `lib/domain/digest_projection.dart`,
`lib/application/digest_plan_builder.dart`, `notification_scheduler.dart`
(digest body), `lib/application/stats_service.dart`, `lib/features/stats/*`,
`lib/app/app_shell.dart` (settings dot expiry), `lib/app/providers.dart`
(filter default, done-recently provider), `lib/data/repositories/chore_repository.dart`
(closed-recently query), `lib/data/repositories/settings_repository.dart`
(`choreRemindersEnabled` setter), `lib/l10n/*.arb`, matching tests,
`docs/specs/stats.md`, `notifications-n2.md`, `ui-foundation-chores.md`.

- **E1:** when `memberIdentityModeProvider` is pinned and no filter is stored,
  the member filter defaults to the claimed member (store it so it persists).
  Member menu marks the acting/claimed member "{name} (you)" (`choresFilterYou`,
  DE "{name} (du)"). The member filter now ALSO includes occurrences with
  `assignedMember == null`; their tile shows the chip `choresAssigneeAnyone`
  "Anyone" (DE "Jemand") where the avatar would be. Update
  `chores_filter_restore_test.dart` and add a test that unassigned rows pass
  the member filter.
- **E2:** `choresCatchUpBanner` → "Your repeating chores jumped ahead to their
  latest due date — you didn't miss anything extra." (DE "Deine wiederkehrenden
  Aufgaben sind zu ihrem neuesten Fälligkeitstermin gesprungen — du hast nichts
  zusätzlich verpasst."). Update `bootstrap_catchup_banner_test.dart`.
- **E3:** Settings notifications group gains `settingsChoreRemindersTitle`
  "Chore reminders" (DE "Aufgaben-Erinnerungen") toggle bound to
  `Settings.choreRemindersEnabled` (column exists from W5); `planReminders`
  takes `{required bool enabled}` and returns an empty plan when false; the
  recompute path passes the setting. The Settings-tab dot is hidden once
  `digestPrepromptShownAt` is older than 7 days. Tests for planner + dot.
- **E5:** progress card: `M` = pending due TODAY + done today; overdue shown
  separately as `choresProgressCatchUp` "{count} to catch up" (DE "{count}
  nachzuholen") on the subtitle line. Replace "nice work" copy:
  `choresEmptyPending` → "Nothing left for today." (DE "Für heute ist nichts
  mehr offen."), `choresProgressAllDone` → "That's everything for today." (DE
  "Das war alles für heute."). Update `chore_progress_card` tests and any
  `first_run_banners.yaml`/E2E text asserts that match old copy.
- **E6:** done-today rows: tag `choresDoneEarly` "Done early" (DE "Vorzeitig
  erledigt") when `closedOn < dueDate`; skipped rows drop the "by {name}"
  suffix; Reopen shows `choresReopenedSnackbar` "Reopened" (DE "Wieder
  geöffnet"); reopening a row whose `completedBy` ≠ the acting member asks
  `choresReopenOthersTitle` "Reopen {name}'s completion?" / body "This removes
  it from their history." / Reopen (DE "Erledigung von {name} zurücknehmen?" /
  "Das entfernt sie aus seinem Verlauf." / "Zurücknehmen"). Tests.
- **E7:** `StatsService` clamps each member's window start to
  `max(windowStart, member.createdAt)`; the share row shows `statsSince`
  "since {date}" (DE "seit {date}") when the member clamp is later than the
  window start. Amend `stats.md` §2.2 (G-1 amendment, dated). Tests.
- **E8 (digest body):** digest notification body lists up to three chore
  titles: "{title1}, {title2}, {title3}" and, if more, `digestMoreCount`
  " and {count} more" (DE " und {count} weitere"); the count line stays as the
  title. `DigestProjection` carries the titles. Update
  `digest_plan_builder_test.dart`/`notification_scheduler_test.dart`.
- **E9:** "Done today" section becomes `choresDoneRecently` "Done recently
  ({count})" (DE "Kürzlich erledigt ({count})") listing closed occurrences
  from the last 3 days, newest first, each row showing the day
  (Today/Yesterday/weekday); Reopen only on today's rows (unchanged guard).
  Update `done_today_reopen.yaml` E2E if it asserts the header text (prefer
  the semantic id `chores.section.done`).
- **E10 (chores):** when linked and the occurrence row is `syncDirty`, show the
  same 14 dp `Icons.schedule` glyph as W2 with `syncPendingItemTooltip` (key
  exists from W2).
- **B9:** reminder row label `choreFormReminderLabel` → "Remind whoever it's
  assigned to" (DE "Erinnere, wer dran ist"); hint → "Rings on their phone at
  this time. That day's daily summary leaves this chore out." (DE "Klingelt um
  diese Zeit auf ihrem Handy. Die Tagesübersicht lässt diese Aufgabe an dem
  Tag aus."). Update `chore_reminder.yaml` E2E only if it asserts the text.

---

## W6 — Honesty, privacy, errors, server hygiene (B1, B2, B3, B7, H4, H5, H8; migration `20261006140000_privacy_and_grants.sql`)

**Model:** Sonnet. **Files:** `PRIVACY.md`, `lib/app/snackbars.dart`
(`showAppErrorSnackbar`), every error call site (grep `Error(` keys in
`app_en.arb`: `accountDeleteError`, `householdLeaveError`, `settingsResetError`,
`settingsExportError`, `syncRefreshError*`, `settingsAccountSendError`, join
errors, shopping/chores load errors), `lib/application/household_archive.dart`,
`household_join_service.dart`, `lib/features/settings/` (archives row, reset
flow), `lib/application/data_reset.dart`, `lib/application/notification_action_handler.dart`,
`lib/application/error_scrubber.dart`, `lib/application/sync_engine.dart`
(`_pushHouseholds` payload only), `lib/data/sync/row_mappers.dart`
(`householdRow`), `supabase/migrations/20261006140000_privacy_and_grants.sql`,
`supabase/tests/`, `lib/l10n/*.arb`, tests, `docs/specs/household-lifecycle.md`
§2.4, `docs/specs/client-error-reporting.md`.

- **B7:** `showAppErrorSnackbar(context, {required message, VoidCallback? onRetry})`:
  `Icons.error_outline` in `colorScheme.error`, duration 8 s, optional action
  `commonRetry` "Retry" (DE "Erneut versuchen"), `persist: false`. Replace
  `showAppSnackbar` at every error call site (list them in your report).
  Widget test for icon + duration.
- **B2:** migration: `purge_orphaned_households()` (security definer, pinned
  search_path, revoked from all roles) hard-deletes, for households with
  `deleted_at < now() - interval '30 days'`: `chore_occurrences`,
  `chore_assignees`, `chores`, `shopping_items`, `categories`,
  `household_invites`, `members`, then the household row (FK order);
  `cron.schedule('purge-orphaned-households', '41 3 * * *', …)`. pgTAP: a
  household stamped 31 days ago is purged with its children; one stamped 1 day
  ago is not. Copy: in `householdLeaveConfirmBodyLastMember` and
  `accountDeleteConfirmBodyLastMember` replace "the shared copy and its history
  are removed from the server" with "the shared copy is hidden from everyone
  right away and permanently deleted from the server after 30 days" (DE "die
  gemeinsame Kopie ist sofort für alle verborgen und wird nach 30 Tagen
  endgültig vom Server gelöscht"). Amend `household-lifecycle.md` §2.4.
- **H4:** same migration: `revoke update on public.households from authenticated; grant update (name) on public.households to authenticated;`
  and `revoke update on public.household_invites from authenticated; grant update (revoked_at) on public.household_invites to authenticated;`.
  `create_invite` generates the code from `encode(gen_random_bytes(8), 'hex')`
  mapped onto the existing 32-symbol alphabet (keep 8 chars). **Client side
  (load-bearing, see memory of the 42501 bug):** `_pushHouseholds` must send
  ONLY `{'name': …}` in `updateHousehold` — trim `householdRow` usage there (a
  SET list containing `created_at`/`updated_at` fails at plan time against a
  column-scoped grant). pgTAP: a member can update `households.name` but not
  `created_at`; can set `household_invites.revoked_at` but not `expires_at`.
- **B3:** archive filename gets a time component (`famdo-archive-<yyyy-MM-dd-HHmmss>.json`).
  After a join/reconnect that archived, the snackbar becomes
  `settingsAccountJoinSuccessSnackbar` "Your previous data was saved inside the
  app" with action `commonShare` "Share…" (DE "Deine bisherigen Daten wurden in
  der App gesichert" / "Teilen …") opening the OS share sheet for that file
  (reuse the `SharePlus` call from `export_row.dart`). Settings → Data gains
  `settingsArchivesRow` "Saved copies of earlier households ({count})" (DE
  "Gesicherte Kopien früherer Haushalte ({count})"), hidden when 0, opening a
  list with Share and Delete per file (confirm on delete). `resetAppData`
  deletes every archive file. Copy at `settingsAccountReconnectIntro` and
  `joinHouseholdImportBody`: "saved to a backup file on this device" → "kept as
  a saved copy inside the app (Settings → Data)" (DE "als gesicherte Kopie in
  der App behalten (Einstellungen → Daten)"). Tests for filename, reset
  deletion, archive listing.
- **B1:** rewrite PRIVACY.md to match the code: error reports (what, when —
  only signed in and linked, opt-out under About, pseudonymous ids, 90-day
  prune, deleted with the account); the server data list including categories
  and the ids; the local saved copies (archives) and that Reset removes them;
  deletion pointing at Settings → Household → Delete my account / Leave; the
  30-day purge; operator "the app's author (Igor Zamyslov, github.com/igorzamyslov)";
  hosting "a Supabase-hosted Postgres project (the region is shown in the
  project's dashboard; the author's project is intended to be EU-hosted —
  verify there)". Keep it plain-language engineering notes.
- **H5:** `handleNotificationAction`'s isolate entry attaches
  `DatabaseErrorLogSink(database)` before the try and detaches in `finally`.
  Test if the existing harness allows; otherwise document the manual check.
- **H8:** `ErrorScrubber` runs the message rules over every `context` value;
  `FormatException` is reduced to `error.message` only. Tests.

---

## W7 — Accessibility, hygiene, release prep (G1, G2, H1, H2, H3, H6-retention, H7, Priya Q1 shopping ring label)

**Model:** Sonnet. **Files:** `lib/features/chores/chore_occurrence_tile.dart`,
`lib/features/shopping/shopping_item_tile.dart`, `lib/features/settings/settings_group.dart`,
`lib/app/app_shell.dart`, `lib/data/repositories/chore_repository.dart`
(`watchActiveChores`), `lib/data/repositories/shopping_repository.dart`
(compaction), `lib/app/providers.dart` (bootstrap compaction call),
`.github/workflows/db.yml`, `.github/workflows/release.yml`,
`test/data/db/schema_migration_test.dart`, `pubspec.yaml`, `fastlane/metadata/android/*/changelogs/22.txt`,
`docs/backlog.md`, `docs/future-improvements.md`.

- **G1:** tile buttons get `Semantics(label: '${l10n.choresOccurrenceCompleteTooltip}: $title')`
  / more-actions likewise; shopping `_CheckRing` gets `label: item.name`;
  `SettingsGroup` headers `header: true`; shell tab semantics label
  `MaterialLocalizations.of(context).tabLabel(tabIndex: i + 1, tabCount: 3)`
  appended. Widget tests asserting the semantics labels.
- **G2:** the bottom bar wraps its children in
  `MediaQuery.withClampedTextScaling(maxScaleFactor: 2.0)`; chore note
  `maxLines: 2` when `MediaQuery.textScalerOf(context).scale(1) > 1.3`.
- **H1:** `db.yml` scope regex adds `lib/data/repositories/sync_repository\.dart$`
  and `lib/data/db/tables\.dart$`.
- **H2:** `release.yml` step before the build: read `version:` from
  `pubspec.yaml`, assert `v<name>` == `${{ github.ref_name }}`, fail with
  `::error::` otherwise.
- **H3:** parametrised migration test: for every fixture version N in the
  existing fixtures directory, open at N, migrate to current, assert the full
  current column set of every table (use `drift`'s schema verifier already in
  the test file if present).
- **H6 (retention):** `ShoppingRepository.compactHistory({required DateTime before})`
  hard-deletes soft-deleted, non-dirty shopping rows with `deletedAt < before`
  (1 year); called from bootstrap after catch-up. Test.
- **H7:** `watchActiveChores` becomes one joined query (chores ⋈ assignees)
  mapped in Dart, or a custom select with `readsFrom: {chores, choreAssignees}`.
  Existing tests must stay green; add one asserting a pulled assignee-only
  change re-emits.
- **Release prep:** `pubspec.yaml` → `0.15.0+22`; changelogs `22.txt` (EN +
  DE, ≤ 500 chars, user-facing summary of this release); `docs/backlog.md`
  gets a dated section "Closed 2026-10-06 (persona review PR)" listing the
  finding ids; `docs/future-improvements.md` closes F11 and F14 with a note.

---

## Execution order and merge protocol (orchestrator)

Wave 1: W1 (Fable) ∥ W5 (Opus). Wave 2: W2 (Sonnet) ∥ W3 (Opus). Wave 3: W4
(Sonnet) ∥ W6 (Sonnet). Wave 4: W7 (Sonnet). Each agent works in its own
worktree branched from the integration branch at dispatch time and commits
there; the orchestrator merges each branch into the integration branch,
resolves conflicts (expected: ARB files, `providers.dart`, `snackbars.dart`),
runs `flutter analyze` and the touched tests, pushes, and watches CI (`ci.yml`,
`e2e.yml` Android, `db.yml`). PR opened as draft after wave 1 so CI runs per
wave. After wave 4 and green CI: squash-merge, apply the three prod migrations
via MCP in timestamp order, tag `v0.15.0`, confirm the Release workflow is
green, update the feedback doc with an outcome column.
