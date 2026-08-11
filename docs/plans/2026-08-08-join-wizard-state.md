# Join-wizard resume state (B-3 / T2.4) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A process kill while a new member is away in Mail tapping the
magic link (Anna's "old tablet" scenario, `docs/research/persona-anna.md`
finding 3; `docs/research/triage.md` T2.4) no longer strands the user on the
welcome gate's two-card chooser with no sign anything was in progress. On
relaunch, a signed-in user with no household yet lands directly back on the
join subpage, at whichever step is actually true (reconnect offer, or code
entry with the last-submitted code prefilled) — never on a stale cached step.

**Architecture:** Two independent, additive mechanisms, both cheap and
narrowly scoped to `lib/features/onboarding/`:

1. **Navigation-level auto-resume (the actual safety net).**
   `WelcomeScreen` currently only reaches `WelcomeJoinPage` via an explicit
   tap on the "Join" card. It's extended to auto-push that page, once, the
   moment it observes a signed-in `currentAuthUserProvider` with no local
   household — which can only mean a join was interrupted (nothing else
   signs this device in while the welcome gate is showing). Once on the
   subpage, its EXISTING reactive design (`build()` re-derives the step
   from `currentAuthUserProvider`/`myMembershipProvider` on every build,
   already true today for in-session rebuilds) takes over unchanged. This
   needs no new persisted state at all: a kill after the claim/join RPC has
   already succeeded server-side self-heals through the P2d reconnect-offer
   path, because `myMembershipProvider`'s probe finds the now-claimed
   membership regardless of whether the local device finished applying it.
2. **One persisted breadcrumb: the invite code.** The one genuinely
   expensive-to-reproduce piece of state is the 8-character invite code —
   unlike an email address or a typed name, the user may not have it
   memorized or written down, and reproducing it means asking the inviting
   family member to redisplay it. `settings.pendingJoinCode` (new nullable
   column) is set once a code has been validated against the server
   (`listClaimableMembers` succeeded) and prefills the code field on the
   next mount of `WelcomeJoinPage`. It is purely advisory — never read by
   any routing decision, only used to pre-fill a `TextEditingController`
   the user is free to overwrite — so a stale value can never trap anyone
   (see "Why not persist more" in Analysis, and D-1 in this doc's
   Analysis section on the deliberate choice not to persist the
   claim/new-member choice or a typed name).

**Tech Stack:** Flutter, Riverpod (`ref.listenManual` for one-shot
imperative navigation from `initState`), drift (SQLite, schema v9 → v10),
the existing `testChoreApp`/`testFreshChoreApp` integration-test harness
(real in-memory `AppDatabase`, fixed `clockProvider`, `FakeAuthGateway`/
`FakeHouseholdGateway` for the two documented seams).

## Global Constraints

- Every user-visible string goes through gen_l10n (`app_en.arb` template +
  `app_de.arb`, German du-form). **This plan adds zero new user-visible
  strings** — every screen/copy involved already exists; only routing and
  one internal prefill are added.
- Every interactive widget gets a stable id via `semantic()`. **No
  `welcome.join.*` semantic id is added, renamed, or removed.**
  `welcome.join.email`, `welcome.join.send`, `welcome.join.reconnect`,
  `welcome.join.retry`, and the shared `settings.account.join.*` ids
  (`JoinCodeStep`/`JoinChooserStep`/`JoinNewMemberNameStep`/`JoinWorkingStep`
  in `lib/features/settings/join_flow_steps.dart`) keep their current
  behavior unchanged. The only observable UI changes are (a) `WelcomeScreen`
  may auto-push `WelcomeJoinPage` without a tap, and (b) the code field may
  arrive pre-filled.
- Widget tests are integration-style: real in-memory `AppDatabase` + fixed
  `clockProvider`, overriding only `appDatabaseProvider`/`clockProvider`
  plus the two documented fake seams (`authGatewayProvider` →
  `FakeAuthGateway`, `householdGatewayProvider` → `FakeHouseholdGateway`,
  both under `test/features/settings/`). Never mock repositories or
  services.
