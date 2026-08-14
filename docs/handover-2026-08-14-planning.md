# Handover: planning the work after v0.5.0

*Written 2026-08-14 by the agent that shipped v0.5.0, for whoever authors
the next round of implementation plans. This is a PLANNING handover, not an
implementation one — it assumes you will be writing plans that other agents
execute. Everything below was verified against source or a live database at
the time of writing; where it wasn't, it says so.*

---

## 1. Where things stand

**v0.5.0 is released** — https://github.com/igorzamyslov/chore-app/releases/tag/v0.5.0,
signed APK attached, CI + E2E green, 787 tests, `flutter analyze
--fatal-infos` clean. `main` is at the merge of the four pre-release gates.

**The production Supabase migration `20260808120000_membership_exit.sql`
has been applied** (confirmed by Igor 2026-08-14). Note production has NO
`supabase_migrations.schema_migrations` table — every migration there was
applied by pasting SQL into the editor, so the CLI's history table was
never created. If anyone ever wants CLI-managed migrations on prod, the
supported path is `supabase link` then `supabase migration repair --status
applied <all six versions> --linked`. Do NOT hand-create that table.

**Closed since 2026-08-08:** all four release gates from
`docs/feedback/2026-08-08-prerelease-audit.md` — P0 (digest), P1 (day
rollover), P2 (allowBackup), T1.3/A-5 (acting-member pinning) — plus
slices 1-3 of the household-lifecycle spec (server-side membership exit +
revocation detection).

**Still open in that audit:** P3 ("Reset app data" leaves the account
signed in) and the S1/S2 items. P4 in the audit is a list of smaller
verified findings, not the P4 household-lifecycle cluster — the two uses
of "P4" in this project's docs mean different things and have caused
confusion; check which one a document means before acting on it.

---

## 2. Plans that already exist — do NOT re-author these

`docs/plans/` holds 19 plans. Five are DONE and merged:

- `android-backup` (gate P2)
- `daily-digest-scheduling` (gate P0)
- `day-rollover` (gate P1)
- `acting-member-pinning` (gate T1.3 / A-5)
- `household-lifecycle-slices-1-3`

Fourteen remain unexecuted and are, as far as I inspected them, still
valid: `catchup-visibility`, `category-delete-impact`,
`household-lifecycle-slices-4-6`, `join-wizard-state`,
`notification-actions`, `notification-permission-recovery`,
`offline-indicator`, `push-retry`, `reset-signs-out`, `rotation-reorder`,
`shell-navigation`, `shopping-gestures`, `small-fixes-wave`,
`stats-screen`.

I executed four of the five done ones and found their quality high —
decisions closed up front, deviations from binding specs tracked rather
than absorbed, verbatim code that mostly compiled. Assume the remaining
fourteen are of the same standard and read them before writing anything
new; the gap is more likely to be a missing plan than a bad one.

`docs/backlog.md` §"Suggested execution order" and §"Execution hazards
between plans" already encode sequencing thinking. Read both before
re-deriving an order.

---

## 3. What genuinely needs a NEW plan

### 3.1 The digest's 7-day horizon ceiling (no plan exists)

This is the main gap I would hand to a planner. Context:

The P0 fix replaced a one-shot digest notification with a rolling 7-day
horizon (ids 1001..1007) rewritten on every recompute. An app left
unopened for 8+ days still goes silent. That is documented and deliberate
— it degrades into silence, never into wrong counts — but it fails
precisely the disengaged user a reminder exists to re-engage.

**The non-obvious finding, which should shape the plan:** the horizon
length buys no accuracy. The projection assumes the local DB does not
change, and while the app is closed it does not. Accuracy is binary — the
counts are right if nothing changed and stale if another device changed
something — and that staleness applies equally at day 2. **Day 28 is
exactly as accurate as day 8.** `digestHorizonDays`' own doc comment
justifies 7 as "comfortably inside iOS's 64-pending-notification cap",
which is true but so is 14 or 28.

The real competitor for that iOS budget is **per-chore reminders (N2 /
F16)**, which are unbuilt. That is the number a plan should protect, not
64.

Three options, cheapest first:

1. **Raise `digestHorizonDays`.** One constant in
   `lib/domain/digest_planner.dart`. Costs iOS slots and makes each
   recompute N sequential platform calls instead of 7 — safe now that
   `NotificationScheduler.applyDigestPlans` serializes, but it is N× the
   work on a 2s-debounced write, so the plan should say something about
   battery.
