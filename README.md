# Chores

Family chores + shared shopping list app (Android & iOS, Flutter).
See [DESIGN.md](DESIGN.md) for the full product and architecture design;
specs for individual components live in [docs/specs/](docs/specs/).

## Setup after cloning

```sh
flutter pub get
lefthook install   # activates the git hooks (brew install lefthook)
```

## Checks

Every commit runs (via [lefthook.yml](lefthook.yml)):

| Check | Command |
|---|---|
| Format | `dart format` (auto-fixes staged files) |
| Analyze | `flutter analyze --fatal-infos --fatal-warnings` |
| Tests | `flutter test` |
| Lockfile | `dart pub get --enforce-lockfile --offline` |

CI ([.github/workflows/ci.yml](.github/workflows/ci.yml)) runs the same
checks — keep them in sync.
