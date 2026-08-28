# Release-Integrity Hardening (F-1 receiver assertion + A-6) Implementation Plan

**Goal:** Close the two release-integrity gaps wave 4 left open:

1. `.github/workflows/release.yml` asserts two of the three capabilities the
   shipped APK must carry (`INTERNET`, `allowBackup=false`) and **not** the
   third — the `flutter_local_notifications` `ActionBroadcastReceiver` that
   makes F-1's digest "Done" action reach anything at all. Add the third
   assertion, in the same fail-closed style, and retire the stale "not added
   here" note the F-1 agent left in the manifest.
2. **A-6** — `e2e.yml`'s `ios` job is gated `if: github.ref ==
   'refs/heads/main'`, so iOS breakage is only ever discovered *after* merge.
   Decide what to do about that, on evidence, and record the reasoning in the
   workflow itself.

**Architecture:** Pure CI-configuration and documentation. No Dart, no
manifest behaviour change, no schema change, no l10n. Two workflow files, one
manifest comment, one backlog row, one plan file (this one).

**Tech stack touched:** GitHub Actions YAML (`release.yml`, `e2e.yml`),
`aapt2 dump xmltree`, Maestro 2.7.0 (read-only — no flow edits), Markdown.

## Global constraints

- The pinned Flutter version (`3.44.8`) and the runner images
  (`ubuntu-latest`, `macos-latest`) are **out of bounds**. Not to be touched.
- A capability boundary is verified on the **release artifact**, never on a
  debug build or an emulator — the project's hard-won rule from the v0.2.0
  `INTERNET` incident, already recorded in both existing assertion comments.
- A fail-closed check with a wrong pattern is worse than no check: it breaks
  every future release, and it breaks it at tag time when someone is trying
  to ship. **No grep ships that has not been seen to match real `aapt2`
  output, with a negative control.**
- `release.yml` is **tag-triggered** (`on: push: tags: ["v*"]`). No run on
  this branch's PR can ever exercise the new step. That is a property of the
  task, not a thing to work around; it must be stated in the report and
  verification arranged out of band.
- The executing agent cannot run `aapt2`, `flutter build`, Maestro, a
  simulator, or Docker. Anything whose correctness depends on running one of
  those is either verified by the orchestrator on request or not shipped.

---

## Task 0 — establish the facts (done before any edit)

Both items in this plan were briefed with a recorded cause. Both recorded
causes were checked against the artefacts. One held; one did not.

- [x] **Item 1's premise holds.** `android/app/src/main/AndroidManifest.xml`
  declares three receivers in `src/main` (shared by every build variant):
  `ScheduledNotificationReceiver`, `ActionBroadcastReceiver`, and
  `ScheduledNotificationBootReceiver`. The comment block above the second one
  says the receiver ought to be asserted on the built RELEASE artifact "the
  same way INTERNET and allowBackup already are", and that `release.yml` was
  left out of scope. This plan is the follow-up that comment asks for.

- [x] **Item 2's recorded cause does NOT hold.** `docs/backlog.md` A-6
  records run `31800958022`'s two iOS failures as "the app was not in
  fresh-install state at flow start … state-isolation flake on the macOS
  runner". The run's Maestro debug artifact (still retrievable on 2026-08-28,
  hours before its 14-day expiry) refutes that. See Task 3.

---

## Task 1 — assert the F-1 receiver on the built release APK

**File:** `.github/workflows/release.yml`

Add a third verification step immediately after "Verify release APK has
auto-backup disabled", before "Rename artifact". It must reuse the
neighbours' three conventions exactly: the
`AAPT="$(ls "$ANDROID_HOME"/build-tools/*/aapt2 | tail -1)"` idiom, the
`|| { echo "::error::…"; exit 1; }` fail-closed tail, and a comment that
explains *why the assertion is on the shipped artifact* rather than what the
line does.

**The pattern.** Verified by the orchestrator against a real merged manifest
(`flutter build apk --debug` at `integration/wave-5`, then aapt2 36.0.0 —
5 `E: receiver` elements present). The receiver's compiled form is:

```
            A: http://schemas.android.com/apk/res/android:name(0x01010003)="com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver" (Raw: "com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver")