2. **A generic repeating backstop.** One extra notification using
   `matchDateTimeComponents` — the repeating API the P0 plan correctly
   rejected *for the digest*, because it freezes the body. A body with NO
   counts ("Open Famdo to see this week's chores") cannot go stale, so
   that objection does not apply. One slot, unlimited horizon, cancelled
   and re-armed alongside the horizon.
3. **Server-driven push.** The only approach actually correct for a
   synced household, since the local projection is unreliable the moment
   another device acts regardless of horizon. Needs FCM/APNs, a
   device-token table, a scheduled function. Cannot REPLACE the local
   horizon — never-signed-in users are the local-first premise — so it
   augments. This is a project, not a fix.

My recommendation to Igor was 1 + 2 together: about a day's work, no new
platform capability, no new permission, no new manifest entry to verify on
a release artifact. I explicitly recommended AGAINST background execution
(`WorkManager` / `BGTaskScheduler`): iOS `BGAppRefreshTask` is
opportunistic and fires least often for users who rarely open the app,
which is exactly the failing population.

**Constraint for whoever plans this:** there is no telemetry (correctly —
local-first, no analytics), so nobody can measure how often a user goes
8+ days without opening the app. Do not write a plan that depends on
measuring it first.

### 3.2 Possibly needing plans — verify before assuming

- **`findMyMembership` filters neither `members.deleted_at` nor
  `households.deleted_at`** (`lib/application/household_gateway.dart`).
  Reconnect is a DESTRUCTIVE local replace (deletes the local household,
  inserts the downloaded snapshot). Spec §2.5 deliberately closed the
  invite door into a cascaded household but left the reconnect door
  unexamined. Latent today; slices 4-6 make more households reachable in a
  deleted state. Two predicates, cheap, but it is a real hole.
- **Adopt deterministically fails after a revocation-triggered unlink.**
  `create_household` is called with the local household id, which still
  exists server-side, so the plain insert PK-conflicts into a generic
  failure state. Join-by-code works. A user who was just removed is
  exactly the user who will try Adopt. Needs a product decision, not just
  code.
- **iOS backup exclusion (A-3b).** P2 was Android-only by scope.
  `allowBackup=false` has no iOS equivalent; excluding the local SQLite
  file from iCloud backup is a separate mechanism and is tracked in
  `docs/backlog.md`. Only matters if a release ever ships iOS.

---

## 4. Carried findings that belong in plan inputs

These came out of reviews during the v0.5.0 work and are recorded here so
they are not rediscovered:

- **`exit_confirm_sheet` needs a `SingleChildScrollView` BEFORE slices 5-6
  land.** Today's two strings fit. The last-member cascade warning (D-L5)
  and the delete-account copy are explicitly longer, and the sheet is
  `isScrollControlled: true` with no scroll view — that is an overflow on
  a small phone in German. Make it slice 4's first task. This is the one
  hard ordering constraint I know of.
- **`syncRefreshError`'s copy says "will sync later"**, which is untrue for
  a device that was just revoked and unlinked. Needs its own string when
  slice 4 touches that area.
- **Digest notification ids are slot-relative** (`base + k` where k is the
  offset from the next slot), so id 1001 means Monday at 07:00 and Tuesday
  at 09:00. Correctness rests on every apply rewriting all seven, which
  holds only if the loop finishes. A date-derived mapping would make a
  partial apply idempotent. Bounded by the serialization now in
  `applyDigestPlans`; worst case is one duplicate morning notification
  after a mid-apply process kill.
- **`cancelDigest()` is unserialized against `applyDigestPlans`** — no
  concurrent caller today.
- **v4 → v10 drift migration is untested** (pre-existing; no known
  population on v4). v9 → v10 IS tested and v9 is the shipped schema.

---

## 5. Plan-authoring rules for THIS repo

I wrote one plan in this session (`household-lifecycle-slices-1-3`) and it
had **seven defects** that execution caught, while the plans I inherited
had roughly one each. The difference was not care — it was that I wrote
code into a plan from memory instead of reading the repo. Encode these as
Global Constraints in anything you author.

