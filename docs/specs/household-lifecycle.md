# Spec: Household lifecycle — membership exit (P4)

*Status: BINDING for the P4 membership phase. Covers backlog items F9
(leave a household), F10 (remove a claimed member), F11 (delete account),
F13 (orphan household cleanup) from `docs/future-improvements.md`. Designed
2026-08-08 with the user; all five product decisions below were taken in
that session and are recorded as decisions, not proposals.*

*F12 (restore from a backup file) was deliberately excluded — it is local
JSON import sharing machinery with `lib/application/data_export.dart` and
`lib/application/household_archive.dart`, touches no server, and has its
own hard problem (importing into a non-empty database). It gets its own
spec.*

## 0. What this spec is about

F9/F10/F11/F13 are one operation seen from four angles: **severing
`user_id` from a `members` row**, differing in who triggers it and what
happens to the household afterwards. They share a server helper, a confirm
shape, and a single hard question — *what happens to the departed person's
phone* — which is where the real design work is.

The question this cluster is NOT about is what happens to a departed
member's history. That was settled by `docs/specs/sync-backend.md` §0 (the
household owns its history; profiles just become unclaimed) and is already
implemented for unclaimed profiles by `lib/application/member_service.dart`.

### 0.1 The trap this spec closes

`public.is_household_member(hid)` requires `deleted_at IS NULL`
(`supabase/migrations/20260731120000_initial_schema.sql`,
`docs/specs/sync-backend.md` §2). Soft-deleting a claimed member therefore
revokes that person's RLS access the instant it replicates. Meanwhile
`docs/specs/sync-backend.md` §8.3 mandates that every sync error is
swallowed into a silent retry-later and that the app "NEVER surfaces sync
errors".

Composed, those two rules produce a device that shows a complete,
healthy-looking household which silently stopped updating, permanently.
That is the same class of trust defect as the signed-out state fixed in
`docs/feedback/2026-08-07-field-feedback.md` A1.

### 0.2 Live bug found while specifying this (fix is a prerequisite, §3.1)

The existing claimed-member protection is **inert**. Three layers guard on
`member.userId != null`:

- `_canDelete` — `lib/features/settings/member_edit_sheet.dart`
- the blocked-reason copy — same file, `_deleteBlockedReason`
- `MemberService.deleteMember`'s guard — `lib/application/member_service.dart`

No code path ever writes local `members.userId`:
`HouseholdGateway.uploadHouseholdData` documents members as uploaded with
`user_id` null, `downloadHousehold` does not map it back, and
`SupabaseSyncEngine._pushMembers` sends only the four granted columns.
Local `userId` is therefore always `null` and all three guards are
unreachable.

So F10's premise ("today only unclaimed profiles can be deleted") is false.
Today the app cannot tell which profiles are claimed, so it permits
deleting **any** of them; on a linked device that soft-deletes locally and
pushes `deleted_at` through the granted column — revoking a real person's
access with no server-side unclaim, welding their `user_id` to a dead row
(which breaks their §7.6 reconnect path), and telling them nothing.

This is a shipped bug, not a missing feature. §3.1 is its fix.

## 1. Decisions (taken 2026-08-08)

- **D-L1 — Scope.** F9+F10+F11+F13 are one spec. F12 is excluded (above).
- **D-L2 — Removal rights.** Any member may remove any other member,
  consistent with D1's flat household (`docs/specs/sync-backend.md` §2).
  No role gate is introduced; D1 stands and `members.role` stays vestigial.
- **D-L3 — The local copy.** Every exit KEEPS this device's data by
  default and offers an explicit, **unchecked** "also delete this phone's
  copy" checkbox with a one-line explanation of what that means. Applies
  identically to all three exits, including delete-account: GDPR erasure
  covers the server copy and the account, not the user's own device.
  Checked routes into the existing `resetAppData`
  (`lib/application/data_reset.dart`).
