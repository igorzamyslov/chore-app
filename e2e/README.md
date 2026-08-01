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

The FIRST element wait after a `launchApp` that clears state AND sets
`permissions:` must be an `extendedWaitUntil` (60–90s), never a bare
`assertVisible`: that combination produces the coldest possible app
start (fresh ART verification, nothing cached), and on CI emulators the
first Flutter frame can land after Maestro's default element window —
observed 2026-08-01 (logcat showed the first frame at ~30s while the
default window expired at ~19s; the Maestro version pin shifts the odds
but does not remove the race). Later steps run against a live app and
keep normal timeouts. CI uploads `~/.maestro/tests` as a debug artifact
on failure — start every CI-only investigation from those screenshots.
