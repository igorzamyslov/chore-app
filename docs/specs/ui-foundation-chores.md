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
  `chore_form.repeat.interval`, `chore_form.repeat.unit` (opens the unit
  menu), `chore_form.repeat.unit.<day|week|month>` (entries **inside** that
  menu — they do not exist until it is opened),
  `chore_form.repeat.anchor.<schedule|completion>`,
  `chore_form.repeat.weekday.<1..7>`,
  `chore_form.repeat.monthly_mode.<day_of_month|nth_weekday>`,
  `chore_form.repeat.monthly_day`, `chore_form.repeat.monthly_ordinal`,
  `chore_form.repeat.monthly_weekday`, `chore_form.repeat.preview`,
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
- Repeat toggle OFF = one-off. ON reveals the repeat block, which since
  **G-2** (`docs/plans/2026-08-18-repeat-form-sentence.md`, field feedback
  G3 stage 2) is one **fill-in-the-blank sentence** plus the pattern
  pickers that belong to the chosen unit, an anchor section, and a preview.

  **The organising rule: a control that does not apply DOES NOT EXIST.** It
  is never disabled, never greyed, never present-but-inert. This design has
  no disabled pattern, and the rule applies uniformly — to the weekday
  chips for a non-week unit, to the monthly holes for a non-month unit, to
  the whole monthly-mode row under a completion anchor, and to the
  after-last-completion anchor card in monthly weekday mode.

  - **The sentence** (`RepeatSentence`): one whole localized ARB message per
    shape, with widget-shaped holes punched into it by splitting on
    Unicode-noncharacter sentinels, laid out as a `Wrap` of one `Text` per
    literal word and a chip per hole. **Never a concatenation of
    fragments** — German inflects the frame by both the unit's gender and
    the interval's number, and a fixed widget order bakes English syntax
    into the tree. Every hole shares one chip container and is a ≥40px tap
    target. The four shapes are: day, week (trailing preposition, chips
    below), month + day-of-month, month + nth-weekday.
  - **The interval hole** stays a `TextField` (int ≥ 1; invalid input →
    inline error 'Must be at least 1' under the hole itself). A bounded
    picker would forbid legitimate rules like 'every 90 days'.
  - **The unit hole** is a menu, not a segmented control. The chip shows the
    current unit, pluralized live by the interval the user is typing
    ('Day'/'Days', field feedback G3 stage 1). The three
    `chore_form.repeat.unit.<x>` ids moved into that menu — see
    `theme-v2.md` §4.4 for the recorded §0 exception.
  - **week unit:** weekday chips Mon..Sun, multi-select, **at least one
    always selected**. The form seeds the start date's own weekday on open
    (including for an already-persisted rule with an empty stored set) and
    refuses to deselect the last one. The model still permits an empty set,
    meaning 'derive from the start date' — the form simply no longer lets a
    user reach it, because that derivation is the hidden dependency G3
    stage 2 exists to remove.
  - **month unit + schedule anchor:** a monthly-mode row naming the MODE
    ('A day of the month' / 'A weekday'), and the concrete day / ordinal +
    weekday as holes in the sentence itself. Nothing is computed from the
    start date. The row is absent under a completion anchor, where
    `nextAfterCompletion` reads no monthly field.
  - **The anchor** sits below a 1px hairline under an uppercase 'Counting
    from' header, as explanatory radio cards naming the actual configured
    rule ('Every 2 weeks on Tuesday, Friday' / '3 days after last done'). In
    monthly weekday mode the after-last-completion card is **absent**, with
    one `bodySmall` line saying why — an nth-weekday pattern is a position
    in the calendar, so there is nothing for a completion date to count
    from, and `Recurrence.validated` throws on the pair.
  - **The preview** (`chore_form.repeat.preview`) is always visible, for
    every unit and both anchors. For a schedule anchor it names the next
    **three real dates**, because 'every 2 weeks on Tuesday and Friday' is
    ambiguous in prose and unambiguous in dates, and because it lets the
    month-length clamp show itself rather than being explained. For a
    completion anchor there are no real dates to name, so it is prose.
  - **One formatter, two surfaces.** `recurrenceSentence` /
    `recurrencePreview` in `lib/features/chores/recurrence_sentence.dart`
    is the only thing in the app that turns a recurrence into prose. It
    serves the form and the paused rows. The design that motivated G-2
    assumed 'one formatter serves three places' because the paused rows and
    the chore tiles supposedly already rendered such a string; they did not
    — there were **zero** such places, and neither file even imported
    `recurrence.dart`. **Two** is the right number, not three: the pending
    tiles are excluded deliberately, because a tile answers 'when is this
    due', already carries a due chip, and recurrence prose there would
    spend density on the most-opened screen for something the user did not
    come there for. Do not 'complete' the third place later. A second
    switch over `RecurrenceUnit` producing user-facing prose anywhere in
    `lib/` is a regression.
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
   mode only for month+schedule; the after-last-completion anchor absent in
   monthly weekday mode; anchor selection, an explicitly picked monthly day,
   and an explicitly picked ordinal + weekday all persist to the saved
   Recurrence (assert via repository read). The preview names the next three
   real dates, and picking a monthly day moves the start date onto that day
   (the cross-version alignment invariant, `recurrence-engine.md` §2).
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
