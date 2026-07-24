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
