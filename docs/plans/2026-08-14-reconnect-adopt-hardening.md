# Reconnect / Adopt Hardening — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development`
> (recommended) or `superpowers:executing-plans` to implement this plan
> task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the two holes on the journey of a user who has just been cut
off from their online household and is trying to get back in — the P2d
reconnect offer (`sync-backend.md` §7.6) and the P2b adopt row (§7.3).

> ### ⚠ The headline: reconnect can wipe a device, and it ships in v0.5.0
>
> `ReconnectChoice` deliberately makes **no RPC**. `downloadHousehold` returns
> an **empty result** rather than an error when RLS denies access. `join` then
> **deletes the local household and inserts nothing**. Every chore,
> occurrence, category, member and shopping item on the device is gone, and
> **there is no recovery** — the JSON archive it writes first is the only
> trace, and the app has no importer for it (backlog **G-3 / F12** is
> unbuilt).
>
> This is **live in the released v0.5.0**, not latent. Task 1 is the fix; it
> is the first task for that reason.

Alongside it, adopt presents a permanent dead end as a retryable action
(Finding 3).

**Architecture:** No new services, no new screens, no schema change on either
side. Two typed failures on existing seams (`HouseholdJoinService`,
`HouseholdGateway`), four predicates on one PostgREST query, one new terminal
state on an existing row, four pgTAP assertions, and copy.

**Tech Stack:** Flutter 3.44.8, Riverpod, drift/SQLite, gen_l10n; Postgres 15
/ Supabase, pgTAP.

**Spec:** `docs/specs/sync-backend.md` §7.3 (adopt), §7.6 (reconnect) and
`docs/specs/household-lifecycle.md` §2.4/§2.5/§3.5 are the binding contracts.
Task 7 amends the first two to record what this plan establishes.

**Depends on:** slices 1–3 of `docs/specs/household-lifecycle.md`, which are
landed on `main` (migration `20260808120000_membership_exit.sql`, pgTAP
`002_membership_exit_test.sql`, `SettingsRepository.clearSyncLink`'s G-A
cleanup, `HouseholdLinkService.adopt`'s G-B claim mirror, the revocation probe
in `SupabaseSyncEngine._pullSinceInner`, `MembershipRevokedNotice`).

---

## Sequencing verdict vs. `docs/plans/2026-08-08-household-lifecycle-slices-4-6.md`

**This plan lands BEFORE slices 4–6 — specifically before that plan's Task
12.** Four reasons, in descending weight:

1. **Task 1 fixes a defect that is live in the released v0.5.0** (Finding 1
   below) and whose blast radius is the user's entire local household, with no
   in-app recovery — the JSON archive it writes has no importer (backlog G-3 /
   F12 is unbuilt). That is not "hardening"; it is a shipped data-loss bug, and
   those do not queue behind features.
2. **Slices 4–6 multiply the population that reaches it.** Leave (slice 5),
   remove-a-claimed-member (slice 4) and delete-account (slice 6) all end with
   a device that is signed in, unlinked, holding a full local copy, and
   carrying a `MyMembership` that may already be stale — which is exactly the
   input Task 1 guards against.
3. **The slices 4–6 plan already forbids this shape.** Its own rule — "Do not
   ship slice 4 before slice 3 is in… slice 3's notice is what makes it
   honest" — is the same argument one level out: do not ship the exits before
   the re-entry path they feed is safe.
4. **Merge mechanics.** Both plans append to `lib/application/household_gateway.dart`,
   `lib/features/settings/account_section.dart`,
   `test/features/settings/fake_household_gateway.dart` and both `.arb` files.
   This plan is ~7 tasks against that plan's 11; landing the small one first
   makes the large one's rebase mechanical rather than the other way round.

Nothing here depends on slices 4–6. The two plans can be executed by different
agents; only the merge order is constrained.

---

## What was actually verified (read this before Task 1)

The ticket that commissioned this plan carried two findings. **One held up as
stated. One did not — and the real defect on that path turned out to be far
worse, so it leads this section.** Both are recorded honestly here, because a
plan built on the wrong premise is how the slices 1–3 plan acquired seven
defects.

### Finding 1 (HEADLINE) — the reconnect replace is unconditional, and it wipes the device

`HouseholdJoinService.join` (`lib/application/household_join_service.dart:194-275`)
runs, in order: write the archive → resolve the choice → `downloadHousehold` →
**one transaction that deletes the old household and inserts the snapshot**.