```

Controls the orchestrator ran against that APK:

- POSITIVE: `name\(0x01010003\)="com\.dexterous\.flutterlocalnotifications\.ActionBroadcastReceiver"` → **matches**
- NEGATIVE: the same pattern with `NoSuchReceiver` substituted → **does not match**

Ship the resource id as `0x[0-9a-f]+` rather than the literal `0x01010003`,
matching the `allowBackup` step and the explicit instruction in
`docs/plans/2026-08-08-android-backup.md` ("don't hardcode it, `aapt2` fills
it in from the platform's `public.xml`"). This is a *strict generalisation* of
the verified pattern, so both controls carry over deductively rather than by
assumption: `0x[0-9a-f]+` matches the observed `0x01010003`, so the positive
control still passes; the class-name half is byte-identical, and no
`NoSuchReceiver` string exists anywhere in the manifest, so the negative
control still fails. Report the shipped pattern to the orchestrator so both
controls can be re-run before merge.

**Two limits to state in the comment, not paper over:**

- The sample was a **debug** build; the step asserts on `app-release.apk`.
  The three `<receiver>` elements come from `src/main`, which every variant
  merges, and Flutter's release build does not minify or rename manifest
  components — so the compiled form is the same. Sound, but *inferred*: the
  release variant was not itself sampled.
- The pattern matches the `android:name` **attribute**, not the enclosing
  `<receiver>` element — `aapt2 dump xmltree` puts the element and its
  attributes on separate lines and a multi-line match here would be more
  fragile than the thing it buys. Nothing else in this app would ever carry
  that class name, so the single-line attribute match is sufficient and the
  comment says so.

**Scope decision:** assert only `ActionBroadcastReceiver`. The other two
receivers fail equally invisibly, but their compiled lines have not been
sampled, and shipping unverified greps into a fail-closed release gate is the
exact thing this plan's constraints forbid. Recorded as a follow-up instead.

- [x] Add the step.
- [x] Update the manifest comment block above the receiver so the two places
  agree: the assertion now exists; drop "Not added here … raised in the PR
  instead", which becomes false the moment this lands.

### Task 1b — the idiom being copied is broken (found while verifying Task 1)

Not planned; found by running the committed step body under Actions' actual
shell (`bash -e -o pipefail`) against a stub `aapt2`. **`aapt2 … | grep -q …`
produces a FALSE FAILURE whenever the dump exceeds the 64 KB pipe buffer:**
`grep -q` exits on first match, `aapt2` takes SIGPIPE and returns 141, and
`pipefail` promotes 141 to the pipeline's status — so the `||` branch fires
and prints an error accusing the APK of exactly the thing it just proved.

Measured, on identical content, capability present:

| shape | small dump (today) | > 64 KB dump |
| --- | --- | --- |
| `origin/main`'s INTERNET check (piped) | exit 0 | **exit 1** |
| `origin/main`'s allowBackup check (piped) | exit 0 | **exit 1** |
| all three after the fix (dump to file) | exit 0 | exit 0 |

and all three still exit 1, with their annotation, when the capability is
absent. So these gates were roughly one plugin's worth of manifest growth
away from failing **every release, at tag time**, for a reason unrelated to
what they assert — the worst possible time and the most misleading possible
message.

- [x] Redirect the dump to `$RUNNER_TEMP` and grep the file, in **all three**
  steps. Patterns and error messages are byte-identical; only the plumbing
  changes. This is inside a file the plan already touches, and leaving two
  known landmines beside a freshly-fixed third would be indefensible.
- [x] Keep the three steps self-contained (each does its own dump) rather
  than consolidating to one dump plus three greps: for a release gate,
  a step you can read in isolation and know exactly what it proves is worth
  more than removing a duplicated `ls`.

---

## Task 2 — diagnose A-6 before touching its trigger

Evidence, all from run `31800958022` (`625ea72`, the only red `ios` run in
the 30 most recent `e2e.yml` runs on `main`):

- **Not a state leak.** The failure-step accessibility hierarchy for both
  failed flows contains the status bar and the app window titled "Famdo" and
  **nothing else** — no welcome gate, and *no tab shell either*. A stale
  household would have rendered the shell. The screenshot is a blank white
  frame under a live status bar.
- **Not a marginal timeout.** Across the run's 14 flows the wait for
  `welcome.create` after a `clearState` launch was 4.8 – 9.0 s in all 12
  passes, and a full 60 s in both failures. The distribution is bimodal:
  roughly seven seconds, or never. A larger timeout buys nothing.
- **Not a hang, and not a crash.** XCTest runs in-process
  (`Runner[17341]`); its log shows the app's main thread answering the
  snapshot query — "MT responded in time" — and the accessibility snapshot
  captured cleanly in 0.01 s with zero Flutter nodes in it. The process was
  never terminated.
- **Mechanism of the platform difference.** The simulator log shows Maestro's
  iOS `clearState: true` implemented as **uninstall + reinstall** (`Request
  received for uninstallation …` → `applicationsDidInstall` → open request),
  i.e. a brand-new bundle container and a genuinely cold start per flow. On
  Android `clearState` clears app data and leaves the app installed. So the
  `ios` job's warm-up launch is mostly discarded by the first flow, and the
  iOS job takes a cold start 14 times where Android takes one.
- **Rate — and a correction to my own first figure.** An early six-run sample
  gave ≈17 % of runs, and that number is wrong; the `ios` job runs on *every*
  push to `main`, so the denominator is the whole history. Full history: **61
  runs, 10 red**, but **9 of the 10 fall on 2026-07-31/08-01** — CI bring-up
  (the workflow header's own "expect first-run adjustments") plus the
  cold-start hardening that produced `e2e/README.md` convention 8. Since the
  last of those: **1 red in 32 runs ≈ 3 % of runs, ≈ 0.4 % of flows** (2 bad
  flows in ~448).
- **Zero confirmed catches.** Across all 61 runs, no red has ever been an
  iOS-specific code regression. Every one is bring-up or this flake.

Conclusion: a real, **unfixed and not-understood** iOS startup flake in which
the Flutter view permanently fails to present on a fresh install. The nearest
documented precedent is `e2e/README.md` convention 8 rule 3's "permanently
blank" race — but that one is Android-specific and needs a `permissions:`
stanza, which neither failing flow has.

- [ ] Correct the A-6 row in `docs/backlog.md` to the verified mechanism. The
  recorded *decision* framing stays closed; the recorded *cause* is a factual
  claim that the artefacts contradict, and leaving it would send the next
  agent hunting a `clearState` bug that is not there.

---

## Task 3 — settle A-6

**Decision: (b) — keep the `main`-only gate, plus a `workflow_dispatch`
escape hatch so iOS can be verified on a branch, pre-merge, on demand.**

Why not (a), and note that the reason is **not** the one the brief and my own
first draft assumed. At ~3 % of runs the flake would cost about one falsely
red PR run in 32 — ordinary flaky-test territory, and not on its own enough
to keep iOS off PRs. What decides it is **value per macOS minute**: in 61
runs this job has never gone red for an iOS-specific code regression, so it
has *no catch record*, while a macOS runner is ≈10× Linux, the job takes
17-20 minutes, and PR pushes here arrive in bursts
(`wave4/shopping-gestures` produced four PR runs inside an hour). Paying that
on every push for a job that has never caught anything is poor value; paying
it on demand for the PR that actually touches iOS-sensitive surfaces
(gestures, platform channels, `AppDelegate`) buys the same protection where
the risk is. A path filter would not rescue the cost side either: nearly
every PR here touches `lib/**`, which is iOS-relevant, so "PRs touching
iOS-relevant paths" is in practice "all PRs".

The flake is also not *fixed* here, and cannot be: it did not reproduce on
wave-4 code, there is no local reproduction, and the executing agent cannot
run Maestro or a simulator to build one. Every in-flow remedy that fits the
bimodal shape — a Maestro `retry`, a `--retry-on-failure` CLI flag — is
unverifiable here, and Maestro is pinned at 2.7.0 precisely because
unverified Maestro changes have burned this repo before.

**Two conditions flip this decision**, both recorded in the workflow: the
first time `ios` catches a genuine iOS-only regression on `main`, or the
dispatch path falling out of use. Either means the 10× is worth paying
automatically.

What (b) buys that today's gate does not: `workflow_dispatch` gives exactly
the thing A-6 actually complains about — pre-merge iOS verification with
attribution, for the PR that needs it (wave 4's swipe gesture was precisely
that PR) — at zero cost for the PRs that do not. The job-level `if` must be
widened to admit the manual event or the dispatch would skip `ios` on any
branch that is not `main`.

**Behaviour for a PR that touches nothing iOS-relevant** (and for every other
PR): the workflow still runs on `pull_request`, `android` still runs, `ios`
skips. No check named `ios` is ever expected on a PR, so no required check
can hang. Recorded in the comment: `main`'s only required status check today
is `pgtap`, and `ios` must not be made required until the trigger is widened
*and* the flake is fixed — a workflow-level `paths:` filter is the shape that
would deadlock a required check forever, because the workflow then never runs
and the check run is never created for branch protection to satisfy.

- [ ] Add `workflow_dispatch:` to `e2e.yml`'s `on:`.
- [ ] Widen the `ios` job's `if:` to admit `workflow_dispatch`.
- [ ] Replace the file-header's one-line "iOS runs on main only (macOS
  runners cost ~10x Linux)" and add a comment on the `ios` job carrying the
  diagnosis, the decision, the required-check interaction, and the condition
  under which the gate should be widened — in the voice of the neighbouring
  comments, which are unusually detailed on purpose.

---

## What this plan does NOT do

- **Does not fix the iOS flake.** Not diagnosed to root cause, not
  reproducible here, and not fixable without running a simulator. Task 2
  leaves the next agent a correct starting point instead of a wrong one.
- **Does not touch `e2e/flows/**` or `e2e/common/**`.** Any flow change would
  need a Maestro run to verify and would be shipped blind.
- **Does not assert the other two notification receivers**, and does not
  touch `ci.yml` or `db.yml`.

## Verification reality

- `checks` will be a fast green on a YAML+Markdown diff. It proves the YAML
  parses and nothing else — in particular nothing about either assertion.
- `db.yml` will report a fast green **without** running the pgTAP suite,
  because the diff touches nothing under `supabase/**`. Not verification.
- `android` (E2E) is unaffected and its result carries no information about
  either item.
- `release.yml` is tag-triggered: **no run on this PR can exercise Task 1.**
  Its pattern rests on the orchestrator's positive and negative controls
  against a real merged manifest, plus the deductive generalisation argued in
  Task 1. First real exercise is the next `v*` tag.
- `ios` on `workflow_dispatch` is checkable the moment this lands on a branch
  the orchestrator can dispatch — that is the one part of this change whose
  effect can be observed before merge, and it is the orchestrator's call
  whether to spend a macOS run on it.