- Deadlock traps: never await a drift stream outside a widget pump; never
  bare-await `bootstrapProvider.future` in a `ProviderContainer` test
  (not applicable here — no container test is added); `tester.pump(small
  duration)` between `container.dispose()` and `database.close()` (not
  applicable here either — no container test is added, but every widget
  test still closes its own `database` at the end of its body per
  `testChoreApp`/`testFreshChoreApp`'s existing contract).
- Strict lints (very_good_analysis, `--fatal-infos`); public members need
  doc comments.
- TDD: write-failing-test → run → implement → run → commit. **Exception,
  flagged explicitly where it applies (Task 1):** a drift schema/migration
  change can't fail "cleanly" before the column exists in generated code —
  referencing `settings.pendingJoinCode` before Task 1's implementation
  step is a *compile* failure, not a runtime assertion failure. This
  mirrors the same accepted nuance in
  `docs/plans/2026-08-08-category-delete-impact.md` Task 3.
- Drift's generated file `lib/data/db/app_database.g.dart` is
  `// GENERATED CODE - DO NOT MODIFY BY HAND`; every schema change is
  followed by `dart run build_runner build --delete-conflicting-outputs`,
  never a hand edit.
- E2E is fully offline (empty `SUPABASE_*` defines force `NoopAuthGateway`,
  spec `docs/specs/sync-backend.md` §7.5) — `currentAuthUserProvider` always
  emits `null` there, so the new auto-navigation branch is structurally
  unreachable in E2E. No `e2e/` file needs to change.

## Analysis (for context — do not re-derive)

**What already works and must not regress** (per the ticket): `_buildBody`
in `WelcomeJoinPage` derives its step from `ref.watch(currentAuthUserProvider)`
and `ref.watch(myMembershipProvider)` on every build rather than caching a
decision in `initState` — this is what already makes "signed in but not
finished → resumes at the signed-in step" work whenever the page itself
survives (an in-session backgrounding, or the app never being killed at
all). Nothing in this plan touches that derivation; it only makes sure the
page is *mounted at all* after a process kill, and prefills one field.

**Why the "point of maximum anxiety" doesn't need full state persistence —
approaches considered**

1. **Persist the whole flow (step/substep, code, and the exact
   `JoinChoice` — kind, memberId, name, color) in `settings`, restore it
   verbatim on mount.** Rejected. This needs serializing a sealed class
   into columns, needs to treat the restored code/choice as *possibly
   stale* (the invite could have expired or been revoked while the device
   was away, or someone else could have claimed the same profile) rather
   than trusting it blindly, and reintroduces exactly the "cached decision"
   pattern the file's own doc comment calls out as the thing NOT to do.
   Every extra byte of restored state is also one more thing that must be
   cleared correctly or it becomes stale — more surface area for the "half
   join traps a user who moved on" failure mode the ticket explicitly
   warns about, for a payoff (skipping the "Are you Anna?" tap or a
   one-field name retype) that's marginal next to the code below.
2. **Navigation-level auto-resume only, zero schema changes (rejected as
   incomplete on its own).** `WelcomeScreen` auto-pushes `WelcomeJoinPage`
   whenever it observes a signed-in user with no household. This alone
   already fixes the actual "point of maximum anxiety" the ticket
   describes (the return-from-Mail moment, which by definition is
   *already signed in*) with no persistence at all — a self-contained,
   trap-free mechanism. Its one real gap: a kill between submitting the
   invite code and the claim/join RPC actually reaching the server forces
   retyping the code, which — unlike an email address or a name — the user
   may not have written down.
3. **Approach 2 + persist the code only (chosen).** Keeps approach 2's
   navigation fix as the actual safety net (it is what prevents the
   stranded-on-the-two-card-screen failure), and adds exactly one nullable
   `settings.pendingJoinCode` column as a **prefill, never a routing
   input**. It's written once a code has round-tripped successfully
   against the server (`listClaimableMembers` didn't throw), so it's never
   worse than "the user has to retype a code that turned out to be
   right"; it's read only to seed a `TextEditingController`'s initial
   text, which the user can freely edit or clear before tapping Continue
   again — so even a maximally stale value (invite meanwhile revoked, say)
   degrades to exactly today's behavior (retype), never a trap. This is
   the plan below.

**Why the claim/new-member *branch* and a typed new-member *name* are
deliberately NOT persisted:** if the claim/join-as-new RPC had already
succeeded before the kill (the only case where losing this choice would
otherwise mean redoing real, committed work), the account is now already a
claimed member of the joined household *server-side* — so on relaunch,
`myMembershipProvider`'s `findMyMembership()` probe finds it and
`_buildReconnectOffer` shows the reconnect card automatically (P2d, spec
`docs/specs/sync-backend.md` §7.6), which resolves via `ReconnectChoice`
and skips the RPC entirely (see `HouseholdJoinService._resolveChoice`,
`lib/application/household_join_service.dart:328-330`). This is exactly
the "resumes for free from live state" property the file already
advertises — no new state needed to get it. If the RPC had NOT yet
succeeded, nothing was committed anywhere, and redoing one tap ("Are you
Anna?"/"I'm new here") plus, for the new-member branch, retyping a name is
bounded, cheap, and — per persona-anna.md's own risk framing — nowhere near
the severity of the "stranded with no idea what happened" failure this
ticket exists to fix.

**Where `pendingJoinCode` lives and how it's cleared:** device-scoped
`settings` singleton table (`lib/data/db/tables.dart`), via
`SettingsRepository`, exactly like `syncHouseholdId`/`actingMemberId`/every
other per-device flag already there — never synced (spec
`docs/specs/sync-backend.md` §0: "settings is device-scoped and never
synced"). Set in `WelcomeJoinPage._submitCode()` right after a successful
`listClaimableMembers` call. Cleared in two places, both already-existing
transactions that touch `settings`:
- `HouseholdJoinService.joinFresh` (success path) — the join this code was
  for is done; nothing ever reads it again once a household exists (the
  welcome gate never reappears for an existing install, spec
  `docs/specs/onboarding-v2.md` §1).
- `HouseholdCreateService.create` (the user abandoned the join and started
  a new household instead) — pure hygiene, since the code becomes
  unreachable either way once a household exists, but there's no reason to
  leave a stale value sitting in the row.

Neither clearing step is required for *safety* (the value is never
authoritative), only for cleanliness — worth stating plainly since the
ticket asks specifically "when is it cleared so a stale half-join never
traps a user."

## Open product decisions

None. Every choice above is derived from this codebase's existing patterns
(reactive-derivation-over-cached-state, the P2d reconnect self-heal
already implemented for the Settings-side join sheet) or from the spec
text itself. The Settings-side join sheet
(`lib/features/settings/join_household_sheet.dart`) is deliberately left
untouched: it only ever runs once a local household already exists, so a
kill there returns the user straight to a working, populated app (household
intact, since `HouseholdJoinService.join`'s delete-old-household step is
inside one atomic `database.transaction()` that a kill can only roll back,
never leave half-applied) — not to the disorienting "no household, not
sure what's going on" state this ticket is about. Extending the same
prefill convenience there would be a reasonable follow-up, but it is a
materially lower-severity gap (the ticket names
`lib/features/onboarding/welcome_join_page.dart` specifically) and is out
of scope here.

## File map

- Modify `lib/data/db/tables.dart` — add `Settings.pendingJoinCode`
  (nullable `TextColumn`).
- Modify `lib/data/db/app_database.dart` — bump `schemaVersion` 9 → 10, add
  the migration branch, fix a now-stale doc-comment version reference.
- Regenerate `lib/data/db/app_database.g.dart` (`build_runner`) — do not
  hand-edit.
- Modify `test/data/db/schema_migration_test.dart` — one new drop-column
  helper, six existing tests updated to drop the new column when seeding a
  pre-v10 install, one new v9→v10 migration test.
- Modify `lib/data/repositories/settings_repository.dart` — add
  `setPendingJoinCode(String? code)`.
- Modify `test/data/repositories/settings_repository_test.dart` — unit
  tests for the new method.
- Modify `lib/application/household_join_service.dart` — `joinFresh` clears
  `pendingJoinCode` on success.
- Modify `test/application/household_join_service_test.dart` — new
  `joinFresh`-specific unit test (this method currently has no direct unit
  test — only widget-level coverage via `welcome_join_test.dart`).
- Modify `lib/application/household_create_service.dart` — `create` clears
  `pendingJoinCode`.
- Modify `test/features/onboarding/welcome_screen_test.dart` — new test:
  creating a household clears a leftover `pendingJoinCode`.
- Modify `lib/features/onboarding/welcome_join_page.dart` — persist the
  code on a successful submit; prefill it on mount.
- Modify `lib/features/onboarding/welcome_screen.dart` — one-shot
  auto-navigation to `WelcomeJoinPage` when signed in with no household.
- Modify `test/features/onboarding/welcome_screen_test.dart` — new test:
  cold start already signed in lands on the join subpage, with an escape
  hatch back to the two-card chooser.
- Modify `test/features/onboarding/welcome_join_test.dart` — new capstone
  test: kill after code submission, before the claim RPC, resumes with the
  code prefilled and completes normally.
- Modify `docs/specs/onboarding-v2.md` — update §1's kill-mid-welcome
  paragraph to state the new guarantee precisely.
- Modify `docs/backlog.md` — close out **B-3** once the above lands and
  tests pass.

---

## Task 1: Schema — `settings.pendingJoinCode` (v9 → v10)

**Files:**
- Modify: `lib/data/db/tables.dart`
- Modify: `lib/data/db/app_database.dart`
- Modify: `test/data/db/schema_migration_test.dart`

**Interfaces:**
- Produces: `Settings.pendingJoinCode` (nullable `TextColumn`), and its
  generated `DeviceSettings.pendingJoinCode` (`String?`) /
  `SettingsCompanion.pendingJoinCode` fields. Consumed by Task 2.

- [ ] **Step 1: Write the failing migration test**

In `test/data/db/schema_migration_test.dart`, add this helper right after
`_dropMemberDeletedAtColumn`'s definition (before `void main()`):

```dart
/// Drops `pending_join_code` (schema v10, spec
/// `docs/specs/onboarding-v2.md` §1) from `settings` on [seed] -- mirrors
/// `_dropMemberDeletedAtColumn`'s reasoning: [seed] always opens at the
/// *current* (now v10) schema first, so every test below that simulates a
/// pre-v10 install needs this too, or the later `onUpgrade` would try to
/// `ADD COLUMN pending_join_code` on a column that's already there.
Future<void> _dropPendingJoinCodeColumn(AppDatabase seed) async {
  await seed.customStatement(
    'ALTER TABLE settings DROP COLUMN pending_join_code',
  );
}
```

Then add this test at the end of `main()`, right after the "schemaVersion 8
-> 9" test's closing `);`:

```dart
  test(
    'schemaVersion 9 -> 10 upgrade adds pendingJoinCode (NULL by default, '
    'no data rewrite), keeping the existing settings row',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'chore_app_migration_v10_test',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });
      final file = File('${dir.path}/test.sqlite');

      // Simulate a pre-existing v9 install: open the *current* (v10)
      // schema once so `onCreate` materializes every table with its full
      // v10 column set, insert a settings row with a non-NULL
      // actingMemberId (so the upgrade's "existing row survives"
      // guarantee is actually exercised), then drop only
      // `pending_join_code` (every other v10-affected column already
      // exists at v9) and roll `user_version` back to 9 -- reproducing
      // exactly what a real v9 database on a user's device looks like.
      final seed = AppDatabase(NativeDatabase(file));
      await seed
          .into(seed.settings)
          .insert(
            SettingsCompanion.insert(
              id: 'device',
              createdAt: 't0',
              updatedAt: 't0',
              actingMemberId: const Value('member-1'),
            ),
          );
      await _dropPendingJoinCodeColumn(seed);
      await seed.customStatement('PRAGMA user_version = 9');
      await seed.close();

      // Re-opening the same file with the real (schemaVersion: 10)
      // `AppDatabase` now sees `user_version == 9` on disk vs. a declared
      // `schemaVersion` of 10, so drift runs `onUpgrade(migrator, 9, 10)`
      // -- exactly the real upgrade path a v9 user's device would go
      // through.
      final upgraded = AppDatabase(NativeDatabase(file));
      addTearDown(upgraded.close);

      final row = await upgraded.select(upgraded.settings).getSingle();
      expect(row.id, 'device');
      expect(row.pendingJoinCode, isNull);
      // Pre-existing settings data survived the upgrade untouched.
      expect(row.createdAt, 't0');
      expect(row.actingMemberId, 'member-1');
      expect(row.digestEnabled, isTrue);
      expect(row.digestMinutes, 480);
    },
  );
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/data/db/schema_migration_test.dart`
Expected: FAIL — `pendingJoinCode`/`pending_join_code` don't exist yet, so
this fails to compile/analyze (`Settings`/`DeviceSettings` have no such
member). A compile failure here is the expected "red" for a schema change,
mirroring the same nuance in
`docs/plans/2026-08-08-category-delete-impact.md` Task 3.

- [ ] **Step 3: Add the column to `tables.dart`**

In `lib/data/db/tables.dart`, insert this new column right after
`syncLastPulledAt`'s declaration (before the `createdAt`/`updatedAt`
columns that close the `Settings` class):

```dart
  /// The pull cursor (spec `docs/specs/sync-backend.md` §8.1/8.3): the
  /// server-clock ISO timestamp fetched via the `server_now()` RPC in the
  /// same round trip as the last successful pull, or `NULL` before this
  /// device's first pull. NEVER the device clock -- see
  /// `SupabaseSyncEngine.pullSince`. Added in schemaVersion 8; see
  /// `AppDatabase.migration`.
  TextColumn get syncLastPulledAt => text().nullable()();

  /// The invite code most recently and successfully submitted on the
  /// welcome-join subpage's code-entry step (spec
  /// `docs/specs/onboarding-v2.md` §1, `docs/research/triage.md` T2.4), or
  /// `NULL`. Prefills the code field again after a process kill mid-join
  /// (see `WelcomeJoinPage._prefillPendingCode`) so the user isn't forced
  /// to retype an 8-character code they may not have written down.
  /// Deliberately advisory, never authoritative: it never drives routing
  /// by itself -- only `currentAuthUserProvider`/`myMembershipProvider` do
  /// that (see `WelcomeScreen`/`WelcomeJoinPage`'s own doc comments) -- so
  /// a stale value can only ever sit in a text field the user is free to
  /// overwrite, never trap anyone. Cleared by
  /// `HouseholdJoinService.joinFresh` on a successful join and by
  /// `HouseholdCreateService.create` (an abandoned join). Added in
  /// schemaVersion 10; see `AppDatabase.migration`.
  TextColumn get pendingJoinCode => text().nullable()();
```

- [ ] **Step 4: Bump the schema version and add the migration branch**

In `lib/data/db/app_database.dart`:

Replace:
```dart
  @override
  int get schemaVersion => 9;
```
with:
```dart
  @override
  int get schemaVersion => 10;
```

Replace the comment fragment `*current* (here, v8) column set` (in the
`onUpgrade` doc comment, just above `if (from < 2) {`) with
`*current* (here, v10) column set` — it's already stale for v9 and would
otherwise become more so.

Replace:
```dart
        if (from < 8) {
          // v7 -> v8 (spec `docs/specs/sync-backend.md` §8.1): the
          // nullable `settings.syncLastPulledAt` pull-cursor column,
          // defaulting to `NULL` (no pull yet) -- no data rewrite.
          await migrator.addColumn(settings, settings.syncLastPulledAt);
        }
      }
```
with:
```dart
        if (from < 8) {
          // v7 -> v8 (spec `docs/specs/sync-backend.md` §8.1): the
          // nullable `settings.syncLastPulledAt` pull-cursor column,
          // defaulting to `NULL` (no pull yet) -- no data rewrite.
          await migrator.addColumn(settings, settings.syncLastPulledAt);
        }
        if (from < 10) {
          // v9 -> v10 (spec `docs/specs/onboarding-v2.md` §1): the
          // nullable `settings.pendingJoinCode` column, defaulting to
          // `NULL` -- no data rewrite.
          await migrator.addColumn(settings, settings.pendingJoinCode);
        }
      }
```

(This nests inside the `else` of `if (from < 2)`, exactly like every other
`settings`-only column before it — `migrator.createTable` on a fresh
install already builds the v10 shape directly, so this backfill only runs
for installs that already had an older `settings` table.)

- [ ] **Step 5: Regenerate drift's generated code**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: `lib/data/db/app_database.g.dart` is rewritten; no errors.

- [ ] **Step 6: Update the six pre-existing migration tests to drop the new column**

Every test in `test/data/db/schema_migration_test.dart` that seeds a
pre-existing install by opening the *current* schema and rolling
`user_version` back below 10 must also drop `pending_join_code` from that
seed, or `onUpgrade`'s new `if (from < 10)` branch throws a duplicate-column
error. The two tests that don't need this are "schemaVersion 1 -> 2..."
(drops the whole `settings` table first, so there's nothing to drop a
column from) and "a fresh (never-opened) database..." (exercises no
upgrade path at all). Make these six edits (each anchor below is unique in
the file because of its distinct `PRAGMA user_version = N` line):

In the "schemaVersion 3 -> 9" test, replace:
```dart
      await _dropSyncDirtyColumns(seed);
      await _dropMemberDeletedAtColumn(seed);
      await seed.customStatement('PRAGMA user_version = 3');
```
with:
```dart
      await _dropSyncDirtyColumns(seed);
      await _dropMemberDeletedAtColumn(seed);
      await _dropPendingJoinCodeColumn(seed);
      await seed.customStatement('PRAGMA user_version = 3');
```

In the "schemaVersion 2 -> 9" test, replace:
```dart
      await _dropSyncDirtyColumns(seed);
      await _dropMemberDeletedAtColumn(seed);
      await seed.customStatement('PRAGMA user_version = 2');
```
with:
```dart
      await _dropSyncDirtyColumns(seed);
      await _dropMemberDeletedAtColumn(seed);
      await _dropPendingJoinCodeColumn(seed);
      await seed.customStatement('PRAGMA user_version = 2');
```

In the "schemaVersion 5 -> 9" test, replace:
```dart
      await _dropSyncDirtyColumns(seed);
      await _dropMemberDeletedAtColumn(seed);
      await seed.customStatement('PRAGMA user_version = 5');
```
with:
```dart
      await _dropSyncDirtyColumns(seed);
      await _dropMemberDeletedAtColumn(seed);
      await _dropPendingJoinCodeColumn(seed);
      await seed.customStatement('PRAGMA user_version = 5');
```

In the "schemaVersion 6 -> 9" test, replace:
```dart
      await _dropSyncDirtyColumns(seed);
      await _dropMemberDeletedAtColumn(seed);
      await seed.customStatement('PRAGMA user_version = 6');
```
with:
```dart
      await _dropSyncDirtyColumns(seed);
      await _dropMemberDeletedAtColumn(seed);
      await _dropPendingJoinCodeColumn(seed);
      await seed.customStatement('PRAGMA user_version = 6');
```

In the "schemaVersion 7 -> 9" test, replace:
```dart
      await _dropSyncDirtyColumns(seed);
      await _dropMemberDeletedAtColumn(seed);
      await seed.customStatement(
        'ALTER TABLE settings DROP COLUMN sync_last_pulled_at',
      );
      await seed.customStatement('PRAGMA user_version = 7');
```
with:
```dart
      await _dropSyncDirtyColumns(seed);
      await _dropMemberDeletedAtColumn(seed);
      await seed.customStatement(
        'ALTER TABLE settings DROP COLUMN sync_last_pulled_at',
      );
      await _dropPendingJoinCodeColumn(seed);
      await seed.customStatement('PRAGMA user_version = 7');
```

In the "schemaVersion 8 -> 9" test, replace:
```dart
      await _dropMemberDeletedAtColumn(seed);
      await seed.customStatement('PRAGMA user_version = 8');
```
with:
```dart
      await _dropMemberDeletedAtColumn(seed);
      await _dropPendingJoinCodeColumn(seed);
      await seed.customStatement('PRAGMA user_version = 8');
```

Note: these six tests' titles and internal "onUpgrade(migrator, N, 9)"
comments still say "9" — left as-is deliberately (they were already
accurate descriptions of the specific column set each is about; renaming
every occurrence to "10" is pure churn with no coverage benefit, since the
new column's own behavior is fully covered by Step 1's dedicated test).

- [ ] **Step 7: Run the full migration suite**

Run: `flutter test test/data/db/schema_migration_test.dart`
Expected: PASS — 9 tests (8 existing + the new v9→v10 one).

- [ ] **Step 8: Commit**

```bash
git add lib/data/db/tables.dart lib/data/db/app_database.dart \
  lib/data/db/app_database.g.dart test/data/db/schema_migration_test.dart
git commit -m "Add settings.pendingJoinCode (schema v10)"
```

---

## Task 2: `SettingsRepository.setPendingJoinCode`

**Files:**
- Modify: `lib/data/repositories/settings_repository.dart`
- Modify: `test/data/repositories/settings_repository_test.dart`

**Interfaces:**
- Consumes: `Settings.pendingJoinCode` (Task 1).
- Produces: `Future<void> SettingsRepository.setPendingJoinCode(String? code)`.
  Consumed by Tasks 3, 4, 5.

- [ ] **Step 1: Write the failing tests**

Add these tests to `test/data/repositories/settings_repository_test.dart`,
right after the existing `clearSyncLink` tests (at the end of `main()`,
before the closing `}`):

```dart
  test('setPendingJoinCode sets the value and bumps updated_at', () async {
    final created = await repo.ensureSettings();
    expect(created.pendingJoinCode, isNull);
    clock.advance(const Duration(minutes: 5));

    await repo.setPendingJoinCode('ABC12345');

    final updated = await (db.select(
      db.settings,
    )..where((tbl) => tbl.id.equals(SettingsRepository.deviceId))).getSingle();
    expect(updated.pendingJoinCode, 'ABC12345');
    expect(updated.updatedAt, isNot(created.updatedAt));
  });

  test('setPendingJoinCode(null) clears a previously-set value', () async {
    await repo.setPendingJoinCode('ABC12345');
    var row = await (db.select(
      db.settings,
    )..where((tbl) => tbl.id.equals(SettingsRepository.deviceId))).getSingle();
    expect(row.pendingJoinCode, 'ABC12345');

    await repo.setPendingJoinCode(null);
    row = await (db.select(
      db.settings,
    )..where((tbl) => tbl.id.equals(SettingsRepository.deviceId))).getSingle();
    expect(row.pendingJoinCode, isNull);
  });

  test('setPendingJoinCode implicitly creates the row if missing', () async {
    await repo.setPendingJoinCode('ABC12345');
    final rows = await db.select(db.settings).get();
    expect(rows, hasLength(1));
    expect(rows.single.pendingJoinCode, 'ABC12345');
  });

  test(
    'watchSettings emits an updated value after setPendingJoinCode',
    () async {
      final emissions = <String?>[];
      final sub = repo.watchSettings().listen(
        (settings) => emissions.add(settings.pendingJoinCode),
      );
      addTearDown(sub.cancel);

      await pumpEventQueue();
      await repo.setPendingJoinCode('ABC12345');
      await pumpEventQueue();

      expect(emissions.last, 'ABC12345');
    },
  );
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/data/repositories/settings_repository_test.dart`
Expected: FAIL — `setPendingJoinCode` is not defined on
`SettingsRepository`.

- [ ] **Step 3: Implement `setPendingJoinCode`**

In `lib/data/repositories/settings_repository.dart`, add this method right
after `setSyncLastPulledAt` (before `clearSyncLink`):

```dart
  /// Records [code] as the invite code most recently and successfully
  /// submitted on the welcome-join subpage's code-entry step (spec
  /// `docs/specs/onboarding-v2.md` §1) -- or clears it when `null`, this is
  /// an explicit write, not "leave unchanged", so [Value] wraps it
  /// unconditionally. Read only as a prefill for the code field
  /// (`WelcomeJoinPage._prefillPendingCode`); never drives routing on its
  /// own. Cleared by `HouseholdJoinService.joinFresh` on success and by
  /// `HouseholdCreateService.create` when the user starts a new household
  /// instead of finishing a join.
  Future<void> setPendingJoinCode(String? code) async {
    await ensureSettings();
    await (db.update(
      db.settings,
    )..where((tbl) => tbl.id.equals(deviceId))).write(
      SettingsCompanion(
        pendingJoinCode: Value(code),
        updatedAt: Value(_isoNow()),
      ),
    );
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/data/repositories/settings_repository_test.dart`
Expected: PASS (all tests, including the four new ones).

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/settings_repository.dart \
  test/data/repositories/settings_repository_test.dart
git commit -m "Add SettingsRepository.setPendingJoinCode"
```

---

## Task 3: `HouseholdJoinService.joinFresh` clears the code on success

**Files:**
- Modify: `lib/application/household_join_service.dart`
- Modify: `test/application/household_join_service_test.dart`

**Interfaces:**
- Consumes: `SettingsRepository.setPendingJoinCode` (Task 2).

- [ ] **Step 1: Write the failing test**

`joinFresh` currently has no dedicated unit test in this file (only
widget-level coverage via `welcome_join_test.dart`). Add this test at the
end of `test/application/household_join_service_test.dart`'s `main()`,
after the existing "reconnect (spec §7.6)..." test:

```dart
  test(
    'joinFresh (welcome path, spec docs/specs/onboarding-v2.md §1): no '
    'archive, no old household to delete, and clears any pendingJoinCode '
    'left over from the code-entry step',
    () async {
      final settings = SettingsRepository(db);
      await settings.setPendingJoinCode('ABC12345');

      final gateway = FakeHouseholdGateway()
        ..claimResultHouseholdId = 'joined-hh'
        ..downloadSnapshotOverride = const HouseholdSnapshot(
          household: Household(
            id: 'joined-hh',
            name: 'Joined household',
            createdAt: 't0',
            updatedAt: 't0',
            syncDirty: false,
          ),
        );
      final service = HouseholdJoinService(
        gateway: gateway,
        database: db,
        settings: settings,
        clock: Clock.fixed(DateTime.utc(2026, 7, 24)),
      );

      final joinedHouseholdId = await service.joinFresh(
        choice: const ClaimMemberChoice('m-anna'),
        code: 'ABC12345',
      );

      expect(joinedHouseholdId, 'joined-hh');
      // No archive/old-household bookkeeping -- the welcome path has
      // nothing local to preserve. The pre-existing 'old-hh' seeded in
      // `setUp` (this file's shared fixture) is untouched by `joinFresh`
      // (unlike `join`, which deletes it); assert only on what
      // `joinFresh` itself is responsible for.
      final households = await db.select(db.households).get();
      expect(households.map((h) => h.id), containsAll(['joined-hh']));

      final row = await db.select(db.settings).getSingle();
      expect(row.syncHouseholdId, 'joined-hh');
      expect(row.actingMemberId, 'm-anna');
      expect(
        row.pendingJoinCode,
        isNull,
        reason: 'the code this join was for has done its job',
      );
    },
  );
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/application/household_join_service_test.dart`
Expected: FAIL — `row.pendingJoinCode` is `'ABC12345'`, not `null`
(`joinFresh` doesn't clear it yet).

- [ ] **Step 3: Clear `pendingJoinCode` in `joinFresh`**

In `lib/application/household_join_service.dart`, replace `joinFresh`'s
transaction body:

```dart
    await database.transaction(() async {
      await _insertSnapshot(downloaded);
      await settings.setActingMember(actingMemberId);
      await settings.setSyncLinked(
        householdId: joinedHouseholdId,
        linkedAt: clock.now(),
      );
    });
```
with:
```dart
    await database.transaction(() async {
      await _insertSnapshot(downloaded);
      await settings.setActingMember(actingMemberId);
      await settings.setSyncLinked(
        householdId: joinedHouseholdId,
        linkedAt: clock.now(),
      );
      // The code (if any) that got the caller here has done its job --
      // clear it so it never resurfaces as a stale prefill. Harmless
      // either way (the welcome gate never reappears once a household
      // exists, spec `docs/specs/onboarding-v2.md` §1), but nothing reads
      // it again after this.
      await settings.setPendingJoinCode(null);
    });
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/application/household_join_service_test.dart`
Expected: PASS (all tests, including the new one).

- [ ] **Step 5: Commit**

```bash
git add lib/application/household_join_service.dart \
  test/application/household_join_service_test.dart
git commit -m "joinFresh clears pendingJoinCode on success"
```

---

## Task 4: `HouseholdCreateService.create` clears an abandoned code

**Files:**
- Modify: `lib/application/household_create_service.dart`
- Modify: `test/features/onboarding/welcome_screen_test.dart`

**Interfaces:**
- Consumes: `SettingsRepository.setPendingJoinCode` (Task 2).

- [ ] **Step 1: Write the failing test**

Add this test to `test/features/onboarding/welcome_screen_test.dart`, after
the existing "mid-flow kill (partway through the create form)..." test (at
the end of `main()`, before the closing `}`). This needs one new import:
add `import 'package:chore_app/data/repositories/settings_repository.dart';`
alongside the existing imports at the top of the file.

```dart
  testFreshChoreApp(
    'creating a new household clears any pendingJoinCode left over from '
    'an abandoned join attempt -- spec docs/specs/onboarding-v2.md §1',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await SettingsRepository(database).setPendingJoinCode('OLDCODE1');

      await tester.tap(find.bySemanticsIdentifier('welcome.create'));
      await tester.pumpAndSettle();
      await tester.enterText(_fieldFor('welcome.create.name'), 'Sam');
      await tester.pump();
      await tester.tap(find.bySemanticsIdentifier('welcome.create.confirm'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('shell.tab.chores'), findsOneWidget);
      final row = await database.select(database.settings).getSingle();
      expect(row.pendingJoinCode, isNull);

      handle.dispose();
    },
  );
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/onboarding/welcome_screen_test.dart`
Expected: FAIL — `row.pendingJoinCode` is `'OLDCODE1'`, not `null`.

- [ ] **Step 3: Clear `pendingJoinCode` in `create`**

In `lib/application/household_create_service.dart`, replace:
```dart
  Future<String> create(String name) {
    return database.transaction(() async {
      final household = await households.createLocalHousehold(name);
      await categories.seedDefaults(household.id);
      await settings.markOnboardingNamePromptShown();
      return household.id;
    });
  }
```
with:
```dart
  Future<String> create(String name) {
    return database.transaction(() async {
      final household = await households.createLocalHousehold(name);
      await categories.seedDefaults(household.id);
      await settings.markOnboardingNamePromptShown();
      // Belt-and-suspenders: a user who abandoned an in-progress join to
      // start fresh instead shouldn't have that code linger forever (spec
      // `docs/specs/onboarding-v2.md` §1) -- harmless either way (the
      // welcome gate never reappears once a household exists), but
      // nothing reads it again after this.
      await settings.setPendingJoinCode(null);
      return household.id;
    });
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/onboarding/welcome_screen_test.dart`
Expected: PASS (all tests, including the new one).

- [ ] **Step 5: Commit**

```bash
git add lib/application/household_create_service.dart \
  test/features/onboarding/welcome_screen_test.dart
git commit -m "HouseholdCreateService.create clears a leftover pendingJoinCode"
```

---

## Task 5: `WelcomeJoinPage` — persist and prefill the code

**Files:**
- Modify: `lib/features/onboarding/welcome_join_page.dart`
- Modify: `test/features/onboarding/welcome_join_test.dart`

**Interfaces:**
- Consumes: `SettingsRepository.setPendingJoinCode` (Task 2),
  `settingsProvider`/`settingsRepositoryProvider` (already exist in
  `lib/app/providers.dart`).
- Produces: `WelcomeJoinPage`'s code field is prefilled from
  `settings.pendingJoinCode` on mount; a successful code submission
  persists it. Consumed by Task 6's capstone test.

- [ ] **Step 1: Write the failing test**

Add this test to `test/features/onboarding/welcome_join_test.dart`, at the
end of `main()` (after the existing "reconnect offer..." test, before the
closing `}`):

Deliberately NOT tested here via a kill+relaunch (that full end-to-end
path, including the interaction with Task 6's auto-navigation, is Task 6's
own capstone test) — this test instead seeds `pendingJoinCode` directly and
checks the prefill in isolation, with a single manual tap on the
already-visible `welcome.join` card (which stays valid regardless of
whether `WelcomeScreen` also auto-navigates there, since tapping a visible
button that leads to the same page either way never breaks). This needs one
new import at the top of the file:
`import 'package:chore_app/data/repositories/settings_repository.dart';`.

```dart
  final prefillFakeAuth = FakeAuthGateway();
  final prefillGateway = FakeHouseholdGateway()
    ..claimableMembers = const [
      ClaimableMember(memberId: 'm-anna', name: 'Anna', color: 0xFF6D9F71),
    ]
    ..claimResultHouseholdId = 'joined-hh'
    ..downloadSnapshotOverride = const HouseholdSnapshot(
      household: Household(
        id: 'joined-hh',
        name: 'Joined household',
        createdAt: 't0',
        updatedAt: 't0',
        syncDirty: false,
      ),
      members: [
        Member(
          id: 'm-anna',
          householdId: 'joined-hh',
          name: 'Anna',
          color: 0xFF6D9F71,
          role: MemberRole.member,
          createdAt: 't0',
          updatedAt: 't0',
          syncDirty: false,
        ),
      ],
    );

  testFreshChoreApp(
    'a pre-existing pendingJoinCode prefills the code field as soon as '
    'the join subpage reaches code entry, and a successful submit '
    'persists a fresh one in its place',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(prefillFakeAuth),
      householdGatewayProvider.overrideWithValue(prefillGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await SettingsRepository(database).setPendingJoinCode('OLD12345');

      await tester.tap(find.bySemanticsIdentifier('welcome.join'));
      await tester.pumpAndSettle();
      prefillFakeAuth.signIn(const AuthUser(id: 'u1', email: 'me@example.com'));
      await tester.pumpAndSettle();

      // Reached code entry (no membership -> no reconnect offer), and the
      // pre-existing code is already sitting in the field.
      final codeField = tester.widget<TextField>(
        _fieldFor('settings.account.join.code'),
      );
      expect(codeField.controller!.text, 'OLD12345');

      // Submitting a DIFFERENT code overwrites the persisted value.
      await tester.enterText(
        _fieldFor('settings.account.join.code'),
        'new67890',
      );
      await tester.pump();
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.join.continue'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Are you Anna?'), findsOneWidget);

      final row = await database.select(database.settings).getSingle();
      expect(row.pendingJoinCode, 'NEW67890');

      handle.dispose();
    },
  );
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/onboarding/welcome_join_test.dart`
Expected: FAIL — the code field is empty (nothing prefills it yet), and
`row.pendingJoinCode` is `'OLD12345'`, not `'NEW67890'` (nothing persists a
fresh submit yet).

- [ ] **Step 3: Persist the code on a successful submit**

In `lib/features/onboarding/welcome_join_page.dart`, replace `_submitCode`:

```dart
  Future<void> _submitCode() async {
    final code = _codeController.text.trim().toUpperCase();
    setState(() {
      _busy = true;
      _inlineError = null;
    });
    try {
      final members = await ref
          .read(householdGatewayProvider)
          .listClaimableMembers(code);
      if (!mounted) {
        return;
      }
      setState(() {
        _code = code;
        _claimableMembers = members;
        _subStep = _SubStep.chooser;
        _busy = false;
      });
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _inlineError = joinCodeErrorMessage(
          AppLocalizations.of(context),
          error,
        );
      });
    }
  }
