# A-5 — Acting-member pinning + "Mark done for…" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On a linked-and-signed-in household, pin the acting member to the
member this device's account has claimed and hide the app-bar switcher, and
move the rare "I finished something for someone else" case to a single
**Mark done for…** row in the chore action sheet — so two devices can no
longer credit different people for the same work.

**Architecture:** Two new providers in `lib/app/providers.dart` decide,
from local state only, whether this device *knows who is holding it*:
`memberIdentityModeProvider` (`unknown` / `switching` / `pinned`, derived
from `settings.syncHouseholdId` + `currentAuthUserProvider`) and
`claimedMemberProvider` (the member row whose `userId` equals the signed-in
auth user id). `actingMemberProvider` consults the claim first and only
falls back to the device-scoped `settings.actingMemberId` when not pinned or
when the claim hasn't arrived yet. The app bar's `ActingMemberButton`
branches on the mode; the chore action sheet gains one gated row that opens
a member picker and calls the existing
`ChoreService.completeOccurrence(id, completedBy: …)` with someone else's
id. No schema change, no new sync surface, no new service method.

**Tech Stack:** Flutter, Riverpod (`Provider`/`StreamProvider`), drift,
gen_l10n (`app_en.arb` template + `app_de.arb`), `flutter_test`
integration-style widget tests, Maestro E2E.

## Global Constraints

- **Specs in `docs/specs/` are binding contracts.** This work contradicts
  `docs/specs/members-management.md` §4 (which mandates an always-visible
  switcher); Task 7 amends it. Do not land Tasks 1–6 without Task 7.
- **Every user-visible string goes through gen_l10n**: add to
  `lib/l10n/app_en.arb` (template, with an `@key` description block) *and*
  `lib/l10n/app_de.arb` (German **du-form**). Never inline English.
  Key prefixes for this work: `actingMember*`, `choresMenu*`,
  `choresMarkDoneFor*`, `choresSnackbar*` (spec `members-management.md` §5).
- **Every interactive widget gets a stable id via `semantic()`**
  (`lib/app/semantics.dart`). E2E selects only by id or `(?s)`-substring
  text.
- **Existing ids are load-bearing.** `chores.actingMember`,
  `actingMember.sheet`, `actingMember.sheet.row.<memberId>` and
  `acting.manage` all survive this work **verbatim, on the local-only
  path**, which is the only path `flutter test` widget tests and every
  Maestro flow can reach (see "E2E impact" below). Nothing is renamed and
  nothing is deleted.
- **Igor's binding constraint (field feedback B1, 2026-08-07):**
  *"Mark done for… shouldn't be annoying."* It is ONE ordinary row in a
  sheet the user already opened deliberately. It does **not** get a place on
  the tile, does **not** prompt or confirm on a normal completion, does
  **not** ask "who did this?" on the common path, and never appears as a
  banner, tooltip or first-run hint. **Completing a chore as yourself stays
  exactly one tap.**
- **Widget tests are integration-style**: real in-memory `AppDatabase` +
  fixed clock via `testChoreApp` (`test/test_utils/pump_app.dart`),
  overriding ONLY `appDatabaseProvider`/`clockProvider` plus the documented
  seams — here `authGatewayProvider` (fake at
  `test/features/settings/fake_auth_gateway.dart`). Never mock a repository
  or a service.
- **Deadlock traps:** never await a drift stream outside a widget pump;
  never bare-await `bootstrapProvider.future` in a `ProviderContainer` test
  (poll `.hasValue` with `tester.pump(const Duration(milliseconds: 5))`
  loops); `tester.pump(small duration)` between `container.dispose()` and
  `database.close()`.
- **Riverpod trap (documented at `lib/app/providers.dart:358-377`):** never
  watch the bare `settingsProvider` from a provider that gates sync-adjacent
  behaviour — the sync engine's own `syncLastPulledAt` write re-emits it.
  `memberIdentityModeProvider` therefore watches a **`select`ed record**, so
  the pull's write can never change the watched value.
- **Strict lints** (`very_good_analysis`, `--fatal-infos`): every public
  member (including every enum value) needs a doc comment.
- **TDD**: write-failing-test → run → implement → run → commit, per task.
- **Never run `flutter`/`dart` while other agents hold the SDK lock.** The
  commands in this plan are for the executing session, which owns the lock.

---

## Analysis (how this design was chosen)

### What is true in the code today (verified)

- `ActingMemberButton` is the unconditional `leading` of the chores app bar
  (`lib/features/chores/chores_list_screen.dart:96`), with no linked-household
  gate.
- `actingMemberProvider` (`lib/app/providers.dart:626-643`) resolves from
  `settings.actingMemberId` — a **device-scoped** column that never syncs —
  falling back to "first admin, else first member".
- `markDoneFor` exists nowhere in `lib/`.
- `members.userId` exists locally (`lib/data/db/tables.dart:142`), and the
  server value **does** flow down: `memberFromRow`
  (`lib/data/sync/row_mappers.dart:56`) reads `user_id`, and both
  `HouseholdGateway.downloadHousehold` (join) and the sync engine's
  `applyPulledMember` → `insertOnConflictUpdate` (pull) write it locally.
- The server owns `user_id`: `grant update (name, color, role, deleted_at)`
  (`supabase/migrations/20260731120000_initial_schema.sql:416`) excludes it,
  and it is set exclusively by the `create_household` / `claim_member` /
  `join_as_new_member` RPCs.
- `HouseholdJoinService` (`join` and `joinFresh`) already calls
  `settings.setActingMember(<the claimed/created member id>)` — so on every
  join path the stored acting member is already this device's own member.
- `HouseholdLinkService.adopt` (`lib/application/household_link_service.dart`)
  does **not** mirror the claim locally. The server links `user_id` in step 1;
  the local row keeps `userId == null` and step 3's `setMemberRole` marks it
  `syncDirty`, so `applyPulledMember` skips it on the next pull. It only
  self-heals because `SyncEngine.start()` pushes first (clearing the dirty
  flag) and pulls afterwards with a still-null cursor. Offline right after
  adopting, that window stays open indefinitely.
  `docs/specs/household-lifecycle.md` §3.1 already specifies the fix as
  **G-B**; this plan pulls G-B forward (Task 3) because A-5 depends on it and
  C-1 is an L-effort cluster.
- `ChoreService.completeOccurrence(occurrenceId, completedBy:)`
  (`lib/application/chore_service.dart:101`) already takes the credited
  member as a parameter and reads no provider. Rotation advances on
  `assigned_member_id`, not `completed_by`. **The service is already correct;
  the misattribution lives entirely at the call site**
  (`chores_list_screen.dart:205`).

### Approaches considered

**(A) Sync the acting member.** Add `acting_member_id` to a synced table so
both devices agree on "who is acting".
*Rejected.* It preserves the inverted model B1 rejects (the phone can still
"become Anna"), and under last-push-wins it makes things worse: one phone
flipping the shared value silently re-attributes the other phone's next
completion. It also needs a schema + RLS + migration change.

**(B) Resolve identity from the server on demand** — call
`HouseholdGateway.findMyMembership()` and cache the member id.
*Rejected as the primary mechanism.* It is a network round trip on a path
that must work offline and on every cold start, and `myMembershipProvider`
already exists purely as a one-shot join-flow probe. It also duplicates a
fact the local database already holds. (`findMyMembership` keeps its role in
`household-lifecycle.md` §3.5 revocation detection — untouched here.)

**(C) Resolve identity from the local `members.userId`, gated on
linked+signed-in.** ← **chosen**
The claim is already replicated into the local database by both the join
snapshot and the ongoing pull, so identity resolution is a pure local read
that works offline, survives process death, and needs no schema change. The
only hole is the adopt path, which is closed by G-B (Task 3) — a three-line
local mirror of a server fact the spec already asks for.

The gate is computed **directly** from `settings.syncHouseholdId` +
`currentAuthUserProvider`, *not* from `syncEngineProvider is! NoopSyncEngine`
(the pattern `chores_list_screen.dart:60` uses for the refresh indicator).
Reason: `syncEngineProvider` additionally requires the compile-time
`supabaseConfigured` constant, which would force every widget test to
override `syncTransportProvider` to reach the pinned branch, and would tie
"who am I" to "can I reach the network" — two different questions. In
production the two gates coincide, because a household cannot become linked
without a configured gateway.

### State machine (the transitional states, spelled out)

| State | `memberIdentityMode` | App-bar leading | `actingMemberProvider` |
| --- | --- | --- | --- |
| Settings or auth still loading | `unknown` | disabled placeholder icon (same widget as today's pre-resolve state) | today's stored-id resolution |
| Not linked (local-only) | `switching` | **today's switcher, unchanged** | stored id → first admin → first member |
| Linked, signed **out** | `switching` | today's switcher | stored id → first admin → first member |
| Linked, signed in, claim resolved | `pinned` | non-interactive claimed-member avatar | **the claimed member** |
| Linked, signed in, claim not yet local | `pinned` | non-interactive avatar of the stored member | stored id, else `null` — **never** the first-admin guess |

Notes on the two subtle rows:

- **`unknown` exists to prevent a flash.** `currentAuthUserProvider` is a
  `StreamProvider`, so its first state is `AsyncLoading`; without `unknown`,
  a linked, signed-in phone would render a tappable "become Anna" switcher
  for one frame on every cold start. `unknown` renders the placeholder the
  button already shows before `actingMemberProvider` resolves, so there is no
  width jump either.
- **Linked-but-signed-out keeps the switcher.** The app genuinely does not
  know who is holding the phone, and Settings already offers Disconnect for
  this state (`HouseholdLinkService.disconnect`, field feedback A1.2).
  Silently pinning to a stale guess would be exactly the dishonest
  attribution A-5 exists to remove.
- **Pinned-with-no-claim returns `null` rather than "first admin".** On a
  linked household the stored id is always this device's own member (both
  join paths write it; adopt passes it in), so the stored fallback is safe;
  the first-admin guess is not, and is precisely how a second device credits
  the wrong person. When it resolves to `null`, `_complete` falls back to
  `occurrence.assignedMember?.id` exactly as it does today during the
  pre-bootstrap window. This state is transient by design —
  `household-lifecycle.md` §3.5 clears the sync link on a revoked
  membership.