**Do not transcribe widget-test code from memory.** State requirements and
point at a reference test file. My drafted test hand-rolled a
`ProviderScope` pump and closed the database in `tearDown` — the exact
pattern `test/test_utils/pump_app.dart`'s own header documents as
deadlocking (flutter_test's pending-Timer leak check runs BEFORE
tear-downs, so drift's stream-cleanup timer never drains). It HUNG rather
than failed, which also hung the full suite and therefore the pre-commit
hook, blocking every commit on the branch. Use `testChoreApp` /
`openSettingsTab` / `find.bySemanticsIdentifier`.

**Verify a claim about the codebase before writing it into a plan.** I
asserted three guards were dead code based on a grep over three files that
missed `lib/data/sync/row_mappers.dart`. The claim was wrong, it reached a
committed spec, and it had to be corrected in a follow-up commit.

**Check that a task's own stub can pass its own acceptance test.** My
Task 1 mandated a deliberately-incomplete function AND a test that the
function could not satisfy. Two agent round-trips lost.

**Test-command constraints that are not obvious:**
- Tests need the Supabase dart-defines, exactly as `lefthook.yml` does:
  `flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY=`
  Without them six unrelated tests fail and read as regressions.
- `supabase test db` does NOT apply migrations. `supabase db reset` first.
- `semantic()` is `Widget semantic(String id, {required Widget child})` —
  NAMED child. Positional will not compile.
- pgTAP: `test_login()` sets `role=authenticated` via `set_config(...,
  true)`, which persists for the REST of the transaction. Any statement
  needing superuser must `reset role;` first. And UUIDs are hex only —
  `g`, `h`, `j`, `z` are not valid hex digits and fail to parse.

**Beware assertions that cannot fail.** Three separate tests in this
series passed before their own fix existed. One asserted `is(<no such
row>, null)`, which passes vacuously because a scalar subquery over a
missing row yields NULL and pgTAP's `is()` treats NULL as equal to NULL.
Plans should state the expected RED failure mode, not just the green
assertion, so an executor can tell a real red from a vacuous pass.

**Say what a task does NOT close.** The P0 plan's tasks 1-5 built the
whole horizon machine but left it with zero callers in `lib/` — nothing
about shipping behaviour changed until task 6. That was correct
sequencing, but only the review noticed it. Plans should mark which task
actually makes the fix live.

---

## 6. Facts worth encoding in any Global Constraints block

- Strict lints: `very_good_analysis` with `--fatal-infos`. Public members
  need doc comments.
- All user-visible strings via gen_l10n: `lib/l10n/app_en.arb` (template,
  with @-descriptions) AND `lib/l10n/app_de.arb` (informal du-form). The
  German for device is "Gerät", never "Handy". Generated
  `app_localizations*.dart` files ARE committed.
- Never add `Co-Authored-By:` or any co-author trailer to commit messages.
- `members.role` is VESTIGIAL (decision D1). No role-based enforcement.
- `public.is_household_member(hid)` is the security boundary for every RLS
  policy; it reads `members.user_id` / `household_id` / `deleted_at`.
  Anything weakening it or those columns is a Critical defect.
- DELETE is granted nowhere on any table; soft deletes only. The one
  sanctioned exception is `delete from auth.users` inside
  `delete_account()`.
- Capability boundaries (permissions, manifest flags) must be verified on
  the RELEASE artifact, not a debug run — from the v0.2.0 incident where
  Flutter's debug-only `INTERNET` declaration shipped a release with sync
  completely dead. `release.yml` now asserts both `INTERNET` and
  `allowBackup=false` on the built APK, fail-closed.
- CI pins Flutter 3.44.8 in all four `flutter-action` setups. An unpinned
  `channel: stable` drifted past `pubspec.lock` on 2026-08-13 and turned
  an unrelated upstream release into a red build. Bump deliberately,
  together with a regenerated lockfile.
- The E2E suite runs fully offline (empty Supabase dart-defines →
  `NoopAuthGateway`), so no plan should expect E2E to cover a linked or
  signed-in path.

---

## 7. Process note

The execute-review loop earned its cost in this session: every defect
listed in §5 was caught by an implementer or reviewer refusing to work
around a bad instruction, and several would have surfaced five tasks later
tangled with other changes. Two findings in the final whole-branch review
were things no per-task review could structurally have seen — a
denial-of-erasure one household member could inflict on another, and a
notification flag that survived re-linking and would have offered to wipe
the household the user had just joined. Plan for that review, not just for
the tasks.