`ReconnectChoice` deliberately makes **no RPC at all** (`_resolveChoice`, lines
328-331; spec §7.6: "idempotency also covers a re-claim, but no call is
cleaner"). That is the only one of the three `JoinChoice` variants with no
server-side authorization step — so `downloadHousehold` is the *sole* thing
standing between a stale offer and the delete.

And `downloadHousehold` **does not fail when access is denied.** RLS filters
rows; it does not error. The sync engine's own revocation probe is built on
exactly this property and says so ("RLS stops returning rows rather than
erroring", `lib/application/sync_engine.dart:404-406`). So a reconnect to a
household the caller is no longer a member of returns
`HouseholdSnapshot(household: null, members: [], …)`, and the transaction then:

- deletes every local chore, occurrence, assignee, shopping item, category,
  member and the household row (`_deleteHousehold`, lines 343-372);
- inserts nothing (`_insertSnapshot` no-ops on every empty list, lines 379-402);
- points `settings.actingMemberId` at a member that no longer exists and
  `settings.syncHouseholdId` at a household that was never inserted.

`householdGateProvider` then reports no household and the app lands on the
welcome gate, empty. **The wipe is unrecoverable in-app:** the archive file
written at step 1 is the only trace of the data, and restore-from-backup
(**G-3 / F12**) is not built.

**This is live in the released v0.5.0 — narrow, but not theoretical.** The
exposure today:

- `remove_member` **exists in the production migration**
  (`20260808120000_membership_exit.sql`, confirmed applied to production
  2026-08-14 per `docs/handover-2026-08-14-planning.md` §1). The *client UI*
  for it is still slice 4, but the RPC is callable now, and the earlier
  direct-grant soft-delete path on `members.deleted_at` has always been.
- Revocation detection **already ships** (`_pullSinceInner`,
  `sync_engine.dart:413-417`), so devices already reach the
  signed-in-and-unlinked state that renders the reconnect offer.
- `myMembershipProvider` is a plain, **non-`autoDispose`** `FutureProvider`
  (`lib/app/providers.dart:320-330`) that re-runs only when
  `householdGatewayProvider` or `currentAuthUserProvider` changes. It does not
  re-probe when Settings is opened, and it does not re-probe between the probe
  and the tap. Any removal, leave-cascade or delete-account landing in that
  window produces exactly this.

Slices 4–6 do not create this bug; they turn a narrow window into a routine
one. Task 1 is the fix and is the task that makes it live.

### Finding 2 — `findMyMembership`'s missing `deleted_at` predicates (as handed over: REFUTED)

**The code observation is real; the consequence asserted from it is not.** The
predicates really are absent, and noticing that is what led to Finding 1 —
but the state they were supposed to admit is already closed one layer down.
`SupabaseHouseholdGateway.findMyMembership`
(`lib/application/household_gateway.dart:443-474`) does run
`.from('members').select().eq('user_id', userId).limit(1)` with no
`deleted_at` predicate, and the follow-up `households` select has none either.
But neither query is reachable in the state the finding describes, because
**RLS closes both**:

- `members_select` is `using (public.is_household_member(household_id))`
  (`20260731120000_initial_schema.sql:192-193`), and
  `public.is_household_member(hid)` is true only when a `members` row exists
  with `user_id = auth.uid() AND deleted_at IS NULL` (same file, lines
  156-175). `members_one_claim_per_household unique (household_id, user_id)`
  (line 42) means an account has **at most one** row per household. So an
  account whose only row in a household is soft-deleted cannot select that row
  at all: the query returns empty, not a stale membership.
- A soft-deleted household cannot hold a claimed **active** member.
  `_cascade_if_orphaned` stamps `households.deleted_at` only when
  `count(*) where user_id is not null and deleted_at is null` is zero
  (`20260808120000_membership_exit.sql:142-167`), and every re-claim path into
  a soft-deleted household is already blocked — `_valid_invite` rejects it
  (§2.5, same migration, lines 220-245), `members_insert` requires
  `user_id is null`, and `user_id` is not in the client's UPDATE grant.
  So the `households` select cannot return a soft-deleted row to a caller who
  got past the `members` select.

The predicates are still worth adding (Task 3) — as **defense in depth,
labelled as such**. Their real value is that today the entire reconnect offer
rests on one clause in one `SECURITY DEFINER` function, undocumented and
untested from this direction. Task 4 pins that with pgTAP so any future
weakening of `is_household_member` turns a test red instead of turning a
destructive replace live.

**Do not let the refuted version reach a spec.** Task 7 writes only what was
verified: `is_household_member` is the boundary, the predicates are redundant
today, and pgTAP now proves both. This project has already had to correct a
committed spec that carried a claim derived from an incomplete grep
(`household-lifecycle.md` §0.2's correction note); this is that failure mode
caught one step earlier.

### Finding 3 — adopt deterministically fails after a revocation-triggered unlink

**Holds, and the mechanism is slightly more interesting than stated.**

`createHousehold` passes the local household id verbatim
(`household_gateway.dart:117-123, 251-268`) into `create_household`, whose
first statement is a plain `insert into households (id, name, created_by)`
(`20260731120000_initial_schema.sql:263-286`). After a revocation,
`_pullSinceInner` calls `settings.clearSyncLink()`
(`sync_engine.dart:413-417`), which clears the link but keeps every local row —
including the household, still carrying the server household's id. So the
insert PK-conflicts.

The interesting part is `adopt`'s resume heuristic
(`household_link_service.dart:65-85`): on any exception from step 1 it calls
`downloadHousehold(householdId)` and treats a readable household as
"step 1 already succeeded, continue". That heuristic keys on *"can I still read
this household"* — which is **true after a Disconnect** (the server keeps your
`user_id`, so `is_household_member` still passes and Disconnect → Adopt works
today) and **false after a revocation**. The one user for whom the resume path
cannot fire is precisely the removed user. The result is `rethrow` → the row's
generic `settingsAccountAdoptError` + "Try again", which will never succeed, on
this device, ever.

Tasks 4–6 replace that with a typed signal and a terminal state that names the
recourse. **Fixing this needs a product decision, not only code — see OPD-1.**

### Not folded in: `syncRefreshError`

The handover records that `syncRefreshError`'s copy ("Your changes are saved
here and will sync later" — `lib/l10n/app_en.arb:1166`) is untrue for a device
that was just revoked and unlinked. **This plan does not touch that surface.**
Its two call sites are `lib/features/chores/chores_list_screen.dart:461` and
`lib/features/shopping/shopping_list_screen.dart:210` — the pull-to-refresh
snackbars — and nothing here goes near them. It stays with the slices 4–6
patch that is adding it there. Recorded so it is not lost.

Note for whoever does touch it: `app_de.arb:258` stores that one string's
umlauts as `ä`-style JSON escapes while the other 65 German lines use
literal `ä/ö/ü/ß` (`docs/backlog.md`, "Execution hazards between plans"). An
edit anchored on its rendered German text will not match.

---

## Product decisions — both RESOLVED 2026-08-14

Both were genuinely open when this plan was drafted: user-visible, and not
derivable from any binding spec. **Both recommendations were accepted**, OPD-2
with one added requirement (see its "Determinism alone is not sufficient"
block). They are recorded below as decisions, not proposals; the options and
reasoning are kept so the choice can be re-opened on evidence rather than
re-derived.

### OPD-1 — May a removed member take their local copy online as a household of their own? → **NO for now; backlogged**

A user removed from household H keeps their local copy by design (D-L3). They
now want to be online again. Two legitimate intents: *"get me back into my
family's household"* (join by code — works today) and *"make this copy MY
household"* (adopt — impossible today, and after this plan, honestly refused).

**Option 1 — No, for now. Adopt explains and points at join-by-code.**
Tasks 5–6 as written. The adopt row stops being a retry loop and becomes a
terminal, explanatory state naming the join row as the recourse (the project's
standing bar: a notice that reports a fault and offers nothing is a dead end —
`docs/backlog.md` E-2, D-5). Cost: two l10n strings and one widget branch.
Leaves the fork intent unserved; the only escape is "Reset app data", which is
destructive.

**Option 2 — Yes, via a local re-key ("fork") before adopting.**
On the detected conflict, mint a fresh UUID for the household **and for every
local row that carries an id or an FK** — `members`, `categories`, `chores`,
`chore_assignees` (composite `chore_id, member_id`), `chore_occurrences`
(`id`, `chore_id`, `assignedMemberId`, `completedBy`), `shopping_items`
(`id`, `categoryId`, `addedBy`), plus `settings.actingMemberId` — then adopt.
**The household-id-only version does not work and must not be attempted:**
`create_household` inserts the acting member *by id*, and every local row id is
a copy of the original household's server id, so the member insert
PK-conflicts too, and the subsequent `uploadHouseholdData` would either be
silently skipped (`members` uses `ignoreDuplicates: true`) or rejected by RLS
(the other tables' plain upserts would target rows in a household the caller
cannot update). A full re-key is the smallest correct version: one local
transaction, an id map per table, ~7 tables. Real work (S–M) with real bug
surface — a missed FK is silently orphaned history — for a use case nobody has
reported.

**Option 3 — Make `create_household` idempotent for a caller who is already a
claimed member of that household.** Recorded so it is not proposed later as
"the obvious fix": **it does not fix this bug.** The removed user is not a
member. It would only move the client's existing resume heuristic
(`household_link_service.dart:73-85`) server-side, where it is admittedly
tidier — a separate, optional cleanup, not this.

**DECIDED: Option 1 now, Option 2 as a backlog row** (Task 7 adds it).
Rationale as accepted: a removed member **keeping** their local copy is already
the D-L3 default, so nothing is being taken away; turning that copy into an
*independent online household* is a genuinely bigger feature than this ticket.
The re-key finding above is precisely why it must not be improvised inside an
adopt-failure branch — Task 7's backlog row carries that finding verbatim so
whoever picks it up does not rediscover it.

**What the plan assumes:** Tasks 4–5 build the typed conflict signal
(`HouseholdIdTakenFailure`, pinned by pgTAP) regardless of the answer. Task 6
consumes it as a terminal state. If Igor picks Option 2, Tasks 4–5 are
unchanged and Task 6's blocked state becomes the entry point for a re-key task
appended after it. Nothing has to be undone.

### OPD-2 — What should reconnect offer when the account is a claimed member of several households? → **Deterministic most-recent-first now; chooser backlogged**

Legitimate and reachable: adopt on device 1, then join a second household by
code on device 2, and the account claims a member in both — `delete_account`'s
own comment relies on this ("`user_id` is UNIQUE per household, so there may be
several", `20260808120000_membership_exit.sql:29-31`). Today `findMyMembership`
does `.limit(1)` with **no `ORDER BY`** (`household_gateway.dart:451-455`), so
the destructive replace is offered for whichever household Postgres happens to
return first, and the answer can change between app launches.

- **(a) Deterministic single offer, most-recent membership first** —
  `.order('created_at', ascending: false)` on the `members` select. One line.
- **(b) A chooser** — `findMyMembership` returns a list, the reconnect row
  becomes a picker. Correct, and a new UI surface plus a gateway signature
  change plus l10n plus tests.
- **(c) Offer none when there are several** — safest, and punishes the
  multi-household user for no reason.

**Recommendation: (a) now, (b) as a backlog row.**

**Determinism alone is not sufficient, and the plan does not claim it is.**
Picking the wrong household deterministically is still picking the wrong one,
and the pick drives a destructive replace. Two things make (a) safe enough to
ship as an interim:

**The ordering column, named and justified: `members.created_at`, descending.**
The household someone joined *last* is the one they are most likely trying to
return to — a returning device is almost always returning to its most recent
home, not to a household it left years ago. `created_at` is the honest proxy
available: it is **exact** for `join_as_new_member` (the row is inserted at
join time) and for `create_household`/adopt (same), and **approximate** for
`claim_member`, where the profile may predate the claim by any amount because
the RPC only sets `user_id` on an already-existing row. There is no true
claim-timestamp column — `updated_at` is trigger-maintained and moves on every
edit, so it is a recency signal for *activity*, not for *joining*, and would
rank a household you were merely mentioned in above one you actually joined
yesterday. Task 3 must record this reasoning at the query, including the
`claim_member` imprecision, so nobody "improves" it to `updated_at` later.

**The user can always decline, because the offer names the household.**
Verified on both paths that reach it: `_ReconnectRow` in
`lib/features/settings/account_section.dart:556` and `_buildReconnectOffer` in
`lib/features/onboarding/welcome_join_page.dart:250-252` both render
`l10n.settingsAccountReconnectTitle(membership.householdName)` — "Reconnect to
{householdName}" — and both are pinned by existing tests
(`account_section_test.dart` and `welcome_join_test.dart` each assert
`find.text('Reconnect to Joined household')`). **There is no path to the offer
that hides the name, so no gap to close here.** Task 3 strengthens this: its
`return null`-on-missing-household change removes the one way a nameless
"Reconnect to " could ever render.

**What the plan assumes:** Task 3 adds the descending `.order`; Task 7 files
(b). If Igor picks (b), Task 3's one line is discarded and the signature change
is additive.

---

## Judgement calls (resolved here, no decision needed)

- **The guard belongs in `HouseholdJoinService`, not in the gateway.** The
  gateway is a thin "move bytes" seam (its own doc comment); "an empty
  snapshot must not be allowed to replace live local data" is an application
  rule.
- **The guard aborts BEFORE the transaction, not inside it.** Throwing before
  `database.transaction(...)` opens means nothing was deleted, so no rollback
  is relied upon and the failure is provably non-destructive. The already-
  written archive is harmless.
- **Strictness is asymmetric by choice.** All three `JoinChoice` variants get
  the "household row present" check. Only `ReconnectChoice` additionally
  requires its member to be present and active in the snapshot, because it is
  the only variant with no server-side authorization step. Both existing
  reconnect widget tests already seed that member
  (`account_section_test.dart:748-767`, `welcome_join_test.dart:157-176`), so
  this costs one unit-test fixture line, not a sweep.
- **A failed reconnect invalidates `myMembershipProvider`.** An offer the
  server just refused to honour must not stay on screen. One `ref.invalidate`
  at the two failure sites; no persistence, no new state.
- **The blocked adopt state is per-visit, not persisted.** It lives in
  `_AdoptRowState`, so it resets on rebuild. Correct: a user who rejoins by
  code and later disconnects genuinely *can* adopt again (the resume path
  fires), and persisting "blocked" would be wrong for them. No schema change.
- **Three of this plan's server assertions are characterization tests, not
  red-green ones.** They pass the moment they are written, because they pin
  behaviour that already holds. Task 4 says so explicitly per assertion rather
  than pretending otherwise — see the handover's warning about assertions that
  cannot fail.

---

## Global Constraints

- Tests run as
  `env -u GIT_DIR -u GIT_INDEX_FILE flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= <file>`.
  **Without both dart-defines six unrelated tests fail and read as
  regressions.** `lefthook.yml` is the reference.
- `env -u GIT_DIR -u GIT_INDEX_FILE` on every `flutter`/`dart` invocation when
  anywhere near git hooks or worktrees. Never more than 2 concurrent
  `flutter test`/`build` processes.
- **Never hand-roll a `ProviderScope` pump in a widget test.** Use
  `test/test_utils/pump_app.dart`'s `testChoreApp` / `testFreshChoreApp`,
  `test/features/settings/settings_test_utils.dart`'s `openSettingsTab`, and
  `find.bySemanticsIdentifier` inside a `tester.ensureSemantics()` handle. A
  hand-rolled pump that closes the database in `tearDown` **hangs** —
  flutter_test's pending-Timer leak check runs before tear-downs, so drift's
  stream-cleanup timer never drains — which hangs the whole suite and the
  pre-commit hook with it. `pump_app.dart`'s own header documents this.
- Never `await` a drift stream outside a widget pump.
- Widget tests are integration-style: real in-memory `AppDatabase`, fixed
  clock, overriding only `appDatabaseProvider` / `clockProvider` plus the
  documented gateway seams (`authGatewayProvider`, `householdGatewayProvider`)
  with the fakes under `test/features/settings/`. Never mock a repository or a
  service.
- Every user-visible string goes through gen_l10n: `lib/l10n/app_en.arb`
  (template, **with an `@`-description**) AND `lib/l10n/app_de.arb` (informal
  du-form). German for device is **"Gerät"**, never "Handy". The generated
  `app_localizations*.dart` files ARE committed.
- `semantic()` is `Widget semantic(String id, {required Widget child})` —
  NAMED `child:`. Positional will not compile.
- Strict lints: `very_good_analysis` with `--fatal-infos`. Public members need
  doc comments.
- `supabase test db` does **NOT** apply migrations — run `supabase db reset`
  first. In pgTAP, `test_login()` sets `role=authenticated` via
  `set_config(..., true)`, which persists for the **rest of the transaction**:
  any statement needing superuser must `reset role;` first. UUID literals are
  **hex only** — `g`, `h`, `j`, `z` are not valid hex digits and fail to parse.
- Beware vacuous assertions. `is((select <col> from <missing row>), null, …)`
  passes because a scalar subquery over no rows yields NULL and pgTAP's `is()`
  treats NULL as equal to NULL. Assert `count(*)` against `0::bigint` instead.
- `public.is_household_member(hid)` is the security boundary for every RLS
  policy. Nothing in this plan may weaken it or `members.user_id` /
  `household_id` / `deleted_at`. DELETE is granted nowhere; soft deletes only.
- `members.role` is vestigial (D1). No role checks anywhere, not even in a
  comment implying one is coming.
- Never call a network RPC inside a `database.transaction(...)`.
- Never add `Co-Authored-By:` or any co-author trailer to a commit message.
- E2E runs fully offline (`NoopAuthGateway`), so **no task here gets Maestro
  coverage**. The gates are the widget/unit suite plus pgTAP.

---

## File map

**New:** none.

**Modified:**

| Path | What |
| --- | --- |
| `lib/application/household_join_service.dart` | `HouseholdSnapshotUnavailable`; the pre-transaction guard in `join` + `joinFresh` (Task 1) |
| `lib/features/settings/join_household_sheet.dart` | Maps the new failure to its own inline copy; invalidates `myMembershipProvider` (Task 2) |
| `lib/features/onboarding/welcome_join_page.dart` | Same, for the welcome reconnect offer (Task 2) |
| `lib/application/household_gateway.dart` | `findMyMembership` predicates/order/null-on-missing-household (Task 3); `HouseholdIdTakenFailure` from `createHousehold` (Task 5) |
| `lib/application/household_link_service.dart` | `HouseholdAlreadyOnlineFailure` from `adopt`'s resume branch (Task 6) |
| `lib/features/settings/account_section.dart` | `_AdoptRowState`'s terminal blocked state (Task 6) |
| `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb` | Three new strings (Tasks 2, 6) |
| `supabase/tests/002_membership_exit_test.sql` | Four assertions, `plan(33)` → `plan(37)` (Task 4) |
| `test/application/household_join_service_test.dart` | Guard tests; one existing fixture gains a member (Task 1) |
| `test/features/settings/join_household_sheet_test.dart` | The stale-reconnect failure surface (Task 2) |
| `test/features/settings/account_section_test.dart` | The blocked adopt row (Task 6) |
| `test/features/settings/fake_household_gateway.dart` | Nothing new needed — `createHouseholdError` and `downloadSnapshotOverride` already cover every case here. **Verify before adding anything.** |
| `docs/specs/sync-backend.md` | §7.3 failure taxonomy, §7.6 probe contract (Task 7) |
| `docs/backlog.md` | Two new rows from OPD-1 / OPD-2 (Task 7) |

**Unchanged, deliberately:** `supabase/migrations/` (no schema change on either
side), `lib/application/sync_engine.dart`, `lib/data/db/` (no client schema
bump — this plan must not collide with the B-3 / G-1 schema-v10 contention
recorded in `docs/backlog.md`).

---

## Task 1: `HouseholdJoinService` refuses to replace on an unconfirmed snapshot

**⚑ This task makes the Finding 1 (headline) fix LIVE.** After it, no code path can
delete a local household in exchange for an empty snapshot.

**Files:**
- Modify: `lib/application/household_join_service.dart`
- Modify: `test/application/household_join_service_test.dart`

**Interfaces:**
- Produces: `HouseholdSnapshotUnavailable implements Exception` — public,
  exported from `household_join_service.dart`, consumed by Task 2.
- `join` and `joinFresh` may now throw it. Both already run inside `on
  Exception` catches at every call site (`join_household_sheet.dart:309`,
  `welcome_join_page.dart`), so no call site breaks.

- [ ] **Step 1: Write the failing tests first**

In `test/application/household_join_service_test.dart` (which already has the
`setUp`/`tearDown` scaffolding, a seeded `old-hh`, and a `FakeHouseholdGateway`
pattern — copy the existing `reconnect (spec §7.6)` test at line ~73 as the
shape), add:

1. **`reconnect against a household the caller can no longer read aborts and
   destroys nothing`** — gateway with `downloadSnapshotOverride =
   const HouseholdSnapshot()` (all empty), `join(oldHouseholdId: 'old-hh',
   choice: ReconnectChoice(householdId: 'joined-hh', memberId: 'm-anna'),
   importAccepted: false)`. Expect `throwsA(isA<HouseholdSnapshotUnavailable>())`,
   then assert the local household survives:
   `expect((await db.select(db.households).get()).map((h) => h.id), ['old-hh'])`,
   and that `settings.syncHouseholdId` is still `null`.
2. **`reconnect whose own member row is missing from the snapshot aborts`** —
   snapshot carries the `joined-hh` household row but **no members**. Same
   assertions. This is the `ReconnectChoice`-only strictness.
3. **`reconnect whose member row is present but soft-deleted aborts`** — same
   snapshot with one `Member(id: 'm-anna', …, deletedAt: 't1')`.
4. **`claim against an empty snapshot aborts`** — `ClaimMemberChoice`, empty
   snapshot. Proves the household-row check applies to all three variants.
5. **`joinFresh against an empty snapshot aborts without linking`** — assert
   `settings.syncHouseholdId` stays `null` (the welcome path has no household
   to lose, but it must not record itself as linked to nothing).

Also **update the existing reconnect test at line ~73**: its
`downloadSnapshotOverride` is household-only, so the new member check will
reject it. Add a `members: [Member(id: 'm-anna', householdId: 'joined-hh',
name: 'Anna', color: 0xFF6D9F71, role: MemberRole.member, createdAt: 't0',
updatedAt: 't0', syncDirty: false)]` list. **This is a fixture correction, not
a regression** — the two reconnect *widget* tests
(`account_section_test.dart:748`, `welcome_join_test.dart:157`) already seed
exactly this member and need no change; verify that before touching them.

- [ ] **Step 2: Run to verify they fail — and check the failure mode**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/application/household_join_service_test.dart
```

**Expected RED, per test:** each new test fails on the `throwsA` matcher with
*"Expected: throws <Instance of 'HouseholdSnapshotUnavailable'> / Actual:
<Future> … which returned a HouseholdJoinResult"* — the call **succeeds**
today. If you comment the `throwsA` out and keep only the survival assertion,
the second red is `Expected: ['old-hh'] Actual: []` — the households table is
**empty**, which is the data loss this task exists to stop. Confirm you have
seen one of those two reds before writing the fix; a test that goes green
without the fix means the guard is in the wrong place.

- [ ] **Step 3: Add the failure type and the guard**

In `lib/application/household_join_service.dart`, add a public exception class
next to `HouseholdJoinResult` with a doc comment recording *why* it exists (RLS
filters rows rather than erroring, so an empty snapshot is what a revoked
membership looks like on the wire — cite `sync_engine.dart`'s revocation-probe
comment).

Then, in **both** `join` and `joinFresh`, immediately after the
`await gateway.downloadHousehold(...)` line and **before** the
`database.transaction(...)` call, reject:

- `downloaded.household == null` → throw, for every choice;
- additionally, when `choice is ReconnectChoice`, when
  `downloaded.members` contains no row with `id == choice.memberId &&
  deletedAt == null` → throw.

Keep the check in one small private helper called from both methods so the two
paths cannot drift. Document at the call site that the archive has already been
written and that this is deliberate: an extra archive is harmless, a deleted
household is not.

- [ ] **Step 4: Run to verify green**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/application/household_join_service_test.dart
env -u GIT_DIR -u GIT_INDEX_FILE flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/settings/join_household_sheet_test.dart test/features/settings/account_section_test.dart test/features/onboarding/welcome_join_test.dart
env -u GIT_DIR -u GIT_INDEX_FILE flutter analyze --fatal-infos
```

Expected: all green, `No issues found!`. The second command is the regression
check that the asymmetric strictness cost nothing.

- [ ] **Step 5: Commit**

```bash
git add lib/application/household_join_service.dart test/application/household_join_service_test.dart
git commit -m "Never replace a local household with an unconfirmed snapshot (spec §7.6)"
```

---

## Task 2: The reconnect failure names its cause and retires the stale offer

**Files:**
- Modify: `lib/features/settings/join_household_sheet.dart`
- Modify: `lib/features/onboarding/welcome_join_page.dart`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`
- Modify: `test/features/settings/join_household_sheet_test.dart`

**Interfaces:**
- Consumes: `HouseholdSnapshotUnavailable` (Task 1).
- Produces: l10n key `joinHouseholdNoLongerMemberError`. No new semantic id —
  the existing `settings.account.join.retry` inline-error slot is reused.

- [ ] **Step 1: Write the failing widget test first**

In `test/features/settings/join_household_sheet_test.dart`, copy the shape of
the existing reconnect-flow tests (they already build a `FakeHouseholdGateway`
with `membership` + `downloadSnapshotOverride` and drive the sheet through
`openSettingsTab` → tap `settings.account.reconnect` → tap
`settings.account.join.import.decline`). Set
`downloadSnapshotOverride = const HouseholdSnapshot()` so the reconnect aborts,
and assert:

- the new copy is on screen (`find.text(...)` against the EN string);
- the generic `joinHouseholdWorkingError` copy is **not**;
- the local household still exists in `database` (guard against a regression of
  Task 1 from the UI side);
- after dismissing the sheet, `find.bySemanticsIdentifier('settings.account.reconnect')`
  is `findsNothing` — the invalidated probe re-resolved to the fake's
  `membership`… **note:** `FakeHouseholdGateway.findMyMembership` returns
  `membership` unconditionally, so an invalidation alone will re-offer it. To
  assert the retirement, set `gateway.membership = null` immediately before
  the failing tap, so the re-probe returns null. Assert
  `gateway.findMyMembershipCallCount` increased, which is the invalidation
  actually firing.

Remember `tester.ensureSemantics()` around every `bySemanticsIdentifier`
lookup, and dispose the handle before the test body returns.

- [ ] **Step 2: Run to verify it fails**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/settings/join_household_sheet_test.dart
```

**Expected RED:** the new copy assertion fails with *"Expected: exactly one
matching node … Actual: _TextFinder … found 0 widgets"*, because the sheet
still renders the generic `joinHouseholdWorkingError`. The call-count
assertion also fails (`1` vs the expected `2`).

- [ ] **Step 3: Add the strings**

`lib/l10n/app_en.arb` — append near the existing `joinHousehold*` block, with
an `@`-description explaining that this is the one join/reconnect failure the
user can act on, and that the recourse it names is an invite code:

```json
  "joinHouseholdNoLongerMemberError": "This household is no longer available to your account. Nothing on this device was changed. Ask someone in the household for a new invite code.",
```

`lib/l10n/app_de.arb` — the du-form counterpart. Use **"Gerät"**. Keep the
umlauts **literal** (`ä/ö/ü`), matching the file's dominant convention.

- [ ] **Step 4: Map the failure at both call sites**

In `join_household_sheet.dart`'s `_runJoin` catch (currently
`on Exception { … _inlineError = l10n.joinHouseholdWorkingError; }`), branch on
`error is HouseholdSnapshotUnavailable` for the new copy, keeping the generic
message for everything else. In the same branch, call
`ref.invalidate(myMembershipProvider)` — with a comment stating that an offer
the server refused to honour must not survive the failure.

Apply the identical branch in `welcome_join_page.dart`'s join failure handler.
Do **not** extract a shared helper for two lines; `joinCodeErrorMessage`
(`lib/features/settings/join_flow_steps.dart:50-54`) is the existing precedent
for a shared *mapper*, and if you prefer one, put it there next to that
function rather than inventing a new file.

- [ ] **Step 5: Run to verify green**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter gen-l10n
env -u GIT_DIR -u GIT_INDEX_FILE flutter analyze --fatal-infos
env -u GIT_DIR -u GIT_INDEX_FILE flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/settings/ test/features/onboarding/
```

Expected: green. Commit the regenerated `lib/l10n/app_localizations*.dart`.

- [ ] **Step 6: Commit**

```bash
git add lib/features/settings/join_household_sheet.dart lib/features/onboarding/welcome_join_page.dart lib/l10n/ test/features/settings/join_household_sheet_test.dart
git commit -m "Name the stale-reconnect failure and retire the offer that caused it"
```

---

## Task 3: `findMyMembership` becomes honest on its own, not only via RLS

**Files:**
- Modify: `lib/application/household_gateway.dart`

**Interfaces:** none changed. `MyMembership` and the method signature are
untouched; `myMembershipProvider` and both reconnect rows are unaffected.

**This task has NO Dart test.** `SupabaseHouseholdGateway` is never exercised
by the suite (every test substitutes `FakeHouseholdGateway`, by design —
`household_gateway.dart`'s own header says so). Do not invent one; Task 4 is
where this behaviour is proven. Say this in the commit message so a reviewer
does not read the absence as an oversight.

- [ ] **Step 1: Add the predicates, the ordering, and the null return**

In `SupabaseHouseholdGateway.findMyMembership` (line ~443):

- members select: add `.isFilter('deleted_at', null)` and
  **`.order('created_at', ascending: false)`** before `.limit(1)` — most
  recent membership first, per **OPD-2**. Use `.isFilter(..., null)` — the
  same idiom `revokeActiveInvites` already uses at line 341 — not
  `.eq('deleted_at', null)`, which compiles to a SQL `=` against NULL and
  matches nothing.
- households select: add `.isFilter('deleted_at', null)`.
- replace the `householdRows.isEmpty ? '' : …` fallback with an early
  `return null`. A blank `householdName` renders the reconnect row as
  "Reconnect to " with nothing after it; there is no state in which the
  members row is readable and its household row is not (both policies gate on
  `is_household_member` of the same id), so `null` is both correct and strictly
  better than an empty string.

- [ ] **Step 2: Document what these are and are not**

Extend the method's doc comment (and the interface's, line ~168) to record:

- these predicates are **defense in depth**: `is_household_member` already
  requires the caller's own `members` row to be active, and `_cascade_if_orphaned`
  never soft-deletes a household that still has a claimed active member, so
  neither predicate changes any reachable result today;
- they exist because a single clause in one `SECURITY DEFINER` function is the
  only thing standing between this probe and a destructive local replace, and
  that dependency should be visible at the query, not inferred;
- `.order('created_at', ascending: false)` makes the multi-household case
  (legitimate per `20260808120000_membership_exit.sql`'s `delete_account`
  comment) deterministic **and defensible**: the household joined last is the
  one a returning device is most likely returning to. Record that
  `created_at` is exact for join-as-new and adopt but **approximate for
  `claim_member`**, where the profile can predate the claim, and that
  `updated_at` is NOT a substitute — it is trigger-maintained and moves on
  every edit, so it ranks activity rather than joining. Cite **OPD-2** for the
  chooser that would actually solve this, and note that the auto-pick is only
  acceptable because the reconnect row displays the household name, so the
  user can decline it.

- [ ] **Step 3: Verify**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter analyze --fatal-infos
env -u GIT_DIR -u GIT_INDEX_FILE flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/
```

Expected: `No issues found!` and a fully green suite — nothing in the suite
touches this class, so any red here is a genuine surprise worth stopping for.

- [ ] **Step 4: Commit**

```bash
git add lib/application/household_gateway.dart
git commit -m "Filter soft deletes in findMyMembership (defense in depth; RLS is proven in pgTAP)"
```

---

## Task 4: pgTAP pins the boundary the reconnect probe rests on

**Files:**
- Modify: `supabase/tests/002_membership_exit_test.sql`

**Interfaces:**
- Produces: the proof that Task 3's predicates are redundant-but-correct, and
  the proof of the error code Task 5 branches on.

**Honesty requirement — read before writing:** three of the four assertions
below are **characterization tests. They pass the moment they are written**,
because they pin behaviour that already holds on `main`. There is no red phase
for them and you must not manufacture one. Their value is regression: any
future change that weakens `is_household_member`'s `deleted_at IS NULL` clause,
or `_valid_invite`'s household check, turns them red. State this in the SQL
comments so the next reader does not mistake them for the plan's own fix.
The fourth (the `23505` code) is a genuine new contract: Task 5's client branch
is only correct if it holds.

- [ ] **Step 1: Reset the local stack, then confirm the file is green as-is**

```bash
supabase db reset
supabase test db
```

Expected: `002_membership_exit_test.sql` reports 33 passing. **`supabase test
db` does not apply migrations** — if you skip the reset you will be testing a
stale schema.

- [ ] **Step 2: Add the assertions and bump the plan**

Change `select plan(33);` (line 6) to `select plan(37);`. Append a new section
at the end of the file, before the final `select * from finish();` /
`rollback;`:

1. **A removed member's own `members` row is invisible to them.** After an
   existing fixture's `remove_member`, `test_login()` as the removed user and
   assert `is((select count(*) from members where user_id = <them>), 0::bigint,
   …)`. **Assert `count(*)`, never a scalar column against `null`** — the
   latter passes vacuously.
2. **A soft-deleted-but-still-claimed row is equally invisible to its
   claimant.** Build it the only way it is reachable: `reset role;`, then a
   direct `update members set deleted_at = now()` on a claimed row — the exact
   state `20260808120000_membership_exit.sql:45-61` documents as reachable
   through the `members` UPDATE grant. Then `test_login()` as that user and
   assert `count(*) = 0` again. This is the case the ticket's Finding A worried about; the
   test is what makes "RLS already closes it" a fact rather than a reading.
3. **After the cascade, the departed account sees no household row.** Assert
   `count(*)` of `select from households where id = <cascaded>` is `0::bigint`
   for the account that left last.
4. **`create_household` on an id that already exists raises `23505`.**
   `select throws_ok($$select create_household(<existing hh id>, …)$$, '23505',
   null, 'create_household on a taken id raises unique_violation')` — follow
   the `throws_ok(sql, sqlstate, null, description)` form already used
   throughout `001_rls_isolation_test.sql:82-118`. Run it as a caller who is
   **not** a member of that household, which is the revoked user's exact
   position.

**pgTAP hazards for this file, again:** `test_login()` sets
`role=authenticated` for the **rest of the transaction**, so every fixture
statement needing superuser (writing `auth.users`, inserting a *claimed*
`members` row, the direct `deleted_at` update above) must be preceded by
`reset role;`. And every UUID literal must be **hex only** — no `g`/`h`/`j`/`z`.

- [ ] **Step 3: Run**

```bash
supabase db reset && supabase test db
```

Expected: 37 passing in `002`, `001` unchanged at 32.

- [ ] **Step 4: Sanity-check that assertion 4 can actually fail**

Temporarily change the expected sqlstate to `'42501'` and re-run; it must go
red. Change it back. (Assertions 1–3 cannot be made red without editing the
migration — that is the point, and it is not worth doing.)

- [ ] **Step 5: Commit**

```bash
git add supabase/tests/002_membership_exit_test.sql
git commit -m "pgTAP: pin the RLS boundary the reconnect probe rests on, and create_household's 23505"
```

---

## Task 5: `createHousehold` surfaces a taken id as a typed failure

**Files:**
- Modify: `lib/application/household_gateway.dart`

**Interfaces:**
- Consumes: the `23505` contract proven in Task 4.
- Produces: `HouseholdIdTakenFailure implements Exception`, public, thrown only
  by `SupabaseHouseholdGateway.createHousehold`. `NoopHouseholdGateway` and
  `FakeHouseholdGateway` are unchanged — the fake's existing
  `createHouseholdError` field lets a test throw this type directly.

- [ ] **Step 1: Add the type and the mapping**

Declare `HouseholdIdTakenFailure` alongside `MyMembership` in
`household_gateway.dart`, with a doc comment that: names the RPC statement
that conflicts (`insert into households (id, name, created_by)` in
`20260731120000_initial_schema.sql`), states that the household ids are
client-generated UUIDv4s so a collision means *this device's own household is
already on the server*, and points at Task 6's consumer.

In `SupabaseHouseholdGateway.createHousehold`, wrap the `rpc` call:

```dart
    try {
      await _client.rpc<dynamic>('create_household', params: {...});
    } on supabase.PostgrestException catch (error) {
      if (error.code == '23505') {
        throw const HouseholdIdTakenFailure();
      }
      rethrow;
    }
```

`PostgrestException` is already reachable from this file's
`package:supabase_flutter` import; `join_flow_steps.dart:20` is the precedent
for narrowing it with a `show` clause if you prefer. Record in the doc comment
that exposing this code to a non-member is a considered non-issue: the caller
already knows the id (it is their own local one) and household ids are
unguessable UUIDv4s, so it is not an enumeration oracle of the kind
`remove_member`'s single-message rule guards against.

- [ ] **Step 2: Verify**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter analyze --fatal-infos
env -u GIT_DIR -u GIT_INDEX_FILE flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/
```

Expected: green. **This task ships no behaviour change** — nothing consumes
`HouseholdIdTakenFailure` yet, and `SupabaseHouseholdGateway` has no test
coverage by design. Task 6 is where it becomes visible. Say so in the commit
message.

- [ ] **Step 3: Commit**

```bash
git add lib/application/household_gateway.dart
git commit -m "Type create_household's id conflict (no caller yet; Task 6 consumes it)"
```

---

## Task 6: Adopt states the dead end instead of offering an endless retry

**⚑ This task makes the Finding 3 fix LIVE.**

**Files:**
- Modify: `lib/application/household_link_service.dart`
- Modify: `lib/features/settings/account_section.dart`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`
- Modify: `test/features/settings/account_section_test.dart`

**Interfaces:**
- Consumes: `HouseholdIdTakenFailure` (Task 5).
- Produces: `HouseholdAlreadyOnlineFailure implements Exception` on
  `household_link_service.dart`; l10n `settingsAccountAdoptBlockedTitle` and
  `settingsAccountAdoptBlockedBody`. Semantic id `settings.account.adopt` is
  **unchanged** — this is a third state of the same row, not a new row.

- [ ] **Step 1: Write the failing widget test first**

In `test/features/settings/account_section_test.dart`, next to the existing
adopt tests, add one modelled on them (`testChoreApp`, `FakeAuthGateway` with a
`currentUser`, `householdGatewayProvider` overridden, `openSettingsTab`,
`tester.ensureSemantics()`):

- gateway: `createHouseholdError = const HouseholdIdTakenFailure()` and **no**
  `downloadSnapshotOverride`, so `downloadHousehold` returns
  `const HouseholdSnapshot()` for an id the fake never "created" (its existing
  `_createdHouseholdIds` behaviour, line 248-250) — exactly the revoked user's
  server state;
- tap `settings.account.adopt`, `pumpAndSettle`;
- assert the blocked title/body copy is on screen;
- assert the retry copy (`settingsAccountAdoptRetry`) is **not**;
- assert the row is no longer tappable — `tester.widget<ListTile>(...)`'s
  `onTap` is `null` (and/or `enabled` is `false`);
- assert `settings.syncHouseholdId` is still `null` and the local household is
  untouched;
- assert `settings.account.join` is still present, since it is the recourse the
  copy names.

Add a second test pinning the **unchanged** resume path: gateway with
`createHouseholdError` set **and** the household readable
(`downloadSnapshotOverride` carrying the local household row) → adopt still
**succeeds** and links. This is the Disconnect → Adopt case and it must not
regress.

- [ ] **Step 2: Run to verify it fails**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/settings/account_section_test.dart
```

**Expected RED:** the blocked-copy assertion fails with *"found 0 widgets"* —
the row renders `settingsAccountAdoptError` + `settingsAccountAdoptRetry` and
stays tappable. The `onTap == null` assertion fails too. The second test
(resume path) should be **green from the start**; if it is red, stop — you have
broken the existing behaviour before writing any fix.

- [ ] **Step 3: Classify the failure in the service**

In `HouseholdLinkService.adopt`'s step-1 catch (lines 65-85), keep the existing
resume heuristic first and add a terminal branch after it. Shape:

- capture the caught error (`on Exception catch (error)`);
- `downloadHousehold(householdId)` as today;
- household readable → resume (unchanged);
- household not readable **and** `error is HouseholdIdTakenFailure` → throw
  `HouseholdAlreadyOnlineFailure`;
- otherwise → `rethrow` (unchanged).

Update the method's existing comment block, which currently asserts *"a genuine
first-time failure instead finds no household yet … so it rethrows"* — that
sentence is now incomplete and is the exact reasoning Finding 3 disproved.
Replace it with the real taxonomy: readable ⇒ resume; taken-and-unreadable ⇒
terminal, this device can never adopt this id; anything else ⇒ retryable.

Note explicitly that a network failure inside `downloadHousehold` propagates
before any classification happens, and that this is correct — an unreachable
server is retryable, not terminal.

- [ ] **Step 4: Add the strings and the third row state**

`app_en.arb` (with `@`-descriptions) — copy that states three things and no
more: this household is already online, this device is no longer part of it,
and an invite code is the way back. It must **name the recourse**; a notice
that reports a fault and offers nothing is the dead end this project has
rejected twice already (`docs/backlog.md` E-2, D-5). Do not use the word
"error". `app_de.arb`: du-form, literal umlauts, **"Gerät"**.

In `_AdoptRowState`, add a `bool _blocked` alongside `_running` / `_failed`,
set it in a `on HouseholdAlreadyOnlineFailure` branch of `_adopt`'s existing
catch (before the generic `on Exception`), and render it as a leading
`Icons.cloud_off_outlined`, the blocked title/body, `enabled: false`,
`onTap: null`. Keep `semantic('settings.account.adopt', child: …)` wrapping the
whole row so the id is stable across all four states.

- [ ] **Step 5: Run to verify green**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter gen-l10n
env -u GIT_DIR -u GIT_INDEX_FILE flutter analyze --fatal-infos
env -u GIT_DIR -u GIT_INDEX_FILE flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/
```

Expected: full suite green (787 + this plan's new tests).

- [ ] **Step 6: Commit**

```bash
git add lib/application/household_link_service.dart lib/features/settings/account_section.dart lib/l10n/ test/features/settings/account_section_test.dart
git commit -m "Adopt states the terminal case instead of offering a retry that cannot succeed"
```

---

## Task 7: Record it in the specs and the backlog

**Files:**
- Modify: `docs/specs/sync-backend.md`
- Modify: `docs/backlog.md`

No code, no tests. This is the "record the deviation rather than absorb it"
step this repo applies to every plan.

- [ ] **Step 1: `sync-backend.md` §7.3 — adopt's failure taxonomy**

Add a short paragraph to the "Failure surface" sentence: the resume rule
("treat *household already exists with my user as member* as step-1 success")
stands, and its complement is now specified — *household exists and I am NOT a
member* is **terminal for this device and this household id**, surfaced as a
non-retryable state naming join-by-code as the recourse. Cite **OPD-1** for the
fork capability that was deliberately not built.

- [ ] **Step 2: `sync-backend.md` §7.6 — the reconnect contract**

Record three things:

- `findMyMembership` filters `deleted_at` on both selects and orders
  deterministically, and returns `null` rather than a blank household name;
- these predicates are defense in depth — `is_household_member` is the actual
  boundary, and `supabase/tests/002_membership_exit_test.sql` now proves it;
- **the replace is conditional.** Reconnect skips the claim RPC (as specced),
  so the downloaded snapshot is the only authorization evidence; an absent
  household row, or an absent/soft-deleted member row for the reconnecting
  member, aborts the whole flow **before** anything local is deleted. Note that
  this is the one place §7.4's "the replace is one local transaction" needs a
  precondition stated outside the transaction.

- [ ] **Step 3: `docs/backlog.md` — two new rows**

Append to the appropriate table (the E/G groups; give them ids that do not
collide with existing ones and say what they came from):

- **Fork a removed member's local copy into a new online household** — OPD-1
  Option 2. **The row must carry the re-key finding, not just the title**, so
  it is not rediscovered: after a revocation the local rows are copies of the
  original household's server rows and share their ids, so minting a fresh
  **household** id alone is insufficient — `create_household` inserts the
  acting member *by id* and PK-conflicts, and `uploadHouseholdData` would then
  be silently skipped for members (`ignoreDuplicates: true`) or RLS-rejected
  for the other tables. The smallest correct version re-keys **every** local
  row that carries an id or FK: `households`, `members`, `categories`,
  `chores`, `chore_assignees` (composite `chore_id, member_id`),
  `chore_occurrences` (`id`, `chore_id`, `assignedMemberId`, `completedBy`),
  `shopping_items` (`id`, `categoryId`, `addedBy`), plus
  `settings.actingMemberId`, in one local transaction. A missed FK is silently
  orphaned history. Also record that this is *not* a bug fix: keeping the local
  copy is already the D-L3 default, and turning that copy into an independent
  online household is a new capability. Effort **S–M**. Build on evidence of
  demand. Entry point: the terminal adopt state added by this plan's Task 6.
- **Reconnect chooser for an account in several households** — OPD-2 Option
  (b). Today the offer is deterministic (**most recent membership first, by
  `members.created_at` descending**) and always names the household so the user
  can decline, but it can still be the wrong one and reconnect is destructive.
  Effort **S**.

- [ ] **Step 4: Commit**

```bash
git add docs/specs/sync-backend.md docs/backlog.md
git commit -m "Record the reconnect/adopt contracts and the two deferred capabilities"
```

---

## Done criteria

- [ ] `env -u GIT_DIR -u GIT_INDEX_FILE flutter analyze --fatal-infos` → `No issues found!`
- [ ] `env -u GIT_DIR -u GIT_INDEX_FILE flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/` → fully green, no skips
- [ ] `supabase db reset && supabase test db` → `001` 32 passing, `002` 37 passing
- [ ] No reconnect, join or join-fresh path can delete a local household without
      a confirmed snapshot (Task 1) — the one behaviour a reviewer should
      re-derive from the code rather than trust the tests for
- [ ] The adopt row has no state in which it invites a retry that cannot succeed
- [ ] Every path that reaches the reconnect offer still displays the household
      NAME (`settingsAccountReconnectTitle`) — the deterministic auto-pick of
      OPD-2 is only acceptable because the user can read it and decline
- [ ] The OPD-1 backlog row carries the **re-key finding** (household-id-only
      is insufficient; the full list of tables), not just a title
- [ ] No migration was added; client schema version unchanged (do not collide
      with the pending v10 contention in `docs/backlog.md`)
- [ ] `is_household_member` and the `members` grants are untouched
- [ ] Merged **before** `docs/plans/2026-08-08-household-lifecycle-slices-4-6.md`
      Task 12
- [ ] `syncRefreshError` was **not** touched here — confirm it is still carried
      by the slices 4–6 patch before closing this plan

## Whole-branch review prompts

Two findings in the v0.5.0 session's final review were structurally invisible
to any per-task review. Ask these explicitly at the end:

- Is there any remaining path — not only reconnect — where a *successful*
  network call with an *empty* result set is treated as authoritative? Grep
  every `downloadHousehold` and `pullTable` consumer.
- Does any flag or cached provider value survive an unlink and then get applied
  against a *different* household? (`membershipRevoked` had exactly this shape;
  `myMembershipProvider` is non-autoDispose and is the candidate here.)