### What happens to the stored `actingMemberId` when a local household links

**Nothing — deliberately.** This work never writes and never clears
`settings.actingMemberId`. It remains:
- the sole resolution source while local-only (unchanged behaviour), and
- the correct value the moment a device disconnects again, because both link
  paths already agree with it (`adopt` is called with the current acting
  member's id; `join`/`joinFresh` call `setActingMember` with the claimed
  member's id).

Once pinned, the stored value is simply **not read** while a claim resolves.
No migration, no cleanup, no repair write.

### E2E impact

`e2e/flows/settings/members_and_acting.yaml` (the only flow that drives the
switcher) is **unchanged and still passes**: E2E runs with empty Supabase
dart-defines, so `NoopHouseholdGateway` makes linking unreachable,
`settings.syncHouseholdId` is always `null`, and the flow stays on the
`switching` path where `chores.actingMember` → `actingMember.sheet` →
`actingMember.sheet.row.<id>` behave exactly as today.

For the same reason the pinned path and **Mark done for…** get **no Maestro
coverage** — the same conclusion `docs/specs/household-lifecycle.md` §4
reaches for the whole P4 cluster ("E2E stays offline per `sync-backend.md`
§7.5"). The gate is the widget suite (Tasks 1–6) plus a manual two-device
pass. New ids are still declared so a future online E2E harness can use
them: `chores.menu.markDoneFor`, `chores.markDoneFor.sheet`,
`chores.markDoneFor.row.<memberId>`.

### Judgement calls made (not open questions)

1. **No `ChoreService.markDoneFor` method.** `completeOccurrence(id,
   completedBy:)` is already the seam; "Mark done for…" is a UI affordance
   name, not a service concept. Adding a parallel method would duplicate
   `_closeAndAdvance` for zero behavioural difference.
2. **No new "recorded by" column.** B1 says the action "credits another
   member"; `completed_by` *is* the credit. A separate recorder field would
   be a schema + RLS + sync change nobody asked for.
3. **The picker excludes the claimed member.** "For someone else" is the
   whole point, and if you meant yourself the one-tap tile is right there.
4. **The row is hidden when the household has fewer than 2 members** —
   derivable, not a decision: there is nobody else to credit.
5. **G-B (adopt mirrors the claim) is pulled forward; G-A (unlink nulls
   every local `userId`) stays with C-1.** A-5's gate is
   linked-and-signed-in, so a stale `userId` on an unlinked household is
   already inert here.

---

## Open product decisions

*Genuinely user-visible, underivable, and not settled by B1. The plan
assumes the recommendation in each case; changing an answer changes only the
task noted.*

**D-A5-1 — What stands where the switcher stood, once pinned?**
B1 says "the app-bar switcher is hidden", but
`docs/specs/members-management.md` §4 also calls the same button "the
affordance that teaches *the app knows who I am*", which is arguably worth
more on a synced household than on a local one.
- (a) Nothing — `leading` falls back to the default (Android back/nothing);
  the title shifts left.
- (b) **A non-interactive avatar of the claimed member** (no `IconButton`, no
  tap target, long-press tooltip "You're signed in as Anna").
- (c) Still tappable, but the sheet degrades to "You're signed in as Anna" +
  the existing `acting.manage` row.
- **Recommendation: (b).** It satisfies "the switcher is hidden" literally —
  there is no switcher and no sheet — while keeping the identity teaching
  §4 asks for, and it keeps `chores.actingMember` present in every state so
  no selector ever disappears. (c) reintroduces a sheet whose only purpose
  duplicates Settings → Members; (a) throws away a spec-blessed affordance to
  save nothing.
- **The plan assumes (b)** (Task 4). Choosing (a) reduces Task 4 to
  returning `null` from `leading`; choosing (c) adds a reduced sheet.

**D-A5-2 — Does "Mark done for…" also appear in local-only households?**
- (a) **No** — the row exists only when pinned. Local-only keeps the
  switcher, where standing in for others already *is* the model, so a second
  path to the same outcome is redundant surface.
- (b) Yes, everywhere with ≥2 members — one consistent way to credit someone
  else, and the switcher becomes the redundant one.
- **Recommendation: (a).** B1 scopes the new row to the case it was invented
  for and explicitly keeps local-only "unchanged"; (b) would add a row to a
  sheet every existing user already knows, for no new capability.
- **The plan assumes (a)** (Task 5's gate is `mode == pinned`). Choosing (b)
  changes that gate to "≥2 members" alone and adds a local-only widget test.

**D-A5-3 — Does the confirmation snackbar name who got the credit?**
- (a) **Yes** — "Done — credited to Anna", with the same UNDO.
- (b) No — reuse today's "Done" / "Done — next due …".
- **Recommendation: (a).** The entire ticket is about attribution being
  believable; a rare, deliberate action that silently changes who gets credit
  is the failure mode in miniature. It costs one string and no extra tap.
- **The plan assumes (a)** (Task 6). Choosing (b) drops
  `choresSnackbarDoneBy` and the `creditedTo` parameter.

---

## File map

**Modified**

| File | Responsibility after this work |
| --- | --- |
| `lib/app/providers.dart` | Adds `MemberIdentityMode`, `memberIdentityModeProvider`, `claimedMemberProvider`; `actingMemberProvider` consults the claim before the stored id |
| `lib/features/chores/acting_member_sheet.dart` | `ActingMemberButton` branches three ways on the mode; the switcher sheet itself is untouched |
| `lib/features/chores/chore_action_sheet.dart` | New `ChoreMenuAction.markDoneFor` + one gated row, via a new `showMarkDoneFor` parameter (the sheet stays Riverpod-free) |
| `lib/features/chores/chores_list_screen.dart` | Passes the gate into the action sheet; handles `markDoneFor` (picker → `completeOccurrence` → snackbar naming the credited member) |
| `lib/application/household_link_service.dart` | `adopt` takes `authUserId` and mirrors the server's claim locally (G-B) |
| `lib/data/repositories/household_repository.dart` | New `setMemberClaim(memberId, userId)` — writes `members.userId` without touching `updatedAt`/`syncDirty` |
| `lib/features/settings/account_section.dart` | Passes the signed-in user id into `adopt` |
| `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb` | 4 new strings |
| `docs/specs/members-management.md` | §4 rewritten for the two modes; §6 gains the new test cases |
| `docs/specs/household-lifecycle.md` | §3.1 notes G-B landed with A-5 |
| `docs/backlog.md`, `docs/research/triage.md` | A-5 / T1.3 marked closed |

**Created**

| File | Responsibility |
| --- | --- |
| `lib/features/chores/mark_done_for_sheet.dart` | `showMarkDoneForSheet(...) → Future<Member?>`: the member picker, Riverpod-free like `chore_action_sheet.dart` |
| `test/app/member_identity_provider_test.dart` | The four identity states, at provider level |
| `test/features/chores/acting_member_pinning_test.dart` | App-bar behaviour in both modes |
| `test/features/chores/mark_done_for_test.dart` | The row's gate + the full credit-someone-else flow |

---

## Task 1: Identity providers

**Files:**
- Modify: `lib/app/providers.dart` (insert directly above
  `actingMemberProvider`, currently line 626)
- Test: `test/app/member_identity_provider_test.dart` (create)

**Interfaces:**
- Consumes: existing `settingsProvider`, `currentAuthUserProvider`,
  `membersProvider`.
- Produces:
  - `enum MemberIdentityMode { unknown, switching, pinned }`
  - `final memberIdentityModeProvider = Provider<MemberIdentityMode>(…)`
  - `final claimedMemberProvider = Provider<Member?>(…)`

- [ ] **Step 1: Write the failing test**

Create `test/app/member_identity_provider_test.dart`:

```dart
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/settings/fake_auth_gateway.dart';

/// `memberIdentityModeProvider` / `claimedMemberProvider` tests (A-5, spec
/// `docs/feedback/2026-08-07-field-feedback.md` B1): this device is
/// "pinned" to a claimed member only while it is LINKED and SIGNED IN, and
/// the claim is resolved from the local `members.userId` mirror.
///
/// Bare-`ProviderContainer` pattern with the polling helper, exactly as in
/// `test/app/acting_member_provider_test.dart`: a bare
/// `await container.read(x.future)` deadlocks under `flutter test`'s fake
/// clock, so progress is nudged with repeated nonzero-duration pumps.
Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 400; i++) {
    if (condition()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 5));
  }
  throw StateError('condition never became true');
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  /// Seeds a household + 'Me' member, builds a container whose auth gateway
  /// reports [user], and waits for bootstrap/members/settings to resolve.
  Future<({ProviderContainer container, String householdId, Member me})> setUpContainer(
    WidgetTester tester,
    AppDatabase database, {
    AuthUser? user,
  }) async {
    await HouseholdRepository(database).createLocalHousehold('Me');
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        clockProvider.overrideWithValue(Clock.fixed(DateTime(2026, 7, 24, 9))),
        authGatewayProvider.overrideWithValue(FakeAuthGateway(currentUser: user)),
      ],
    );
    addTearDown(container.dispose);
    await _pumpUntil(tester, () => container.read(bootstrapProvider).hasValue);
    final householdId = container.read(bootstrapProvider).requireValue;
    await _pumpUntil(
      tester,
      () =>
          container.read(membersProvider).hasValue &&
          container.read(settingsProvider).hasValue &&
          container.read(currentAuthUserProvider).hasValue,
    );
    final me = container.read(membersProvider).requireValue.single;
    return (container: container, householdId: householdId, me: me);
  }

  testWidgets('a local-only household is in switching mode with no claim', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    final setUpResult = await setUpContainer(tester, database);
    final container = setUpResult.container;

    expect(
      container.read(memberIdentityModeProvider),
      MemberIdentityMode.switching,
    );
    expect(container.read(claimedMemberProvider), isNull);

    await database.close();
  });

  testWidgets('linked but signed out stays in switching mode', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final setUpResult = await setUpContainer(tester, database);
    final container = setUpResult.container;

    await SettingsRepository(database).setSyncLinked(
      householdId: setUpResult.householdId,
      linkedAt: DateTime.utc(2026, 7, 24),
    );
    await _pumpUntil(
      tester,
      () =>
          container.read(settingsProvider).value?.syncHouseholdId ==
          setUpResult.householdId,
    );

    expect(
      container.read(memberIdentityModeProvider),
      MemberIdentityMode.switching,
    );
    expect(container.read(claimedMemberProvider), isNull);

    await database.close();
  });

  testWidgets('linked AND signed in pins to the member holding the claim', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    final setUpResult = await setUpContainer(
      tester,
      database,
      user: const AuthUser(id: 'u-1', email: 'me@example.com'),
    );
    final container = setUpResult.container;

    await SettingsRepository(database).setSyncLinked(
      householdId: setUpResult.householdId,
      linkedAt: DateTime.utc(2026, 7, 24),
    );
    await _pumpUntil(
      tester,
      () => container.read(memberIdentityModeProvider) ==
          MemberIdentityMode.pinned,
    );

    // Linked + signed in, but the claim hasn't been pulled down yet.
    expect(container.read(claimedMemberProvider), isNull);

    // The claim arrives (pull, join snapshot, or adopt's G-B mirror).
    await (database.update(
      database.members,
    )..where((tbl) => tbl.id.equals(setUpResult.me.id))).write(
      const MembersCompanion(userId: Value('u-1')),
    );
    await _pumpUntil(
      tester,
      () => container.read(claimedMemberProvider)?.id == setUpResult.me.id,
    );

    expect(
      container.read(memberIdentityModeProvider),
      MemberIdentityMode.pinned,
    );
    expect(container.read(claimedMemberProvider)!.name, 'Me');

    await database.close();
  });

  testWidgets("another account's claim is not this device's claim", (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    final setUpResult = await setUpContainer(
      tester,
      database,
      user: const AuthUser(id: 'u-1', email: 'me@example.com'),
    );
    final container = setUpResult.container;

    await (database.update(
      database.members,
    )..where((tbl) => tbl.id.equals(setUpResult.me.id))).write(
      const MembersCompanion(userId: Value('someone-else')),
    );
    await SettingsRepository(database).setSyncLinked(
      householdId: setUpResult.householdId,
      linkedAt: DateTime.utc(2026, 7, 24),
    );
    await _pumpUntil(
      tester,
      () => container.read(memberIdentityModeProvider) ==
          MemberIdentityMode.pinned,
    );

    expect(container.read(claimedMemberProvider), isNull);

    await database.close();
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/app/member_identity_provider_test.dart`
Expected: FAIL to compile — "Undefined name 'memberIdentityModeProvider'",
"Undefined name 'claimedMemberProvider'", "Undefined name
'MemberIdentityMode'".

- [ ] **Step 3: Write the implementation**

In `lib/app/providers.dart`, insert immediately **above** the
`actingMemberProvider` doc comment:

```dart
/// Whether this device can know, from the server, WHICH member is holding
/// it (A-5; spec `docs/feedback/2026-08-07-field-feedback.md` B1).
enum MemberIdentityMode {
  /// Linked state or auth state hasn't resolved yet. Render the neutral
  /// placeholder — deliberately NOT [switching], so a linked, signed-in
  /// phone never flashes a "become someone else" switcher for one frame on
  /// a cold start (`currentAuthUserProvider` is a stream: its first state
  /// is always `AsyncLoading`).
  unknown,

  /// Local-only, or linked but signed out: the app genuinely does not know
  /// who is holding the phone, so the acting-member switcher stays — for a
  /// local-only household, standing in for others IS the model.
  switching,

  /// Linked AND signed in: the acting member is pinned to the claimed
  /// member and the switcher is hidden. Crediting someone else moves to the
  /// chore action sheet's "Mark done for…" row.
  pinned,
}

/// [MemberIdentityMode] for the current linked/auth state.
///
/// Gated on `settings.syncHouseholdId` plus [currentAuthUserProvider]
/// DIRECTLY, deliberately not on `syncEngineProvider is! NoopSyncEngine`:
/// that additionally requires the compile-time [supabaseConfigured]
/// constant, which would tie "who am I?" to "can I reach the network?" and
/// force every widget test to override [syncTransportProvider] to reach the
/// pinned branch. In production the two coincide — a household cannot
/// become linked without a configured gateway.
///
/// **Watches a `select`ed record, never the bare [settingsProvider]** — see
/// [syncEngineProvider]'s doc comment: a started sync engine writes
/// `settings.syncLastPulledAt` on every pull, and an unscoped watch would
/// rebuild this provider on each of them.
final memberIdentityModeProvider = Provider<MemberIdentityMode>((ref) {
  final linkState = ref.watch(
    settingsProvider.select(
      (settings) => (
        loading: settings.isLoading,
        householdId: settings.valueOrNull?.syncHouseholdId,
      ),
    ),
  );
  if (linkState.loading) {
    return MemberIdentityMode.unknown;
  }
  if (linkState.householdId == null) {
    return MemberIdentityMode.switching;
  }
  final auth = ref.watch(currentAuthUserProvider);
  if (auth.isLoading) {
    return MemberIdentityMode.unknown;
  }
  return auth.valueOrNull == null
      ? MemberIdentityMode.switching
      : MemberIdentityMode.pinned;
});

/// The member this device's signed-in account has claimed in the current
/// household, resolved from the LOCAL `members.userId` mirror.
///
/// `user_id` is server-owned (the initial-schema grants exclude it from
/// UPDATE; only the `create_household`/`claim_member`/`join_as_new_member`
/// RPCs set it) and reaches this device three ways: the join snapshot
/// (`HouseholdGateway.downloadHousehold`), the sync engine's pull
/// (`applyPulledMember`), and `HouseholdLinkService.adopt`'s local mirror
/// (spec `docs/specs/household-lifecycle.md` §3.1 G-B). Reading it locally
/// is therefore offline-safe and survives process death — unlike a
/// `findMyMembership()` round trip.
///
/// `null` whenever the mode isn't [MemberIdentityMode.pinned], or while the
/// claim hasn't reached this device yet, or when this account is no longer
/// a member of the household (revocation — handled by
/// `docs/specs/household-lifecycle.md` §3.5, not here).
final claimedMemberProvider = Provider<Member?>((ref) {
  if (ref.watch(memberIdentityModeProvider) != MemberIdentityMode.pinned) {
    return null;
  }
  final userId = ref.watch(currentAuthUserProvider).valueOrNull?.id;
  final members = ref.watch(membersProvider).value;
  if (userId == null || members == null) {
    return null;
  }
  for (final member in members) {
    if (member.userId == userId) {
      return member;
    }
  }
  return null;
});
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/app/member_identity_provider_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Run the analyzer**

Run: `flutter analyze --fatal-infos lib/app/providers.dart test/app/member_identity_provider_test.dart`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add lib/app/providers.dart test/app/member_identity_provider_test.dart
git commit -m "A-5: resolve the claimed member from the local user_id mirror"
```

---

## Task 2: Pin `actingMemberProvider` to the claim

**Files:**
- Modify: `lib/app/providers.dart` (`actingMemberProvider`, currently
  lines 610-643 including its doc comment)
- Test: `test/app/acting_member_provider_test.dart` (append two tests)

**Interfaces:**
- Consumes: `MemberIdentityMode`, `memberIdentityModeProvider`,
  `claimedMemberProvider` (Task 1).
- Produces: `actingMemberProvider` — same `Provider<Member?>` signature, new
  resolution order. Every existing consumer
  (`chores_list_screen.dart:205` completion, `chore_form_screen.dart:488`
  `createdBy`, `shopping_quick_add_row.dart:283` `addedBy`,
  `account_section.dart:629` adopt) becomes correct with no change of its
  own.

- [ ] **Step 1: Write the failing tests**

Append to `test/app/acting_member_provider_test.dart`, inside `main()`. Add
these imports at the top of the file (keep the existing ones):

```dart
import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';

import '../features/settings/fake_auth_gateway.dart';
```

```dart
  testWidgets(
    'a linked, signed-in device pins to the CLAIMED member, ignoring a '
    'stored actingMemberId that points at someone else',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      await HouseholdRepository(database).createLocalHousehold('Me');
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(
            Clock.fixed(DateTime(2026, 7, 24, 9)),
          ),
          authGatewayProvider.overrideWithValue(
            FakeAuthGateway(
              currentUser: const AuthUser(id: 'u-1', email: 'me@example.com'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await _pumpUntil(
        tester,
        () => container.read(bootstrapProvider).hasValue,
      );
      final householdId = container.read(bootstrapProvider).requireValue;
      await _pumpUntil(
        tester,
        () =>
            container.read(membersProvider).hasValue &&
            container.read(settingsProvider).hasValue,
      );
      final me = container.read(membersProvider).requireValue.single;

      final anna = await container
          .read(householdRepositoryProvider)
          .addMember(householdId, name: 'Anna', color: 0xFF112233);
      // The device-scoped leftover this ticket exists to defeat: this phone
      // still thinks it is Anna.
      await container.read(settingsRepositoryProvider).setActingMember(anna.id);
      await (database.update(
        database.members,
      )..where((tbl) => tbl.id.equals(me.id))).write(
        const MembersCompanion(userId: Value('u-1')),
      );
      await SettingsRepository(database).setSyncLinked(
        householdId: householdId,
        linkedAt: DateTime.utc(2026, 7, 24),
      );

      await _pumpUntil(
        tester,
        () => container.read(actingMemberProvider)?.id == me.id,
      );
      expect(container.read(actingMemberProvider)?.name, 'Me');

      await database.close();
    },
  );

  testWidgets(
    'while pinned with no claim yet, falls back to the stored member and '
    'NEVER to the first-admin guess',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      await HouseholdRepository(database).createLocalHousehold('Me');
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(
            Clock.fixed(DateTime(2026, 7, 24, 9)),
          ),
          authGatewayProvider.overrideWithValue(
            FakeAuthGateway(
              currentUser: const AuthUser(id: 'u-1', email: 'me@example.com'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await _pumpUntil(
        tester,
        () => container.read(bootstrapProvider).hasValue,
      );
      final householdId = container.read(bootstrapProvider).requireValue;
      await _pumpUntil(
        tester,
        () =>
            container.read(membersProvider).hasValue &&
            container.read(settingsProvider).hasValue,
      );

      final anna = await container
          .read(householdRepositoryProvider)
          .addMember(householdId, name: 'Anna', color: 0xFF112233);
      await container.read(settingsRepositoryProvider).setActingMember(anna.id);
      await SettingsRepository(database).setSyncLinked(
        householdId: householdId,
        linkedAt: DateTime.utc(2026, 7, 24),
      );
      await _pumpUntil(
        tester,
        () =>
            container.read(memberIdentityModeProvider) ==
            MemberIdentityMode.pinned,
      );

      // Stored id still resolves: use it (both link paths set it to this
      // device's own member).
      expect(container.read(actingMemberProvider)?.id, anna.id);

      // Stored id dangles: return null rather than crediting 'Me' (the
      // first admin) — that guess is exactly the A-5 misattribution.
      await container
          .read(settingsRepositoryProvider)
          .setActingMember('does-not-exist');
      await _pumpUntil(
        tester,
        () => container.read(actingMemberProvider) == null,
      );
      expect(container.read(actingMemberProvider), isNull);

      await database.close();
    },
  );
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/app/acting_member_provider_test.dart`
Expected: the three pre-existing tests PASS; the two new ones FAIL — the
first with `'Anna' != 'Me'` (the stored id still wins), the second with
`Member(... 'Me' ...) != null` (the first-admin fallback still fires).

- [ ] **Step 3: Write the implementation**

Replace `actingMemberProvider`'s doc comment and body in
`lib/app/providers.dart` with:

```dart
/// The member who acts on behalf of the user for attribution flows
/// (completing an occurrence, `createdBy` on a new chore, shopping
/// `addedBy`), and the member the acting-member switcher (spec
/// `docs/specs/members-management.md` §4) shows as "current".
///
/// Resolution order, re-run whenever [memberIdentityModeProvider],
/// [claimedMemberProvider], [settingsProvider] or [membersProvider] change:
///
/// 1. **Pinned** ([MemberIdentityMode.pinned] — linked AND signed in):
///    [claimedMemberProvider], if the claim has reached this device. This
///    is A-5 (spec `docs/feedback/2026-08-07-field-feedback.md` B1): on a
///    synced household the phone IS a person, and `settings.actingMemberId`
///    is device-scoped and never syncs, so trusting it there is exactly how
///    two devices credit different people for the same work.
/// 2. `settings.actingMemberId`, if it matches a member in
///    [membersProvider]'s current list. While pinned this is only the
///    pre-claim window (offline right after adopting, or before the first
///    pull), and the value is safe there because every link path sets it to
///    THIS device's own member: `HouseholdJoinService.join`/`joinFresh`
///    call `setActingMember` with the claimed member id, and
///    `HouseholdLinkService.adopt` is called with the current acting
///    member.
/// 3. Not pinned only: the household's first admin member, else its first
///    member.
///
/// While pinned, step 3 is deliberately SKIPPED and this resolves to `null`
/// instead: guessing "the first admin" on a synced household is the
/// misattribution A-5 removes. `null` there means the caller falls back to
/// the occurrence's assignee (`ChoresListScreen._complete`), and the state
/// is transient by design — a signed-in account that is no longer a member
/// is a revoked membership, which clears the sync link per
/// `docs/specs/household-lifecycle.md` §3.5.
///
/// `null` also while [membersProvider] hasn't loaded yet or has no members.
/// A stored id that doesn't resolve is a read-time self-heal, not a repair:
/// nothing is ever written back to settings from here.
final actingMemberProvider = Provider<Member?>((ref) {
  final members = ref.watch(membersProvider).value;
  if (members == null || members.isEmpty) {
    return null;
  }
  final pinned =
      ref.watch(memberIdentityModeProvider) == MemberIdentityMode.pinned;
  if (pinned) {
    final claimed = ref.watch(claimedMemberProvider);
    if (claimed != null) {
      return claimed;
    }
  }
  final storedId = ref.watch(settingsProvider).value?.actingMemberId;
  if (storedId != null) {
    for (final member in members) {
      if (member.id == storedId) {
        return member;
      }
    }
  }
  if (pinned) {
    return null;
  }
  return members.firstWhere(
    (member) => member.role == MemberRole.admin,
    orElse: () => members.first,
  );
});
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/app/acting_member_provider_test.dart test/app/member_identity_provider_test.dart`
Expected: PASS (9 tests).

- [ ] **Step 5: Run the full offline suite (nothing else may regress)**

Run: `flutter test`
Expected: PASS. Every existing widget test is a local-only household
(`switching` mode), so resolution there is byte-for-byte today's.

- [ ] **Step 6: Commit**

```bash
git add lib/app/providers.dart test/app/acting_member_provider_test.dart
git commit -m "A-5: pin the acting member to the claimed member when linked and signed in"
```

---

## Task 3: Adopt mirrors the server's claim locally (G-B)

**Files:**
- Modify: `lib/data/repositories/household_repository.dart` (add
  `setMemberClaim` next to `setMemberRole`, currently line 271)
- Modify: `lib/application/household_link_service.dart` (`adopt`, step 3)
- Modify: `lib/features/settings/account_section.dart` (`_adopt`, line 623)
- Test: `test/application/household_link_service_test.dart` (append)

**Interfaces:**
- Consumes: nothing from Tasks 1–2 (this task is independent and may be done
  first).
- Produces:
  - `HouseholdRepository.setMemberClaim(String memberId, String? userId) → Future<void>`
  - `HouseholdLinkService.adopt({required String householdId, required String actingMemberId, required String authUserId}) → Future<void>`

**Why:** without this, the person who put their household online keeps
`members.userId == null` locally until a push/pull round trip completes, so
Task 1's claim never resolves while offline. `docs/specs/household-lifecycle.md`
§3.1 **G-B** already specifies exactly this fix.

- [ ] **Step 1: Write the failing test**

Append to `test/application/household_link_service_test.dart`, inside
`main()`:

```dart
  test(
    'adopt mirrors the server claim onto the local member row (G-B, spec '
    'docs/specs/household-lifecycle.md §3.1) without dirtying it',
    () async {
      final household = await HouseholdRepository(db).createLocalHousehold(
        'Me',
      );
      final me = await (db.select(
        db.members,
      )..where((tbl) => tbl.householdId.equals(household.id))).getSingle();
      expect(me.userId, isNull);

      await service.adopt(
        householdId: household.id,
        actingMemberId: me.id,
        authUserId: 'auth-user-1',
      );

      final claimed = await (db.select(
        db.members,
      )..where((tbl) => tbl.id.equals(me.id))).getSingle();
      expect(claimed.userId, 'auth-user-1');
      // Still admin (step 3's existing role mirror) and still marked dirty
      // by that role write -- setMemberClaim itself must not bump
      // updatedAt or syncDirty, because user_id is server-owned and is not
      // even UPDATE-granted (initial schema grants).
      expect(claimed.role, MemberRole.admin);
      expect(claimed.updatedAt, isNot(equals(me.updatedAt)));
    },
  );
```

Add `import 'package:chore_app/data/db/app_database.dart';` if the file does
not already have it (it does — keep the existing imports as they are).

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/application/household_link_service_test.dart`
Expected: FAIL to compile — "No named parameter with the name 'authUserId'".

- [ ] **Step 3: Write the implementation**

In `lib/data/repositories/household_repository.dart`, directly after
`setMemberRole`:

```dart
  /// Sets (or clears) [memberId]'s claim link to an auth user.
  ///
  /// Deliberately writes NEITHER `updatedAt` NOR `syncDirty`: `user_id` is
  /// server-owned — the initial schema grants UPDATE on
  /// `(name, color, role, deleted_at)` only, and the value is set
  /// exclusively by the `create_household`/`claim_member`/
  /// `join_as_new_member` RPCs. This write is a local MIRROR of a server
  /// fact, not a local change to be pushed, so marking the row dirty would
  /// queue a push that can never carry it (spec
  /// `docs/specs/household-lifecycle.md` §3.1: "Push is unchanged:
  /// `user_id` is server-owned").
  Future<void> setMemberClaim(String memberId, String? userId) async {
    await (db.update(
      db.members,
    )..where((tbl) => tbl.id.equals(memberId))).write(
      MembersCompanion(userId: Value(userId)),
    );
  }
```

In `lib/application/household_link_service.dart`, change `adopt`'s signature
and step 3:

```dart
  /// Runs the adopt flow for [householdId] (the local household -- its id
  /// is preserved verbatim on the server), [actingMemberId] (the caller's
  /// own member profile within it), and [authUserId] (the currently
  /// signed-in Supabase user id, mirrored onto that member locally in step
  /// 3).
  Future<void> adopt({
    required String householdId,
    required String actingMemberId,
    required String authUserId,
  }) async {
```

and replace step 3's single call with:

```dart
    // Step 3: acting member becomes admin locally, mirroring the server
    // rule `create_household` just applied -- and takes the claim with it
    // (G-B, spec `docs/specs/household-lifecycle.md` §3.1). Without the
    // claim mirror the row is dirty-and-unclaimed, and `_applyPulled`
    // skips dirty rows, so `claimedMemberProvider` (A-5) would stay
    // unresolved until a full push/pull round trip closed the window --
    // never, on a device that adopts while offline.
    await households.setMemberRole(actingMemberId, MemberRole.admin);
    await households.setMemberClaim(actingMemberId, authUserId);
```

In `lib/features/settings/account_section.dart`, inside `_adopt`, directly
after the existing acting-member null check:

```dart
    // Unreachable in practice for the same reason as the acting-member
    // check above: the adopt row only renders while signed in
    // (`AccountSectionBody`), so a null user here is a programming bug.
    final authUserId = ref.read(currentAuthUserProvider).valueOrNull?.id;
    if (authUserId == null) {
      throw StateError('No signed-in user to adopt with.');
    }
```

and change the call:

```dart
      await ref
          .read(householdLinkServiceProvider)
          .adopt(
            householdId: householdId,
            actingMemberId: actingMemberId,
            authUserId: authUserId,
          );
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/application/household_link_service_test.dart test/features/settings/account_section_test.dart`
Expected: PASS. If `account_section_test.dart` fails with "No signed-in user
to adopt with", the adopt-path test needs its `FakeAuthGateway` seeded with
a `currentUser` — check that test's overrides before changing anything in
`lib/`.

- [ ] **Step 5: Run the analyzer**

Run: `flutter analyze --fatal-infos lib test`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add lib/data/repositories/household_repository.dart lib/application/household_link_service.dart lib/features/settings/account_section.dart test/application/household_link_service_test.dart
git commit -m "A-5/G-B: adopt mirrors the server's claim onto the local member row"
```

---

## Task 4: The app bar stops offering "become someone else"

**Files:**
- Modify: `lib/features/chores/acting_member_sheet.dart` (`ActingMemberButton`,
  lines 16-41; the `_ActingMemberSheet` below it is **untouched**)
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`
- Test: `test/features/chores/acting_member_pinning_test.dart` (create)

**Interfaces:**
- Consumes: `MemberIdentityMode`, `memberIdentityModeProvider`,
  `actingMemberProvider` (Tasks 1–2).
- Produces: no new public API. New l10n key
  `actingMemberSignedInAs(String name)`.

**Implements open decision D-A5-1(b).** If (a) is chosen instead, the
`pinned` branch returns `const SizedBox.shrink()` and the test's avatar-name
assertion is dropped.

- [ ] **Step 1: Write the failing test**

Create `test/features/chores/acting_member_pinning_test.dart`:

```dart
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:chore_app/features/members/member_avatar.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import '../settings/fake_auth_gateway.dart';

/// A-5 (spec `docs/feedback/2026-08-07-field-feedback.md` B1): the app-bar
/// acting-member SWITCHER is offered only while this device cannot know who
/// is holding it. Once linked AND signed in, the same slot shows a
/// non-interactive avatar of the claimed member and opens nothing.
///
/// The linked state is driven exactly as a real link flow would drive it
/// (`SettingsRepository.setSyncLinked` + the local `members.userId` mirror
/// `HouseholdLinkService.adopt` now writes), and auth through the
/// documented `authGatewayProvider` seam -- no repository or service is
/// mocked (spec `docs/specs/testing-strategy.md`).
Future<void> _pumpUntilPinned(WidgetTester tester) async {
  final button = find.bySemanticsIdentifier('chores.actingMember');
  for (var i = 0; i < 400; i++) {
    final tappable = find
        .descendant(of: button, matching: find.byType(IconButton))
        .evaluate()
        .isNotEmpty;
    if (!tappable && button.evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 5));
  }
  throw StateError('the app-bar button never became non-interactive');
}

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'a local-only household keeps the switcher exactly as it was',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      final button = find.bySemanticsIdentifier('chores.actingMember');
      expect(button, findsOneWidget);
      expect(
        find.descendant(of: button, matching: find.byType(IconButton)),
        findsOneWidget,
      );

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.bySemanticsIdentifier('actingMember.sheet'), findsOneWidget);
      expect(find.bySemanticsIdentifier('acting.manage'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'once linked AND signed in, the slot shows the claimed member and opens '
    'nothing',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(
          currentUser: const AuthUser(id: 'u-1', email: 'me@example.com'),
        ),
      ),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final me = await (database.select(
        database.members,
      )..where((tbl) => tbl.householdId.equals(householdId))).getSingle();

      await (database.update(
        database.members,
      )..where((tbl) => tbl.id.equals(me.id))).write(
        const MembersCompanion(userId: Value('u-1')),
      );
      await SettingsRepository(
        database,
      ).setSyncLinked(householdId: householdId, linkedAt: today);

      await _pumpUntilPinned(tester);

      final button = find.bySemanticsIdentifier('chores.actingMember');
      // The id survives -- it just isn't a control any more.
      expect(button, findsOneWidget);
      expect(
        find.descendant(of: button, matching: find.byType(IconButton)),
        findsNothing,
      );
      expect(
        tester
            .widget<MemberAvatar>(
              find.descendant(of: button, matching: find.byType(MemberAvatar)),
            )
            .member
            .name,
        'Me',
      );

      // Tapping it does nothing at all: no sheet, ever.
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.bySemanticsIdentifier('actingMember.sheet'), findsNothing);

      handle.dispose();
    },
  );
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/chores/acting_member_pinning_test.dart`
Expected: the local-only test PASSES; the pinned test FAILS in
`_pumpUntilPinned` with "the app-bar button never became non-interactive".

- [ ] **Step 3: Add the l10n strings**

In `lib/l10n/app_en.arb`, directly after the `@actingMemberSheetTitle` block:

```json
  "actingMemberSignedInAs": "You're signed in as {name}",
  "@actingMemberSignedInAs": {
    "description": "Tooltip/accessibility label on the chores app-bar avatar once the household is linked and signed in (A-5, docs/feedback/2026-08-07-field-feedback.md B1). The avatar is NOT a switcher in this state: it only states which member this device is.",
    "placeholders": {
      "name": { "type": "String" }
    }
  },