- **D-L4 — Erasure mechanism.** `delete_account()` attempts the whole job
  in one paste-SQL RPC (`delete from auth.users where id = auth.uid()`
  inside a `SECURITY DEFINER` function owned by `postgres`), preserving the
  established no-credentials-in-chat handoff. This is an EXPECTATION, not
  a verified fact — §5 slice 1 proves it before any client work, and falls
  back to the §2 edge function if refused.
- **D-L5 — Last claimed member.** Leaving as the last claimed member warns
  plainly that the online household and its shared history go with you,
  then cascades. It does not silently cascade and is not blocked.

## 2. Server

**No schema change on either side.** Server `households.deleted_at`
already exists (`20260731120000_initial_schema.sql`); local `Households`
has no such column and does not need one (§2.4). Local `Members.userId`
already exists (`lib/data/db/tables.dart`) and only needs populating (§3.1).

### 2.1 Shape

Three `SECURITY DEFINER` RPCs (`set search_path = public`, per
`20260801150000_pin_function_search_paths.sql`) over one internal helper
`_exit_membership(p_member_id)` that is NOT granted to `authenticated`.

Structure decision: one RPC per exit, rejecting a single
`exit_membership(p_member_id, p_mode)`. Mode branching inside a
`SECURITY DEFINER` function is where authorization mistakes hide, and
"remove someone else" and "delete my own account" have different blast
radii; separate functions keep separate grants and a readable pgTAP
authorization matrix.

### 2.2 The three exits are not the same operation

- **`leave_household()`** — unclaims ONLY: `user_id → null`, the member
  row stays active. Per `sync-backend.md` §0 the profile stays with the
  household, so the family still sees the person and their history, and
  they can return later by claiming that same profile through the existing
  `list_claimable_members` / `claim_member` path. Note this deliberately
  does NOT preserve the §7.6 reconnect path (which matches on
  `user_id = auth.uid()`); rejoining after leaving goes through an invite
  code, which is correct — leaving is a real exit.
- **`remove_member(p_member_id)`** — unclaims AND soft-deletes the
  profile. Requires `is_household_member` on the target's household.
  REJECTS `p_member_id` = the caller's own member row, pointing at
  `leave_household` instead. No further authorization check (D-L2).
  It accepts an unclaimed target too (the unclaim is then a no-op) and is
  idempotent on an already-removed one, so a retry after a partial failure
  is safe — but the client only calls it for CLAIMED targets (§3.2).
- **`delete_account()`** — performs the `leave_household` unclaim for
  EVERY household where the caller is a claimed member (`members.user_id`
  is UNIQUE per household, so an account may legitimately be in several),
  runs the §2.4 cascade for each, then deletes the `auth.users` row (D-L4).

### 2.3 remove_member can never orphan a household

The caller is always a claimed member who stays behind, and self-removal
is rejected — so only `leave_household` and `delete_account` can trigger
the cascade. Two cascade paths, not three; pgTAP asserts the negative case
explicitly.

### 2.4 Cascade (F13)

After unclaiming, if the household has zero remaining claimed active
members (`user_id is not null and deleted_at is null`), stamp
`households.deleted_at`.

Child rows are left alone: RLS already hides every row from everyone once
no one is a member, so soft-deleting children buys nothing and costs a
large write. The local `Households` table needs no `deleted_at` mirror
because the only device that could receive the tombstone is the departing
one, which by D-L3 keeps its data as a local-only household anyway.

A scheduled sweep (pg_cron) is explicitly NOT specified: with the cascade
inline in both orphaning paths, a sweep is a backstop for half-failed
exits only. Revisit only with evidence of such failures.

### 2.5 Existing RPCs need a new guard

`redeem_invite`, `list_claimable_members`, `claim_member`, and
`join_as_new_member` must all reject a soft-deleted household. Without it
a still-live invite code resurrects an abandoned household. This is a
change to shipped server functions and needs its own pgTAP case.

