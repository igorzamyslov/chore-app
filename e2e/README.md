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
8. **A text assertion is an assertion about a whole MERGED accessibility
   node.** Flutter merges related widgets into one node, and Maestro
   matches that node's text EXACTLY — so a label sitting next to anything
   else is not matchable on its own. This bit three times on 2026-08-06
   alone: a section header plus its new count became `"Today\n1"`; a form
   field plus its inline error became `"Title\nTitle is required"`; chore
   tiles merge title + metadata (the reason for the older `"(?s).*Foo.*"`
   asserts). The merges are all CORRECT for screen readers — an error
   should be announced with its field — so the app stays and the assertion
   adapts:
   - content doesn't matter → **assert the semantic id** (e.g.
     `chores.section.today`). Preferred: immune to copy and layout changes.
   - content matters → **`"(?s).*substring.*"`**, and say in a comment
     what it is sharing a node with.

   When an assertion fails with "is visible" on text you can plainly see
   on screen, do NOT theorise — Maestro already dumped the answer. Read
   `~/.maestro/tests/<run>/<flow>/screen-hierarchy/<last step>.json` and
   look at `text`, `accessibilityText` AND `hintText` (a `TextField`'s
   label/error land in `hintText`, not the other two).

9. **A swipe never gets a wait — it gets an `assertVisible` on an element
   that only exists on the destination.** The shell's tab `PageView`
   (backlog D-1) settles with standard `PageScrollPhysics`, so the frame
   the swipe lands on is not predictable; `assertVisible` polls, a sleep
   does not (spec `docs/specs/testing-strategy.md` §2.5). Keep both swipe
   endpoints well inside the screen (20%/80% is the suite's default): a
   gesture starting at a screen edge is an iOS interactive-pop or an
   Android system edge gesture, not your swipe — the same failure class as
   convention 3's `hideKeyboard`. And remember that a horizontal drag
   starting on a shopping ITEM row belongs to that row's `Dismissible`, not
   to the page (spec `docs/specs/ui-shopping.md`), so flows that swipe on
   the Shopping tab must do it over an empty list or over the quick-add
   row / a category header.

   **The trap that will silently poison this whole suite:
   `PageView.allowImplicitScrolling`.** It is `false` in
   `lib/app/app_shell.dart` and must stay `false`. Setting it true (the
   obvious-looking "fix" for the one-frame spinner on a tab's first visit)
   widens the viewport's cache extent so the NEIGHBOURING tab is laid out
   inside the viewport's semantics clip — unlike a kept-alive page, which
   is excluded. Its `Semantics(identifier: ...)` nodes then join the
   accessibility tree while a different tab is on screen, so `assertVisible`
   starts passing for ids that are not on screen and `assertNotVisible`
   starts failing for ids that are correctly hidden. The failures look like
   flakes and point nowhere near the shell. Guarded by
   `test/app/shell_navigation_test.dart` and spec
   `docs/specs/ui-foundation-chores.md`, "App shell navigation" item 2.

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

Three rules:

1. **Every `launchApp` is followed by a first-frame settle** — an
   `extendedWaitUntil` (60s) before the first interaction. On slow CI
   machines the first frame after a launch (cold OR warm relaunch) can
   lose the race against the first tap; the default element window is
   not enough headroom. Later steps run against a live app and keep
   normal timeouts. Root-caused 2026-08-01 from CI debug artifacts
   (white first frame in the failure screenshots on BOTH platforms).
   **On a COLD (`clearState: true`) launch the target is `welcome.create`,
   not `shell.tab.chores`** (spec `docs/specs/onboarding-v2.md`): there is
   no household — and so no tab shell — until one is explicitly created
   or joined, so a fresh install always lands on the welcome gate first.
   A warm relaunch (no `clearState`) still targets `shell.tab.chores`,
   since the household created earlier in the same flow already exists.
2. **Every flow clears the welcome gate right after that settle.**
   `e2e/common/onboard_fresh.yaml` taps `welcome.create`, types the
   name "Me", and confirms — every flow prepends
   `- runFlow: ../../common/onboard_fresh.yaml` (path-relative) directly
   after its cold-launch settle wait, landing on the tab shell exactly
   where every flow used to assume it started. `first_run_banners.yaml`
   is the one exception: it needs a distinctive name ("Jordan") to keep
   its own final assert meaningful, and its permission-stanza recovery
   dance (rule 3 below) is already intertwined with the cold-start wait,
   so it inlines the same three steps instead of calling the shared
   sub-flow.
3. **Permission overrides ride inside EVERY `launchApp` that needs
   them — there is no other way.** Proven empirically via dumpsys
   (2026-08-01): Maestro's Android driver auto-grants all manifest
   runtime permissions on every launchApp, so standalone
   `setPermissions` or a bare relaunch always ends granted=true again;
   only a launch carrying the `permissions:` stanza applies the
   override. The stanza launch has an internal revoke-vs-start race
   that can leave the app permanently blank on slow emulators — handle
   it with the bounded-optional-wait + conditional stanza-relaunch
   pattern in first_run_banners.yaml (relaunch WITH the stanza, WITHOUT
   clearState).

CI uploads `~/.maestro/tests` as a debug artifact on failure — start
every CI-only investigation from those screenshots, never from theory.
