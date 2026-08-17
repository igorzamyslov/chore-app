# Spec: polish round 1 (G1/G2/G3/G8/G9 + lifecycle robustness)

*Status: BINDING. Sources: docs/app-lifecycle.md gaps, docs/
next-session-plan.md small-items backlog. Schema v5 (the two shown-once
flags) is already committed — nothing here changes the schema.*

## A. First-run experience (G1 + G2) — banners, never modals

E2E constraint that shaped this design: every Maestro flow starts from a
cleared state, so any MODAL first-run UI would break all of them. Both
first-run aids are therefore inline, dismissible banner cards at the top
of the chores list, and flows keep passing untouched.

### A1. Two distinct chores empty states (G1)
- **Fresh install** (zero non-deleted chores in the household): icon
  (outlined `add_task`-family) + copy inviting the first chore
  ("Add your first chore with +" tone, l10n key `choresEmptyFresh`).
  Child semantic id `chores.empty.fresh`.
- **All done** (chores exist, none pending): keep the existing praise
  copy (`choresEmptyState`), add a fitting icon. Child id
  `chores.empty.done`.
- The existing `chores.empty` id REMAINS on the shared container in both
  states — E2E flows assert it after deleting the only chore and must
  keep passing.
- Shopping empty state: single state, add an icon above the existing
  copy (design-language "empty states get an icon" debt). No id changes.

### A2. Name prompt banner (G2)
- Card at the top of the chores list, shown only while
  `settings.onboardingNamePromptShownAt` is NULL **and** the household
  still consists of exactly the bootstrap member named 'Me'. (If the user
  already renamed/added members — e.g. an upgrading install — mark the
  flag silently on first evaluation instead of showing the banner.)
- Content: friendly one-liner ("Who's doing the chores here?" tone) +
  two actions: **Set my name** (id `onboarding.name.set`) opens the
  EXISTING member edit sheet (lib/features/settings/member_edit_sheet.dart)
  prefilled for the bootstrap member; saving there renames the member,
  and the banner marks the flag and disappears. **Dismiss** (X, id
  `onboarding.name.dismiss`) marks the flag; the members screen remains
  the permanent path. Banner container id `onboarding.name`.
- Never blocks anything; renders above the Overdue/Today sections and
  above the A3 banner (they are mutually exclusive in practice anyway:
  this one requires zero *interactions*, see A3 trigger).

### A3. Digest pre-prompt banner (G3)
- **Remove** `NotificationScheduler`'s automatic `requestPermission()`
  on the first schedule attempt (lib/application/notification_scheduler.dart,
  the call inside the scheduler around line 221). After this change the
  OS permission dialog can NEVER appear except from an explicit user tap
  (this banner, or the existing Settings digest row) — kills the
  uncontrolled cold-launch dialog class for good.
- Card at the top of the chores list, shown only while ALL hold:
  `settings.digestPrepromptShownAt` is NULL, the digest is enabled,
  OS notification permission is not granted, and at least one chore
  exists (so a fresh install shows the A2 banner first, this one only
  after the first chore was created — the moment G3 recommends).
- Content: "Want a daily summary of what's due?" + **Turn on** (id
  `digest.preprompt.enable`): mark flag, then `requestPermission()` (the
  one-shot OS dialog), then trigger a digest recompute. **Not now** (id
  `digest.preprompt.dismiss`): mark flag only — the digest stays enabled
  but silent until permission arrives via Settings (existing hint row is
  the recovery path). Banner id `digest.preprompt`.

## B. Settings data operations (G8 + G9)

