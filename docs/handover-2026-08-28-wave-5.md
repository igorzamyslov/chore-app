# Handover: wave 5

*Written 2026-08-28 by the agent that orchestrated wave 5, for whoever scopes
the next one. Same rule as the wave-4 handover: every claim here was verified
against source, CI output, a build artifact, or a device — and where it wasn't,
it says so explicitly.*

---

## 1. Where things stand

Wave 5 ran as five streams on `integration/wave-5` (PR #24), each merged only
after a line-by-line review and a green `gh pr checks` at the reviewed SHA.

**Schema is still at v12.** No stream needed a migration — C-2's remaining
slices are UI and service work over server RPCs that already existed. **The next
migration is still v13.**

Nothing was released. `main` is untouched by this wave; everything is on
`integration/wave-5` awaiting the human's single reviewed merge.

**Final state, verified not predicted.** `integration/wave-5` at `2a0e3a9`,
47 files vs `main`, +5915/-420. All four jobs on PR #24 at that SHA:
`android` pass (15m56s), `checks` pass (4m5s) with **1037 tests passing**,
`pgtap` pass (2m14s), `ios` skipping. That `pgtap` is a **genuine** run, not
the fast skip — `Files=2, Tests=69, Result: PASS` — because slice 6's
`supabase/` correction is in the accumulated diff, so the integration state
itself got real SQL verification. `dart format` reports 283 files, 0 changed,
and `flutter gen-l10n` is a zero diff, so no stream leaked formatter churn or a
hand-written localization file.

---

## 2. What shipped

| Row / slice | What landed |
| --- | --- |
| **A-7** | The worktree formatter trap is now *detectable*, which is the half that mattered. `tool/check_formatter_config.sh` formats a fixture that comes out differently under `preserve` vs `automate`, so it asserts the setting that actually matters rather than the "does `.dart_tool/` exist" proxy that would pass while the bug was live. Wired as a `&&` guard in FRONT of lefthook's pre-commit `format` job (before, never after — after is undetectable) and into `ci.yml`. |
| **Release integrity** | `release.yml` gained a third fail-closed assertion, for F-1's `ActionBroadcastReceiver`. Verified against real `aapt2` output in both directions before merge. |
| **A-6** | Trigger settled, flake **still open**. `ios` stays off automatic PR runs; a `workflow_dispatch` trigger was added so any branch can be iOS-verified on demand. The row's recorded *cause* was wrong and is corrected — see §4. |
| **C-2 Tasks 15+16** | Delete is no longer hidden for a claimed member (F10 is finally user-reachable), with the inline failure surface `ClaimedMemberRemovalFailure` requires. Shipped as the pair they are. |
| **C-2 slice 5** | Leave the household (F9) with the D-L5 last-member cascade warning. |
| **C-2 slice 6** | Delete the account (F11): the shared exit sheet FIRST, then ONE final dialog whose copy differs by the checkbox state and carries D-L7's export pointer. **C-2 is now closed.** |
| **G-12** | `cancelDigest()` now rides the same serialized digest-write queue as `applyDigestPlans`, so a wipe cannot interleave with an apply. |
| **A-3b** | The local database is excluded from iOS backups, in pure Swift at launch. |
| **A-2b** | The Settings "Last synced" line ticks itself, boundary-aligned and band-derived. |

### Fixes nobody asked for, found while in the area

- **One bug class turned up three times in one wave.** `AlertDialog` puts its
  content in a bare `Flexible` unless asked to be `scrollable`, so a long body
  is silently **clipped** — no exception, no scrollbar, the rest of the sentence
  simply unreachable. Task 12 fixed it in `exit_confirm_sheet.dart` in wave 4;
  this wave fixed it in `member_delete_dialog.dart` (Task 16) and in
  `destructive_confirm.dart` (slice 5). The last one had a **live victim**: the
  German `settingsResetConfirm1BodyLinked` already clips at text scale 2 on a
  320×640 screen. If you add a destructive dialog, set `scrollable: true`.
- **`_canDelete`'s bool-plus-reason pair became a `_DeleteGate` enum** — one
  value, one `membersProvider` watch, and the gate precedence in one place
  instead of two that could drift.

---

## 3. Verification status — read this before trusting §2

**Proven by a build artifact:** A-3b's Swift genuinely compiles and is genuinely
in the binary. `flutter build ios --simulator` succeeds, and
`Runner.debug.dylib` contains the mangled symbol
`excludeLocalDatabaseFromBackup` plus all four database file-name literals.
(Note for whoever checks this next: the app's code is **not** in `Runner` — Xcode
16 splits debug builds, and `nm`/`strings` on `Runner` show 107 outlined stubs
and nothing else. Look in `Runner.debug.dylib`.)

**Proven against real tooling output:** release integrity. The exact committed
grep and `::error::` message were run under GitHub's real default shell against
real `aapt2` 36.0.0 output: receiver present → exit 0 silent, receiver absent →
exit 1. Non-vacuous, with a negative control. Both pre-existing assertions were
re-checked green in their new file-based shape.

**Proven against library source, not assumed:** A-2b's central premise. See §4.

**NOT verified, and structurally cannot be by CI:**
- **The manual live smoke against the local Supabase stack is the real gate for
  every server-touching path in C-2, and nobody has run it.** The plan's own
  done criteria list five scenarios. `supabase` and `docker` are off the agent
  allow list, and E2E stays permanently offline, so *no automated check in this
  repo exercises `leave_household`, `remove_member` or `delete_account` against
  a real server.* Every one of them merged CI-green and server-unverified. **This
  is the largest single gap in the wave** and it is the same shape as F-1's
  GATE 3: it needs a human.
- **`pgtap` green meant nothing on four of the five streams.** `db.yml` only
  stands the stack up when the diff touches `supabase/**` or `db.yml`. Those
  four were Dart/YAML-only, so `pgtap` reported a 4-to-8-second green **having
  run no SQL at all**. Do not read those greens as server verification.
  **Slice 6 is the exception, and it is worth copying:** it needed real server
  verification, so it made a genuine `supabase/` correction to earn the stack
  (two test comments claimed a bad migration "would pass 54/54"; the suite is
  69). That push really did run `supabase start` → `supabase db reset` →
  `supabase test db`, and I confirmed it in the log: **`Files=2, Tests=69,
  Result: PASS`** in 2m19s, against ~20s for a skipped stack. **The duration is
  how you tell the two apart at a glance.**
- **`release.yml`'s new assertion has never executed.** The workflow is
  tag-triggered. Its first real exercise is the next `v*` tag. The pattern is
  verified; the *step in situ* is not.
- **A-6's `workflow_dispatch` escape hatch is inert until it reaches `main`.**
  GitHub only offers the button for a workflow present on the default branch,
  so it could not be exercised from the PR that added it.
- **A-3b's attribute is not observed being set.** Nothing automated reaches
  `xattr -l <container>/Documents/chore_app.sqlite`. The name-mirror test
  (`test/data/db/ios_backup_exclusion_test.dart`) catches only a rename drifting
  out of sync with the Swift — it is honest about that in its own doc comment.
- **F-1 GATE 3** — untouched, still needs a human with a phone. A **one-off**
  chore actioned with the app swiped away, then no later notification claiming
  it overdue. Its fallback is to accept the truncation and document it, **not**
  to call `cancelDigest()`, which trades one wrong notification for up to 83
  days of silence.

---

## 4. Recorded facts that turned out to be WRONG

This is the section worth reading first. **Seven** written-down claims were
false — four backlog rows (A-7, A-6, A-3b, A-2b), two doc comments
(`destructive_confirm.dart`, and the plan's for Task 23), and one in
`lefthook.yml` — and every one was caught by an implementer verifying instead of
trusting. Three of them were claims *this orchestrator repeated to subagents as
fact*. Assume the same rate next wave, and note where these lived: the wrong
claims were not in the code, they were in the documents describing it.

- **A-7's own suggested fix was impossible.** The row proposed "a committed
  formatter config that does not depend on package resolution". An unresolvable
  `package:` include makes `dart format` discard the **entire** options file, so
  an explicit `formatter: trailing_commas: preserve` block sitting right beside
  the failing include is dropped with it. Four YAML arrangements measured, all
  four reflowed. The row now records this as measured-impossible.
- **A-6's recorded cause was wrong.** It blamed state isolation — "the app was
  not in fresh-install state". The Maestro artifact from run `31800958022`
  (retrieved hours before its 14-day expiry) says otherwise: the failure
  hierarchy holds the app window and *nothing inside it* — no welcome gate **and
  no tab shell**, so nothing leaked; the wait was 4.8–9.0 s in all 12 passing
  flows and a full 60 s in both failures, i.e. bimodal, so a larger timeout buys
  nothing; and XCTest logged the main thread *responding* with zero Flutter
  nodes. Real cause: **the Flutter view permanently fails to present on a fresh
  install.** Likely lead, also from the log: Maestro implements iOS `clearState`
  as **uninstall + reinstall** — a new bundle container and a genuinely cold
  start, 14× per run — where Android just clears app data.
- **A-3b's stated mechanism does not exist here.** The row warned about a torn
  restore via `-wal`/`-shm` sidecars. Nothing in `lib/` enables WAL, and drift
  leaves sqlite3 in its default rollback-journal mode, where every committed
  byte is always in the main file. The reachable sidecar is
  `chore_app.sqlite-journal`. Its "Files" column also named
  `ios/Runner/Info.plist`; there is no such plist key — it is a per-URL runtime
  attribute. Both corrected in the row.
- **A-2b's blocker was not real.** The row, and `todayProvider`'s doc comment,
  said a provider-armed timer trips `flutter_test`'s pending-timer check. It
  does not, if the timer is cancelled on disposal:
  `TestWidgetsFlutterBinding._runTest` calls `runApp(Container(...))` to unmount
  the tree and `await pump()`s **before** `_verifyInvariants()`, and the
  assertion's own text is "A Timer is still pending even **after the widget tree
  was disposed**." What the check catches is a timer nothing owns. So the timer
  could be *owned* rather than dodged.
- **`lefthook.yml` claimed `AppShell` is an `IndexedStack`** that builds the
  Settings Account section for every widget test. It has been a lazy `PageView`
  since wave 3. The `SUPABASE_*` dart-defines are still required, but for a
  smaller set of tests than the comment claimed.
- **`destructive_confirm.dart` claimed its `settings.reset.*` semantic ids are
  load-bearing for Maestro.** `grep -rn "settings.reset" e2e/` is **empty**.
  They are load-bearing for `reset_flow_test.dart` and `test/widget_test.dart`.
  The orchestrator repeated this falsehood to two subagents before it was
  caught — a doc comment is not evidence.

- **Task 23's doc comment claimed the session dies with the auth row.** The
  gateway's own doc comment says the opposite, in as many words: GoTrue JWTs are
  stateless, so deleting `auth.users` cascades refresh tokens but an
  already-issued access token works until its `exp`. For that window
  `auth.uid()` still resolves and every claim is already nulled, so a pull's
  `hasMembership` probe SUCCEEDS and answers false — indistinguishable from
  being removed by somebody else. **Without the local sign-out, a user who
  deleted their own account would be shown §3.5's "you were removed" notice.**
  The sign-out is load-bearing, not cosmetic; its failure is still tolerated.

### Plan defects caught before they shipped

The wave-4 handover's headline finding held: **every plan needed its refresh
pass, and every refreshed task found defects.** Tasks 15-16 had 7 stale items,
Tasks 19-20 had 5.

- **The German copy said "Handy" throughout the plan.** `app_de.arb` uses
  "Gerät" 27 times and "Handy" zero times, and "Gerät" is the binding
  convention. Caught in Tasks 15/16, then again in Task 20, then again in
  Task 24. The shipped `app_de.arb` has **zero** occurrences.
- **The plan claimed the existing deletion tests were "unaffected" by Task 15.**
  One asserted Delete is *hidden* for a claimed member and asserted the very
  copy Task 15 retires. Updated to the new intended behaviour, not deleted.
- **Two plan instructions would have degraded provider discipline:**
  re-`watch`ing `membersProvider` in a helper whose own doc comment said it was
  avoiding a second watch, and watching bare `settingsProvider` — which two
  provider doc comments forbid, because a started sync engine writes
  `settings.syncLastPulledAt` on every pull and an unscoped watch rebuilds the
  sheet on each one.
- **The plan had `_finishLocally`'s two settings writes in the wrong order.**
  Clearing the revocation flag before unlinking leaves the racing-pull window
  the flag-clear exists for wide open (`syncEngineProvider` is gated on
  `syncHouseholdId`, so unlinking first shuts it), and it puts a defensive write
  ahead of the load-bearing one — so a throw between them strands the device
  LINKED while the server has already unclaimed it.
- **Two plan test snippets had unused imports**, which fail `--fatal-infos`, so
  neither would have failed the way its own "run to verify it fails" step
  predicted.
- **Task 24 hand-rolled an `AlertDialog` for the final gate**, which omits
  `scrollable: true` — and `accountDeleteFinalBodyDeletePhone` is the longest
  confirm body in the app, longer again in German. The clipped tail would have
  been **precisely D-L7's export pointer**. Fixed by promoting the shared
  builder instead.
- **Two plan assertions were vacuous as written.** One used
  `find.textContaining("this phone's copy")`, which is verbatim the exit
  sheet's own checkbox label — it would have passed on the sheet rather than on
  the dialog under test. Another named an export control that does not exist
  ("Export"/„Exportieren"; the row is "Export data"/„Daten exportieren").
- **Task 21 pointed at a "§5 slice 1 verification record" that did not exist**,
  and owned neither the `sync-backend.md` §2 correction its own done criteria
  require nor the file. Both assigned and done; §5.1 created.

Task 24's refresh pass found **12** stale items, against 7 in Tasks 15-16 and 5
in Tasks 19-20. The rate did not fall as the wave went on.

### An orchestrator instruction that was itself a defect

Worth recording because it is the failure mode a human reviewer should expect
from *this* setup, not just from stale plans. The orchestrator told the slice-5
agent to promote `destructive_confirm.dart`'s private `_showStep` and use a
one-step dialog for Leave, reasoning from the plan's "Leave and member-removal
still have exactly ONE confirmation each".

**The agent refused, correctly.** Spec `household-lifecycle.md` §3.3 is binding
and gives all three exits **one confirm shape**: body, then D-L3's *unchecked*
"also delete this phone's copy" checkbox, then the action. A
`DestructiveConfirmStep` has nowhere to put a checkbox and returns a bare
`bool` — so the instruction would have **deleted D-L3 from the Leave flow**, the
closed decision the same instruction told it to protect with three tests. "One
confirmation" means one *sheet*, not one *dialog*. And `showExitConfirmSheet`
already existed with a caller, so nothing was being copied.

The promotion is right for exactly one caller: delete-account's D-L6 final gate,
which genuinely is one dialog *after* the sheet.

---

## 5. Process findings

- **Merging a stream branch into the integration branch DISARMS that stream's
  CI.** GitHub auto-closes the branch's PR as merged, and a merged PR's branch
  gets **no CI at all** — every workflow here triggers on `pull_request` and
  `push: [main]` only, so subsequent pushes register zero runs and
  TDD-through-CI silently becomes impossible. This cost A-3b its entire
  observed red/green cycle before it was noticed. If you relay agents on one
  branch, either open a fresh PR immediately after each merge or do not merge
  until the relay is finished.
- **A green `checks` on a YAML-only or Swift-only diff proves nothing about the
  change.** No PR job compiles Swift; `release.yml` is tag-triggered. Two of
  this wave's five streams could not be exercised by their own PR's CI at all.
- **The A-7 guard paid for itself inside the same wave.** Every worktree was
  pre-seeded with `.dart_tool/package_config.json`, and the guard confirmed
  `preserve` in effect before each agent's first format. Zero format churn
  landed: the final `dart format` reports no changes across the tree.
- **A force-push happened again** (`--force-with-lease`, on an agent's own draft
  branch, to drop a temporary inversion commit). It breaches the standing
  hard stop, and it destroys the evidence for the inversion it was tidying — the
  red had to be recovered from the orphaned run. Subsequent agents were told to
  use `git revert` instead. Tell them up front.
- **Inversions keep failing at `analyze` instead of at the test step** unless
  they are done *inside* a method body. Two agents hit this: deleting a method
  trips `unused_element`, and `scrollable: false` trips
  `avoid_redundant_argument_values` — in both cases the tests never ran, so the
  "red" proved nothing. The valid shape is to change behaviour inside the
  method while keeping every symbol referenced.
- **If you need real SQL verification, earn the stack deliberately.** Slice 6
  did: a legitimate `supabase/` correction in the same push, which flipped
  `db.yml` from its ~20s skip to a genuine 2m19s run. Do not fake it, and do
  not assume a Dart-only diff got you anything.
- **One false red worth knowing about:** a hand-rolled localizations delegate
  list missing `GlobalCupertinoLocalizations` makes `takeException()` return a
  locale warning, which fails the test before its actual subject does. Use
  `AppLocalizations.localizationsDelegates` — what `ChoreApp` passes.

---

## 6. What is open

- **The manual live smoke against the local Supabase stack** — the real gate for
  all of C-2. See §3. This is the top of the list.
- **F-1 GATE 3**, unchanged. See §3.
- **A-6's blank-frame flake.** The trigger question is settled; the flake is
  not, and it now has a correct starting point plus the `clearState`
  uninstall/reinstall lead. Not root-caused, no local reproduction. `ios` must
  not be made a required check until the flake is fixed AND the trigger
  widened. Note the shape that deadlocks a required check: a workflow-level
  `paths:` filter means the workflow never runs, so no check run is ever
  created and a required check waits forever — a job-level `if` skip (what
  `ios` uses) is not that, and still produces a skipped check run.
- **`release.yml`'s third assertion is unexercised** until the next tag.
- **G-12's sibling hazard is deliberately still open:** the digest write queue
  is per-instance and does NOT cross isolates, so the background isolate and
  the main isolate can still interleave writes to the same 24 ids. It is argued
  to be self-correcting whenever it can occur at all. **Do not add a
  cross-isolate lock** — that is recorded in three places now.
- **A-3b's cost, recorded rather than hidden:** *all* of `Documents/` is
  excluded from backup, matching what `allowBackup="false"` does on Android. A
  future user-facing document placed there would silently get no backup.
- **The Supabase refresh token is in `NSUserDefaults`, not the database**, so an
  iOS restore still returns the session. Benign: the household link and pull
  cursor are in the database, so a restored device with a session and no DB
  lands on the welcome screen with nothing to push.
- **Eight wave-4 worktrees and their branches still exist**, plus this wave's
  five. All merged; cleanup is a human call.
