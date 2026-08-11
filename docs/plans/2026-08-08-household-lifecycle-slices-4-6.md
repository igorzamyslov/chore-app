# Household Lifecycle (P4) — Slices 4–6 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the three user-facing exits on top of the server surface and
shared widgets built by slices 1–3: remove a claimed member (F10), leave a
household including the last-claimed-member cascade warning (F9 / D-L5), and
delete an account (F11).

**Architecture:** Three new `HouseholdGateway` methods (one per server RPC),
one new application service (`HouseholdExitService`) for the two
account-scoped exits, a claim-state split inside the existing
`MemberService.deleteMember`, and three call sites — the member edit sheet
and two new rows in the Account section — all reusing slice 2's
`showExitConfirmSheet`. No new SQL except in slice 6's fallback branch.

**Tech Stack:** Flutter 3.44, Riverpod, drift/SQLite, gen_l10n; Postgres 15 /
Supabase (and, in slice 6's fallback branch only, one Deno edge function).

**Spec:** `docs/specs/household-lifecycle.md` (BINDING). Section references
below (§2.2, §3.2, D-L3, …) point into it. `docs/specs/sync-backend.md` §2
and §7 are the secondary contract.

**Depends on:** `docs/plans/2026-08-08-household-lifecycle-slices-1-3.md`
(Tasks 1–11) being complete and committed. Task numbering here continues
from it: this plan starts at **Task 12**. Concretely it consumes:

| From | What |
| --- | --- |
| Task 2 | `leave_household(p_household_id uuid)` |
| Task 3 | `_cascade_if_orphaned` (fires inside leave/delete-account) |
| Task 4 | `remove_member(p_member_id uuid)` |
| Task 6 | `delete_account()` |
| Task 7 | `clearSyncLink()` also nulls every local `members.userId` (G-A) |
| Task 8 | `adopt` sets the acting member's local `userId` (G-B) |
| Task 9 | `showExitConfirmSheet` / `ExitConfirmResult` (§3.3, D-L3) |
| Task 10 | `SettingsRepository.clearMembershipRevoked()` |

Tasks 12–18 (slices 4 and 5) are executable the moment slices 1–3 are green.
Tasks 19–22 (slice 6) depend on Task 1's gate, which has since been **proven**
— see the next section.

## Framing: delete-account is required, but it is not a launch gate

`docs/backlog.md` decision **D-B2** made distribution open-source only,
permanently: GitHub Releases and F-Droid, no Play/App Store accounts. Account
deletion is therefore **GDPR-driven rather than store-mandated**. It is still
genuinely required once accounts exist — a user who signed in with their email
must be able to erase that account and the email behind it — but it does not
have to precede the first public release, and nothing in slice 6 should be
rushed to hit a store review. Slices 4 and 5 are the ones with day-to-day
user value; slice 6 is the obligation.

---

## The slice-1 gate: RESOLVED — D-L4 holds, single RPC, no edge function

Decision **D-L4** was an EXPECTATION when the spec was written: `delete_account()`
would do the whole job in one paste-SQL `SECURITY DEFINER` RPC
(`delete from auth.users where id = auth.uid()`, owned by `postgres`). Slice 1
Task 1 existed to prove or refuse it.

**It is proven.** Commit `f184f4a` on branch `p4-membership-exit` (worked in a
separate worktree) has the `auth.users` delete succeeding from the
`postgres`-owned `SECURITY DEFINER` function. Two details from that commit
matter to the tasks below:

- It relaxes the two §2.7 `created_by` foreign keys — `households.created_by`
  to `on delete set null`, `household_invites.created_by` to
  `on delete cascade` — exactly as §2.7 specified.
- It adds a **one-line unclaim of the caller's own membership before the auth
  delete**, because `members.user_id` is a THIRD `NO ACTION` FK into
  `auth.users` and, unlike the other two, it cannot be relaxed:
  `is_household_member()` reads it, so `on delete set null` there would be an
  RLS change, not a cleanup change. The unclaim §2.2 already required is what
  clears the constraint.

**Consequences for this plan:**

- **D-L4 resolves to the single-RPC path.** Task 20's gateway method is one
  `rpc('delete_account')` call. There is no edge function, no service-role
  key anywhere, and the established no-credentials-in-chat paste-SQL handoff
  is preserved exactly as D-L4 intended.
- **Task 19 is a verification-and-record task, not an implementation task.**
- **The edge-function fallback is retained but demoted** to Appendix A at the
  end of this plan. It is not a branch to choose between; it is the recovery
  route if the proven RPC ever regresses (a Supabase platform change to
  `auth` schema permissions is the realistic trigger). Do not implement it.
- Slices 4 and 5 never depended on the gate at all: `remove_member` and
  `leave_household` do not touch `auth.users`.

---

## Global Constraints

- Every user-visible string goes through gen_l10n: add to `lib/l10n/app_en.arb`
  (template) AND `lib/l10n/app_de.arb` (du-form). Never hardcode display text.
- Every interactive widget gets a semantic id via the `semantic()` helper —
  signature `Widget semantic(String id, {required Widget child})`
  (`lib/app/semantics.dart:13`), so the widget goes in the NAMED `child:`
  parameter, not positionally.
- Semantic id prefixes for this cluster are fixed by §3.6: `members.remove.*`,
  `settings.account.leave`, `settings.account.deleteAccount`.
- l10n key prefixes are fixed by §3.6: `memberRemove*`, `householdLeave*`,
  `accountDelete*`.
- Strict lints: `very_good_analysis` with `--fatal-infos`. Public members need
  doc comments.
- Widget tests are integration-style: real in-memory `AppDatabase`, fixed
  clock, overriding only `appDatabaseProvider`/`clockProvider` plus the
  documented gateway seams (`authGatewayProvider`, `householdGatewayProvider`)
  with the fakes under `test/features/settings/`. Never mock repositories or
  services.
- Never `await` a drift stream outside a widget pump — it deadlocks.
- Run Flutter/Dart commands as `env -u GIT_DIR -u GIT_INDEX_FILE flutter ...`
  when anywhere near git hooks or worktrees.
- Do NOT run more than 2 concurrent `flutter test`/`build` processes.
- Never add `Co-Authored-By` trailers to commits.
- `members.role` is vestigial (D1/D-L2). **Any member may remove any other
  member.** Do not add a role check anywhere in this plan — not in a widget,
  not in a service, not in a comment implying one is coming.
- Never call a network RPC inside a `database.transaction(...)`: it holds
  drift's write lock across a round trip and cannot be rolled back anyway.

---

## Deviations from the spec (recorded, not silently applied)

Following the precedent of the slices 1–3 plan, which recorded three.

1. **`sync-backend.md` §5 says delete-account is a "double-confirm patterned
   on G9"; `household-lifecycle.md` §3.3 says ONE confirm shape for all three
   exits.** Both are honoured, on different axes (decision D-L6 below):
   delete-account gets §5's second confirmation IN ADDITION TO §3.3's shared
   sheet. §3.3's requirement is about the SHAPE of the exit confirm — the
   consequences, then the unchecked "also delete this phone's copy" checkbox,
   then the action — and that shape is used unchanged for all three exits. §5
   adds a FINAL confirmation AFTER it, for the one exit that is irreversible.
   Leave and remove-a-member keep the single sheet. See **D-L6** for the full
   rationale; Task 22 implements it.
2. **§3.2 says `MemberService.deleteMember`'s `userId != null` guard "is
   replaced by this routing".** This plan performs the `remove_member` RPC
   *before* opening the drift transaction rather than inside it (see the last
   Global Constraint). The guards are consequently evaluated twice: once
   before the RPC, so a removal that local rules would refuse never reaches the
   server, and once inside the transaction, which is the atomic one.
   Behaviourally identical to the spec's intent; the ordering is now explicit.
3. **§3.3 places Leave and Delete account "beside the existing Disconnect
   row"**, which only exists while linked. This plan additionally shows
   **Delete account while signed in and UNLINKED**. An account can exist with
   no household link at all (signed in, never adopted/joined), and GDPR
   erasure must not require linking first. Leave stays linked-only, as
   specced.
4. **`leave_household()` is parameterless in §2.2.** The slices 1–3 plan
   already deviated to `leave_household(p_household_id uuid)` and recorded it;
   this plan consumes that signature. Not a new deviation, restated so the
   gateway's parameter is not read as an error.

## Judgement calls (resolved here, no decision needed)

- **All three RPCs go on `HouseholdGateway`, not `SyncTransport`.** Slice 3
  put the membership probe on `SyncTransport` because it runs inside the sync
  engine's pull path. These three are user-initiated actions invoked from
  widgets, which is precisely what `HouseholdGateway` exists for
  (`sync-backend.md` §7.2). Adding them there also gets `NoopHouseholdGateway`
  and `FakeHouseholdGateway` coverage for free.
- **"My own row" is `member.userId == currentAuthUser.id`, not "the acting
  member".** The acting member is a per-device display choice
  (`actingMemberProvider`); the claim is the thing the server rejects
  self-removal on. They usually coincide and must not be conflated.
- **The claimed-member count for D-L5's warning comes from LOCAL rows**
  (`members` where `userId != null and deletedAt is null`). It can be stale by
  up to one pull cycle, so the warning is best-effort; the server's cascade is
  authoritative either way (§2.4 recomputes it inside the RPC). This is
  acceptable because §3.1 G-A/G-B just made local claim state honest, and
  Leave is only ever offered while linked.
- **Leave and Delete account surface RPC failures with the existing
  `showAppSnackbar`**, matching `_SignedInTile._signOut`'s handling in the
  same file. The member edit sheet gets a real INLINE error instead, because
  §3.2 mandates one there specifically ("it needs a real inline error surface
  — unlike every other local action in this app").
- **Both exits clear `membershipRevoked` defensively.** A pull in flight
  during a leave could set slice 3's flag; the user who chose to leave should
  not then be told they were removed. One extra call, documented at the call
  site.
- **Neither exit signs out on its own except delete-account**, where the
  session is dead by construction. See **D-L8**.

---

## Product decisions, resolved 2026-08-11

Three questions were genuinely open when this plan was drafted: user-visible,
underivable from D-L1…D-L5, and not settled by the spec. All three have since
been decided. They are recorded here as decisions, not proposals, and the
tasks below implement them.

### D-L6 — Delete account: the shared sheet, then one final confirmation

`sync-backend.md` §5 promised a "double-confirm patterned on G9" (the
`ResetDataTile` two-dialog chain). This plan's first draft recommended
dropping it in favour of `household-lifecycle.md` §3.3/D-L3's single shared
sheet. **That recommendation was OVERRULED**: account deletion deserves more
than the single sheet the two recoverable exits get.

**Decision: shared exit sheet FIRST (the choice, including the checkbox),
then ONE final confirmation dialog.** Two gates, not three, and the last one
sits immediately before the irreversible act.

Rationale, recorded so it is not re-litigated:

- The app already double-confirms *Reset app data*
  (`lib/features/settings/reset_flow.dart`, `settings.reset.confirm1` →
  `settings.reset.confirm2`), and that operation is **purely local and fully
  recoverable** — sign back in, re-sync, and the household comes back.
  `delete_account()` is **irreversible server-side erasure**. Guarding the
  weaker action more heavily than the stronger one is backwards.
- But a confirmation placed *before* the choice cannot describe the
  consequence. Asking the user to commit twice before showing them the one
  control that changes what actually happens — D-L3's "also delete this
  phone's copy" checkbox — produces two generic warnings that read alike and
  get clicked through. **Configure, then confirm** keeps the same rhythm as
  the reset flow (which is confirm → confirm only because it has nothing to
  configure) while making the final gate specific.
- Because the sheet has already run, the final dialog's copy is **accurate**:
  it states what is about to happen *including the checkbox outcome*, so the
  two cases read differently — "your account and email are erased from the
  server; this phone keeps its copy" versus "…and this phone's copy is
  deleted too; the app starts fresh". Confirming the specific thing you just
  configured is a materially stronger safeguard than a second identical
  warning asked in advance.

Two boundaries on this decision:

- **Delete account ONLY.** Leave and remove-a-member keep the single shared
  sheet: both are recoverable (rejoin with an invite, re-invite the person),
  so an extra step there is friction with no safety benefit.
- **D-L3's checkbox is NOT the confirmation and does not move.** It stays
  exactly where §3.3 put it, on the shared sheet, unchecked by default. It
  answers a different question — *what happens to this device* — and it is
  now the INPUT to the final dialog's copy rather than a substitute for it.

The order the user experiences: row tap → shared exit sheet (consequences,
unchecked checkbox, action) → final confirmation naming the exact outcome →
the RPC. Cancelling at either gate does nothing at all.

### D-L7 — The delete-account flow points at the JSON export first (as recommended)

GDPR erasure and data portability are neighbours, and the app already ships an
export (`lib/features/settings/export_row.dart`).

- **A. One line of copy** in the confirm body naming Settings → Data →
  Export. No navigation, no new control.
- **B. An "Export first" button inside the sheet** that runs the export flow
  and returns.
- **C. Say nothing.**

**Decided: A.** It costs one clause in a string that is being written
anyway, and B would need the shared sheet to grow a slot for a caller-supplied
action — a change to slice 2's widget, which slices 3–6 all share. Under D-L6
the sentence lives on the **final dialog**, not the sheet: that is the last
thing read before the point of no return, which is exactly where "keep a copy
first" is still actionable.

### D-L8 — After leaving a household, the device stays signed in (as recommended)

- **A. Stay signed in, just unlinked.** The Account section immediately offers
  Reconnect/Adopt/Join, so joining a different household — or the same one
  with a fresh invite — is one tap away. Delete account also stays reachable.
- **B. Also sign out.** Cleaner "I'm done" feeling; costs the user a whole
  magic-link round trip to do anything online again.

**Decided: A.** Leaving a household is not leaving the app, and §2.2
deliberately keeps the profile claimable so returning is a supported path.
This differs from delete-account, where sign-out is forced because the session
is invalid the instant the auth row is gone — that asymmetry is intentional.
Task 17's `HouseholdExitService.leaveHousehold` therefore never calls
`auth.signOut()`, and a test pins that.

---

## File map

**New:**

| Path | What |
| --- | --- |
| `lib/application/household_exit_service.dart` | `HouseholdExitService` — leave + delete-account orchestration (Task 21) |
| `test/application/household_exit_service_test.dart` | Its unit tests (Task 21) |
| `test/features/settings/account_exit_rows_test.dart` | Widget tests for the Leave / Delete account rows (Tasks 18, 22) |
| `supabase/functions/delete-user/index.ts` | **NOT implemented** — Appendix A's regression fallback only |

**Modified:**

| Path | What |
| --- | --- |
| `lib/application/household_gateway.dart` | `removeMember`, `leaveHousehold`, `deleteAccount` on the interface, `NoopHouseholdGateway`, `SupabaseHouseholdGateway` |
| `lib/application/member_service.dart` | Claim-state routing replacing the claimed guard; `ClaimedMemberRemovalFailure` |
| `lib/app/providers.dart` | `memberServiceProvider` gains the gateway; new `householdExitServiceProvider`, `claimedMemberCountProvider` |
| `lib/features/settings/member_edit_sheet.dart` | `_canDelete` / `_deleteBlockedReason` split by claim state; inline removal error |
| `lib/features/settings/member_delete_dialog.dart` | `claimed` variant of the body copy |
| `lib/features/settings/account_section.dart` | `_LeaveRow`, `_DeleteAccountRow` |
| `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb` | All new strings |
| `test/features/settings/fake_household_gateway.dart` | The three new methods + call records + error hooks |
| `test/features/settings/fake_auth_gateway.dart` | `signOutError` hook (Task 21) |
| `test/application/member_service_test.dart` | The claimed-member guard test becomes a routing test |
| `supabase/migrations/20260808120000_membership_exit.sql` | **Unchanged** — slice 1 / commit `f184f4a` finished it; Appendix A only |
| `supabase/tests/002_membership_exit_test.sql` | **Unchanged** — Appendix A only |

---

## Slice 4 — Remove a claimed member (F10, §3.2)

Today `MemberService.deleteMember` (`lib/application/member_service.dart:79-82`)
throws outright for a claimed member, and `_canDelete`
(`lib/features/settings/member_edit_sheet.dart:79-86`) hides the button. §3.2
replaces that flat refusal with a split by claim state.

**Do not ship slice 4 before slice 3 is in.** Removing a claimed member is
exactly the operation that produces the §0.1 trap on the removed person's
device; slice 3's notice is what makes it honest.

### Task 12: `removeMember` on the gateway

**Files:**
- Modify: `lib/application/household_gateway.dart`
- Modify: `test/features/settings/fake_household_gateway.dart`

**Interfaces:**
- Consumes: `public.remove_member(p_member_id uuid)` (slice 1 Task 4).
- Produces: `HouseholdGateway.removeMember(String memberId) → Future<void>`, implemented by `NoopHouseholdGateway` (throws), `SupabaseHouseholdGateway` (the RPC) and `FakeHouseholdGateway` (records + optional error).

- [ ] **Step 1: Add the fake's side first**

In `test/features/settings/fake_household_gateway.dart`, add the fields next
to the existing `*Calls` / `*Error` pairs:

```dart
  /// Every [removeMember] call's member id, in call order.
  final List<String> removeMemberCalls = [];

  /// Set to make the next [removeMember] call throw this instead of
  /// succeeding -- the claimed-removal failure surface (spec
  /// `docs/specs/household-lifecycle.md` §3.2) is the one place in this app
  /// a failed action must be shown inline, so tests need to force it.
  Exception? removeMemberError;
```

and the method next to `claimMember`:

```dart
  @override
  Future<void> removeMember(String memberId) async {
    removeMemberCalls.add(memberId);
    final error = removeMemberError;
    if (error != null) {
      throw error;
    }
  }
```

- [ ] **Step 2: Run to verify it fails**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter analyze --fatal-infos
```

Expected: FAIL — `removeMember` isn't a member of `HouseholdGateway`, so the
`@override` is invalid.

- [ ] **Step 3: Add it to the interface and both real implementations**

In `lib/application/household_gateway.dart`, in `abstract class
HouseholdGateway`, after `joinAsNewMember`:

```dart
  /// RPC `remove_member` (spec `docs/specs/household-lifecycle.md` §2.2,
  /// F10): unclaims AND soft-deletes another member's profile server-side.
  ///
  /// Any member may remove any other (D-L2 -- the household is flat by D1;
  /// no role is consulted). The server REJECTS the caller's own member row,
  /// pointing at `leave_household` instead, so this is never the way to
  /// leave. Idempotent on an already-removed row, so a retry after a
  /// partial failure is safe.
  Future<void> removeMember(String memberId);
```

In `NoopHouseholdGateway`:

```dart
  @override
  Future<void> removeMember(String memberId) => _unreachable();
```

In `SupabaseHouseholdGateway`, next to `claimMember`:

```dart
  @override
  Future<void> removeMember(String memberId) async {
    await _client.rpc<dynamic>(
      'remove_member',
      params: {'p_member_id': memberId},
    );
  }
```

- [ ] **Step 4: Run analyze to verify it passes**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter analyze --fatal-infos
```

Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/application/household_gateway.dart test/features/settings/fake_household_gateway.dart
git commit -m "Add removeMember to HouseholdGateway (spec §2.2, F10)"
```

---

### Task 13: `MemberService.deleteMember` routes by claim state

**Files:**
- Modify: `lib/application/member_service.dart`
- Modify: `lib/app/providers.dart` (`memberServiceProvider`)
- Modify: `test/application/member_service_test.dart`

**Interfaces:**
- Consumes: `HouseholdGateway.removeMember` (Task 12).
- Produces: `MemberService({required database, required chores, required gateway, clock})` — **the `gateway` parameter is new and every construction site must pass it**; `ClaimedMemberRemovalFailure` (exported from the same library). `deleteMember`'s signature is unchanged.

- [ ] **Step 1: Rewrite the claimed-member guard test as a routing test**

In `test/application/member_service_test.dart`, the `setUp` gains a fake and
`MemberService` gains the parameter:

```dart
import '../features/settings/fake_household_gateway.dart';
```

```dart
  late FakeHouseholdGateway gateway;
```

```dart
    gateway = FakeHouseholdGateway();
    memberService = MemberService(
      database: db,
      chores: chores,
      gateway: gateway,
      clock: Clock.fixed(DateTime(2026, 7, 24, 9)),
    );
```

Then REPLACE the existing test named
`'guard: throws for a claimed member (userId != null), changing nothing'`
(around line 152) with these three:

```dart
  test(
    'claimed target: calls remove_member FIRST, then runs the same local '
    'referential cleanup (spec docs/specs/household-lifecycle.md §3.2)',
    () async {
      final anna = await households.addMember(
        household.id,
        name: 'Anna',
        color: 1,
      );
      await (db.update(
        db.members,
      )..where((tbl) => tbl.id.equals(anna.id))).write(
        const MembersCompanion(userId: Value('server-user-1')),
      );

      await memberService.deleteMember(anna.id);

      expect(gateway.removeMemberCalls, [anna.id]);
      final after = await (db.select(
        db.members,
      )..where((tbl) => tbl.id.equals(anna.id))).getSingle();
      expect(after.deletedAt, isNotNull);
      expect(
        after.syncDirty,
        isTrue,
        reason:
            'the local soft-delete still pushes deleted_at -- a harmless '
            'no-op convergence on a row the server already soft-deleted '
            '(§3.2), so the engine needs no special case',
      );
    },
  );

  test(
    'claimed target whose RPC fails: throws ClaimedMemberRemovalFailure and '
    'changes NOTHING locally -- the member stays active',
    () async {
      final anna = await households.addMember(
        household.id,
        name: 'Anna',
        color: 1,
      );
      await (db.update(
        db.members,
      )..where((tbl) => tbl.id.equals(anna.id))).write(
        const MembersCompanion(userId: Value('server-user-1')),
      );
      gateway.removeMemberError = Exception('offline');

      await expectLater(
        memberService.deleteMember(anna.id),
        throwsA(isA<ClaimedMemberRemovalFailure>()),
      );

      final after = await (db.select(
        db.members,
      )..where((tbl) => tbl.id.equals(anna.id))).getSingle();
      expect(after.deletedAt, isNull);
    },
  );

  test(
    'unclaimed target: purely local, the RPC is never called',
    () async {
      final anna = await households.addMember(
        household.id,
        name: 'Anna',
        color: 1,
      );

      await memberService.deleteMember(anna.id);

      expect(gateway.removeMemberCalls, isEmpty);
      final after = await (db.select(
        db.members,
      )..where((tbl) => tbl.id.equals(anna.id))).getSingle();
      expect(after.deletedAt, isNotNull);
    },
  );

  test(
    'the last-member guard is checked BEFORE the RPC, so a refused removal '
    'never reaches the server',
    () async {
      final me = await (db.select(
        db.members,
      )..where((tbl) => tbl.householdId.equals(household.id))).getSingle();
      await (db.update(
        db.members,
      )..where((tbl) => tbl.id.equals(me.id))).write(
        const MembersCompanion(userId: Value('server-user-1')),
      );

      await expectLater(
        memberService.deleteMember(me.id),
        throwsA(isA<StateError>()),
      );
      expect(gateway.removeMemberCalls, isEmpty);
    },
  );
```

- [ ] **Step 2: Run to verify it fails**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/application/member_service_test.dart
```

Expected: FAIL to compile — `MemberService` has no `gateway` parameter and
`ClaimedMemberRemovalFailure` does not exist.

- [ ] **Step 3: Implement the routing**

In `lib/application/member_service.dart`, add the import and the exception,
above `class MemberService`:

```dart
import 'package:chore_app/application/household_gateway.dart';
```

```dart
/// Thrown by [MemberService.deleteMember] when the server-side removal of a
/// CLAIMED member failed (spec `docs/specs/household-lifecycle.md` §3.2).
///
/// This is the one action in this app whose failure must be shown to the
/// user inline rather than swallowed into a silent retry
/// (`docs/specs/sync-backend.md` §8.3): it needs the network, it changed
/// nothing, and the person the user was trying to remove is still in the
/// household. Nothing local has been written when this is thrown.
class ClaimedMemberRemovalFailure implements Exception {
  /// Wraps the underlying transport/RPC [cause].
  const ClaimedMemberRemovalFailure(this.cause);

  /// The error the gateway threw.
  final Object cause;

  @override
  String toString() => 'ClaimedMemberRemovalFailure($cause)';
}
```

Add the field and constructor parameter:

```dart
  MemberService({
    required this.database,
    required this.chores,
    required this.gateway,
    this.clock = const Clock(),
  });
```

```dart
  /// The Supabase seam used to remove a CLAIMED member server-side (spec
  /// §3.2). Never touched for an unclaimed profile, which stays a purely
  /// local operation -- so a local-only household never reaches the network
  /// even though this dependency is always present.
  final HouseholdGateway gateway;
```

Now change `deleteMember`. Everything up to and including the last-member
guard moves OUT of the transaction (it is a read-only pre-check), the RPC runs
between the two, and the transaction keeps its own re-checked copies of both
guards:

```dart
  /// Soft-deletes the member [memberId].
  ///
  /// Routing by claim state (spec `docs/specs/household-lifecycle.md`
  /// §3.2), which replaced the old flat refusal of any claimed member:
  ///
  /// - **unclaimed** (`userId == null`) -- purely local, exactly as before;
  /// - **claimed** -- `remove_member` on the server FIRST (which unclaims
  ///   and soft-deletes the profile there), then the identical local
  ///   cleanup. A failed RPC throws [ClaimedMemberRemovalFailure] with
  ///   nothing written locally.
  ///
  /// Removing one's OWN row is not this method's job and is rejected by the
  /// server (§2.2); the UI hides the action and points at Leave instead
  /// (`lib/features/settings/member_edit_sheet.dart`).
  ///
  /// The two guards below (member exists and is active; the household keeps
  /// at least one active member) are evaluated TWICE on the claimed path:
  /// once here, before the RPC, so a removal the local rules refuse never
  /// reaches the server; once inside the transaction, which is the atomic
  /// one. The RPC deliberately runs OUTSIDE the transaction -- a network
  /// round trip inside one holds drift's write lock and cannot be rolled
  /// back anyway.
  ///
  /// [The existing steps 2-4 doc text stays exactly as it is.]
  Future<void> deleteMember(String memberId) async {
    final member = await _requireRemovable(memberId);
    if (member.userId != null) {
      try {
        await gateway.removeMember(memberId);
      } on Exception catch (error) {
        throw ClaimedMemberRemovalFailure(error);
      }
    }
    await database.transaction(() async {
      await _requireRemovable(memberId);
      // ... the existing body from `final activeChores = ...` onward,
      // unchanged, minus the two guards now performed by _requireRemovable.
    });
  }

  /// Reads [memberId] and re-asserts both removal guards, throwing
  /// [StateError] (changing nothing) when either fails. Called once before
  /// the RPC and once inside the transaction -- see [deleteMember].
  Future<Member> _requireRemovable(String memberId) async {
    final member = await (database.select(
      database.members,
    )..where((tbl) => tbl.id.equals(memberId))).getSingleOrNull();
    if (member == null || member.deletedAt != null) {
      throw StateError('No active member with id $memberId');
    }
    final activeMembers =
        await (database.select(database.members)..where(
              (tbl) =>
                  tbl.householdId.equals(member.householdId) &
                  tbl.deletedAt.isNull(),
            ))
            .get();
    if (activeMembers.length <= 1) {
      throw StateError(
        'Cannot delete member $memberId: it is the last remaining '
        'member of household ${member.householdId}',
      );
    }
    return member;
  }
```

The old `if (member.userId != null) throw StateError(...)` block is **deleted**
— that is the whole point of the slice.

- [ ] **Step 4: Wire the provider**

In `lib/app/providers.dart`, `memberServiceProvider` (around line 457):

```dart
final memberServiceProvider = Provider<MemberService>((ref) {
  return MemberService(
    database: ref.watch(appDatabaseProvider),
    chores: ref.watch(choreRepositoryProvider),
    // Only ever used for a CLAIMED target (spec §3.2). Under
    // NoopHouseholdGateway (Supabase unconfigured) a claimed member cannot
    // exist in the first place -- nothing ever populated `user_id` -- so
    // the unreachable-throw is correct rather than a hazard.
    gateway: ref.watch(householdGatewayProvider),
    clock: ref.watch(clockProvider),
  );
});
```

- [ ] **Step 5: Run to verify it passes**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/application/member_service_test.dart
```

Expected: PASS, all tests in the file.

- [ ] **Step 6: Commit**

```bash
git add lib/application/member_service.dart lib/app/providers.dart test/application/member_service_test.dart
git commit -m "Route member removal by claim state (spec §3.2, F10)"
```

---

### Task 14: The member edit sheet stops hiding Delete for claimed members

**Files:**
- Modify: `lib/features/settings/member_edit_sheet.dart`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`
- Modify: `test/features/settings/members_screen_test.dart`

**Interfaces:**
- Consumes: `currentAuthUserProvider`, `settingsProvider`, `membersProvider`.
- Produces: no new symbol — `_canDelete` and `_deleteBlockedReason` change meaning.

The new rule, in one table (`me` = the member whose `userId` equals the
signed-in auth user's id):

| Target | Delete shown? | Blocked reason |
| --- | --- | --- |
| last active member | no | `memberEditDeleteBlockedLastMember` (unchanged) |
| own claimed row | no | `memberEditDeleteBlockedSelf` (new — points at Leave) |
| unclaimed | yes | — |
| claimed, linked + signed in | **yes (new)** | — |
| claimed, unlinked or signed out | no | `memberEditDeleteBlockedOffline` (new) |

- [ ] **Step 1: Add the l10n strings**

In `lib/l10n/app_en.arb`, next to the existing `memberEditDeleteBlocked*`
keys:

```json
  "memberEditDeleteBlockedSelf": "This is your own profile. To leave the household yourself, use “Leave the household” in Settings → Account.",
  "@memberEditDeleteBlockedSelf": {
    "description": "Replaces the Delete button in the member edit sheet when the member being edited is the signed-in user's own claimed profile (spec docs/specs/household-lifecycle.md §3.2). Mirrors the server's self-removal rejection and points at the right action instead."
  },
  "memberEditDeleteBlockedOffline": "This profile is used on someone else's phone. Sign in and connect to the online household to remove it.",
  "@memberEditDeleteBlockedOffline": {
    "description": "Replaces the Delete button when the target is claimed but this device is signed out or unlinked, so the remove_member call cannot be made (spec §3.2)."
  },
```

`memberEditDeleteBlockedClaimed` is now **unused** — delete both it and its
`@` metadata entry from both arb files, in this task, rather than leaving a
stale string behind.

In `lib/l10n/app_de.arb` (du-form):

```json
  "memberEditDeleteBlockedSelf": "Das ist dein eigenes Profil. Wenn du selbst den Haushalt verlassen willst, nutze „Haushalt verlassen“ unter Einstellungen → Konto.",
  "memberEditDeleteBlockedOffline": "Dieses Profil wird auf dem Handy einer anderen Person benutzt. Melde dich an und verbinde dich mit dem Online-Haushalt, um es zu entfernen.",
```

Regenerate:

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter gen-l10n
```

- [ ] **Step 2: Write the failing tests**

Append inside the existing `main()` of
`test/features/settings/members_screen_test.dart` (it already imports
`FakeAuthGateway`, `FakeHouseholdGateway`, `SettingsRepository` and
`openManageMembers`):

```dart
  /// Seeds a second member claimed by [userId], so the sheet under test is
  /// looking at somebody else's claimed profile.
  Future<Member> claimedMember(
    AppDatabase database, {
    required String name,
    required String userId,
  }) async {
    final householdId = await currentHouseholdId(database);
    final member = await HouseholdRepository(
      database,
    ).addMember(householdId, name: name, color: 2);
    await (database.update(
      database.members,
    )..where((tbl) => tbl.id.equals(member.id))).write(
      MembersCompanion(userId: Value(userId)),
    );
    return member;
  }

  testChoreApp(
    'claimed target, linked and signed in: Delete is shown (spec '
    'docs/specs/household-lifecycle.md §3.2, D-L2 -- no role gate)',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(currentUser: const AuthUser(id: 'me', email: 'me@x.y')),
      ),
      householdGatewayProvider.overrideWithValue(FakeHouseholdGateway()),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final anna = await claimedMember(
        database,
        name: 'Anna',
        userId: 'anna-auth',
      );
      await SettingsRepository(database).setSyncLinked(
        householdId: await currentHouseholdId(database),
        linkedAt: DateTime.utc(2026),
      );

      await openManageMembers(tester);
      await tester.tap(find.bySemanticsIdentifier('members.row.${anna.id}'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('members.edit.delete'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('members.edit.deleteBlockedReason'),
        findsNothing,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    "own claimed row: Delete stays hidden and the reason points at Leave "
    '(mirrors the server rejecting self-removal, §2.2)',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(currentUser: const AuthUser(id: 'me', email: 'me@x.y')),
      ),
      householdGatewayProvider.overrideWithValue(FakeHouseholdGateway()),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await claimedMember(database, name: 'Anna', userId: 'anna-auth');
      final me = await soleBootstrapMember(database);
      await (database.update(
        database.members,
      )..where((tbl) => tbl.id.equals(me.id))).write(
        const MembersCompanion(userId: Value('me')),
      );
      await SettingsRepository(database).setSyncLinked(
        householdId: await currentHouseholdId(database),
        linkedAt: DateTime.utc(2026),
      );

      await openManageMembers(tester);
      await tester.tap(find.bySemanticsIdentifier('members.row.${me.id}'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('members.edit.delete'), findsNothing);
      expect(find.textContaining('your own profile'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'claimed target while unlinked: Delete hidden, reason explains the '
    'connection requirement rather than a permission',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(FakeAuthGateway()),
      householdGatewayProvider.overrideWithValue(FakeHouseholdGateway()),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final anna = await claimedMember(
        database,
        name: 'Anna',
        userId: 'anna-auth',
      );

      await openManageMembers(tester);
      await tester.tap(find.bySemanticsIdentifier('members.row.${anna.id}'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('members.edit.delete'), findsNothing);
      expect(find.textContaining('Sign in and connect'), findsOneWidget);

      handle.dispose();
    },
  );
```

`soleBootstrapMember` already exists at the top of that file. `AuthUser`'s
constructor shape is in `lib/application/auth_gateway.dart` — match it
(`const AuthUser(id: ..., email: ...)`); if the real one differs, use the same
form the existing tests in `account_section_test.dart` use.

- [ ] **Step 3: Run to verify it fails**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/features/settings/members_screen_test.dart
```

Expected: FAIL — Delete is still hidden for a claimed target, and the new
copy does not exist.

- [ ] **Step 4: Implement**

In `lib/features/settings/member_edit_sheet.dart`, replace `_canDelete` and
`_deleteBlockedReason`:

```dart
  /// The signed-in account's own claimed member row, if the member being
  /// edited IS it. Self-removal is the server's rejection (§2.2) and the
  /// UI's Leave action, never Delete.
  bool get _isOwnClaimedRow {
    final member = widget.member;
    final authUserId = ref.watch(currentAuthUserProvider).valueOrNull?.id;
    return member != null &&
        authUserId != null &&
        member.userId == authUserId;
  }

  /// Whether removing a CLAIMED member is possible right now: the RPC needs
  /// both a signed-in session and a linked household (spec §3.2).
  bool get _canRemoveClaimed {
    final signedIn = ref.watch(currentAuthUserProvider).valueOrNull != null;
    final linked =
        ref.watch(settingsProvider).valueOrNull?.syncHouseholdId != null;
    return signedIn && linked;
  }

  /// Whether the delete action should be shown at all (spec: HIDDEN, not
  /// disabled).
  ///
  /// Claim state no longer blocks outright (spec
  /// `docs/specs/household-lifecycle.md` §3.2, F10): a claimed profile IS
  /// removable, via the `remove_member` RPC, by ANY member (D-L2 -- there
  /// is no role gate and none is coming). What still blocks: the
  /// household's last active member, the caller's own claimed row, and a
  /// claimed target while this device cannot reach the server.
  bool get _canDelete {
    final member = widget.member;
    if (member == null) {
      return false;
    }
    final activeMembers = ref.watch(membersProvider).value ?? const <Member>[];
    if (activeMembers.length <= 1) {
      return false;
    }
    if (member.userId == null) {
      return true;
    }
    return !_isOwnClaimedRow && _canRemoveClaimed;
  }
```

and the reason:

```dart
  String? _deleteBlockedReason(
    AppLocalizations l10n, {
    required bool canDelete,
  }) {
    final member = widget.member;
    if (member == null || canDelete) {
      return null;
    }
    final activeMembers = ref.watch(membersProvider).value ?? const <Member>[];
    if (activeMembers.length <= 1) {
      return l10n.memberEditDeleteBlockedLastMember;
    }
    if (_isOwnClaimedRow) {
      return l10n.memberEditDeleteBlockedSelf;
    }
    return l10n.memberEditDeleteBlockedOffline;
  }
```

Note the ordering change: the last-member reason is now checked FIRST, since
"you are the only member left" outranks "this is your own profile" when both
are true (a one-member household whose sole member is you). Keep the doc
comment's "worded as an accident prevented, not a permission" paragraph — it
is still the rule, and `memberEditDeleteBlockedOffline` obeys it.

- [ ] **Step 5: Run to verify it passes**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/features/settings/members_screen_test.dart
```

Expected: PASS, all tests in the file (including the pre-existing deletion
ones, which use unclaimed members and are unaffected).

- [ ] **Step 6: Commit**

```bash
git add lib/features/settings/member_edit_sheet.dart lib/l10n/ test/features/settings/members_screen_test.dart
git commit -m "Show Delete for a claimed member when removal is possible (spec §3.2)"
```

---

### Task 15: Claimed-removal copy and the inline failure surface

**Files:**
- Modify: `lib/features/settings/member_delete_dialog.dart`
- Modify: `lib/features/settings/member_edit_sheet.dart`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`
- Modify: `test/features/settings/members_screen_test.dart`

**Interfaces:**
- Consumes: `ClaimedMemberRemovalFailure` (Task 13).
- Produces: `showMemberDeleteDialog(context, {required String memberName, required bool claimed})` — **the `claimed` parameter is new**; the sheet gains an inline error region with semantic id `members.remove.error`.

- [ ] **Step 1: Add the l10n strings**

In `lib/l10n/app_en.arb`:

```json
  "memberRemoveDialogBodyClaimed": "{memberName} uses this household on their own phone. Removing them stops that phone from syncing — it keeps everything it already has, as its own local copy. Their profile and history stay here with the household: rotation chores drop them from the turn order, chores fixed to them open up to anyone, and anything currently assigned to them becomes unassigned. Past history — who completed what — stays unchanged.",
  "@memberRemoveDialogBodyClaimed": {
    "description": "Body of the member-removal confirm dialog for a CLAIMED member (spec docs/specs/household-lifecycle.md §3.2). Used instead of memberDeleteDialogBody; adds what happens on the removed person's own phone, which is the only part they cannot see from here.",
    "placeholders": { "memberName": { "type": "String" } }
  },
  "memberRemoveError": "Couldn't remove {memberName}. This needs a connection to the online household — nothing was changed. Try again.",
  "@memberRemoveError": {
    "description": "Inline error shown in the member edit sheet when the remove_member call failed (spec §3.2 -- the one action in this app whose failure is surfaced rather than silently retried).",
    "placeholders": { "memberName": { "type": "String" } }
  },
```

In `lib/l10n/app_de.arb` (du-form):

```json
  "memberRemoveDialogBodyClaimed": "{memberName} nutzt diesen Haushalt auf einem eigenen Handy. Wenn du die Person entfernst, synchronisiert dieses Handy nicht mehr — es behält alles, was es schon hat, als eigene lokale Kopie. Profil und Verlauf bleiben hier im Haushalt: In Wechsel-Aufgaben fällt die Person aus der Reihenfolge, fest zugewiesene Aufgaben stehen wieder allen offen, und alles, was ihr gerade zugewiesen ist, wird frei. Der bisherige Verlauf — wer was erledigt hat — bleibt unverändert.",
  "memberRemoveError": "{memberName} konnte nicht entfernt werden. Dafür braucht die App eine Verbindung zum Online-Haushalt — es wurde nichts geändert. Versuch es noch mal.",
```

Regenerate:

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter gen-l10n
```

- [ ] **Step 2: Write the failing tests**

Append to `test/features/settings/members_screen_test.dart`:

```dart
  testChoreApp(
    'removing a claimed member: the confirm names the consequence for their '
    'phone, and confirming calls remove_member then cleans up locally',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(currentUser: const AuthUser(id: 'me', email: 'me@x.y')),
      ),
      householdGatewayProvider.overrideWithValue(gatewayForRemoval),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final anna = await claimedMember(
        database,
        name: 'Anna',
        userId: 'anna-auth',
      );
      await SettingsRepository(database).setSyncLinked(
        householdId: await currentHouseholdId(database),
        linkedAt: DateTime.utc(2026),
      );

      await openManageMembers(tester);
      await tester.tap(find.bySemanticsIdentifier('members.row.${anna.id}'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('members.edit.delete'));
      await tester.pumpAndSettle();

      expect(find.textContaining('their own phone'), findsOneWidget);

      await tester.tap(
        find.bySemanticsIdentifier('members.edit.delete.confirm'),
      );
      await tester.pumpAndSettle();

      expect(gatewayForRemoval.removeMemberCalls, [anna.id]);
      expect(find.text('Anna'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'a failed removal is shown inline and changes nothing (spec §3.2)',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(currentUser: const AuthUser(id: 'me', email: 'me@x.y')),
      ),
      householdGatewayProvider.overrideWithValue(failingGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final anna = await claimedMember(
        database,
        name: 'Anna',
        userId: 'anna-auth',
      );
      await SettingsRepository(database).setSyncLinked(
        householdId: await currentHouseholdId(database),
        linkedAt: DateTime.utc(2026),
      );

      await openManageMembers(tester);
      await tester.tap(find.bySemanticsIdentifier('members.row.${anna.id}'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('members.edit.delete'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('members.edit.delete.confirm'),
      );
      await tester.pumpAndSettle();

      // The sheet stays open, says why, and Anna is still a member.
      expect(find.bySemanticsIdentifier('members.remove.error'), findsOneWidget);
      final after = await (database.select(
        database.members,
      )..where((tbl) => tbl.id.equals(anna.id))).getSingle();
      expect(after.deletedAt, isNull);

      handle.dispose();
    },
  );
```

Declare the two gateways above the tests, in `main()`'s scope, so the
overrides and the assertions see the same instance:

```dart
  final gatewayForRemoval = FakeHouseholdGateway();
  final failingGateway = FakeHouseholdGateway()
    ..removeMemberError = Exception('offline');
```

- [ ] **Step 3: Run to verify it fails**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/features/settings/members_screen_test.dart
```

Expected: FAIL — the claimed copy isn't shown and the failure crashes the
test instead of rendering an error.

- [ ] **Step 4: Add the `claimed` branch to the dialog**

In `lib/features/settings/member_delete_dialog.dart`, add the parameter and
branch the body (the title is unchanged — "Delete {memberName}?" is right in
both cases):

```dart
/// Shows a confirmation dialog for deleting the member named [memberName],
/// resolving to whether the user confirmed (defaults to `false` if
/// dismissed).
///
/// [claimed] picks the body: an unclaimed profile gets the original
/// referential-consequences copy, while a CLAIMED profile gets the variant
/// that also states what happens on that person's own phone (spec
/// `docs/specs/household-lifecycle.md` §3.2) -- the one consequence the
/// person tapping Delete cannot see from here.
Future<bool> showMemberDeleteDialog(
  BuildContext context, {
  required String memberName,
  required bool claimed,
}) async {
```

```dart
        content: Text(
          claimed
              ? l10n.memberRemoveDialogBodyClaimed(memberName)
              : l10n.memberDeleteDialogBody(memberName),
        ),
```

- [ ] **Step 5: Add the inline error to the sheet**

In `lib/features/settings/member_edit_sheet.dart`'s state class, add:

```dart
  /// The localized message for a failed CLAIMED-member removal (spec §3.2),
  /// or `null` when nothing has failed. Cleared on every new attempt.
  String? _removalError;

  /// True while the `remove_member` round trip is in flight -- the Delete
  /// button is disabled meanwhile so a double tap cannot fire two RPCs.
  bool _removing = false;
```

Render it immediately above the button `Row` (and below the blocked-reason
block), so it takes the same visual slot as the other explanation:

```dart
          if (_removalError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: semantic(
                'members.remove.error',
                child: Text(
                  _removalError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ),
```

and change the Delete button's `onPressed` to `_removing ? null : _delete`.

Replace `_delete`:

```dart
  Future<void> _delete() async {
    final existing = widget.member;
    if (existing == null) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final confirmed = await showMemberDeleteDialog(
      context,
      memberName: existing.name,
      claimed: existing.userId != null,
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() {
      _removing = true;
      _removalError = null;
    });
    try {
      await ref.read(memberServiceProvider).deleteMember(existing.id);
    } on ClaimedMemberRemovalFailure catch (_) {
      // The ONE inline error in this app (spec §3.2): the removal needs the
      // network, nothing was written, and the user must be told -- unlike
      // every local action here, and unlike sync-backend.md §8.3's
      // swallow-and-retry posture for background sync.
      if (mounted) {
        setState(() {
          _removing = false;
          _removalError = l10n.memberRemoveError(existing.name);
        });
      }
      return;
    }
    // Any OTHER throw stays uncaught: `_canDelete` already excludes every
    // locally-refusable case, so a StateError here is a genuine bug (or an
    // exceedingly rare cross-device race), exactly as before this slice.
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }
```

- [ ] **Step 6: Run to verify it passes**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/features/settings/members_screen_test.dart
```

Expected: PASS, all tests in the file.

- [ ] **Step 7: Analyze and commit**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter analyze --fatal-infos
git add lib/features/settings/ lib/l10n/ test/features/settings/members_screen_test.dart
git commit -m "Confirm and surface claimed-member removal inline (spec §3.2, F10)"
```

**Slice 4 is now complete.** A member can remove any other member, claimed or
not; the removed person's device shows slice 3's notice on its next pull.

---

## Slice 5 — Leave household (F9) + the cascade warning (§3.4, D-L5)

### Task 16: `leaveHousehold` on the gateway

**Files:**
- Modify: `lib/application/household_gateway.dart`
- Modify: `test/features/settings/fake_household_gateway.dart`

**Interfaces:**
- Consumes: `public.leave_household(p_household_id uuid)` (slice 1 Task 2, whose parameter is that plan's deviation 2).
- Produces: `HouseholdGateway.leaveHousehold(String householdId) → Future<void>` across all three implementations.

- [ ] **Step 1: Add the fake's side**

```dart
  /// Every [leaveHousehold] call's household id, in call order.
  final List<String> leaveHouseholdCalls = [];

  /// Set to make the next [leaveHousehold] call throw this instead of
  /// succeeding.
  Exception? leaveHouseholdError;
```

```dart
  @override
  Future<void> leaveHousehold(String householdId) async {
    leaveHouseholdCalls.add(householdId);
    final error = leaveHouseholdError;
    if (error != null) {
      throw error;
    }
  }
```

- [ ] **Step 2: Add it to the interface and both implementations**

```dart
  /// RPC `leave_household` (spec `docs/specs/household-lifecycle.md` §2.2,
  /// F9): unclaims the caller's own member row in [householdId] and NOTHING
  /// else -- the profile stays active, so the family keeps seeing the
  /// person and their history, and they can claim it again later through an
  /// invite.
  ///
  /// If that leaves the household with no claimed members at all, the
  /// server cascades it (§2.4, D-L5): the online household and its shared
  /// history are soft-deleted and its invite codes stop working. The Leave
  /// confirm must say so before calling this (§3.4).
  ///
  /// Takes the household id explicitly because `members.user_id` is UNIQUE
  /// *per household*, so an account may legitimately belong to several.
  Future<void> leaveHousehold(String householdId);
```

```dart
  @override
  Future<void> leaveHousehold(String householdId) => _unreachable();
```

```dart
  @override
  Future<void> leaveHousehold(String householdId) async {
    await _client.rpc<dynamic>(
      'leave_household',
      params: {'p_household_id': householdId},
    );
  }
```

- [ ] **Step 3: Analyze and commit**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter analyze --fatal-infos
git add lib/application/household_gateway.dart test/features/settings/fake_household_gateway.dart
git commit -m "Add leaveHousehold to HouseholdGateway (spec §2.2, F9)"
```

---

### Task 17: `HouseholdExitService.leaveHousehold`

**Files:**
- Create: `lib/application/household_exit_service.dart`
- Create: `test/application/household_exit_service_test.dart`
- Modify: `lib/app/providers.dart`

**Interfaces:**
- Consumes: `HouseholdGateway.leaveHousehold` (Task 16), `SettingsRepository.clearSyncLink()` (slice 2 Task 7 — which also nulls every local `members.userId`), `SettingsRepository.clearMembershipRevoked()` (slice 3 Task 10), `resetAppData` (`lib/application/data_reset.dart`).
- Produces: `HouseholdExitService`, `householdExitServiceProvider`, `claimedMemberCountProvider`. `deleteAccount` is added to the same class in Task 21.

- [ ] **Step 1: Write the failing tests**

Create `test/application/household_exit_service_test.dart`:

```dart
/// Service-level tests for the two account-scoped exits (spec
/// `docs/specs/household-lifecycle.md` §2.2, §3.3, D-L3): the server call
/// happens first, the device unlinks, and this phone's data survives unless
/// the caller explicitly asked for it to go.
library;

import 'package:chore_app/application/household_exit_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/settings/fake_auth_gateway.dart';
import '../features/settings/fake_household_gateway.dart';

void main() {
  late AppDatabase db;
  late FakeHouseholdGateway gateway;
  late FakeAuthGateway auth;
  late SettingsRepository settings;
  late HouseholdExitService service;
  late Household household;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    gateway = FakeHouseholdGateway();
    auth = FakeAuthGateway();
    settings = SettingsRepository(db);
    service = HouseholdExitService(
      gateway: gateway,
      auth: auth,
      settings: settings,
      database: db,
    );
    household = await HouseholdRepository(db).createLocalHousehold('Me');
    await settings.setSyncLinked(
      householdId: household.id,
      linkedAt: DateTime.utc(2026),
    );
  });

  tearDown(() => db.close());

  test(
    'leave, keeping this phone: calls the RPC, unlinks, and leaves every '
    'local row in place (D-L3 -- keeping is the default)',
    () async {
      await service.leaveHousehold(
        householdId: household.id,
        alsoDeleteLocalData: false,
      );

      expect(gateway.leaveHouseholdCalls, [household.id]);
      final row = await settings.ensureSettings();
      expect(row.syncHouseholdId, isNull);
      expect(await db.select(db.households).get(), hasLength(1));
      expect(await db.select(db.members).get(), hasLength(1));
    },
  );

  test(
    'leave with the opt-in checked: this phone is wiped as well',
    () async {
      await service.leaveHousehold(
        householdId: household.id,
        alsoDeleteLocalData: true,
      );

      expect(gateway.leaveHouseholdCalls, [household.id]);
      expect(await db.select(db.households).get(), isEmpty);
      expect(await db.select(db.members).get(), isEmpty);
    },
  );

  test(
    'a failed leave changes nothing locally -- the device stays linked, so '
    'a retry is a plain retry',
    () async {
      gateway.leaveHouseholdError = Exception('offline');

      await expectLater(
        service.leaveHousehold(
          householdId: household.id,
          alsoDeleteLocalData: false,
        ),
        throwsA(isA<Exception>()),
      );

      final row = await settings.ensureSettings();
      expect(row.syncHouseholdId, household.id);
      expect(await db.select(db.households).get(), hasLength(1));
    },
  );

  test(
    'leaving clears a revocation flag a racing pull may have set, so the '
    'user who chose to leave is never told they were removed (§3.5)',
    () async {
      await settings.setMembershipRevoked();

      await service.leaveHousehold(
        householdId: household.id,
        alsoDeleteLocalData: false,
      );

      final row = await settings.ensureSettings();
      expect(row.membershipRevoked, isFalse);
    },
  );

  test('leaving does NOT sign the account out (D-L8)', () async {
    auth.signIn(const AuthUser(id: 'me', email: 'me@x.y'));

    await service.leaveHousehold(
      householdId: household.id,
      alsoDeleteLocalData: false,
    );

    expect(auth.currentUser, isNotNull);
  });
}
```

`AuthUser`'s import comes from `package:chore_app/application/auth_gateway.dart` —
add it if the analyzer asks.

- [ ] **Step 2: Run to verify it fails**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/application/household_exit_service_test.dart
```

Expected: FAIL to compile — `household_exit_service.dart` does not exist.

- [ ] **Step 3: Implement the service**

Create `lib/application/household_exit_service.dart`:

```dart
/// The two account-scoped household exits (spec
/// `docs/specs/household-lifecycle.md` §2.2): leaving a household (F9) and
/// deleting the account (F11). Member removal (F10) is not here -- it acts
/// on somebody ELSE's row and belongs with the rest of the member
/// referential cleanup in `MemberService`.
///
/// Both exits share one shape, in this order:
///
/// 1. the server RPC, which is the authoritative part;
/// 2. this device's local link state (`clearSyncLink`, which also nulls
///    every local `members.userId` -- §3.1 G-A);
/// 3. optionally, and ONLY when the caller explicitly asked
///    (`alsoDeleteLocalData`, unchecked by default -- D-L3), `resetAppData`.
///
/// The server call goes FIRST on purpose: if it fails, nothing local has
/// changed and a retry is an ordinary retry rather than a repair.
library;

import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/application/data_reset.dart';
import 'package:chore_app/application/household_gateway.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';

/// Runs the leave-household and delete-account exits.
class HouseholdExitService {
  /// Creates the service.
  HouseholdExitService({
    required this.gateway,
    required this.auth,
    required this.settings,
    required this.database,
  });

  /// The Supabase seam the exit RPCs go through.
  final HouseholdGateway gateway;

  /// The auth seam -- used only by `deleteAccount`, whose session is dead
  /// the moment the auth row is gone.
  final AuthGateway auth;

  /// This device's link state.
  final SettingsRepository settings;

  /// The local database, for the opt-in [resetAppData].
  final AppDatabase database;

  /// Leaves [householdId] (spec §2.2, F9).
  ///
  /// The server unclaims this account's member row and keeps the profile
  /// active, so the family still sees the person and their history and the
  /// profile can be claimed again later through an invite. If this account
  /// was the LAST claimed member, the server also cascades the household
  /// (§2.4, D-L5) -- the caller is responsible for having said so in the
  /// confirm (§3.4); this method does not decide, it reports nothing back,
  /// and the cascade is recomputed server-side either way.
  ///
  /// Does NOT sign the account out: leaving a household is not leaving the
  /// app, and the Account section immediately offers reconnect/adopt/join.
  ///
  /// [alsoDeleteLocalData] is the D-L3 opt-in and is `false` in every
  /// default path. Callers must invalidate `settingsProvider` afterwards
  /// when it was `true` (the documented `resetAppData` contract).
  Future<void> leaveHousehold({
    required String householdId,
    required bool alsoDeleteLocalData,
  }) async {
    await gateway.leaveHousehold(householdId);
    await _finishLocally(alsoDeleteLocalData: alsoDeleteLocalData);
  }

  /// Shared local tail of both exits.
  Future<void> _finishLocally({required bool alsoDeleteLocalData}) async {
    // Defensive: a pull in flight while the user was reading the confirm
    // could have set slice 3's revocation flag (§3.5). Somebody who chose
    // to leave must not then be told they were removed.
    await settings.clearMembershipRevoked();
    await settings.clearSyncLink();
    if (alsoDeleteLocalData) {
      await resetAppData(database);
    }
  }
}
```

- [ ] **Step 4: Add the providers**

In `lib/app/providers.dart`, next to `householdLinkServiceProvider`:

```dart
/// The leave-household / delete-account service (spec
/// `docs/specs/household-lifecycle.md` §2.2), built on
/// [householdGatewayProvider], [authGatewayProvider],
/// [settingsRepositoryProvider] and [appDatabaseProvider].
final householdExitServiceProvider = Provider<HouseholdExitService>((ref) {
  return HouseholdExitService(
    gateway: ref.watch(householdGatewayProvider),
    auth: ref.watch(authGatewayProvider),
    settings: ref.watch(settingsRepositoryProvider),
    database: ref.watch(appDatabaseProvider),
  );
});

/// How many ACTIVE members of the current household are claimed by an
/// account -- the count the Leave confirm branches on (spec §3.4, D-L5).
///
/// Read from LOCAL rows, which §3.1's G-A/G-B fixes just made honest:
/// `members.userId` is populated by every pull and cleared on unlink. It
/// can still be up to one pull cycle stale, so the warning it drives is
/// best-effort -- the server recomputes the cascade condition inside the
/// RPC (§2.4) and is authoritative either way.
final claimedMemberCountProvider = Provider<int>((ref) {
  final members = ref.watch(membersProvider).value ?? const <Member>[];
  return members.where((member) => member.userId != null).length;
});
```

- [ ] **Step 5: Run to verify it passes**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/application/household_exit_service_test.dart
```

Expected: PASS, 5 tests.

- [ ] **Step 6: Commit**

```bash
git add lib/application/household_exit_service.dart lib/app/providers.dart test/application/household_exit_service_test.dart
git commit -m "Add HouseholdExitService.leaveHousehold (spec §2.2, F9)"
```

---

### Task 18: The Leave row, its confirm, and the cascade warning

**Files:**
- Modify: `lib/features/settings/account_section.dart`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`
- Create: `test/features/settings/account_exit_rows_test.dart`

**Interfaces:**
- Consumes: `showExitConfirmSheet` / `ExitConfirmResult` (slice 2 Task 9), `householdExitServiceProvider`, `claimedMemberCountProvider` (Task 17), `showAppSnackbar`.
- Produces: `_LeaveRow` in the Account section's linked branch, semantic ids `settings.account.leave` / `settings.account.leave.{deleteLocal,cancel,confirm}` (the last three come from the shared sheet's `semanticPrefix`).

- [ ] **Step 1: Add the l10n strings**

In `lib/l10n/app_en.arb`:

```json
  "settingsAccountLeave": "Leave the household",
  "@settingsAccountLeave": {
    "description": "Account-section row that leaves the online household (spec docs/specs/household-lifecycle.md §3.3, F9). Sits beside Disconnect, which is a different, purely local action."
  },
  "householdLeaveConfirmTitle": "Leave {householdName}?",
  "@householdLeaveConfirmTitle": {
    "description": "Title of the leave-household confirm sheet.",
    "placeholders": { "householdName": { "type": "String" } }
  },
  "householdLeaveConfirmBody": "Your profile stays with the household, so the others keep seeing you and everything you've done. This phone stops syncing. You can come back later with a new invite code.",
  "@householdLeaveConfirmBody": {
    "description": "Body of the leave-household confirm when other claimed members remain (spec §3.4)."
  },
  "householdLeaveConfirmBodyLastMember": "You're the last person here with an account. Leaving takes the online household with you: the shared copy and its history are removed from the server and any invite codes stop working. Everything on this phone is unaffected unless you tick the box below.",
  "@householdLeaveConfirmBodyLastMember": {
    "description": "Body of the leave-household confirm when the caller is the LAST claimed member (spec §3.4, D-L5): warns plainly, then cascades -- it is neither silent nor blocked."
  },
  "householdLeaveConfirmAction": "Leave",
  "@householdLeaveConfirmAction": {
    "description": "Confirm button of the leave-household sheet."
  },
  "householdLeaveError": "Couldn't leave the household. This needs a connection — nothing was changed. Try again.",
  "@householdLeaveError": {
    "description": "Snackbar shown when the leave_household call failed."
  },
```

In `lib/l10n/app_de.arb` (du-form):

```json
  "settingsAccountLeave": "Haushalt verlassen",
  "householdLeaveConfirmTitle": "{householdName} verlassen?",
  "householdLeaveConfirmBody": "Dein Profil bleibt im Haushalt, die anderen sehen dich und alles, was du erledigt hast, weiterhin. Dieses Handy synchronisiert nicht mehr. Du kannst später mit einem neuen Einladungscode zurückkommen.",
  "householdLeaveConfirmBodyLastMember": "Du bist die letzte Person hier mit einem Konto. Wenn du gehst, verschwindet der Online-Haushalt mit dir: Die geteilte Kopie und ihr Verlauf werden vom Server entfernt, und Einladungscodes funktionieren nicht mehr. Auf diesem Handy ändert sich nichts, außer du setzt unten das Häkchen.",
  "householdLeaveConfirmAction": "Verlassen",
  "householdLeaveError": "Der Haushalt konnte nicht verlassen werden. Dafür braucht die App eine Verbindung — es wurde nichts geändert. Versuch es noch mal.",
```

Regenerate:

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter gen-l10n
```

- [ ] **Step 2: Write the failing tests**

Create `test/features/settings/account_exit_rows_test.dart`:

```dart
/// Widget tests for the Account section's two exit rows (spec
/// `docs/specs/household-lifecycle.md` §3.3/§3.4, D-L3/D-L5): leaving a
/// household and deleting an account, both through the shared
/// keep-or-delete-this-phone confirm.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'fake_auth_gateway.dart';
import 'fake_household_gateway.dart';
import 'settings_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);
  const me = AuthUser(id: 'me', email: 'me@x.y');

  /// Links the seeded household and marks the bootstrap member claimed by
  /// [me], i.e. the ordinary signed-in-and-linked state.
  Future<String> linkAndClaim(AppDatabase database) async {
    final householdId = await currentHouseholdId(database);
    final member = await (database.select(
      database.members,
    )..where((tbl) => tbl.householdId.equals(householdId))).getSingle();
    await (database.update(
      database.members,
    )..where((tbl) => tbl.id.equals(member.id))).write(
      const MembersCompanion(userId: Value('me')),
    );
    await SettingsRepository(
      database,
    ).setSyncLinked(householdId: householdId, linkedAt: DateTime.utc(2026));
    return householdId;
  }

  testChoreApp(
    'linked + signed in: the Leave row is offered beside Disconnect; '
    'unlinked it is not (spec §3.3)',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(FakeAuthGateway(currentUser: me)),
      householdGatewayProvider.overrideWithValue(FakeHouseholdGateway()),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);
      expect(find.bySemanticsIdentifier('settings.account.leave'), findsNothing);

      await linkAndClaim(database);
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('settings.account.leave'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('settings.account.disconnect'),
        findsOneWidget,
        reason: 'Disconnect is a different, purely local action and stays',
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'leaving as the last claimed member warns that the online household '
    'goes too, then leaves anyway (D-L5: neither silent nor blocked)',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(FakeAuthGateway(currentUser: me)),
      householdGatewayProvider.overrideWithValue(leaveGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await linkAndClaim(database);

      await openSettingsTab(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.account.leave'));
      await tester.pumpAndSettle();

      expect(find.textContaining('last person here'), findsOneWidget);

      await tester.tap(
        find.bySemanticsIdentifier('settings.account.leave.confirm'),
      );
      await tester.pumpAndSettle();

      expect(leaveGateway.leaveHouseholdCalls, [householdId]);
      // D-L3 default: this phone keeps everything.
      expect(await database.select(database.households).get(), hasLength(1));
      final row = await SettingsRepository(database).ensureSettings();
      expect(row.syncHouseholdId, isNull);

      handle.dispose();
    },
  );

  testChoreApp(
    'with another claimed member present, the cascade warning is NOT shown',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(FakeAuthGateway(currentUser: me)),
      householdGatewayProvider.overrideWithValue(FakeHouseholdGateway()),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await linkAndClaim(database);
      final anna = await HouseholdRepository(
        database,
      ).addMember(householdId, name: 'Anna', color: 2);
      await (database.update(
        database.members,
      )..where((tbl) => tbl.id.equals(anna.id))).write(
        const MembersCompanion(userId: Value('anna-auth')),
      );

      await openSettingsTab(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.account.leave'));
      await tester.pumpAndSettle();

      expect(find.textContaining('last person here'), findsNothing);
      expect(find.textContaining('Your profile stays'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'ticking "also delete this phone\'s copy" wipes this device too (D-L3)',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(FakeAuthGateway(currentUser: me)),
      householdGatewayProvider.overrideWithValue(wipeGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await linkAndClaim(database);

      await openSettingsTab(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.account.leave'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.leave.deleteLocal'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.leave.confirm'),
      );
      await tester.pumpAndSettle();

      expect(await database.select(database.households).get(), isEmpty);

      handle.dispose();
    },
  );

  testChoreApp(
    'cancelling the leave confirm calls nothing and stays linked',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(FakeAuthGateway(currentUser: me)),
      householdGatewayProvider.overrideWithValue(cancelGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await linkAndClaim(database);

      await openSettingsTab(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.account.leave'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.leave.cancel'),
      );
      await tester.pumpAndSettle();

      expect(cancelGateway.leaveHouseholdCalls, isEmpty);
      final row = await SettingsRepository(database).ensureSettings();
      expect(row.syncHouseholdId, householdId);

      handle.dispose();
    },
  );
}
```

Declare the shared fakes at the top of `main()`, as in Task 15:

```dart
  final leaveGateway = FakeHouseholdGateway();
  final wipeGateway = FakeHouseholdGateway();
  final cancelGateway = FakeHouseholdGateway();
```

- [ ] **Step 3: Run to verify it fails**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/features/settings/account_exit_rows_test.dart
```

Expected: FAIL — `settings.account.leave` does not exist.

- [ ] **Step 4: Implement the row**

In `lib/features/settings/account_section.dart`, add `_LeaveRow` to the
signed-in + linked branch of `AccountSectionBody.build`, ABOVE
`_DisconnectRow` (leaving is the more consequential action and reads first;
Disconnect stays the quieter, local one):

```dart
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SignedInTile(user: user, householdName: householdName),
        _InviteRow(householdId: householdId),
        _LeaveRow(householdId: householdId, householdName: householdName),
        const _DisconnectRow(),
      ],
    );
```

and the widget itself, next to `_DisconnectRow`:

```dart
/// The 'Leave the household' action (spec
/// `docs/specs/household-lifecycle.md` §3.3, F9), shown only while signed in
/// AND linked -- the RPC needs both.
///
/// Deliberately adjacent to, and deliberately NOT the same as,
/// [_DisconnectRow]: Disconnect is purely local, keeps this account's
/// `user_id` on the server and preserves the §7.6 reconnect path, while
/// Leave severs the membership server-side. The two bodies of copy must keep
/// saying which is which.
///
/// As the LAST claimed member, the confirm switches to the D-L5 warning:
/// the online household and its shared history go with you. It says so
/// plainly and then does it -- never silently, never blocked.
class _LeaveRow extends ConsumerWidget {
  const _LeaveRow({required this.householdId, required this.householdName});

  /// The linked household's id, passed to `leave_household`.
  final String householdId;

  /// The linked household's name for the confirm title, or `null` while
  /// `currentHouseholdProvider` is still resolving (momentary).
  final String? householdName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return semantic(
      'settings.account.leave',
      child: ListTile(
        leading: const Icon(Icons.logout),
        title: Text(l10n.settingsAccountLeave),
        onTap: () => _leave(context, ref),
      ),
    );
  }

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    // §3.4: the local claimed count decides which warning the user reads.
    // 1 means "only me" -- the cascade case (D-L5).
    final lastClaimed = ref.read(claimedMemberCountProvider) <= 1;
    final result = await showExitConfirmSheet(
      context,
      title: l10n.householdLeaveConfirmTitle(householdName ?? ''),
      body: lastClaimed
          ? l10n.householdLeaveConfirmBodyLastMember
          : l10n.householdLeaveConfirmBody,
      actionLabel: l10n.householdLeaveConfirmAction,
      semanticPrefix: 'settings.account.leave',
    );
    if (!result.confirmed) {
      return;
    }
    try {
      await ref
          .read(householdExitServiceProvider)
          .leaveHousehold(
            householdId: householdId,
            alsoDeleteLocalData: result.alsoDeleteLocalData,
          );
    } on Exception catch (_) {
      if (context.mounted) {
        showAppSnackbar(context, message: l10n.householdLeaveError);
      }
      return;
    }
    if (result.alsoDeleteLocalData) {
      // The documented `resetAppData` caller responsibility: its device
      // settings row was just deleted out from under this already-running
      // watch (see `ResetDataTile`, which does exactly this).
      ref.invalidate(settingsProvider);
    }
  }
}
```

Add the imports this needs (`exit_confirm_sheet.dart`).

- [ ] **Step 5: Run to verify it passes**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/features/settings/account_exit_rows_test.dart test/features/settings/account_section_test.dart
```

Expected: PASS in both files. `account_section_test.dart` must stay green —
the new row appears in the linked branch it already exercises, so any
`findsNWidgets(...)` count there may need updating; adjust the count, never
the assertion's intent.

- [ ] **Step 6: Analyze and commit**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter analyze --fatal-infos
git add lib/features/settings/account_section.dart lib/l10n/ test/features/settings/
git commit -m "Add the Leave household action with the last-member cascade warning (spec §3.4, D-L5)"
```

**Slice 5 is now complete.**

---

## Slice 6 — Delete account (F11, §2.2, D-L4)

The gate is settled: **D-L4 holds** (commit `f184f4a` — see "The slice-1 gate:
RESOLVED" above). Slice 6 is a single, linear path: one RPC, no edge function.
Appendix A keeps the fallback analysis for the day the RPC regresses; it is
not part of this slice's work.

### Task 19: Server side — verify and record, do not re-implement

Slice 1 Task 6 plus commit `f184f4a` already shipped the final
`delete_account()`. This task exists to confirm that on the machine doing
slice 6 and to convert D-L4 from expectation to recorded fact in the spec —
it changes no SQL.

**Files:**
- Modify: `docs/specs/household-lifecycle.md` (the §5 slice 1 verification record)

**Interfaces:**
- Consumes: `public.delete_account()` in its final form.
- Produces: nothing in code.

- [ ] **Step 1: Confirm the gate on this machine**

```bash
supabase db reset && supabase test db
```

Expected: `002_membership_exit_test.sql` green, including
`delete_account removes the auth user (D-L4)`.

If this is NOT green, stop: something regressed between `f184f4a` and now.
Do not start implementing Appendix A on the strength of one red run — find
out what changed first, because the fallback is a much larger surface than a
broken migration.

- [ ] **Step 2: Record it in the spec**

Append to `docs/specs/household-lifecycle.md` §5 slice 1, converting D-L4 from
expectation to verified fact, in the style of §7.7's verification record in
`sync-backend.md`:

```markdown
*Verified 2026-08-11 (commit `f184f4a`): the `auth.users` delete works from a
`postgres`-owned `SECURITY DEFINER` RPC. D-L4 holds and the edge-function
fallback is NOT needed. Three FKs referenced `auth.users`: the two
`created_by` ones were relaxed per §2.7 (set null / cascade), and the third,
`members.user_id`, is cleared by the unclaim §2.2 already required — it
cannot be relaxed, because `is_household_member()` reads it and an
`on delete set null` there would be an RLS change rather than a cleanup.*
```

- [ ] **Step 3: Commit**

```bash
git add docs/specs/household-lifecycle.md
git commit -m "Record the D-L4 gate result: the in-RPC auth.users delete works"
```

---

### Task 20: `deleteAccount` on the gateway

**Files:**
- Modify: `lib/application/household_gateway.dart`
- Modify: `test/features/settings/fake_household_gateway.dart`

**Interfaces:**
- Consumes: `public.delete_account()` (slice 1 Task 6 + commit `f184f4a`).
- Produces: `HouseholdGateway.deleteAccount() → Future<void>` across all three implementations.

- [ ] **Step 1: Add the fake's side**

```dart
  /// How many times [deleteAccount] has been called.
  int deleteAccountCallCount = 0;

  /// Set to make the next [deleteAccount] call throw this instead of
  /// succeeding.
  Exception? deleteAccountError;
```

```dart
  @override
  Future<void> deleteAccount() async {
    deleteAccountCallCount++;
    final error = deleteAccountError;
    if (error != null) {
      throw error;
    }
  }
```

- [ ] **Step 2: Add it to the interface and `NoopHouseholdGateway`**

```dart
  /// Deletes the signed-in account (spec
  /// `docs/specs/household-lifecycle.md` §2.2, F11, D-L4): unclaims the
  /// caller's member row in EVERY household they belong to, cascades any
  /// household left with no claimed members (§2.4), and erases the
  /// `auth.users` row.
  ///
  /// Local data on THIS device is deliberately untouched -- GDPR erasure
  /// covers the server copy and the account, not the user's own phone
  /// (D-L3). Wiping this device is the confirm sheet's separate, unchecked
  /// opt-in.
  ///
  /// The session is invalid the instant this returns; callers sign out
  /// locally (`HouseholdExitService.deleteAccount`).
  Future<void> deleteAccount();
```

```dart
  @override
  Future<void> deleteAccount() => _unreachable();
```

- [ ] **Step 3: Implement it on `SupabaseHouseholdGateway` as the single RPC**

```dart
  @override
  Future<void> deleteAccount() async {
    // One call does the whole job: the RPC is `postgres`-owned and
    // SECURITY DEFINER, so its `delete from auth.users` is permitted
    // (D-L4, proven by slice 1's pgTAP gate). No edge function, no
    // service-role key anywhere near the client.
    await _client.rpc<dynamic>('delete_account');
  }
```

- [ ] **Step 4: Analyze and commit**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter analyze --fatal-infos
git add lib/application/household_gateway.dart test/features/settings/fake_household_gateway.dart
git commit -m "Add deleteAccount to HouseholdGateway (spec §2.2, F11)"
```

---

### Task 21: `HouseholdExitService.deleteAccount`

**Files:**
- Modify: `lib/application/household_exit_service.dart`
- Modify: `test/application/household_exit_service_test.dart`
- Modify: `test/features/settings/fake_auth_gateway.dart`

**Interfaces:**
- Consumes: `HouseholdGateway.deleteAccount` (Task 20), `AuthGateway.signOut`.
- Produces: `HouseholdExitService.deleteAccount({required bool alsoDeleteLocalData})`; `FakeAuthGateway.signOutError`.

- [ ] **Step 1: Give the auth fake a failure hook**

In `test/features/settings/fake_auth_gateway.dart`:

```dart
  /// Set to make the next [signOut] call throw this instead of succeeding.
  /// Models the realistic post-erasure case: the account is already gone
  /// server-side, so the sign-out round trip can legitimately fail.
  Exception? signOutError;
```

```dart
  @override
  Future<void> signOut() async {
    final error = signOutError;
    if (error != null) {
      throw error;
    }
    currentUser = null;
    _controller.add(null);
  }
```

- [ ] **Step 2: Write the failing tests**

Append to `test/application/household_exit_service_test.dart`:

```dart
  test(
    'delete account: calls the RPC, signs out, unlinks, and keeps this '
    "phone's data by default (D-L3 -- erasure covers the server, not the "
    "user's own device)",
    () async {
      auth.signIn(const AuthUser(id: 'me', email: 'me@x.y'));

      await service.deleteAccount(alsoDeleteLocalData: false);

      expect(gateway.deleteAccountCallCount, 1);
      expect(auth.currentUser, isNull);
      final row = await settings.ensureSettings();
      expect(row.syncHouseholdId, isNull);
      expect(await db.select(db.households).get(), hasLength(1));
    },
  );

  test('delete account with the opt-in checked wipes this phone too', () async {
    auth.signIn(const AuthUser(id: 'me', email: 'me@x.y'));

    await service.deleteAccount(alsoDeleteLocalData: true);

    expect(await db.select(db.households).get(), isEmpty);
  });

  test(
    'a failed delete_account changes nothing: still signed in, still linked',
    () async {
      auth.signIn(const AuthUser(id: 'me', email: 'me@x.y'));
      gateway.deleteAccountError = Exception('offline');

      await expectLater(
        service.deleteAccount(alsoDeleteLocalData: false),
        throwsA(isA<Exception>()),
      );

      expect(auth.currentUser, isNotNull);
      final row = await settings.ensureSettings();
      expect(row.syncHouseholdId, household.id);
    },
  );

  test(
    'a failed sign-out AFTER a successful erasure does not resurrect the '
    'linked state -- the account is gone either way',
    () async {
      auth
        ..signIn(const AuthUser(id: 'me', email: 'me@x.y'))
        ..signOutError = Exception('no such user');

      await service.deleteAccount(alsoDeleteLocalData: false);

      final row = await settings.ensureSettings();
      expect(row.syncHouseholdId, isNull);
    },
  );
```

- [ ] **Step 3: Run to verify it fails**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/application/household_exit_service_test.dart
```

Expected: FAIL to compile — `deleteAccount` is not defined on the service.

- [ ] **Step 4: Implement**

In `lib/application/household_exit_service.dart`, next to `leaveHousehold`:

```dart
  /// Deletes the signed-in account (spec §2.2, F11, D-L4).
  ///
  /// The server unclaims this account's member row in EVERY household it
  /// belongs to, cascades any household left with no claimed members
  /// (§2.4), and erases the `auth.users` row. Then this device signs out --
  /// the session is invalid from the moment the auth row is gone, so this
  /// is bookkeeping, not a request, and a failure is tolerated: the account
  /// is already deleted and refusing to unlink afterwards would strand the
  /// device in a state whose server side no longer exists. (§3.5's
  /// revocation probe explicitly does not cover this case: the probes fail
  /// as UNAUTHENTICATED rather than as revoked, which the existing auth
  /// path already handles.)
  ///
  /// [alsoDeleteLocalData] is the D-L3 opt-in, unchecked by default here
  /// exactly as in the other two exits: GDPR erasure covers the server copy
  /// and the account, not the user's own phone.
  Future<void> deleteAccount({required bool alsoDeleteLocalData}) async {
    await gateway.deleteAccount();
    try {
      await auth.signOut();
    } on Exception catch (_) {
      // Tolerated -- see the doc comment. The account is gone; the only
      // thing left is local bookkeeping, which continues below.
    }
    await _finishLocally(alsoDeleteLocalData: alsoDeleteLocalData);
  }
```

- [ ] **Step 5: Run to verify it passes**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/application/household_exit_service_test.dart
```

Expected: PASS, 9 tests.

- [ ] **Step 6: Commit**

```bash
git add lib/application/household_exit_service.dart test/
git commit -m "Add HouseholdExitService.deleteAccount (spec §2.2, F11)"
```

---

### Task 22: The Delete account row, its exit sheet, and the final confirmation

**Files:**
- Modify: `lib/features/settings/account_section.dart`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`
- Modify: `test/features/settings/account_exit_rows_test.dart`

**Interfaces:**
- Consumes: `showExitConfirmSheet` (slice 2 Task 9), `householdExitServiceProvider` (Task 21), `claimedMemberCountProvider` (Task 17), `ResetDataTile`'s two-dialog shape (`lib/features/settings/reset_flow.dart`) as the pattern to mirror.
- Produces: `_DeleteAccountRow`, semantic ids `settings.account.deleteAccount` (the row) plus `settings.account.deleteAccount.final.cancel` / `settings.account.deleteAccount.final.confirm` for D-L6's final dialog. The shared sheet contributes `.deleteLocal`, `.cancel` and `.confirm` from its `semanticPrefix` — the `.final.` segment keeps the two apart and names the dialog for what it is, a single last gate rather than one of a pair.

**The full order the user walks through (D-L6):** row tap → the shared exit
sheet (consequences, UNCHECKED "also delete this phone's copy" box, action) →
one final confirmation whose copy names the exact outcome the checkbox just
selected → the RPC. Two gates. Cancelling at either does nothing at all.

- [ ] **Step 1: Add the l10n strings**

In `lib/l10n/app_en.arb`:

```json
  "settingsAccountDeleteAccount": "Delete my account",
  "@settingsAccountDeleteAccount": {
    "description": "Account-section row that permanently deletes the signed-in account (spec docs/specs/household-lifecycle.md §2.2, F11). Shown whenever signed in, linked or not."
  },
  "accountDeleteConfirmTitle": "Delete your account?",
  "@accountDeleteConfirmTitle": {
    "description": "Title of the delete-account confirm sheet."
  },
  "accountDeleteConfirmBody": "Your account and your email address are deleted from the server. This can't be undone. Your profile stays with each household you're part of, so the others keep their history — you're just no longer linked to it.",
  "@accountDeleteConfirmBody": {
    "description": "Body of the delete-account exit sheet when claimed members remain in the household(s). The export pointer deliberately lives on the FINAL dialog instead (D-L6/D-L7), where it is the last thing read before the point of no return."
  },
  "accountDeleteConfirmBodyLastMember": "Your account and your email address are deleted from the server. This can't be undone. You're the last person here with an account, so the online household goes with it: the shared copy and its history are removed from the server and any invite codes stop working. Everything on this phone is unaffected unless you tick the box below.",
  "@accountDeleteConfirmBodyLastMember": {
    "description": "Body of the delete-account confirm when the caller is the last claimed member, so §2.4's cascade will fire — the same plain warning D-L5 requires for leaving."
  },
  "accountDeleteConfirmAction": "Delete account",
  "@accountDeleteConfirmAction": {
    "description": "Confirm button of the delete-account sheet."
  },
  "accountDeleteFinalTitle": "Delete your account now?",
  "@accountDeleteFinalTitle": {
    "description": "Title of delete-account's FINAL confirmation (decision D-L6), shown after the shared exit sheet -- the last gate before an irreversible erasure. Same AlertDialog grammar as settingsResetConfirm2* in reset_flow.dart."
  },
  "accountDeleteFinalBodyKeepPhone": "Your account and your email address are erased from the server. That can't be undone. This phone keeps everything it has, as its own local copy. To keep a copy of your data somewhere else first, use Export under Settings → Data.",
  "@accountDeleteFinalBodyKeepPhone": {
    "description": "Body of the final delete-account confirmation when the sheet's 'also delete this phone's copy' box was left UNCHECKED (the D-L3 default). Names the exact outcome the user just configured, which is the whole reason this dialog comes after the sheet rather than before it."
  },
  "accountDeleteFinalBodyDeletePhone": "Your account and your email address are erased from the server, and this phone's copy — members, chores and shopping list — is deleted too, so the app starts fresh. Neither can be undone. To keep a copy of your data first, use Export under Settings → Data.",
  "@accountDeleteFinalBodyDeletePhone": {
    "description": "Body of the final delete-account confirmation when the sheet's checkbox WAS ticked. Deliberately reads differently from accountDeleteFinalBodyKeepPhone -- the point of confirming after the choice is that the two cases are distinguishable."
  },
  "accountDeleteFinalAction": "Delete account",
  "@accountDeleteFinalAction": {
    "description": "Destructive action of the final delete-account confirmation; the next thing that happens is the RPC."
  },
  "accountDeleteError": "Couldn't delete your account. This needs a connection — nothing was changed. Try again.",
  "@accountDeleteError": {
    "description": "Snackbar shown when account deletion failed. 'Try again' is literal: the operation is safe to retry, including after a half-completed erasure."
  },
```

In `lib/l10n/app_de.arb` (du-form):

```json
  "settingsAccountDeleteAccount": "Mein Konto löschen",
  "accountDeleteConfirmTitle": "Konto löschen?",
  "accountDeleteConfirmBody": "Dein Konto und deine E-Mail-Adresse werden vom Server gelöscht. Das lässt sich nicht rückgängig machen. Dein Profil bleibt in jedem Haushalt, zu dem du gehörst, die anderen behalten also ihren Verlauf — du bist nur nicht mehr damit verknüpft.",
  "accountDeleteConfirmBodyLastMember": "Dein Konto und deine E-Mail-Adresse werden vom Server gelöscht. Das lässt sich nicht rückgängig machen. Du bist die letzte Person hier mit einem Konto, deshalb verschwindet der Online-Haushalt mit: Die geteilte Kopie und ihr Verlauf werden vom Server entfernt, und Einladungscodes funktionieren nicht mehr. Auf diesem Handy ändert sich nichts, außer du setzt unten das Häkchen.",
  "accountDeleteConfirmAction": "Konto löschen",
  "accountDeleteFinalTitle": "Konto jetzt löschen?",
  "accountDeleteFinalBodyKeepPhone": "Dein Konto und deine E-Mail-Adresse werden vom Server gelöscht. Das lässt sich nicht rückgängig machen. Dieses Handy behält alles, was es hat, als eigene lokale Kopie. Wenn du vorher woanders eine Kopie deiner Daten sichern willst, nutze „Exportieren“ unter Einstellungen → Daten.",
  "accountDeleteFinalBodyDeletePhone": "Dein Konto und deine E-Mail-Adresse werden vom Server gelöscht, und die Kopie auf diesem Handy — Mitglieder, Aufgaben und Einkaufsliste — wird ebenfalls gelöscht, die App startet neu. Beides lässt sich nicht rückgängig machen. Wenn du vorher eine Kopie deiner Daten willst, nutze „Exportieren“ unter Einstellungen → Daten.",
  "accountDeleteFinalAction": "Konto löschen",
  "accountDeleteError": "Dein Konto konnte nicht gelöscht werden. Dafür braucht die App eine Verbindung — es wurde nichts geändert. Versuch es noch mal.",
```

Regenerate:

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter gen-l10n
```

- [ ] **Step 2: Write the failing tests**

Append to `test/features/settings/account_exit_rows_test.dart`:

```dart
  testChoreApp(
    'the Delete account row is offered whenever signed in -- linked or not '
    '(GDPR erasure must not require linking first)',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(FakeAuthGateway(currentUser: me)),
      householdGatewayProvider.overrideWithValue(FakeHouseholdGateway()),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);
      expect(
        find.bySemanticsIdentifier('settings.account.deleteAccount'),
        findsOneWidget,
      );

      await linkAndClaim(database);
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier('settings.account.deleteAccount'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'deleting the account calls the RPC, signs out, and keeps this phone by '
    'default (D-L3)',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(deleteAuth),
      householdGatewayProvider.overrideWithValue(deleteGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await linkAndClaim(database);

      await openSettingsTab(tester);
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.deleteAccount'),
      );
      await tester.pumpAndSettle();

      // D-L6: the shared sheet comes FIRST -- the choice, before any
      // confirmation of it -- with the D-L3 box unchecked.
      final box = tester.widget<CheckboxListTile>(
        find.descendant(
          of: find.bySemanticsIdentifier(
            'settings.account.deleteAccount.deleteLocal',
          ),
          matching: find.byType(CheckboxListTile),
        ),
      );
      expect(box.value, isFalse);
      // Last claimed member: the cascade warning, same plain wording D-L5
      // requires for leaving.
      expect(find.textContaining('last person here'), findsOneWidget);

      await tester.tap(
        find.bySemanticsIdentifier('settings.account.deleteAccount.confirm'),
      );
      await tester.pumpAndSettle();

      // Then, and only then, the final gate -- naming the outcome the
      // checkbox just selected. Nothing has been called yet.
      expect(deleteGateway.deleteAccountCallCount, 0);
      expect(find.textContaining('This phone keeps everything'), findsOneWidget);
      await tester.tap(
        find.bySemanticsIdentifier(
          'settings.account.deleteAccount.final.confirm',
        ),
      );
      await tester.pumpAndSettle();

      expect(deleteGateway.deleteAccountCallCount, 1);
      expect(deleteAuth.currentUser, isNull);
      expect(await database.select(database.households).get(), hasLength(1));

      handle.dispose();
    },
  );

  testChoreApp(
    'cancelling the final confirmation is a complete no-op -- no RPC, still '
    'signed in, still linked (D-L6)',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(FakeAuthGateway(currentUser: me)),
      householdGatewayProvider.overrideWithValue(cancelDeleteGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await linkAndClaim(database);
      await openSettingsTab(tester);

      await tester.tap(
        find.bySemanticsIdentifier('settings.account.deleteAccount'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.deleteAccount.confirm'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(
          'settings.account.deleteAccount.final.cancel',
        ),
      );
      await tester.pumpAndSettle();

      expect(cancelDeleteGateway.deleteAccountCallCount, 0);
      final row = await SettingsRepository(database).ensureSettings();
      expect(row.syncHouseholdId, householdId);
      expect(await database.select(database.households).get(), hasLength(1));

      handle.dispose();
    },
  );

  testChoreApp(
    'cancelling the exit sheet never reaches the final confirmation at all',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(FakeAuthGateway(currentUser: me)),
      householdGatewayProvider.overrideWithValue(sheetCancelGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await linkAndClaim(database);
      await openSettingsTab(tester);

      await tester.tap(
        find.bySemanticsIdentifier('settings.account.deleteAccount'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.deleteAccount.cancel'),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier(
          'settings.account.deleteAccount.final.confirm',
        ),
        findsNothing,
      );
      expect(sheetCancelGateway.deleteAccountCallCount, 0);

      handle.dispose();
    },
  );

  testChoreApp(
    "ticking the box changes what the final confirmation SAYS, then wipes "
    'this phone as well (D-L6: you confirm the thing you configured)',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(FakeAuthGateway(currentUser: me)),
      householdGatewayProvider.overrideWithValue(wipeDeleteGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await linkAndClaim(database);
      await openSettingsTab(tester);

      await tester.tap(
        find.bySemanticsIdentifier('settings.account.deleteAccount'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(
          'settings.account.deleteAccount.deleteLocal',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.deleteAccount.confirm'),
      );
      await tester.pumpAndSettle();

      // The other body -- this is the point of confirming after the choice.
      expect(find.textContaining("this phone's copy"), findsOneWidget);
      expect(find.textContaining('This phone keeps everything'), findsNothing);

      await tester.tap(
        find.bySemanticsIdentifier(
          'settings.account.deleteAccount.final.confirm',
        ),
      );
      await tester.pumpAndSettle();

      expect(wipeDeleteGateway.deleteAccountCallCount, 1);
      expect(await database.select(database.households).get(), isEmpty);

      handle.dispose();
    },
  );

  testChoreApp(
    'a failed account deletion is reported and changes nothing',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(FakeAuthGateway(currentUser: me)),
      householdGatewayProvider.overrideWithValue(failingDeleteGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await linkAndClaim(database);

      await openSettingsTab(tester);
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.deleteAccount'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.deleteAccount.confirm'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(
          'settings.account.deleteAccount.final.confirm',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining("Couldn't delete your account"), findsOneWidget);
      final row = await SettingsRepository(database).ensureSettings();
      expect(row.syncHouseholdId, householdId);

      handle.dispose();
    },
  );
```

with the fakes declared alongside the slice-5 ones:

```dart
  final deleteGateway = FakeHouseholdGateway();
  final deleteAuth = FakeAuthGateway(currentUser: me);
  final cancelDeleteGateway = FakeHouseholdGateway();
  final sheetCancelGateway = FakeHouseholdGateway();
  final wipeDeleteGateway = FakeHouseholdGateway();
  final failingDeleteGateway = FakeHouseholdGateway()
    ..deleteAccountError = Exception('offline');
```

- [ ] **Step 3: Run to verify it fails**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/features/settings/account_exit_rows_test.dart
```

Expected: FAIL — `settings.account.deleteAccount` does not exist.

- [ ] **Step 4: Implement the row**

In `lib/features/settings/account_section.dart`, add it to BOTH signed-in
branches — last in each, below everything else, because it is the most
destructive row in the section:

```dart
    if (householdId == null) {
      final membership = ref.watch(myMembershipProvider).valueOrNull;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SignedInTile(user: user),
          if (membership != null) _ReconnectRow(membership: membership),
          const _AdoptRow(),
          const _JoinRow(),
          const _DeleteAccountRow(),
        ],
      );
    }
```

```dart
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SignedInTile(user: user, householdName: householdName),
        _InviteRow(householdId: householdId),
        _LeaveRow(householdId: householdId, householdName: householdName),
        const _DisconnectRow(),
        const _DeleteAccountRow(),
      ],
    );
```

and the widget, after `_LeaveRow`:

```dart
/// The 'Delete my account' action (spec
/// `docs/specs/household-lifecycle.md` §2.2, F11, D-L4), shown whenever this
/// device is signed in -- linked or not, since an account can exist with no
/// household link at all and erasure must not require linking first.
///
/// Under D-B2 (open-source distribution only) this is GDPR-driven rather
/// than store-mandated: still genuinely required, not a launch gate.
///
/// Drawn in `error`, the same treatment `ResetDataTile` gets -- the only
/// other irreversible-feeling row in Settings.
///
/// Guarded by TWO gates, in this order (decision D-L6):
///
/// 1. the SAME shared exit sheet the other two exits use (§3.3, D-L3),
///    whose "also delete this phone's copy" checkbox is unchecked here too.
///    This is the CHOICE step.
/// 2. one final confirmation, whose body is picked by what the checkbox
///    ended up as -- so it names the actual outcome rather than a generic
///    warning.
///
/// Configure, then confirm. Reset app data is confirm -> confirm only
/// because it has nothing to configure; this is the same rhythm with the
/// first step carrying the choice, and it exists at all because reset is
/// purely local and fully recoverable while this is irreversible
/// server-side erasure. Putting both confirmations FIRST was rejected: a
/// confirmation that precedes the decision cannot describe the consequence,
/// so it degrades into a speed bump.
///
/// Leave and member-removal deliberately keep the single sheet: both are
/// recoverable (rejoin with an invite, re-invite the person), so an extra
/// gate there would be friction with no safety benefit.
class _DeleteAccountRow extends ConsumerWidget {
  const _DeleteAccountRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    return semantic(
      'settings.account.deleteAccount',
      child: ListTile(
        leading: Icon(Icons.person_remove_outlined, color: errorColor),
        title: Text(
          l10n.settingsAccountDeleteAccount,
          style: TextStyle(color: errorColor),
        ),
        onTap: () => _run(context, ref),
      ),
    );
  }

  Future<void> _run(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    // Same §3.4 count the Leave confirm uses: 1 means "only me", so the
    // server will cascade (§2.4) and the copy must say so first.
    final lastClaimed = ref.read(claimedMemberCountProvider) <= 1;
    final result = await showExitConfirmSheet(
      context,
      title: l10n.accountDeleteConfirmTitle,
      body: lastClaimed
          ? l10n.accountDeleteConfirmBodyLastMember
          : l10n.accountDeleteConfirmBody,
      actionLabel: l10n.accountDeleteConfirmAction,
      semanticPrefix: 'settings.account.deleteAccount',
    );
    if (!result.confirmed || !context.mounted) {
      return;
    }
    // D-L6's final gate, AFTER the choice, so its copy can name the actual
    // outcome. A cancel here has still called nothing.
    if (!await _confirmFinally(
      context,
      alsoDeleteLocalData: result.alsoDeleteLocalData,
    )) {
      return;
    }
    try {
      await ref
          .read(householdExitServiceProvider)
          .deleteAccount(alsoDeleteLocalData: result.alsoDeleteLocalData);
    } on Exception catch (_) {
      if (context.mounted) {
        showAppSnackbar(context, message: l10n.accountDeleteError);
      }
      return;
    }
    if (result.alsoDeleteLocalData) {
      ref.invalidate(settingsProvider);
    }
  }

  /// D-L6's final gate: one `AlertDialog`, same grammar as
  /// `ResetDataTile._showSecondDialog` (`reset_flow.dart`) so the app makes
  /// its "cannot be undone" promise the same way everywhere.
  ///
  /// [alsoDeleteLocalData] picks the body. That is the entire reason this
  /// dialog runs AFTER the sheet instead of before it: the two outcomes are
  /// genuinely different, and the user should be confirming the one they
  /// just configured. The export pointer (D-L7) lives here too -- last
  /// moment it is still actionable.
  Future<bool> _confirmFinally(
    BuildContext context, {
    required bool alsoDeleteLocalData,
  }) async {
    final errorColor = Theme.of(context).colorScheme.error;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext);
        return AlertDialog(
          title: Text(l10n.accountDeleteFinalTitle),
          content: Text(
            alsoDeleteLocalData
                ? l10n.accountDeleteFinalBodyDeletePhone
                : l10n.accountDeleteFinalBodyKeepPhone,
          ),
          actions: [
            semantic(
              'settings.account.deleteAccount.final.cancel',
              child: TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(l10n.commonCancel),
              ),
            ),
            semantic(
              'settings.account.deleteAccount.final.confirm',
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: errorColor),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(l10n.accountDeleteFinalAction),
              ),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }
}
```

- [ ] **Step 5: Run to verify it passes**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/features/settings/account_exit_rows_test.dart test/features/settings/account_section_test.dart
```

Expected: PASS in both. Again, any row-count assertion in
`account_section_test.dart` may need bumping.

- [ ] **Step 6: Full suite and analyze**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter analyze --fatal-infos && env -u GIT_DIR -u GIT_INDEX_FILE flutter test
```

Expected: `No issues found!` and all tests passing.

- [ ] **Step 7: Commit**

```bash
git add lib/ test/
git commit -m "Add the Delete account action (spec §2.2, F11, D-L4)"
```

---

## Done criteria for slices 4–6

- `flutter analyze --fatal-infos` clean; `flutter test` green.
- `supabase test db` still green, with no SQL changed by these slices: the
  server surface was finished in slice 1 and commit `f184f4a`.
- Every string added here exists in BOTH `app_en.arb` and `app_de.arb`, and
  `memberEditDeleteBlockedClaimed` is gone from both.
- No role check was introduced anywhere (D-L2/D1). Grep to be sure:
  `grep -rn "MemberRole" lib/features/ lib/application/household_exit_service.dart`
  should return nothing new.
- The D-L3 default holds in all three exits: a confirm accepted with the box
  untouched leaves this device's households/members/chores in place. Three
  tests assert exactly this — do not let any of them be weakened.
- D-L6 holds: delete-account is sheet-then-dialog, in that order. The sheet
  appears first with its checkbox unchecked, the final dialog's body differs
  by checkbox state, and cancelling at either gate calls nothing. If anyone
  "improves" this by moving a confirmation in front of the sheet, that is the
  rejected design — a confirmation before the choice cannot describe the
  consequence. Leave and member-removal still have exactly ONE confirmation
  each.
- **Manual live smoke against the local stack** (`sync-backend.md` §7.7's
  method), which is the real gate for everything server-touching, since E2E
  stays offline (§4):
  1. Two accounts, one household. From device A, remove B's claimed profile →
     B's next pull shows slice 3's notice; A's roster no longer lists B.
  2. From device A, Leave with another claimed member present → A unlinks and
     keeps its data; the household survives; A's profile is still listed for
     the others and is claimable via a fresh invite.
  3. Last claimed member leaves → `households.deleted_at` is stamped in SQL,
     and a previously issued invite code is now rejected (slice 1 Task 5).
  4. Delete account → after the exit sheet and the final confirmation, the
     `auth.users` row is gone, the device is signed out and unlinked, and its
     local household is still present.
  5. Repeat step 4 with the checkbox TICKED once → the app lands on the
     welcome screen.
- `docs/specs/sync-backend.md` §2's `delete_account()` bullet still describes
  the edge-function split, which is now WRONG: correct it to name the single
  RPC and point at §5's D-L4 verification record (and at Appendix A here for
  the retained fallback). Same file's §5 "double-confirm patterned on G9" for
  delete-account is now accurate again under D-L6 — leave it alone.

---

## Appendix A — the edge-function fallback (RETAINED, NOT IMPLEMENTED)

**Do not implement any of this as part of slices 4–6.** D-L4 is proven
(commit `f184f4a`): `delete_account()` deletes the `auth.users` row itself,
and Task 20 is a single `rpc('delete_account')`. This appendix is kept only
for one scenario: **the proven RPC regresses** — realistically, a Supabase
platform change to `auth` schema permissions that makes a `postgres`-owned
`SECURITY DEFINER` function unable to delete from `auth.users` again. It is
the analysis, ready to execute, so that day costs a migration and a deploy
rather than a fresh design round.

The fallback is `sync-backend.md` §2's original design: *"the RPC marks; the
edge function `delete-user` finishes"*. `delete_account()` keeps the unclaim
and cascade (the parts that need `auth.uid()` and RLS-shaped authorization)
and drops the `auth.users` delete; an edge function holding the service-role
key finishes the job. The client seam does not change: `HouseholdGateway.
deleteAccount()` keeps its signature, and only `SupabaseHouseholdGateway`'s
body swaps the RPC for a `functions.invoke('delete-user')` (the code for
that body is in A.2 below). Tasks 21 and 22 — the service, the rows, the
copy, the confirmations, the tests — are untouched either way.

**What the fallback costs, stated plainly so it is not rediscovered late:**

1. **The handoff changes shape but keeps its no-credentials-in-chat
   property.** An edge function cannot be pasted into the SQL editor, but it
   can be deployed either from the Supabase dashboard's Edge Functions editor
   (paste the TypeScript, click Deploy) or with `supabase functions deploy
   delete-user`. In both cases `SUPABASE_URL`, `SUPABASE_ANON_KEY` and
   `SUPABASE_SERVICE_ROLE_KEY` are **injected by the platform** into the
   function's environment — the service-role key is never written into a
   file, never committed, and never appears in chat. That is the whole reason
   the key lives in the edge function rather than in the app.
2. **A two-step failure window appears.** The RPC can succeed (memberships
   unclaimed, households cascaded) and the admin delete can then fail,
   leaving an account that owns nothing. Recovery is simply retrying
   `deleteAccount()`: the RPC's loop finds no memberships and is a no-op, and
   the admin delete runs again. Task 21's service and Task 22's error copy
   already make a retry the obvious next step, so they need no change.
3. **`supabase/tests/` cannot prove the last step.** pgTAP has no way to
   invoke an edge function, so the `delete_account removes the auth user`
   assertion inverts (the auth user SURVIVES the RPC) and the erasure proof
   moves into a manual live smoke against `supabase functions serve`.
4. **The §2.7 migration stays.** `households.created_by` and
   `household_invites.created_by` are FKs into `auth.users`; the admin delete
   hits exactly the same constraints the in-RPC delete does. Same for the
   `members.user_id` unclaim.

### A.1 — Server: RPC marks, edge function finishes


**Files:**
- Modify: `supabase/migrations/20260808120000_membership_exit.sql`
- Modify: `supabase/tests/002_membership_exit_test.sql`
- Create: `supabase/functions/delete-user/index.ts`

**Interfaces:**
- Produces: `public.delete_account()` WITHOUT the `auth.users` delete (unclaim + cascade only), and the `delete-user` edge function that finishes the job.

- [ ] **Step B1: Change the pgTAP assertion to the new truth**

In `supabase/tests/002_membership_exit_test.sql`, Task 1's second assertion
(`delete_account() runs and removes the auth user (D-L4 gate)`) and Task 6's
`delete_account removes the auth user (D-L4)` both become the opposite claim.
Replace the Task 6 one with:

```sql
select is(
  (select count(*)::int from auth.users
   where id = '00000000-0000-0000-0000-0000000000j1'),
  1,
  'delete_account leaves the auth user for the delete-user edge function '
  '(D-L4 refused; sync-backend.md §2 fallback)');
```

and keep Task 1's `lives_ok` as-is (the RPC still runs; it just does less).
The plan count is unchanged.

- [ ] **Step B2: Run to verify it fails**

```bash
supabase db reset && supabase test db
```

Expected: FAIL — the RPC still deletes the auth user, so the count is 0.

- [ ] **Step B3: Strip the auth.users delete from the RPC**

Append to `supabase/migrations/20260808120000_membership_exit.sql` (a later
`create or replace` wins, matching how the rest of this migration was built
up):

```sql
-- delete_account, edge-function variant (D-L4 REFUSED on <date>: a
-- postgres-owned SECURITY DEFINER function may not delete from auth.users
-- on this project). Per sync-backend.md §2 the RPC now MARKS -- unclaims
-- every membership and cascades every household left with no claimed
-- members -- and the `delete-user` edge function, which holds the
-- service-role key, FINISHES by deleting the auth user.
--
-- Retry-safe by construction: called again after a failed second step, the
-- loop below finds no memberships and does nothing, so the edge function
-- can simply be retried.
--
-- The §2.7 foreign-key relaxations above are STILL required: the admin
-- delete hits households_created_by_fkey and
-- household_invites_created_by_fkey exactly as an in-RPC delete would.
create or replace function public.delete_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  for v_member_id in
    select id from members where user_id = auth.uid() and deleted_at is null
  loop
    perform _cascade_if_orphaned(_exit_membership(v_member_id));
  end loop;
end;
$$;
```

- [ ] **Step B4: Run to verify it passes**

```bash
supabase db reset && supabase test db
```

Expected: PASS, same total as slice 1 ended with.

- [ ] **Step B5: Write the edge function**

Create `supabase/functions/delete-user/index.ts`:

```ts
// delete-user (spec docs/specs/sync-backend.md §2, docs/specs/
// household-lifecycle.md D-L4 fallback): the second half of account
// erasure. `delete_account()` unclaims every membership and cascades any
// orphaned household as the CALLER; this function then deletes the auth
// user with the service-role key, which is the part Postgres refused to a
// SECURITY DEFINER function on this project.
//
// SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY are injected
// by the platform. The key is never committed, never in the app bundle,
// and never pasted anywhere.
import { createClient } from 'jsr:@supabase/supabase-js@2';

Deno.serve(async (req) => {
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return new Response(JSON.stringify({ error: 'missing authorization' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Caller-scoped client: auth.uid() inside the RPC must be the CALLER, so
  // the unclaim and cascade run with exactly the authorization the RPC
  // already proves in pgTAP. Never run this step as the service role.
  const caller = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: userData, error: userError } = await caller.auth.getUser();
  const user = userData?.user;
  if (userError || !user) {
    return new Response(JSON.stringify({ error: 'invalid session' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const { error: rpcError } = await caller.rpc('delete_account');
  if (rpcError) {
    return new Response(JSON.stringify({ error: rpcError.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );
  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) {
    // The unclaim already succeeded and is idempotent, so the client's
    // retry re-runs both steps safely.
    return new Response(JSON.stringify({ error: deleteError.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  return new Response(null, { status: 204 });
});
```

- [ ] **Step B6: Verify it locally**

```bash
supabase functions serve delete-user
```

then, in a second shell, call it with a real local session's access token
(obtained the same way `sync-backend.md` §7.7's smoke test signs in) and
confirm a 204 plus a vanished `auth.users` row. This is the only proof
available for this step — pgTAP cannot reach an edge function.

- [ ] **Step B7: Write the handoff note and commit**

Append to `docs/specs/household-lifecycle.md` §5 slice 1:

```markdown
*Verified <date>: the in-RPC `auth.users` delete is REFUSED on this project
(<exact error>). D-L4's fallback is in force: `delete_account()` unclaims and
cascades, and `supabase/functions/delete-user/index.ts` finishes with the
service-role key. Deploy it from the Supabase dashboard's Edge Functions
editor or with `supabase functions deploy delete-user`; the three
`SUPABASE_*` env vars are injected by the platform, so no credential is ever
pasted.*
```

```bash
git add supabase/ docs/specs/household-lifecycle.md
git commit -m "Fall back to the delete-user edge function for account erasure (D-L4 refused)"
```

### A.2 — Client: the gateway body that would replace the single RPC

`HouseholdGateway.deleteAccount()`'s signature, `NoopHouseholdGateway`, the
fake, `HouseholdExitService` and every widget stay exactly as Tasks 20–22
built them. Only this one method body changes:

```dart
  @override
  Future<void> deleteAccount() async {
    // Two-step erasure behind one call (D-L4 refused; see
    // `supabase/functions/delete-user/index.ts`): the function calls
    // `delete_account()` with THIS caller's JWT -- so the unclaim and
    // cascade keep their authorization -- and then deletes the auth user
    // with the service-role key, which only the function holds.
    //
    // Retrying after a failure is safe: the RPC half is idempotent (no
    // memberships left to unclaim) and the admin delete simply runs again.
    final response = await _client.functions.invoke('delete-user');
    final status = response.status;
    if (status != 200 && status != 204) {
      throw StateError('delete-user failed with status $status');
    }
  }
```

If `functions.invoke` in the pinned `supabase_flutter` version already throws
a `FunctionException` on a non-2xx status, drop the manual check and let it
propagate — the caller only needs "threw or didn't".
