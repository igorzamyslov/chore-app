# Last-tab restore

**Status:** binding. Implemented in schemaVersion 14.

## 1. Behavior

The app reopens on the top-level tab the user was last on. If the last tab
was Shopping, the next cold start opens on Shopping; same for Chores and
Settings.

- **What is remembered:** only the shell tab (`chores` / `shopping` /
  `settings`). Pushed routes (chore form, manage members, …), sheets, scroll
  positions and filter state are not restored.
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