```

In `lib/l10n/app_de.arb`, directly after `"actingMemberSheetTitle"`:

```json
  "actingMemberSignedInAs": "Du bist als {name} angemeldet",
```

- [ ] **Step 4: Write the implementation**

Replace `ActingMemberButton` in
`lib/features/chores/acting_member_sheet.dart` (leave every import and the
`_ActingMemberSheet` class below it exactly as they are):

```dart
/// The chores app bar's leading slot, in the three
/// [MemberIdentityMode] states (A-5, spec
/// `docs/feedback/2026-08-07-field-feedback.md` B1):
///
/// - [MemberIdentityMode.switching] (local-only, or linked but signed out):
///   the acting-member switcher exactly as spec
///   `docs/specs/members-management.md` §4 has always described it — an
///   avatar button opening [showActingMemberSheet]. On a local-only
///   household standing in for others IS the model.
/// - [MemberIdentityMode.pinned] (linked AND signed in): a NON-interactive
///   avatar of the claimed member. There is no switcher and no sheet:
///   offering "become Anna" in the app bar of a synced household inverts
///   the common case, and `settings.actingMemberId` is device-scoped, so
///   acting on it makes multi-device data wrong. Crediting someone else
///   moves to the chore action sheet's "Mark done for…" row.
/// - [MemberIdentityMode.unknown] (either state still resolving): the plain
///   disabled icon, which is also what every state renders before
///   [actingMemberProvider] resolves.
///
/// The `chores.actingMember` semantic id is present in ALL THREE states, so
/// no existing selector (widget test or Maestro flow) ever loses its
/// target.
class ActingMemberButton extends ConsumerWidget {
  /// Creates the acting-member button.
  const ActingMemberButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final mode = ref.watch(memberIdentityModeProvider);
    final member = ref.watch(actingMemberProvider);