### 2.6 Rejected: client-side removal via the existing grant

The codebase baits this: member removal already replicates through the
`members` UPDATE grant on `deleted_at`, which D1 went out of its way to
preserve (`sync-backend.md` §2), so "remove a member" looks free.

It is not. `user_id` is NOT in the granted column list (`name, color,
role, deleted_at` — `20260731120000_initial_schema.sql`), and the cascade
must read every member's claim state atomically. The client-side shortcut
yields a soft-delete that revokes access while leaving `user_id` welded to
a dead row. Recorded here so it is not rediscovered as a shortcut later —
it is also precisely the §0.2 bug.

### 2.7 pgTAP

Extends `supabase/tests/001_rls_isolation_test.sql`:

- per-verb authorization matrix (non-member cannot call any of the three);
- `remove_member` rejects self;
- `remove_member` by any member succeeds regardless of role (D-L2/D1);
- cascade fires on last claimed exit (leave and delete-account);
- cascade does NOT fire when claimed members remain, and never for
  `remove_member` (§2.3);
- every §2.5 RPC rejects a soft-deleted household;
- `delete_account` removes the `auth.users` row (D-L4 — the §5 slice-1
  gate).

## 3. Client

### 3.1 Prerequisite — populate local `members.userId`

Map `user_id` in `HouseholdGateway.downloadHousehold` and in the
`SupabaseSyncEngine` pull path into the existing local column. No
migration. This is what makes the §0.2 guards start working.

Consequence: `_canDelete` becomes `false` for claimed members — so the
Delete affordance for a claimed member must be RE-ROUTED (§3.2), not
merely unblocked. Do not simply drop the guard.

Push is unchanged: `_pushMembers` keeps sending only the four granted
columns. `user_id` is server-owned and pull-only on the client.

**Unlinking must clear it.** Claim state is meaningless in a local-only
household, and a stale `userId` would keep `_canDelete` false forever for
profiles nobody can ever unclaim. So every path that clears the sync link
— `SettingsRepository.clearSyncLink`'s callers: today's Disconnect
(`lib/application/household_link_service.dart`) and §3.5's revocation —
must also null every local `members.userId` in the same transaction.
Disconnect keeps this behaviourally unchanged (it still deletes nothing
and still permits reconnect, since `user_id` on the SERVER is untouched);
it just stops leaving a dead flag behind.

### 3.2 Member removal splits by claim state

- **Unclaimed target** — today's local-only `MemberService.deleteMember`
  path, unchanged (referential cleanup as specified in
  `docs/feedback/2026-08-01-ux-audit.md` A1).
- **Claimed target** — `remove_member` RPC FIRST; on success, the same
  local referential cleanup. This path requires linked-and-online and can
  fail, so it needs a real inline error surface — unlike every other local
  action in this app. `MemberService.deleteMember`'s `userId != null`
  guard is replaced by this routing, not deleted. The local soft-delete
  still marks the row `syncDirty` as it does today; its eventual push of
  `deleted_at` is a harmless no-op convergence on a row the server already
  soft-deleted, so no special-casing in the engine.