```
with:
```dart
  Future<void> _submitCode() async {
    final code = _codeController.text.trim().toUpperCase();
    setState(() {
      _busy = true;
      _inlineError = null;
    });
    try {
      final members = await ref
          .read(householdGatewayProvider)
          .listClaimableMembers(code);
      if (!mounted) {
        return;
      }
      // Persisted BEFORE the chooser renders, right after the server has
      // validated it -- so it's never worse than "retype a code that
      // turned out to be right" (spec `docs/specs/onboarding-v2.md` §1).
      // A kill anywhere past this point can still self-heal via the P2d
      // reconnect offer once the claim/join RPC has actually succeeded
      // (`myMembershipProvider`'s probe finds it); this specifically saves
      // retyping the code itself if the kill happens before that.
      await ref.read(settingsRepositoryProvider).setPendingJoinCode(code);
      if (!mounted) {
        return;
      }
      setState(() {
        _code = code;
        _claimableMembers = members;
        _subStep = _SubStep.chooser;
        _busy = false;
      });
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _inlineError = joinCodeErrorMessage(
          AppLocalizations.of(context),
          error,
        );
      });
    }
  }
```

- [ ] **Step 4: Prefill the code field on mount**

In the same file, replace `initState`:

```dart
  @override
  void initState() {
    super.initState();
    _emailController.addListener(_onFieldChanged);
    _codeController.addListener(_onFieldChanged);
    _nameController.addListener(_onFieldChanged);
  }