    if (mode == MemberIdentityMode.pinned && member != null) {
      return semantic(
        'chores.actingMember',
        child: Tooltip(
          message: l10n.actingMemberSignedInAs(member.name),
          child: Center(child: MemberAvatar(member: member, radius: 14)),
        ),
      );
    }

    final canSwitch =
        mode == MemberIdentityMode.switching && member != null;
    return semantic(
      'chores.actingMember',
      child: IconButton(
        tooltip: l10n.actingMemberButtonTooltip,
        onPressed: canSwitch ? () => showActingMemberSheet(context) : null,
        icon: member == null || mode != MemberIdentityMode.switching
            ? const Icon(Icons.account_circle_outlined)
            : MemberAvatar(member: member, radius: 14),
      ),
    );
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/features/chores/acting_member_pinning_test.dart`
Expected: PASS (2 tests). gen_l10n regenerates
`lib/l10n/app_localizations*.dart` as part of `flutter test`; if the
`actingMemberSignedInAs` getter is missing, run `flutter gen-l10n` first.

- [ ] **Step 6: Run the suites that touch the switcher**

Run: `flutter test test/features/chores/acting_member_widget_test.dart test/features/settings/members_screen_test.dart`
Expected: PASS unchanged — both are local-only households.

- [ ] **Step 7: Commit**

```bash
git add lib/features/chores/acting_member_sheet.dart lib/l10n/ test/features/chores/acting_member_pinning_test.dart
git commit -m "A-5: hide the acting-member switcher on a linked, signed-in household"
```

---

## Task 5: One "Mark done for…" row in the chore action sheet

**Files:**
- Modify: `lib/features/chores/chore_action_sheet.dart`
- Modify: `lib/features/chores/chores_list_screen.dart` (`_openMenu`, line
  225; the `switch` gains one arm that is filled in by Task 6)
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`
- Test: `test/features/chores/mark_done_for_test.dart` (create)

**Interfaces:**
- Consumes: `MemberIdentityMode`, `memberIdentityModeProvider` (Task 1).
- Produces:
  - `ChoreMenuAction.markDoneFor` (a new enum value)
  - `showChoreActionSheet(BuildContext context, {required bool showMarkDoneFor}) → Future<ChoreMenuAction?>`
  - semantic id `chores.menu.markDoneFor`
  - l10n key `choresMenuMarkDoneFor`

**Igor's constraint applies here literally:** ONE ordinary row, in a sheet
the user already opened deliberately. It goes **first**, above Skip — it is
the only row about the occurrence's own completion, and Skip/Edit/Pause/
Delete keep their existing relative order and ids. Nothing on the tile
changes; the one-tap complete path is not touched by this task at all.

**Implements open decision D-A5-2(a)** — the row is `pinned`-only.

- [ ] **Step 1: Write the failing test**

Create `test/features/chores/mark_done_for_test.dart`:

```dart
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import '../settings/fake_auth_gateway.dart';

/// A-5 "Mark done for…" (spec `docs/feedback/2026-08-07-field-feedback.md`
/// B1): the rare "I finished something for someone else" case, as ONE row
/// in the chore action sheet — offered only where the switcher was taken
/// away (linked AND signed in), never on the tile, and never on the
/// one-tap complete path.
const _user = AuthUser(id: 'u-1', email: 'me@example.com');

/// Links the household and mirrors [_user]'s claim onto [memberId], exactly
/// as `HouseholdLinkService.adopt` now does.
Future<void> _linkAndClaim(
  AppDatabase database, {
  required String householdId,
  required String memberId,
  required DateTime now,
}) async {
  await (database.update(
    database.members,
  )..where((tbl) => tbl.id.equals(memberId))).write(
    const MembersCompanion(userId: Value('u-1')),
  );
  await SettingsRepository(
    database,
  ).setSyncLinked(householdId: householdId, linkedAt: now);
}

Future<void> _pumpUntilVisible(WidgetTester tester, String id) async {
  for (var i = 0; i < 400; i++) {
    if (find.bySemanticsIdentifier(id).evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 5));
  }
  throw StateError('$id never appeared');
}

void main() {
  final today = DateTime(2026, 7, 24, 9);

  Future<Chore> seedChore(AppDatabase database, String householdId) {
    return ChoreService(
      database: database,
      chores: ChoreRepository(database),
      clock: Clock.fixed(today),
    ).createChore(
      householdId: householdId,
      title: 'Water plants',
      startDate: PlainDate(2026, 7, 24),
      assignmentMode: AssignmentMode.anyone,
    );
  }

  testChoreApp(
    'a local-only household never sees the Mark done for… row',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await HouseholdRepository(
        database,
      ).addMember(householdId, name: 'Anna', color: 0xFF112233);
      final chore = await seedChore(database, householdId);
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.menu'),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('chores.menu.skip'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('chores.menu.markDoneFor'),
        findsNothing,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'linked and signed in with someone else in the household, the row is '
    'there — and completing normally is still one tap',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(currentUser: _user),
      ),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final me = await (database.select(
        database.members,
      )..where((tbl) => tbl.householdId.equals(householdId))).getSingle();
      await HouseholdRepository(
        database,
      ).addMember(householdId, name: 'Anna', color: 0xFF112233);
      final chore = await seedChore(database, householdId);
      await _linkAndClaim(
        database,
        householdId: householdId,
        memberId: me.id,
        now: today,
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.menu'),
      );
      await tester.pumpAndSettle();
      await _pumpUntilVisible(tester, 'chores.menu.markDoneFor');
      expect(find.text('Mark done for…'), findsOneWidget);

      // Close the sheet and complete normally: ONE tap, no picker, no
      // prompt, credited to me (Igor's constraint).
      await tester.tapAt(const Offset(400, 40));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.complete'),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('chores.markDoneFor.sheet'),
        findsNothing,
      );
      final closed = await (database.select(
        database.choreOccurrences,
      )..where((tbl) => tbl.status.equalsValue(OccurrenceStatus.done)))
          .getSingle();
      expect(closed.completedBy, me.id);

      handle.dispose();
    },
  );

  testChoreApp(
    'a linked household of one has nobody to credit, so no row',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(currentUser: _user),
      ),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final me = await (database.select(
        database.members,
      )..where((tbl) => tbl.householdId.equals(householdId))).getSingle();
      final chore = await seedChore(database, householdId);
      await _linkAndClaim(
        database,
        householdId: householdId,
        memberId: me.id,
        now: today,
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.menu'),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('chores.menu.skip'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('chores.menu.markDoneFor'),
        findsNothing,
      );

      handle.dispose();
    },
  );
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/chores/mark_done_for_test.dart`
Expected: the two "no row" tests PASS; the middle test FAILS in
`_pumpUntilVisible` with "chores.menu.markDoneFor never appeared".

- [ ] **Step 3: Add the l10n strings**

In `lib/l10n/app_en.arb`, directly before `"choresMenuSkip"`:

```json
  "choresMenuMarkDoneFor": "Mark done for…",
  "@choresMenuMarkDoneFor": {
    "description": "Chore occurrence action-sheet entry (A-5, docs/feedback/2026-08-07-field-feedback.md B1): complete this occurrence crediting ANOTHER member, without changing who you are. Shown only on a linked, signed-in household with at least two members — the rare 'I finished something for someone else' case."
  },
```

In `lib/l10n/app_de.arb`, directly before `"choresMenuSkip"`:

```json
  "choresMenuMarkDoneFor": "Für jemand anderen erledigen …",
```

- [ ] **Step 4: Write the implementation**

In `lib/features/chores/chore_action_sheet.dart`, add the enum value (first,
matching the row order):

```dart
enum ChoreMenuAction {
  /// Complete the pending occurrence crediting ANOTHER member (A-5, spec
  /// `docs/feedback/2026-08-07-field-feedback.md` B1). Offered only when
  /// `showMarkDoneFor` is true.
  markDoneFor,

  /// Skip the pending occurrence.
  skip,
```

(keep `edit`, `pause`, `delete` exactly as they are).

Change the function signature and doc comment:

```dart
/// Shows the tile-level bottom sheet offering (optionally) mark-done-for,
/// then skip/edit/pause/delete, and resolves to the chosen
/// [ChoreMenuAction] (or `null` if dismissed).
///
/// Rows are full-width with 22dp icons and a ≥48dp height (spec
/// `docs/specs/theme-v2.md` §4.5); delete sits last, in `error`. The drag
/// handle comes from the app-wide `BottomSheetThemeData`
/// (`lib/app/theme.dart`) -- never hand-rolled here.
///
/// [showMarkDoneFor] adds ONE ordinary row at the top (A-5, spec
/// `docs/feedback/2026-08-07-field-feedback.md` B1). It is deliberately
/// nothing more than that: the constraint on this feature is that it stays
/// rare — no tile placement, no prompt on the common path, no banner, and
/// completing a chore as yourself stays exactly one tap. The caller
/// computes the gate (linked + signed in, ≥2 members) so this sheet stays
/// Riverpod-free.
Future<ChoreMenuAction?> showChoreActionSheet(
  BuildContext context, {
  required bool showMarkDoneFor,
}) {
```

and insert the row as the first child of the `Column`, above
`chores.menu.skip`:

```dart
            if (showMarkDoneFor)
              semantic(
                'chores.menu.markDoneFor',
                child: ListTile(
                  leading: const Icon(Icons.how_to_reg_outlined, size: 22),
                  title: Text(l10n.choresMenuMarkDoneFor),
                  onTap: () {
                    Navigator.pop(sheetContext, ChoreMenuAction.markDoneFor);
                  },
                ),
              ),
```

In `lib/features/chores/chores_list_screen.dart`, update `_openMenu`'s call
and add the (temporarily inert) switch arm:

```dart
  Future<void> _openMenu(OccurrenceWithChore occurrence) async {
    // A-5 gate (spec docs/feedback/2026-08-07-field-feedback.md B1):
    // "Mark done for…" replaces the app-bar switcher, so it is offered in
    // exactly the state where that switcher is gone -- and only when there
    // is somebody else to credit.
    final pinned =
        ref.read(memberIdentityModeProvider) == MemberIdentityMode.pinned;
    final memberCount = ref.read(membersProvider).value?.length ?? 0;
    final action = await showChoreActionSheet(
      context,
      showMarkDoneFor: pinned && memberCount > 1,
    );
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case ChoreMenuAction.markDoneFor:
        // Filled in by the next task.
        return;
      case ChoreMenuAction.skip:
```

(the remaining arms are unchanged).

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/features/chores/mark_done_for_test.dart test/features/chores/menu_actions_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/chores/chore_action_sheet.dart lib/features/chores/chores_list_screen.dart lib/l10n/ test/features/chores/mark_done_for_test.dart
git commit -m "A-5: add the gated Mark done for… row to the chore action sheet"
```

---

## Task 6: The member picker and the credited completion

**Files:**
- Create: `lib/features/chores/mark_done_for_sheet.dart`
- Modify: `lib/features/chores/chores_list_screen.dart` (`_openMenu`'s
  `markDoneFor` arm, `_showCloseSnackbar`)
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`
- Test: `test/features/chores/mark_done_for_test.dart` (append)

**Interfaces:**
- Consumes: `ChoreMenuAction.markDoneFor` (Task 5), `claimedMemberProvider`
  (Task 1), the existing
  `ChoreService.completeOccurrence(String occurrenceId, {required String completedBy})`.
- Produces:
  - `showMarkDoneForSheet(BuildContext context, {required List<Member> members, required String? excludeMemberId}) → Future<Member?>`
  - semantic ids `chores.markDoneFor.sheet`,
    `chores.markDoneFor.row.<memberId>`
  - l10n keys `choresMarkDoneForTitle`, `choresSnackbarDoneBy`

**No new service method.** `completeOccurrence` already takes the credited
member; the misattribution was always at the call site.

**Implements open decision D-A5-3(a)** — the snackbar names the credited
member.

- [ ] **Step 1: Write the failing test**

Append to `test/features/chores/mark_done_for_test.dart`, inside `main()`:

```dart
  testChoreApp(
    'Mark done for… credits the picked member, leaves who I am untouched, '
    'and says whose credit it was',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(currentUser: _user),
      ),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final me = await (database.select(
        database.members,
      )..where((tbl) => tbl.householdId.equals(householdId))).getSingle();
      final anna = await HouseholdRepository(
        database,
      ).addMember(householdId, name: 'Anna', color: 0xFF112233);
      final chore = await seedChore(database, householdId);
      await _linkAndClaim(
        database,
        householdId: householdId,
        memberId: me.id,
        now: today,
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.menu'),
      );
      await tester.pumpAndSettle();
      await _pumpUntilVisible(tester, 'chores.menu.markDoneFor');
      await tester.tap(find.bySemanticsIdentifier('chores.menu.markDoneFor'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('chores.markDoneFor.sheet'),
        findsOneWidget,
      );
      expect(find.text('Who did this one?'), findsOneWidget);
      // "For someone else": my own row is not offered.
      expect(
        find.bySemanticsIdentifier('chores.markDoneFor.row.${me.id}'),
        findsNothing,
      );

      await tester.tap(
        find.bySemanticsIdentifier('chores.markDoneFor.row.${anna.id}'),
      );
      await tester.pumpAndSettle();

      // Credited to Anna...
      final closed = await (database.select(
        database.choreOccurrences,
      )..where((tbl) => tbl.status.equalsValue(OccurrenceStatus.done)))
          .getSingle();
      expect(closed.completedBy, anna.id);
      expect(find.text('Done — credited to Anna'), findsOneWidget);

      // ...and I am still me: the acting member never changed, and neither
      // did the stored device setting.
      final settings = await database.select(database.settings).getSingle();
      expect(settings.actingMemberId, isNot(anna.id));
      await tester.tap(find.bySemanticsIdentifier('chores.done.header'));
      await tester.pumpAndSettle();
      expect(find.textContaining('by Anna'), findsOneWidget);

      handle.dispose();
    },
  );
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/chores/mark_done_for_test.dart`
Expected: the new test FAILS — `chores.markDoneFor.sheet` findsNothing (the
switch arm still returns immediately).

- [ ] **Step 3: Add the l10n strings**

In `lib/l10n/app_en.arb`, after the `@choresMenuMarkDoneFor` block:

```json
  "choresMarkDoneForTitle": "Who did this one?",
  "@choresMarkDoneForTitle": {
    "description": "Title of the member picker opened by the 'Mark done for…' action-sheet row (A-5). Asks who to CREDIT for this one occurrence; it never changes who the device's user is."
  },
```

and after the `@choresSnackbarDoneNextDue` block:

```json
  "choresSnackbarDoneBy": "Done — credited to {name}",
  "@choresSnackbarDoneBy": {
    "description": "Undo snackbar shown after completing an occurrence via 'Mark done for…' (A-5): names the member who got the credit, since this is the one path where that isn't the person holding the phone. The UNDO action reopens the occurrence, exactly as on the normal completion path.",
    "placeholders": {
      "name": { "type": "String" }
    }
  },
```

In `lib/l10n/app_de.arb`, after `"choresMenuMarkDoneFor"` and
`"choresSnackbarDoneNextDue"` respectively:

```json
  "choresMarkDoneForTitle": "Wer hat das gemacht?",
```

```json
  "choresSnackbarDoneBy": "Erledigt — {name} gutgeschrieben",
```

- [ ] **Step 4: Write the picker**

Create `lib/features/chores/mark_done_for_sheet.dart`:

```dart
/// The "Mark done for…" member picker (A-5, spec
/// `docs/feedback/2026-08-07-field-feedback.md` B1).
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/features/members/member_avatar.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Asks which member to CREDIT for one occurrence, and resolves to that
/// member (or `null` if the sheet was dismissed).
///
/// [excludeMemberId] drops one row — the claimed member, i.e. the person
/// holding the phone: this action exists for "I finished something for
/// ANOTHER person", and completing something as yourself is the tile's
/// one-tap path.
///
/// Riverpod-free by design, exactly like `chore_action_sheet.dart`: the
/// caller (`ChoresListScreen`) owns provider reads, so this file stays a
/// pure presentation widget. Picking a member does NOT write
/// `settings.actingMemberId` — crediting somebody is not becoming them.
Future<Member?> showMarkDoneForSheet(
  BuildContext context, {
  required List<Member> members,
  required String? excludeMemberId,
}) {
  return showModalBottomSheet<Member>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final l10n = AppLocalizations.of(sheetContext);
      return semantic(
        'chores.markDoneFor.sheet',
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  l10n.choresMarkDoneForTitle,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
              for (final member in members)
                if (member.id != excludeMemberId)
                  semantic(
                    'chores.markDoneFor.row.${member.id}',
                    child: ListTile(
                      leading: MemberAvatar(member: member, radius: 14),
                      title: Text(member.name),
                      onTap: () => Navigator.pop(sheetContext, member),
                    ),
                  ),
            ],
          ),
        ),
      );
    },
  );
}
```

- [ ] **Step 5: Wire it into the list screen**

In `lib/features/chores/chores_list_screen.dart`, add the import
(alphabetical, after `chore_form_screen.dart`):

```dart
import 'package:chore_app/features/chores/mark_done_for_sheet.dart';
```

Replace the placeholder switch arm from Task 5:

```dart
      case ChoreMenuAction.markDoneFor:
        await _markDoneFor(occurrence);
```

and add the handler directly below `_complete`:

```dart
  /// The rare "I finished something for someone else" path (A-5, spec
  /// `docs/feedback/2026-08-07-field-feedback.md` B1): pick a member, then
  /// close the occurrence crediting THEM.
  ///
  /// Deliberately NOT a new `ChoreService` method: `completeOccurrence`
  /// already takes the credited member, and rotation advances on
  /// `assigned_member_id` rather than `completed_by`, so this differs from
  /// [_complete] only in which id it passes. It also never writes
  /// `settings.actingMemberId` — crediting somebody is not becoming them.
  Future<void> _markDoneFor(OccurrenceWithChore occurrence) async {
    final members = ref.read(membersProvider).value ?? const <Member>[];
    final picked = await showMarkDoneForSheet(
      context,
      members: members,
      excludeMemberId: ref.read(claimedMemberProvider)?.id,
    );
    if (!mounted || picked == null) {
      return;
    }
    await ref
        .read(choreServiceProvider)
        .completeOccurrence(occurrence.occurrence.id, completedBy: picked.id);
    unawaited(HapticFeedback.mediumImpact());
    if (!mounted) {
      return;
    }
    await _showCloseSnackbar(
      occurrence: occurrence,
      skipped: false,
      creditedTo: picked,
    );
  }
```

Finally extend `_showCloseSnackbar`: add the parameter

```dart
  Future<void> _showCloseSnackbar({
    required OccurrenceWithChore occurrence,
    required bool skipped,
    Member? creditedTo,
  }) async {
```

and, immediately after the existing `final l10n = AppLocalizations.of(context);`
line inside it, insert:

```dart
    // A-5: on the "Mark done for…" path the credited member is NOT the
    // person holding the phone, so the confirmation says whose credit it
    // was. The next-due variants are skipped here deliberately — WHO got
    // the credit is the fact worth confirming on this path, and the chore's
    // next occurrence is visible in the list behind the bar anyway.
    if (creditedTo != null) {
      showAppSnackbar(
        context,
        message: l10n.choresSnackbarDoneBy(creditedTo.name),
        action: SnackBarAction(
          label: l10n.choresSnackbarUndo,
          onPressed: () {
            unawaited(
              ref.read(choreServiceProvider).reopenOccurrence(occurrenceId),
            );
          },
        ),
      );
      return;
    }
```

Both names are in scope there: `final occurrenceId = occurrence.occurrence.id;`
is declared at the top of the method (above the `pendingOccurrenceOf` await),
and `final l10n = AppLocalizations.of(context);` is the line this block goes
directly beneath. The early `return` means the `nextPending` lookup above it
is wasted work on this path only — that is deliberate, and keeps the method
one method instead of two near-identical ones.

- [ ] **Step 6: Run the test to verify it passes**

Run: `flutter test test/features/chores/mark_done_for_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 7: Run the full offline suite and the analyzer**

Run: `flutter test`
Expected: PASS.
Run: `flutter analyze --fatal-infos`
Expected: "No issues found!"

- [ ] **Step 8: Commit**

```bash
git add lib/features/chores/mark_done_for_sheet.dart lib/features/chores/chores_list_screen.dart lib/l10n/ test/features/chores/mark_done_for_test.dart
git commit -m "A-5: Mark done for… credits another member without changing who you are"
```

---

## Task 7: Update the binding specs and close the ticket

**Files:**
- Modify: `docs/specs/members-management.md` (§4, §6)
- Modify: `docs/specs/household-lifecycle.md` (§3.1 G-B)
- Modify: `docs/backlog.md` (the A-5 row)
- Modify: `docs/research/triage.md` (T1.3)

**Interfaces:** none — documentation only. This task is **not optional**:
`members-management.md` §4 currently mandates the behaviour Tasks 4–6
remove, and a spec that contradicts the code is the failure mode this
project's conventions exist to prevent.

- [ ] **Step 1: Rewrite `members-management.md` §4**

Replace the whole `## 4. Acting-member switcher` section with:

```markdown
## 4. Who the app acts as

Two modes, decided by `memberIdentityModeProvider` (`lib/app/providers.dart`)
from the linked state (`settings.syncHouseholdId`) and the auth state
(`currentAuthUserProvider`). Amended 2026-08-08 by A-5 / field feedback
`docs/feedback/2026-08-07-field-feedback.md` B1.

### 4.1 Switching mode — local-only, or linked but signed out

Unchanged from this spec's original text: on a local-only household the
phone stands in for everybody, so standing in for others IS the model.

- The chores tab app bar gets a leading avatar button showing the CURRENT
  acting member (color + initial). Semantic id: `chores.actingMember`.
- Tap → modal bottom sheet: title ("Who's doing chores right now?" /
  German du-form equivalent), one row per member (avatar + name + check on
  the current one). Selecting persists via `setActingMember(id)` and closes
  the sheet. Sheet ids: `actingMember.sheet`, rows
  `actingMember.sheet.row.<memberId>`, plus the `acting.manage` row.
- The switcher is GLOBAL (one settings value): chore completions
  (`completedBy`) and any other actingMember reads (shopping quick-add,
  chore form defaults) all follow it.
- One member in household: the switcher still shows (it is also the
  affordance that teaches "the app knows who I am") but the sheet just
  lists the single member.

### 4.2 Pinned mode — linked AND signed in

On a synced household the phone IS a person, and `settings.actingMemberId`
is device-scoped and never syncs, so acting on it lets two devices credit
different people for the same work.

- The acting member is PINNED to the claimed member —
  `claimedMemberProvider`, resolved from the local `members.userId` mirror
  against the signed-in auth user id. There is no switcher and no switcher
  sheet.
- The `chores.actingMember` slot stays, as a NON-interactive avatar of the
  claimed member with the accessible label "You're signed in as {name}".
  The id is present in every mode, so no selector ever loses its target.
- Crediting someone else moves to the chore action sheet's **Mark done
  for…** row (`chores.menu.markDoneFor`), which opens a member picker
  (`chores.markDoneFor.sheet`, rows `chores.markDoneFor.row.<memberId>`)
  and calls `ChoreService.completeOccurrence(..., completedBy: <picked>)`.
  It never writes `settings.actingMemberId`: crediting somebody is not
  becoming them.
- **Binding constraint (Igor, 2026-08-07):** "Mark done for… shouldn't be
  annoying." One ordinary row, in a sheet the user opened deliberately, on
  a linked household with at least two members. No tile placement, no
  prompt or confirmation on a normal completion, no "who did this?" on the
  common path, no banner/tooltip/first-run hint. **Completing a chore as
  yourself is exactly one tap.**
- `settings.actingMemberId` is never written or cleared by pinning; it is
  simply not read while a claim resolves, and it is correct again the
  moment the device disconnects.
- Transitional states: while either the linked or the auth state is still
  resolving, the slot renders the neutral placeholder (never a switcher
  that would vanish a frame later). While pinned with no claim yet (adopted
  offline, or before the first pull) the stored acting member is used, and
  if it dangles the acting member resolves to `null` rather than guessing
  "the first admin". A signed-in account that is no longer a member of the
  household is a revoked membership — see `household-lifecycle.md` §3.5.
```

- [ ] **Step 2: Extend `members-management.md` §6**

Under "Provider:", replace the single bullet with:

```markdown
- actingMemberProvider honors a valid stored id; falls back on NULL and
  on a dangling id (member id that doesn't exist).
- memberIdentityModeProvider: local-only and linked-but-signed-out are
  `switching`; linked + signed in is `pinned`.
- claimedMemberProvider resolves the member whose `userId` matches the
  signed-in auth user, and stays null for another account's claim.
- While pinned, actingMemberProvider returns the claimed member even when a
  stored actingMemberId points elsewhere, and returns null (never the
  first-admin guess) when neither resolves.
```

Under "Widget (…)", append:

```markdown
- Pinning: a local-only household keeps the tappable switcher and its
  sheet; once linked AND signed in the same id is present but not a
  control, and tapping it opens nothing.
- Mark done for…: absent local-only and absent in a linked household of
  one; present when linked, signed in and ≥2 members; picking a member
  credits THEM (`completed_by`), leaves `settings.actingMemberId` untouched,
  and confirms with a snackbar naming them. Completing normally stays one
  tap and never opens the picker.
```

Under "E2E (…)", append:

```markdown
- Pinned mode gets NO Maestro coverage: E2E runs with empty Supabase
  dart-defines, so `NoopHouseholdGateway` makes linking unreachable and
  `settings.syncHouseholdId` is always NULL. The existing switcher journey
  is therefore unchanged and still valid. Same conclusion, same reason as
  `household-lifecycle.md` §4.
```

- [ ] **Step 3: Note G-B in `household-lifecycle.md` §3.1**

Append to the **G-B** paragraph:

```markdown
**Landed 2026-08-08 with A-5** (`docs/plans/2026-08-08-acting-member-pinning.md`
Task 3): `HouseholdRepository.setMemberClaim` plus `adopt`'s new
`authUserId` parameter. A-5's `claimedMemberProvider` depends on it, so it
was pulled out of this cluster rather than blocking on it. **G-A is still
open here** — nulling every local `members.userId` on `clearSyncLink` is
untouched by A-5, whose gate is linked-and-signed-in and so already ignores
a stale flag on an unlinked household.
```

- [ ] **Step 4: Close the ticket rows**

In `docs/backlog.md`, replace the **A-5** table row with a one-line entry
under the "Closed since they were written, verified in code" paragraph
(add `A-5 (acting-member pinning + Mark done for…, 2026-08-08)` to that
list) and delete the row from the A table.

In `docs/research/triage.md`, mark **T1.3** as done in the same style the
file already uses for its other closed Tier 1 rows, and update the
"3. **T1.3** — the B1 work" line in the ordering list at the bottom.

- [ ] **Step 5: Verify no stale claims remain**

Run: `grep -rn "markDoneFor exists nowhere\|unconditional app-bar\|switcher is still" docs/`
Expected: no matches.
Run: `grep -rn "showChoreActionSheet" lib test`
Expected: only `lib/features/chores/chore_action_sheet.dart` and
`lib/features/chores/chores_list_screen.dart` — one call site, already
updated.

- [ ] **Step 6: Final full verification**

Run: `flutter analyze --fatal-infos`
Expected: "No issues found!"
Run: `flutter test`
Expected: PASS, all suites.

E2E is the GitHub CI gate (not a local emulator run). The relevant flow,
`e2e/flows/settings/members_and_acting.yaml`, is unchanged by this work —
push and let CI run it.

- [ ] **Step 7: Commit**

```bash
git add docs/specs/members-management.md docs/specs/household-lifecycle.md docs/backlog.md docs/research/triage.md
git commit -m "A-5: spec the two acting-member modes and close T1.3"
```

---

## Self-review notes

- **Spec coverage.** B1's three requirements map to Task 2 (pin), Task 4
  (hide the switcher), Tasks 5–6 (Mark done for…); "local-only unchanged" is
  asserted by the first test in each of Tasks 4 and 5. Igor's constraint is
  asserted directly by the middle test in Task 5 (one tap, no picker, no
  prompt) and by Task 6's "acting member never changed". The
  device-scoped-drift half of T1.3 is Task 2 + Task 3.
- **Naming consistency.** `memberIdentityModeProvider`,
  `claimedMemberProvider`, `MemberIdentityMode.{unknown,switching,pinned}`,
  `setMemberClaim`, `showMarkDoneForSheet`, `showChoreActionSheet(…,
  showMarkDoneFor:)`, `ChoreMenuAction.markDoneFor` are used identically in
  every task that references them.
- **Ordering.** Task 3 is independent and may run first or in parallel;
  Tasks 1 → 2 → 4 and 1 → 5 → 6 are strictly ordered. Task 7 must land with
  the others, never after them.