- **Own row** — Delete stays hidden; the blocked-reason copy points at
  Leave (mirrors the server's self-removal rejection, §2.2).

### 3.3 One confirm shape for all three exits (D-L3)

Body states the consequences, then an UNCHECKED "also delete this phone's
copy" checkbox with one line explaining what it means, then the action.
Checked → `resetAppData` + `settingsProvider` invalidation (the caller
responsibility documented in `lib/application/data_reset.dart`), which
lands the app on the welcome screen.

Placement: Leave and Delete account join the Account section beside the
existing Disconnect row (`lib/features/settings/account_section.dart`);
Remove stays in the member edit sheet.

Disconnect is unchanged and stays distinct: it is purely local, keeps
`user_id` on the server, and preserves the §7.6 reconnect path
(`lib/application/household_link_service.dart`). The copy must keep the
two clearly apart.

### 3.4 Last-member warning (D-L5)

The Leave confirm needs the count of CLAIMED members to decide whether to
show the cascade warning — another thing §3.1 unlocks. With claimed
members remaining, standard leave copy; as the last claimed member, copy
stating that the online household and its shared history go with you.

### 3.5 Revocation detection

Fold a `findMyMembership()` probe (already exists, `sync-backend.md` §7.6,
`HouseholdGateway`) into the pull path. While linked:

- non-null → normal operation;
- **null → revoked**: clear the sync link, then show the notice carrying
  the same §3.3 keep/delete choice.

This is the ONE place `sync-backend.md` §8.3's swallow-all-errors posture
is deliberately overridden. That contradiction is intentional and is
recorded here so it is not "fixed" back into silence later: §8.3 exists
because the local DB is always self-consistent, which stops being a
sufficient argument once the device has been cut off from its household.

After delete-account the session itself is invalid, so probes fail as
unauthenticated rather than as revoked — a different signal, handled by
the existing auth path, not here.

### 3.6 l10n

All new strings via gen_l10n, EN template + DE (du-form), per
`docs/specs/members-management.md` §5. Key prefixes: `householdLeave*`,
`memberRemove*`, `accountDelete*`, `membershipRevoked*`. Semantic ids
under `settings.account.leave`, `settings.account.deleteAccount`,
`members.remove.*`, `membership.revoked.*`.

## 4. Testing

- **pgTAP** — §2.7, the server's only real test.
- **Widget** — extended `FakeHouseholdGateway` (three RPCs plus
  `findMyMembership` returning null on demand), per
  `sync-backend.md` §7.5's fake-gateway pattern: both checkbox states on
  all three confirms, the §3.2 claimed/unclaimed split including the
  claimed path's failure surface, the §3.4 warning shown/not shown, and
  the §3.5 revocation notice.
- **Unit** — pull populates `userId`; `_canDelete` flips accordingly.
  This pair is what proves the §0.2 bug is dead; without it the fix is
  unverified.
- **E2E** — stays offline per `sync-backend.md` §7.5, so none of this
  gets Maestro coverage. The real gate is the widget suite plus a manual
  live smoke against the local Docker stack following the §7.7 method.

Standard project constraints apply: integration-style widget tests with
only the db/clock/gateway overrides, never awaiting drift streams outside
the pump.

## 5. Slices (dependency order)

1. **Server.** The `auth.users` delete experiment FIRST, then the
   migration and pgTAP. HARD GATE: if the delete is refused, fall back to
   the `sync-backend.md` §2 edge function and revisit the handoff story
   before any client code exists.
2. **`userId` plumbing** (§3.1) + the shared confirm-with-checkbox widget
   (§3.3) that slices 3–6 reuse.
3. **Revocation detection + notice** (§3.5).
4. **Remove a claimed member** (§3.2).
5. **Leave household** + last-member cascade warning (§3.4, D-L5).
6. **Delete account** (§2.2, D-L4).

Slice 3 precedes slice 4 deliberately: shipping claimed-member removal
without the notice means knowingly shipping the §0.1 trap. Slices 1–3 are
independently valuable — they fix a live bug and add no features.

**Main risk:** the `auth.users` delete (D-L4) is the only genuinely
unknown thing here, which is why it is the first task rather than a late
discovery.

## 6. Non-goals

- No role-based enforcement. D1 stands; `members.role` stays vestigial.
- No pg_cron sweep (§2.4).
- No change to Disconnect (§3.3) or to the P2d reconnect flow beyond what
  §3.1 populates.
- No F12 restore-from-backup.
- `chore_assignees` tombstones (`sync-backend.md` §8.5) remain out of
  scope; member removal's assignee cleanup is local and converges via the
  existing full-set replacement.