```
with:
```dart
  @override
  void initState() {
    super.initState();
    _emailController.addListener(_onFieldChanged);
    _codeController.addListener(_onFieldChanged);
    _nameController.addListener(_onFieldChanged);
    // Spec `docs/specs/onboarding-v2.md` §1: prefill a code that survived a
    // process kill (`settings.pendingJoinCode`). Deferred to a post-frame
    // callback: reading a provider synchronously from `initState` is fine,
    // but writing to the controller here would fire `_onFieldChanged`'s
    // `setState` synchronously during this widget's own first build, which
    // throws.
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefillPendingCode());
  }

  /// Prefills [_codeController] from a previously-submitted, still-pending
  /// invite code -- see [initState]'s doc comment. A no-op if the field
  /// already has text (nothing raced ahead of this post-frame callback in
  /// practice, but this keeps it from ever clobbering something the user
  /// already typed) or if no code was persisted.
  void _prefillPendingCode() {
    if (!mounted || _codeController.text.isNotEmpty) {
      return;
    }
    final pendingCode = ref.read(settingsProvider).valueOrNull?.pendingJoinCode;
    if (pendingCode != null) {
      setState(() => _codeController.text = pendingCode);
    }
  }
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/features/onboarding/welcome_join_test.dart`
Expected: PASS (all tests, including the new one).

- [ ] **Step 6: Commit**

```bash
git add lib/features/onboarding/welcome_join_page.dart \
  test/features/onboarding/welcome_join_test.dart
