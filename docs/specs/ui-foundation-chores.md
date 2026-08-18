# Spec: UI Foundation + Chores Screens

*App shell, Riverpod wiring, testability plumbing (semantic IDs, injectable
clock), and the chores feature UI. Shopping UI is a separate spec.*

## Placement

| What | Where |
|---|---|
| Providers (db, repos, service, clock, bootstrap) | `lib/app/providers.dart` |
| Semantic id helper | `lib/app/semantics.dart` |
| Theme | `lib/app/theme.dart` |
| App shell + navigation | `lib/app/app.dart` (ChoreApp moves here; `main.dart` shrinks to bootstrap) |
| Chores screens/widgets | `lib/features/chores/…` (implementer's file split, keep files < ~300 lines) |
| Category picker + icon rendering (shared later with shopping) | `lib/features/categories/…` |
| Widget tests | `test/app/…`, `test/features/chores/…` |

## Foundation contracts

### Providers (`flutter_riverpod`)
- `appDatabaseProvider` — overridden in tests/E2E; default `AppDatabase(openConnection())`.
- `clockProvider` → `package:clock` `Clock`. Default: reads
  `const String.fromEnvironment('E2E_TODAY')` — when non-empty (e.g.
  `2026-07-24`), returns a fixed clock at that date's 09:00 local; otherwise
  `const Clock()`. This is the E2E clock hook from testing-strategy.md.
- `todayProvider` (`NotifierProvider<TodayNotifier, PlainDate>`) — today's
  local calendar date, seeded from `clockProvider` and republished by
  `TodayNotifier.refresh()`, which `CatchUpController` calls unconditionally
  at local midnight and on app resume. EVERY date-bucketed piece of UI reads
  this, never `clockProvider` directly; the domain layer keeps using the
  injected `Clock`. Never overridden in tests — it derives from
  `clockProvider` by construction, which is what keeps `--dart-define=E2E_TODAY`
  authoritative. Added 2026-08-08 (backlog A-2 / audit P1): `clockProvider`
  is a plain `Provider` that never re-emits, so before this an app left open
  overnight kept yesterday's section boundaries and yesterday's 'Done today'
  list indefinitely.
- Repository/service providers built from the above.
- `bootstrapProvider` — `FutureProvider` that runs
  `ensureLocalHousehold()` + `seedDefaults()` + `catchUpOverdue()` once at
  startup and exposes the household id.
- `pendingOccurrencesProvider`, `membersProvider`,
  `choreCategoriesProvider` — StreamProviders over repository watches.

### Semantic IDs (`lib/app/semantics.dart`)
```dart
/// Wraps [child] with a stable identifier for E2E selectors.
Widget semantic(String id, {required Widget child});
// implemented as Semantics(identifier: id, container: true, child: ...)
```
Convention `<screen>.<element>[.<qualifier>]`, kebab-free, dot-separated.
EVERY interactive widget gets one. IDs used in this spec are normative:

- Shell: `shell.tab.chores`, `shell.tab.shopping`, `shell.tab.settings`
- Chores list: `chores.add`, `chores.filter.member`, `chores.filter.category`,
  `chores.occurrence.<choreId>` (tile), `chores.occurrence.<choreId>.complete`,
  `chores.occurrence.<choreId>.menu` (opens skip/edit/pause/delete sheet),
  `chores.menu.skip`, `chores.menu.edit`, `chores.menu.pause`,
  `chores.menu.delete`, `chores.delete.confirm`, `chores.delete.cancel`
- Chore form: `chore_form.title`, `chore_form.notes`, `chore_form.category`,
  `chore_form.category.<categoryId>`, `chore_form.repeat.toggle`,
  `chore_form.repeat.interval`, `chore_form.repeat.unit.<day|week|month>`,
  `chore_form.repeat.anchor.<schedule|completion>`,
  `chore_form.repeat.weekday.<1..7>`,
  `chore_form.repeat.monthly_mode.<day_of_month|nth_weekday>`,
  `chore_form.start_date`, `chore_form.assignment.<fixed|rotation|anyone>`,
  `chore_form.assignee.<memberId>`, `chore_form.assignee.<memberId>.drag`
  (rotation reorder drag handle), `chore_form.assignee.<memberId>.remove`
  (rotation reorder remove button), `chore_form.save`

### Theme (`lib/app/theme.dart`)
Material 3, `ColorScheme.fromSeed(seedColor: Color(0xFF26A69A))`, light +
dark themes (`themeMode: ThemeMode.system`). Category icons render via
`Icons`-by-name lookup: a `categoryIcon(String identifier)` function mapping
the Material Symbols identifiers used in seeds (cleaning_services, skillet,
local_laundry_service, yard, pets, build, directions_car, nutrition, egg,
set_meal, bakery_dining, ac_unit, local_cafe, home, shopping_bag) to
`IconData` constants, falling back to `Icons.label_outlined` for unknown
ids. Icons are always drawn in the category's color at regular weight — the
"flat, not colorful-emoji" decision.

### main.dart
`ProviderScope` → `ChoreApp`. While `bootstrapProvider` loads: blank
scaffold with a centered `CircularProgressIndicator`; on error: a centered
plain-language headline, the raw exception as a de-emphasized detail line
`semantic('app.bootstrap_error')`, and two actions —
`semantic('app.bootstrap_error.retry')`, which re-invalidates whichever of
`householdGateProvider`/`bootstrapProvider` failed, and
`semantic('app.bootstrap_error.reset')`, which runs the same
`confirmAndResetAppData` double-confirm flow as the Settings row. The
escape hatch is mandatory, not decorative (spec
`docs/feedback/2026-08-08-prerelease-audit.md` S2): Settings is
unreachable from this screen, so without it a database-open failure bricks
the app until it is uninstalled. The raw exception stays visible on
purpose — this app has no crash reporting, so a screenshot of that line is
the whole bug report.

## Chores feature

### List screen (default tab)
- Sections in order, each only when non-empty, with plain header text:
  **Overdue** (due < today), **Today**, **Tomorrow**, **This week**
  (until Sunday incl.), **Later**. Sorting inside a section follows the
  repository order. "today" is `todayProvider`, so the boundaries move at
  local midnight even if the app is never touched.
- Occurrence tile: leading circular "complete" button (outlined circle;
  `.complete`), title, subtitle line with category chip (icon+name in
  category color) when categorized + assignee name when assigned; overdue
  tiles show the due date in error color.
- Tapping `.complete` calls `completeOccurrence(completedBy: acting
  member)` — ALWAYS the acting member (`actingMemberProvider`, switchable
  via the app-bar avatar since members-management.md §4), never the
  assignee: credit records who actually did the work (user decision
  2026-07-31). The assignee is only a defensive fallback for the moment
  before the provider resolves. Rotation is unaffected — it advances on
  `assigned_member_id`, not `completed_by`.
- Tile long-press or `.menu` button → bottom sheet: Skip, Edit, Pause,
  Delete (destructive style). Delete asks confirmation dialog
  (`chores.delete.confirm` / `.cancel`).
- Pause/unpause reflects immediately (paused chores vanish from list —
  they have no pending occurrence).
- Empty state (no pending occurrences at all): centered friendly message +
  `semantic('chores.empty')` + the add FAB remains.
- FAB `chores.add` → form screen.

### Form screen (create + edit)
- Title field: required, trimmed; inline error text 'Title is required'
  below the field when submitted empty; `chore_form.save` stays enabled
  (validation happens on save; recovery must work — E2E tests this).
- Notes: optional multiline.
- Category: horizontal chip row of active chore categories (+ 'None').
- Repeat toggle OFF = one-off. ON reveals:
  - interval stepper/text (int ≥ 1; invalid input → inline error 'Must be
    at least 1'),
  - unit segmented control (day/week/month) — chip labels pluralize with
    the current interval ('Day'/'Days' etc., field feedback G3 stage 1:
    it's the only place a unit noun renders next to the interval number,
    so it doubles as the "2 months" composed reading the feedback asked
    for),
  - anchor choice with the user-facing labels 'On fixed days' / 'After
    last completion' (subtitle hints: 'e.g. every Tuesday' / a concrete,
    interval-aware sentence e.g. '3 days after last done' — field
    feedback G3 stage 1),
  - week unit: weekday chips Mon..Sun (multi-select; empty allowed =
    derive from start date),
  - month unit + schedule anchor: monthly mode toggle (day-of-month vs
    nth-weekday, computed from the picked start date, e.g. 'On the 15th' /
    'On the 3rd Tuesday'),
  - whenever the pattern silently derives from the start date (monthly
    mode always; weekly with no weekday picked) a one-line caption below
    it says so ('Follows the start date — change the start date to change
    the day.', field feedback G3 stage 1) — it disappears once a weekday
    is explicitly picked, since the pattern is then fully visible in the
    chips.
- Start date: date picker, defaults to today, min today - 1 year.
- Assignment: segmented fixed/rotation/anyone; fixed → single-select member
  chips, each showing the member's `MemberAvatar` before their name (field
  feedback F3). rotation (backlog B-4 / triage T2.5,
  `docs/plans/2026-08-08-rotation-reorder.md`) → already-selected members
  render as a compact reorderable list (drag handle, avatar, visible order
  label "1. Anna" etc., remove button), directly editable by dragging a
  row or tapping its remove button — not only rebuildable by deselecting
  and reselecting; not-yet-selected members stay a tap-to-add chip row
  below, appending to the end of the order, same as fixed mode's picker.
  Reordering is a widget-tested interaction only (not E2E: Maestro can't
  drive `ReorderableListView` reliably, same limitation already accepted
  for `manage_categories_screen.dart`). Validation errors inline: fixed
  needs exactly one ('Pick one member'), rotation at least two ('Pick at
  least two').
- Save: create via `ChoreService.createChore` (or update via
  `updateChore`; editing recurrence/startDate does NOT regenerate the
  pending occurrence in v1 — document this known simplification in a
  doc comment). Pop back on success.
- Edit prefills everything from `getChore`.

### State handling
Streams → `AsyncValue` with loading (skeleton-free plain
`CircularProgressIndicator`), error (centered text with retry button
`semantic('chores.error.retry')`), data. No animations beyond defaults
(testing-strategy determinism).

## Widget test matrix (minimum)

1. Shell: three tabs render; switching tabs swaps content and preserves
   state per tab (keep-alive `PageView` — see "App shell navigation" below).
2. Bootstrap: loading → list; bootstrap error → error state.
3. List grouping: fabricated occurrences land in the right sections
   (overdue/today/tomorrow/this-week/later boundaries — use a fixed
   clockProvider override; boundary cases: today, +1, Sunday, Monday).
4. Complete: tapping the circle closes the occurrence and (for a recurring
   chore) the tile re-renders with the next due date.
5. Menu actions: skip creates the next occurrence; pause removes the tile;
   delete asks confirmation, cancel keeps, confirm removes.
6. Empty state appears when nothing is pending.
7. Form validation: empty title error + recovery; rotation with one member
   error + recovery; interval 0 error + recovery.
8. Form recurrence controls: weekday chips only for week unit; monthly
   mode only for month+schedule; anchor selection persists to the saved
   Recurrence (assert via repository read).
9. Edit round-trip: open prefilled, change title, save, list shows it.
10. Both themes render the list screen without exceptions (smoke,
    `ThemeMode.dark`).
11. Text scale 2.0 renders the list + form without overflow exceptions.

## App shell navigation (added 2026-08-08 — backlog D-1 / D-4 / D-6)

Binding for `lib/app/app_shell.dart`.

1. **Content is a `PageView`**, one page per tab in `_AppTab.values` order,
   each page kept alive (`AutomaticKeepAliveClientMixin`) so leaving a tab
   preserves its scroll position and in-flight state. Horizontal swipe moves
   one tab at a time; there is no wrap-around.
2. **`allowImplicitScrolling` must stay `false`.** Setting it true lays the
   neighbouring page out inside the viewport's semantics clip, leaking that
   tab's `Semantics(identifier: ...)` nodes into `find.bySemanticsIdentifier`
   and Maestro's `assertVisible` while another tab is on screen. Regression
   test: `test/app/shell_navigation_test.dart`.
3. **A tab TAP switches instantly (`jumpToPage`); only a user's drag
   animates.** Material 3 does not slide between bottom-navigation
   destinations, and an instant tap keeps every E2E flow deterministic
   (`docs/specs/testing-strategy.md` §2.4). Never change this to
   `animateToPage` without re-timing the suite.
4. **Re-tapping the active tab scrolls that tab's list to the top**
   (conventions audit C6). The shell owns one `ScrollController` per tab and
   publishes it through `PrimaryScrollController`; the tab screens' scroll
   views stay uncontrolled and inherit it. A screen that ever needs its own
   `controller:` must instead accept one, or D-4 silently stops working for
   that tab.
5. **Re-tapping the active tab does NOT clear its snackbar.** Clearing is
   tied to *leaving* a tab (field feedback B1) and lives in `onPageChanged`,
   which a re-tap never reaches.
6. **System back on a non-first tab returns to the Chores tab**; on the
   Chores tab it is not intercepted and the app exits (Material's
   start-destination rule). No "press back again" confirmation.
7. **The hand-rolled `_BottomTabBar` and every `shell.tab.*` id are
   unchanged** by all of the above (`docs/specs/theme-v2.md` §4.5).

All tests use in-memory AppDatabase + fixed clock via provider overrides —
no mocks of repositories/services (integration-style, same as data layer).

Done criteria: format clean, analyze --fatal-infos --fatal-warnings clean,
all tests green. New dependency allowed: flutter_riverpod ONLY.
