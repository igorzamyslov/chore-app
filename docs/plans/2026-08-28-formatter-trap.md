# A-7 — make the worktree formatter trap detectable and hard to hit

Backlog row **A-7**. Written 2026-08-28, wave 5 stream 3. No prior plan existed,
so there was nothing to refresh; instead this plan records the measurements that
invalidate the fix the backlog row *suggested*.

## The bug

A fresh `git worktree` has no `.dart_tool/`. `dart format` therefore cannot
resolve `include: package:very_good_analysis/analysis_options.yaml` in
`analysis_options.yaml`. It prints

```
Warning: Package resolution error when reading "analysis_options.yaml" file:
Failed to resolve package URI "package:very_good_analysis/analysis_options.yaml" …
```

to **stderr**, **exits 0**, and falls back to the formatter's default
`trailing_commas: automate` instead of the project's `preserve` — which is set
only inside `very_good_analysis`'s own options file
(`lib/analysis_options.10.3.0.yaml`, `formatter: trailing_commas: preserve`),
i.e. only reachable through the include that just failed.

Bare `dart format .` then reflows ~93 of 255 files: trailing commas dropped,
multi-line calls rejoined.

**Why this is a hazard and not a nuisance:** `preserve` is *stable* on
already-reflowed code. So `dart format --set-exit-if-changed` **passes** on the
churn, and `ci.yml` is structurally incapable of detecting it after the fact.
In wave 4 one agent put 85 out-of-scope files into its branch this way, two of
them being concurrently edited by other agents.

## Measurement that kills the backlog's suggested fix

The row proposes "a committed formatter config that does not depend on package
resolution". **That is not achievable.** Measured on Dart 3.12.2: an
unresolvable `package:` include causes `dart format` to discard the *entire*
options file, not just the failing include.

| Root `analysis_options.yaml` | `.dart_tool` | probe reflowed? |
|---|---|---|
| `include: package:very_good_analysis/...` | absent | **yes** |
| same **plus** an explicit `formatter: trailing_commas: preserve` block | absent | **yes** |
| `include: [./formatter_options.yaml, package:very_good_analysis/...]` | absent | **yes** |
| `include: ./lints_options.yaml` (which has the package include) + explicit `formatter:` block at root | absent | **yes** |
| `formatter: trailing_commas: preserve`, no include at all | absent | no |

So the setting cannot be rescued by *any* arrangement of checked-in YAML while
`analysis_options.yaml` reaches `very_good_analysis` through a `package:` URI —
and it must, for the lints. The only config-only escape would be vendoring the
whole very_good_analysis ruleset into the repo, which trades a silent formatter
bug for a silently-stale lint set. Rejected.

Conclusion: the fix has to be a **check**, not a config.

## Design

### 1. Detectable — `tool/check_formatter_config.sh`

A future agent in a fresh worktree needs to be able to ask "is my formatter
config resolving?" and get a truthful answer. The check asserts the thing that
actually matters — that `trailing_commas: preserve` is in effect — not the proxy
"does `.dart_tool/` exist", which is the kind of check that passes while the bug
is live.

Mechanism: a fixture whose formatting *differs* between `preserve` and
`automate`

```dart
final probe = <int>[
  1,
  2,
];
```

Under `preserve` the trailing comma keeps it split, so the file is already
formatted. Under `automate` the comma is dropped and it collapses to
`final probe = <int>[1, 2];`. So `dart format -o none --set-exit-if-changed` on
the fixture is exit 0 under `preserve` and exit 1 under `automate`. The exit
code alone is the assertion; no output parsing.

Three constraints on the fixture and how they are met:

- **It must not be reformattable by a future tool run.** It is *not committed*.
  The script regenerates it on every run at
  `.dart_tool/formatter_probe/probe.dart`. `.dart_tool/` is gitignored, so it
  can never enter a branch, and `dart format` / `flutter analyze` skip
  dot-directories during traversal — measured: with a deliberately misformatted
  probe in place, `dart format -o none --set-exit-if-changed .` still reports
  "276 files (0 changed)" while formatting the same file directly reports
  "1 changed".
- **It must not break `flutter analyze --fatal-infos` or the test suite.** Same
  reason: dot-directory, plus it is not a `*_test.dart`, plus it only exists
  after the check has run locally.
- **It must sit inside the repo tree**, or `dart format` would walk up and find
  neither `analysis_options.yaml` nor `package_config.json` and report a false
  alarm. `.dart_tool/formatter_probe/` satisfies both that and the above.

**Self-test, so the check cannot become vacuous.** The whole class of bug here is
"a check that stays green while the bug is live". Before making the real
assertion, the script writes the *same* fixture into a throwaway temp dir
carrying `formatter: trailing_commas: automate`, and requires that it *does*
change there. If the fixture is ever edited into something formatting-invariant,
or the two modes stop differing, the check fails loudly instead of passing
vacuously. Pinning `automate` explicitly (rather than relying on "no options
file found") keeps this independent of the SDK's default and of stray ambient
options files.

### 2. Hard to hit — gate the format step, never check after it

`lefthook.yml`'s `pre-commit` `format` job (`dart format --set-exit-if-changed
{staged_files}`, `stage_fixed: true`) is exactly where the trap bites. The check
runs **as a prefix of that job's own command**:

```yaml
run: tool/check_formatter_config.sh && dart format --set-exit-if-changed {staged_files}
```

rather than as a separate job earlier in the list — a separate job would depend
on lefthook's ordering/fail-fast semantics, whereas `&&` cannot be bypassed and
cannot run out of order. One invocation, no redundancy.

Every `dart` call inside the script is prefixed `env -u GIT_DIR -u
GIT_INDEX_FILE`, per the `analyze` job's existing comment: git sets those for
hook subprocesses, Flutter's own git calls inherit them, and the SDK version
then reads `0.0.0-unknown`.

The script also derives the repo root from its own location
(`ROOT="$(cd "$(dirname "$0")/.." && pwd)"`, the convention `tool/e2e.sh`
already uses) rather than from `git rev-parse`, which is unreliable under a
hook's `GIT_DIR`.

Its failure message names the one-line remedy
(`env -u GIT_DIR -u GIT_INDEX_FILE flutter pub get --enforce-lockfile`) and, when
the stderr warning is present, quotes it.

### 3. CI

Added to `ci.yml` before the format step. On a runner `flutter pub get` always
precedes it, so the resolution half is vacuous there — but the *other* half is
not: CI then asserts that the project's configured trailing-comma mode is still
`preserve`, which would catch a `very_good_analysis` upgrade that drops the
setting or an edit to `analysis_options.yaml` that shadows it. Costs ~0.1s.

### 4. Docs

`README.md` gains the worktree caveat in Setup and the check in the Checks
table. The A-7 backlog row is closed and corrected — the "committed formatter
config" suggestion is recorded as measured-impossible so nobody retries it.

## Files

- `tool/check_formatter_config.sh` (new)
- `lefthook.yml`
- `.github/workflows/ci.yml`
- `README.md`
- `docs/backlog.md` (close + correct A-7)

## Verification

CI green proves only that nothing broke; it cannot exercise the trap, because a
runner is never in the bad state. The load-bearing verification is a
good-vs-bad comparison run on **copies outside the repo** — never by removing
`.dart_tool/package_config.json` inside a worktree and formatting the tree,
which is the accident being fixed. Two scratch repos identical but for the
presence of `package_config.json`; the script must exit 0 in one and 1 in the
other, with the remedy printed.