git commit -m "WelcomeJoinPage persists and prefills the submitted invite code"
```

---

## Task 6: `WelcomeScreen` auto-resumes the join subpage

**Files:**
- Modify: `lib/features/onboarding/welcome_screen.dart`
- Modify: `test/features/onboarding/welcome_screen_test.dart`
- Modify: `test/features/onboarding/welcome_join_test.dart`

**Interfaces:**
- Consumes: `currentAuthUserProvider` (existing, `lib/app/providers.dart`),
  `WelcomeJoinPage` (existing).
- Produces: `WelcomeScreen` auto-pushes `WelcomeJoinPage` once per instance
  when a signed-in user with no household is observed.

- [ ] **Step 1: Write the failing test — cold start already signed in**

Add this test to `test/features/onboarding/welcome_screen_test.dart`, at
the end of `main()`. This needs one new import at the top of the file:
`import 'package:chore_app/application/auth_gateway.dart';`.

```dart
  testFreshChoreApp(
    'a signed-in user with no household yet lands directly on the join '
    'subpage on cold start, not the two-card chooser -- only the join '
    'flow could have signed this device in with no local household to '
    'show for it (spec docs/specs/onboarding-v2.md §1, '
    'docs/research/triage.md T2.4)',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(
          currentUser: const AuthUser(id: 'u1', email: 'me@example.com'),
        ),
      ),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();

      expect(find.bySemanticsIdentifier('welcome.create'), findsNothing);
      expect(find.bySemanticsIdentifier('welcome.join'), findsNothing);
      expect(
        find.bySemanticsIdentifier('settings.account.join.code'),
        findsOneWidget,
      );

      // The escape hatch: backing out returns to the two-card chooser,
      // and staying signed in does NOT immediately re-push it -- the
      // auto-push fires at most once per `WelcomeScreen` instance, so the
      // back button stays meaningful rather than looping.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.bySemanticsIdentifier('welcome.create'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('settings.account.join.code'),
        findsNothing,
      );

      handle.dispose();
    },
  );
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/onboarding/welcome_screen_test.dart`
Expected: FAIL — `welcome.create`/`welcome.join` are found (the two-card
chooser is still showing; nothing auto-navigates yet).

- [ ] **Step 3: Implement the one-shot auto-navigation**

In `lib/features/onboarding/welcome_screen.dart`, add the
`ProviderSubscription` field and update `initState`/`dispose`. Replace:

```dart
class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  /// Whether the primary card's inline name form is showing (spec §1:
  /// "Tapping asks for the user's name inline") instead of the two-card
  /// chooser.
  bool _creatingHousehold = false;

  final _nameController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _nameController
      ..removeListener(_onNameChanged)
      ..dispose();
    super.dispose();
  }
