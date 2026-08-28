# Chores

Family chores + shared shopping list app (Android & iOS, Flutter).
See [DESIGN.md](DESIGN.md) for the full product and architecture design;
specs for individual components live in [docs/specs/](docs/specs/).

## Setup after cloning

```sh
flutter pub get
lefthook install   # activates the git hooks (brew install lefthook)
```

## Setup in a new `git worktree`

Run `pub get` there **before** anything else, `dart format` above all:

```sh
flutter pub get --enforce-lockfile
tool/check_formatter_config.sh   # confirms it worked
```

A fresh worktree has no `.dart_tool/`, and without it `dart format` **formats
with the wrong configuration and does not tell you**. It cannot resolve the
`package:very_good_analysis/...` include in
[analysis_options.yaml](analysis_options.yaml), so it loses that file's
`trailing_commas: preserve` and falls back to `automate`. It warns on stderr
only, and still exits 0. A bare `dart format .` then strips trailing commas and
rejoins multi-line calls across ~93 of 255 files — and **nothing can detect
that afterwards**, because `preserve` is stable on `automate`'s output, so both
the hook and CI's `dart format --set-exit-if-changed` pass on the churn.

`tool/check_formatter_config.sh` answers "is my formatter config actually
resolving?" truthfully: it formats a fixture that comes out *differently* under
the two modes, rather than looking for `.dart_tool/` and hoping. Run it whenever
you are unsure — the pre-commit `format` job also runs it before formatting
anything.

## Checks

Every commit runs (via [lefthook.yml](lefthook.yml)):

| Check | Command |
|---|---|
| Formatter config | `tool/check_formatter_config.sh` (guards the next row) |
| Format | `dart format` (auto-fixes staged files) |
| Analyze | `flutter analyze --fatal-infos --fatal-warnings` |
| Tests | `flutter test` |
| Lockfile | `dart pub get --enforce-lockfile --offline` |

CI ([.github/workflows/ci.yml](.github/workflows/ci.yml)) runs the same
checks — keep them in sync.
