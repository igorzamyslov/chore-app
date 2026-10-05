# Last-tab restore

**Status:** binding. Implemented in schemaVersion 14 (tab) and 17 (chores filters, §5).

## 1. Behavior

The app reopens on the top-level tab the user was last on. If the last tab
was Shopping, the next cold start opens on Shopping; same for Chores and
Settings.

- **What is remembered:** the shell tab (`chores` / `shopping` /
  `settings`) and, since schemaVersion 17, the Chores list's member and
  category filters (§5). Pushed routes (chore form, manage members, …),
  sheets and scroll positions are not restored.
- **When it is recorded:** every time the visible tab changes, by any path —
  tab tap, finger swipe, or Android back returning to Chores. Re-tapping the
  active tab (scroll-to-top) changes nothing and writes nothing.
- **Default:** Chores — on a fresh install, after "Reset app data", and when
  the stored value is missing or unrecognized (a tab renamed or removed in a
  later build must degrade to Chores, never throw).
- **No flash:** the shell's first frame already shows the restored tab. It
  never paints Chores and then jumps.
- **Back behavior is unchanged** (`docs/plans/2026-08-08-shell-navigation.md`
  D-6): Chores stays the start destination. Back on Shopping/Settings goes to
  Chores; back on Chores leaves the app. Opening on Shopping therefore means
  one back press goes to Chores, the next exits.
- No user-visible strings, no setting to turn it off.

## 2. Storage

A new device-scoped, **never-synced**, single-row table `ui_state`:

| column     | type | notes                                         |
|------------|------|-----------------------------------------------|
| `id`       | text | PK, constant `'device'`                       |
| `last_tab` | text | nullable; an `_AppTab.name`, `NULL` = default |

**Why not a `settings` column:** `DigestRescheduleController` listens to
`settingsProvider` and recomputes every scheduled notification on any
emission, and a dozen widgets rebuild off it. A write on every tab switch
must not reschedule notifications. `ui_state` has no stream consumers at all
— it is written blind and read once at startup.

**Why not `shared_preferences`:** no new dependency for one value; the drift
DB is already the device store, and widget tests get it for free through the
real in-memory `AppDatabase`.

Migration v13 → v14: `createTable(uiState)`, flat and unconditional (the
table is new, so no shipped install can already carry it — same reasoning as
`reminder_snoozes` in v13). No data rewrite.

- **Reset app data** (`lib/application/data_reset.dart`) deletes the
  `ui_state` row too.
- **Data export** does not include `ui_state` — it is UI state, not household
  data.

## 3. Startup

`lastTabProvider` (a `FutureProvider<String?>`) reads the stored value once.
`_Bootstrapped` (`lib/app/app.dart`) keeps showing the loading scaffold until
both `bootstrapProvider` and `lastTabProvider` have data, then builds
`AppShell`, which takes the initial tab from `lastTabProvider` in
`initState` (`_selected` and `PageController(initialPage:)`). A failed read
falls back to Chores rather than showing the error scaffold — losing the
remembered tab is never worth blocking startup over.

## 4. Testing

- Repository: round-trip, `NULL` before first write, overwrite.
- Migration: v13 → v14 creates `ui_state`; existing schema-migration tests
  stay green.
- Widget (`test/app/`): a DB pre-seeded with `last_tab = 'shopping'` opens on
  the Shopping tab on the first frame; an unknown value opens on Chores;
  switching tabs persists the new tab name; re-tapping the active tab does
  not.
- Reset: the `ui_state` row is gone after `resetAllData`.
- E2E (`e2e/flows/shell/last_tab_restore.yaml`): open Shopping, `stopApp`,
  bare `launchApp`, assert the Shopping screen is showing.

## 5. Chores filters (schemaVersion 17)

Field feedback 2026-10-05: "similar to preserve same screen on app re-open,
preserve the filters that were chosen". The only filters in the app are the
Chores list's member and category filter buttons
(`lib/features/chores/chores_filter_bar.dart`).

### 5.1 Behavior

- The chosen member filter and category filter survive a cold start. Each is
  independent; "All" is stored as `NULL`.
- **Recorded** on every change: picking an entry in either menu, and the
  filtered-empty state's "Show everything" (clears both). Written blind,
  like the tab.
- **Stale ids degrade to "All"**: a stored member id that is not in the
  current `membersProvider` list (member deleted, household left/joined,
  data reset of another kind), or a category id not in
  `choreCategoriesProvider`, is treated as `null` — the list is unfiltered
  and the button shows inactive. This is a READ-TIME rule in
  `ChoresListScreen.build` (nothing is written back). While the
  members/categories provider has no value yet the stored id is kept as-is,
  so there is no unfiltered flash before they load.
- **No flash**: the first frame of the Chores list is already filtered —
  the value is loaded by the same once-at-startup read `_Bootstrapped`
  already waits for.
- No user-visible strings, no setting.

### 5.2 Storage

Two nullable text columns on `ui_state`: `chores_member_filter`,
`chores_category_filter`.

Migration v16 → v17: `addColumn` for both — **guarded `from >= 14`**,
because a `from < 14` upgrade creates `ui_state` at full current width via
`createTable` and a second `addColumn` would throw duplicate-column (the
same reason the `settings` columns live in their `else` branch).

### 5.3 Startup / API

- `UiStateRepository.readUiState()` returns the whole row (`UiStateRow?`);
  `readLastTab()` is replaced by it. `setLastTab` stays (it must not touch
  the filter columns) and `setChoresFilters({memberId, categoryId})` writes
  BOTH filter columns (not the tab) — an upsert that only sets the columns
  it owns.
- `lastTabProvider` becomes `uiStateProvider`
  (`FutureProvider.autoDispose<UiStateRow?>`), still read once; `_Bootstrapped`
  waits on it exactly as before; `AppShell` reads `.lastTab` from it;
  `ChoresListScreen.initState` seeds `_memberFilter`/`_categoryFilter` from
  it (a load error → no filters, same "never block startup" rule as §3).

### 5.4 Testing

- Repository: filters round-trip; `setChoresFilters` leaves `last_tab`
  alone and `setLastTab` leaves the filters alone; nulls clear.
- Migration: 16 → 17 adds both columns, keeps an existing `last_tab`; the
  existing pre-17 tests keep passing.
- Widget: DB pre-seeded with a member + category filter opens filtered on
  the first frame; a stale id opens unfiltered; picking a filter persists it;
  "Show everything" persists nulls.
- Reset: covered by the existing `ui_state` delete.