```
with:
```dart
class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  /// Whether the primary card's inline name form is showing (spec §1:
  /// "Tapping asks for the user's name inline") instead of the two-card
  /// chooser.
  bool _creatingHousehold = false;

  final _nameController = TextEditingController();
  bool _saving = false;
  String? _error;

  /// Guards [_maybeAutoResumeJoin] against firing more than once per
  /// screen instance -- see that method's doc comment.
  bool _autoJoinTriggered = false;

  late final ProviderSubscription<AsyncValue<AuthUser?>> _authSubscription;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onNameChanged);
    // Spec `docs/specs/onboarding-v2.md` §1 (the "point of maximum
    // anxiety"): a process kill while the user is away in Mail wipes this
    // screen's own Navigator stack, so a relaunch always starts back here.
    // If the magic link was already tapped before/during the kill, the
    // Supabase session survives it (`currentAuthUserProvider` resolves
    // non-null) even though nothing else here does -- and nothing other
    // than the join flow ever signs this device in while no household
    // exists. Auto-push the join subpage back open, once, instead of
    // stranding the user on the two-card chooser with no sign anything
    // was in progress. Two entry points cover both timings: the
    // post-frame check below catches "already signed in at cold start"
    // (a `StreamProvider` may not have its first value the instant
    // `initState` runs), and `_authSubscription` catches "signs in while
    // already sitting on this screen" (magic link tapped without ever
    // having left the app, or a kill that landed the user here before
    // sign-in completed).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeAutoResumeJoin(ref.read(currentAuthUserProvider));
    });
    _authSubscription = ref.listenManual<AsyncValue<AuthUser?>>(
      currentAuthUserProvider,
      (previous, next) => _maybeAutoResumeJoin(next),
    );
  }

  @override
  void dispose() {
    _authSubscription.close();
    _nameController
      ..removeListener(_onNameChanged)
      ..dispose();
    super.dispose();
  }

  /// Pushes [WelcomeJoinPage] the first time a signed-in user is observed
  /// while no household exists yet -- see [initState]'s doc comment.
  /// Fires at most once per [_WelcomeScreenState] instance (guarded by
  /// [_autoJoinTriggered]): once pushed, a later `pop` back to this screen
  /// (the user explicitly backing out to reconsider) must NOT be
  /// immediately re-pushed, or the back button would be useless. Skips
  /// silently while [_creatingHousehold] (the "start fresh" name form is
  /// up) -- the two flows are mutually exclusive in practice, but an
  /// interrupted create should never be shoved aside by this.
  void _maybeAutoResumeJoin(AsyncValue<AuthUser?> authState) {
    if (_autoJoinTriggered || _creatingHousehold || !mounted) {
      return;
    }
    if (authState.valueOrNull == null) {
      return;
    }
    _autoJoinTriggered = true;
    Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const WelcomeJoinPage()));
  }