### B1. Export data (G8)
- Settings row `settings.export` (icon `ios_share`-family), between the
  digest section and About. Builds one JSON document:
  `{ "format": 1, "schema_version": 5, "exported_at": <ISO UTC>,
  "tables": { "households": [...], "members": [...], "categories": [...],
  "chores": [...], "chore_assignees": [...], "chore_occurrences": [...],
  "shopping_items": [...], "settings": [...] } }` — raw column names/
  values as stored (recurrence stays its JSON string; no re-encoding),
  soft-deleted rows INCLUDED (it's a backup, not a view).
- Shared via the OS share sheet (`share_plus`, new dependency) as
  `famdo-export-<yyyy-mm-dd>.json`. Failure → `showAppSnackbar` with a
  generic error string. No import in this round (import belongs to the
  sync/adoption work, G4).

### B2. Reset app data (G9)
- Bottom of Settings, visually separated, destructive-styled row
  `settings.reset` ("Reset app data").
- Double-confirm: dialog 1 (id `settings.reset.confirm1` on its confirm
  button) states everything is deleted forever and there is no cloud
  copy; dialog 2 (`settings.reset.confirm2` / `settings.reset.cancel`)
  requires the final destructive tap. Cancel anywhere = no-op.
- Confirmed: inside one transaction delete ALL rows from every table
  (FK-safe order: occurrences, assignees, chores, shopping items,
  categories, members, settings, households), then re-run bootstrap
  (invalidate `bootstrapProvider`) so the app lands in the fresh-install
  state (including the A2 banner — the flags live in the deleted
  settings row, which is exactly right).
- Confirmed also cancels the scheduled digest notification and signs out
  of the current Supabase session, if any (spec
  `docs/feedback/2026-08-08-prerelease-audit.md` P3) — both best-effort,
  run before the wipe, and never blocking it. This is the deliberate
  opposite of the A1.2 Disconnect action (spec
  `docs/feedback/2026-08-07-field-feedback.md` A1), which keeps the
  session and only unlinks the device: Reset is the clean-slate operation,
  Disconnect is the "keep working, just not with this household" one.
- The flow lives in `confirmAndResetAppData`, a top-level function in
  `lib/features/settings/reset_flow.dart` rather than a private method on
  the row widget, so the startup error screen can run it too (spec
  `docs/specs/ui-foundation-chores.md` "main.dart"; spec
  `docs/feedback/2026-08-08-prerelease-audit.md` S2). The two dialogs
  themselves come from the action-agnostic
  `confirmTwoStepDestructiveAction` in
  `lib/features/settings/destructive_confirm.dart`: any further
  irreversible action composes a `DestructiveConfirmStep` pair instead of
  copying a dialog builder.
- If the wipe itself throws — the same broken connection that put a user on
  the startup error screen is what it must write through — that surfaces as
  the `settingsResetError` snackbar, never as an unhandled exception. That
  catch is `on Object`, not `on Exception`, because a closed sqlite3
  connection throws a `StateError`; likewise for the two best-effort
  side-effects above, where a notification-plugin
  `LateInitializationError` once escaped an `on Exception` and aborted a
  double-confirmed wipe. **Do not narrow these catches.**

## C. Lifecycle robustness

### C1. catchUpOverdue on resume + day-change
- `catchUpOverdue` currently runs only at bootstrap. Add a small
  controller (pattern: `DigestRescheduleController`) that re-runs it
  (a) whenever the app resumes from background (hook into the existing
  `_DigestResumeObserver` in lib/main.dart — rename appropriately), and
  (b) when the local calendar day changes while the app stays open
  (timer armed for just past local midnight, re-armed after firing;
  DST-safe: compute the next midnight from calendar components, same
  rule as `nextDigestSlot`). Also trigger a digest recompute after any
  catch-up that changed rows.
- Amended 2026-08-08 (backlog A-2 / audit P1): on BOTH triggers the
  controller also refreshes `todayProvider` — unconditionally, unlike the
  digest recompute. The digest only has news when catch-up changed rows, but
  the calendar date changes every night whether or not anything fell
  overdue, and that common night is exactly the case the UI was getting
  wrong. The day-change timer stays in this controller (rather than moving
  into `todayProvider`) because this controller is activated only from
  `main.dart`: a timer armed by a provider the widget tree watches would trip
  `flutter_test`'s pending-timer check in every chores widget test.
- Internals fix while there: `catchUpOverdue` reads
  `watchActiveChores().first` inside its transaction — replace with a
  new Future-based `ChoreRepository` read (`getActiveChores()`), same
  query, no stream.

### C2. Editing recurrence/start date regenerates the pending occurrence
- Documented v1 simplification (chore_form_screen.dart) becomes real
  behavior: when an EDIT changes `recurrence` and/or `startDate`
  (compare by value — `Recurrence` has a real `==` since backlog E-4; this
  used to be a `jsonEncode` projection), the service must, in the same
  transaction: delete the chore's pending occurrences and insert a fresh
  one using THE SAME two-floors rule as `unpauseChore` (never before
  today; never at/before the latest closed slot; closed one-off →
  nothing; completion anchor → max(today, nextAfterCompletion)). Extract
  the shared due-date helper out of the unpause path rather than
  duplicating it. Assignee re-resolution mirrors unpause. Edits that
  touch neither field keep the pending occurrence untouched (incl. its
  assignee).
- Spec home: fold the rule into docs/specs/occurrence-lifecycle.md §2 as
  `updateChore` semantics (the implementing agent updates that file).

### C3. Shopping item delete gets an undo
- Wherever the UI deletes a shopping item, show `showAppSnackbar` with
  an Undo action that clears `deleted_at` (soft delete makes this a
  plain restore). Copy mirrors the chores undo tone.

## l10n
Every new string in BOTH arb files, du-form German, keys prefixed by
feature (`choresEmpty*`, `onboardingName*`, `digestPreprompt*`,
`settingsExport*`, `settingsReset*`, `shoppingDeleted*`).

## Tests
Same conventions as everywhere (real in-memory DB, two provider
overrides only, no stream awaits outside pumps, no bare bootstrap-future
awaits). Each area ships with widget tests covering: both empty states;
banner show/dismiss/complete paths incl. the upgrading-install silent
mark; export JSON shape (golden-ish assertion on a seeded DB — share
sheet itself may be stubbed at the share_plus boundary); reset wipes and
re-bootstraps; day-change timer via fakeAsync-style controller test;
regeneration matrix (changed recurrence, changed start date, unchanged
edit, closed one-off, completion anchor); shopping delete undo restores
the row. E2E: one new flow for the banner journey (fresh launch → name
banner visible → set name → banner gone → digest banner appears after
first chore) following ALL e2e/README.md conventions.
