# E2E flows (Maestro)

Run with `tool/e2e.sh ios` / `tool/e2e.sh android` (builds with the pinned
`E2E_TODAY` clock, boots a device, runs everything under `e2e/flows/`).

## Flow-authoring conventions (learned the hard way)

1. **Select by semantic id, never by display text** — ids survive copy
   changes and localization. Regex ids need SINGLE-quoted YAML strings
   (`id: 'chores\.occurrence\..*\.complete'`): double quotes make YAML eat
   the backslashes.
2. **Text inside an interactive row needs `(?s).*Title.*`.** Android
   merges a tappable row's descendants into ONE newline-joined
   accessibility label (`'Water plants\nToday'`) — good for TalkBack,
   fatal for full-string regex matching. Standalone texts (section
   headers, snackbars, dialog copy) match plainly on both platforms.
3. **Never `hideKeyboard` on iOS** — it performs a blind gesture that can
   tap random controls (it once opened the date picker). Dismiss via
   `pressKey: Enter` on a single-line field instead.
4. **Assert you LEFT a screen via an element that only exists on the
   destination** (e.g. `chores.add` after saving the form) — a bare text
   assert can false-positive by matching a form field's own content.
5. The app's smart defaults are part of the product: the repeat unit
   defaults to weekly-on-today's-weekday. Flows that need daily must tap
   `chore_form.repeat.unit.day` explicitly.
6. **Settle before touching a freshly-created row.** After saving, assert
   BOTH the destination element (convention 4) AND the new tile's own
   text before tapping anything on that tile. On slow CI simulators the
   row is still animating in right after save, and a tap during the
   animation misses — the first live CI run failed exactly this way in
   `skip_undo_journey` while locally everything was green.
7. **Never use Maestro's bare `back` command.** On iOS it's a blind
   left-edge swipe (same danger class as `hideKeyboard`, convention 3)
   and it failed to pop a pushed route on the simulator. Pop screens by
   tapping the app bar's BackButton instead — Flutter gives it the
   semantics label `Back` (MaterialLocalizations) on both platforms.

## Maestro version (pinned)

CI installs Maestro PINNED via `MAESTRO_VERSION` in
`.github/workflows/e2e.yml` (currently **2.7.0**). Never unpin: cli-2.8.0
(2026-07-31) regressed `launchApp` with `clearState` — clearing takes
~20s and the relaunch is cold enough (ART re-verification) that Flutter's
first frame can land AFTER Maestro's element-wait window on slow
runners; `first_run_banners` flaked red on CI exactly this way with zero
repo change. To upgrade the pin: A/B the SAME debug APK on the SAME
local emulator, old vs new version (install the candidate under a
scratch `HOME` so the local install stays put), run the full suite on
the candidate, then bump the pin and this note together. Keep the local
`~/.maestro` at the pinned version so local runs and CI agree.

## Cold starts (convention 8)

Two rules, both root-caused 2026-08-01 from CI debug artifacts (white
first frame in the failure screenshots on BOTH platforms):

1. **Every `launchApp` is followed by a first-frame settle** — an
   `extendedWaitUntil` on `shell.tab.chores` (60s) before the first
   interaction. On slow CI machines the first frame after a launch
   (cold OR warm relaunch) can lose the race against the first tap;
   the default element window is not enough headroom. Later steps run
   against a live app and keep normal timeouts.
2. **Permission overrides never ride inside `launchApp`.** Bundling
   `permissions:` into the launch stanza lets the permission operations
   race the process start — Android kills a process whose runtime
   permission changes, which intermittently left the app permanently
   blank. Sequence standalone steps instead:
   `clearState` → `setPermissions` → `launchApp`
   (see first_run_banners.yaml), so the permission state is settled
   before the process exists.

CI uploads `~/.maestro/tests` as a debug artifact on failure — start
every CI-only investigation from those screenshots, never from theory.