```

No new import is needed: `AuthUser` already comes from this file's existing
`import 'package:chore_app/application/auth_gateway.dart';` (used today for
`NoopAuthGateway` in `_buildCards`), and `AsyncValue`/`ProviderSubscription`
from the existing `package:flutter_riverpod/flutter_riverpod.dart` import.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/onboarding/welcome_screen_test.dart`
Expected: PASS (all tests, including the new one).

- [ ] **Step 5: Write the capstone test — kill after code submission, before the claim RPC**

This is the ticket's actual target scenario end to end: signed in, code
submitted (and persisted per Task 5), killed before "Are you Anna?" is
even tapped (so nothing has reached the server yet), relaunched, and
everything still completes normally. This test uses `Clock.fixed(...)`
directly, which needs one new import at the top of
`test/features/onboarding/welcome_join_test.dart`:
`import 'package:clock/clock.dart';` (this file doesn't currently import it
— `pump_app.dart` uses `Clock` internally but doesn't re-export it). Add
this test to `test/features/onboarding/welcome_join_test.dart`, at the end
of `main()`:

```dart
  final killFakeAuth = FakeAuthGateway();
  final killGateway = FakeHouseholdGateway()
    ..claimableMembers = const [
      ClaimableMember(memberId: 'm-anna', name: 'Anna', color: 0xFF6D9F71),
    ]
    ..claimResultHouseholdId = 'joined-hh'
    ..downloadSnapshotOverride = const HouseholdSnapshot(
      household: Household(
        id: 'joined-hh',
        name: 'Joined household',
        createdAt: 't0',
        updatedAt: 't0',
        syncDirty: false,
      ),
      members: [
        Member(
          id: 'm-anna',
          householdId: 'joined-hh',
          name: 'Anna',
          color: 0xFF6D9F71,
          role: MemberRole.member,
          createdAt: 't0',
          updatedAt: 't0',
          syncDirty: false,
        ),
      ],
    );

  testFreshChoreApp(
    'mid-flow kill after submitting a code but before the claim RPC '
    'resumes on the join subpage with the code prefilled, not the '
    'two-card chooser, and completes normally from there -- the ticket\'s '
    'own "point of maximum anxiety" scenario end to end',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(killFakeAuth),
      householdGatewayProvider.overrideWithValue(killGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('welcome.join'));
      await tester.pumpAndSettle();
      await tester.enterText(
        _fieldFor('welcome.join.email'),
        'me@example.com',
      );
      await tester.pump();
      await tester.tap(find.bySemanticsIdentifier('welcome.join.send'));
      await tester.pumpAndSettle();

      killFakeAuth.signIn(const AuthUser(id: 'u1', email: 'me@example.com'));
      await tester.pumpAndSettle();

      await tester.enterText(
        _fieldFor('settings.account.join.code'),
        'abc12345',
      );
      await tester.pump();
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.join.continue'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Are you Anna?'), findsOneWidget);

      // Simulated kill+relaunch: a brand-new widget tree/ProviderScope
      // over the exact same, still-open in-memory database and the exact
      // same fake gateway instances. A real kill preserves neither Dart
      // object -- what it DOES preserve is this device's Supabase
      // session, which `killFakeAuth.currentUser` stands in for here, and
      // the database. A fresh `Key` forces a real rebuild from scratch
      // rather than an in-place, hot-reload-style rebuild (see
      // `welcome_screen_test.dart`'s identical "mid-flow kill" test for
      // the same reasoning).
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            clockProvider.overrideWithValue(Clock.fixed(today)),
            authGatewayProvider.overrideWithValue(killFakeAuth),
            householdGatewayProvider.overrideWithValue(killGateway),
          ],
          child: const ChoreApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Landed straight back on the join subpage's code step -- not the
      // two-card chooser -- with the previously-submitted code prefilled.
      expect(find.bySemanticsIdentifier('welcome.create'), findsNothing);
      expect(find.bySemanticsIdentifier('welcome.join'), findsNothing);
      expect(
        find.bySemanticsIdentifier('settings.account.join.code'),
        findsOneWidget,
      );
      final codeField = tester.widget<TextField>(
        _fieldFor('settings.account.join.code'),
      );
      expect(codeField.controller!.text, 'ABC12345');

      // Continuing from here works exactly as before the kill.
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.join.continue'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Are you Anna?'), findsOneWidget);
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.join.claim.m-anna'),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('shell.tab.chores'), findsOneWidget);

      final settings = await database.select(database.settings).getSingle();
      expect(settings.syncHouseholdId, 'joined-hh');
      expect(settings.actingMemberId, 'm-anna');
      expect(settings.pendingJoinCode, isNull);

      handle.dispose();
    },
  );
```

- [ ] **Step 6: Run the full onboarding test suite**

Run: `flutter test test/features/onboarding/`
Expected: PASS — every test in `welcome_screen_test.dart` and
`welcome_join_test.dart`.

- [ ] **Step 7: Run analyzer**

Run: `flutter analyze`
Expected: no new lints (public members documented, no unused imports).

- [ ] **Step 8: Commit**

```bash
git add lib/features/onboarding/welcome_screen.dart \
  test/features/onboarding/welcome_screen_test.dart \
  test/features/onboarding/welcome_join_test.dart
git commit -m "WelcomeScreen auto-resumes the join subpage for a signed-in user"
```

---

## Task 7: Update the spec

**Files:**
- Modify: `docs/specs/onboarding-v2.md`

- [ ] **Step 1: Replace the kill-mid-welcome paragraph in §1**

Replace:
```
Kill-the-app-mid-welcome resumes at the welcome screen (state is simply
"no household yet"). Sign-in completed but join not finished → welcome
join subpage restores to the signed-in step (auth state persists via
supabase session; the gate checks it on build).
```
with:
```
Kill-the-app-mid-welcome, before any sign-in, resumes at the plain welcome
screen (state is simply "no household yet"). Once sign-in has completed, a
kill-and-relaunch instead resumes DIRECTLY on the join subpage, skipping
the two-card chooser: `WelcomeScreen` auto-pushes `WelcomeJoinPage` the
first time it observes a signed-in `currentAuthUserProvider` with no
household yet (once per screen instance, so backing out of the subpage
never loops), and that subpage's own build-time derivation (above) takes
it from there — to the P2d reconnect offer if `myMembershipProvider`
already resolves one, otherwise to code entry. The invite code most
recently and successfully submitted also survives
(`settings.pendingJoinCode`, cleared on a successful join or on starting a
new household instead) and prefills the code field, so a kill after code
entry but before the claim/join RPC completes doesn't force retyping an
8-character code. Neither mechanism is authoritative on its own: the step
shown is always re-derived from live `currentAuthUserProvider`/
`myMembershipProvider` state, never a cached "where was I" flag, and a
half-succeeded claim/join RPC self-heals through the same reconnect-offer
path a returning device uses (§7.6) — the account is already a claimed
member server-side by the time that RPC returns, regardless of whether the
local device finished applying it.
```

- [ ] **Step 2: Commit**

```bash
git add docs/specs/onboarding-v2.md
git commit -m "Document the join subpage's process-kill resume guarantee"
```

---

## Task 8: Close out B-3 in the backlog

**Files:**
- Modify: `docs/backlog.md`

- [ ] **Step 1: Move B-3 into the closed list**

In `docs/backlog.md`, extend the top-of-file "Closed since they were
written, verified in code" paragraph to also name T2.4, and delete the
**B-3** row from the "B. Trust and safety gaps" table.

- [ ] **Step 2: Commit**

```bash
git add docs/backlog.md
git commit -m "Close B-3: the join wizard resumes across a process kill"
```

---

## Self-review notes

- **Spec coverage:** what must survive (Analysis — the code, via one
  advisory column; explicitly NOT the substep/choice/name, with reasoning),
  where it lives (Task 1/2 — `settings.pendingJoinCode` via
  `SettingsRepository`), how the app returns to the right place (Task 6 —
  `WelcomeScreen`'s one-shot auto-navigation, reusing the page's existing
  reactive derivation), when it's cleared (Task 3/4) — all covered, plus
  the explicit "what already works and must not regress" callout
  (Analysis, first paragraph) confirming `_buildBody`'s derivation is
  untouched.
- **No placeholders:** every step has literal, complete code — no "add
  appropriate handling."
- **Type consistency:** `SettingsRepository.setPendingJoinCode(String? code)`
  used identically in Task 2 (defined), Task 3/4 (call sites),
  Task 5 (call site + read via `settingsProvider`). `DeviceSettings
  .pendingJoinCode` (`String?`) referenced consistently across Tasks 1, 3,
  4, 5, 6's tests.
- **Scope:** single ticket (B-3 / T2.4), eight tasks, no unrelated
  refactoring pulled in. The Settings-side join sheet is explicitly left
  alone (Open product decisions section) with reasoning, not silently
  ignored.
