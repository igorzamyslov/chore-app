# Category icons — nine new identifiers (G-5a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the category icon picker from 15 to 24 identifiers by adding
the nine Material Symbols the design canvas picked (`famdo_design.txt` §1d):
`bathtub` (bathroom), `delete` (bins), `potted_plant` (plants indoors),
`child_care` (baby), `pedal_bike` (bike), `description` (admin),
`celebration` (hosting), `thermostat` (heating), `fitness_center` (sport).
**This is the icons half of backlog G-5 only** (G-5a). The colour half is a
separate plan (a palette replacement with a data migration, not an
extension) — this plan does not touch `seedColors`, `ColorSwatchPicker`, or
any color code.

**Architecture:** Pure additive UI-data change, two files.
`categoryIconIdentifiers` (`lib/features/categories/category_icons.dart`) is
a hand-maintained `const List<String>` the icon picker (`_IconGrid` in
`lib/features/settings/category_edit_sheet.dart`) iterates to build its
`Wrap` of tiles; `categoryIcon` (`lib/app/theme.dart`) is the `switch` that
maps each identifier string to an `IconData`, falling back to
`Icons.label_outlined` for anything not in its case list. The two are
independent structures kept in sync only by a doc comment today — the whole
point of this ticket's Task 1 is to also pin that sync with a test. No
picker/grid layout code changes (see Design note 3 below for why).

**Tech Stack:** Flutter/Dart, plain `const` data + a `switch` — no Riverpod,
no drift, no l10n involved (icon identifiers are not user-visible strings).

## Global Constraints

- Never run `flutter`/`dart` commands yourself while *planning* — this
  plan's steps tell the *executor* which commands to run; that constraint
  does not apply to them.
- Widget tests are integration-style: real in-memory `AppDatabase` + fixed
  clock, via `testChoreApp` (`test/test_utils/pump_app.dart`). Never mock
  repositories.
- Tests run as
  `flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= <file>`
  — omitting the defines fails six unrelated tests that then misread as
  regressions from this change.
- Strict lints (very_good_analysis, `--fatal-infos --fatal-warnings`);
  public members need doc comments.
- Every interactive widget already has a stable id via `semantic()`
  (`lib/app/semantics.dart`) — the picker tiles' ids
  (`settings.categories.icon.<identifier>`) are generated from
  `categoryIconIdentifiers` automatically, so adding an entry to the list is
  enough; no new `semantic()` call sites are needed.

---

## Design notes (read before starting)

**1. No data migration, verified against the schema, not assumed.**
`Categories.icon` (`lib/data/db/tables.dart:184`) is
`TextColumn get icon => text()();` — a plain, unconstrained TEXT column, no
CHECK constraint, no enum, no FK. Nothing in the codebase indexes into
`categoryIconIdentifiers` by position or reads its `.length` (checked with
`grep -rn "categoryIconIdentifiers\.length\|categoryIconIdentifiers\["` —
zero hits), and no seeded category (`CategoryRepository._choreSeeds`/
`_shoppingSeeds`, `lib/data/repositories/category_repository.dart:38-53`)
references any of the nine new identifiers. `categoryIcon`'s own `default`
branch (`Icons.label_outlined`) already exists to handle an identifier the
switch doesn't recognize — that's precisely how *unknown-to-this-version*
identifiers degrade today (an older build opening a newer export, for
example), so adding recognized cases only ever *narrows* which stored
strings hit that fallback. **Schema stays at v12; no migration task in this
plan.**

**2. The invariant test — how it actually catches the fallthrough bug.**
The ticket's warning is concrete: an identifier present in
`categoryIconIdentifiers` but absent from `categoryIcon`'s switch silently
renders `Icons.label_outlined` — indistinguishable, by eye, from a
legitimate icon, and worse, *every* such identifier renders the *same*
icon, so the picker would visually offer duplicate tiles. Task 1's test
detects this directly, two ways, on every identifier in the real (not
hand-copied) list:
  - `expect(categoryIcon(identifier), isNot(Icons.label_outlined), ...)` —
    catches a missing case outright, since `Icons.label_outlined` is not
    used as a legitimate mapping by any existing or new identifier (checked
    against both the current 15 cases and the 9 being added here).
  - A `Set<IconData>` accumulated across the loop, asserting
    `seen.add(icon)` is `true` for every identifier — catches two
    identifiers accidentally mapped to the *same* icon (whether or not
    either is the default), which is the "offering duplicate icons"
    symptom by name, not just its most common cause.
  Both assertions run against the actual exported `categoryIconIdentifiers`
  const, so the test breaks the moment the two files drift, not just at
  the moment this plan's own edits land.

**3. "Six across" needs no code change — and forcing it would introduce a
real overflow regression. Investigated, not assumed.**
The design canvas note says both grids "stay six across" so the sheet
height stays within thumb's reach. `_IconGrid` renders via a plain `Wrap`
of 48×48 `PickerTile`s with 8dp spacing (`color_swatch_picker.dart:45` for
the tile size, `category_edit_sheet.dart:239-241` for the spacing) — a
`Wrap`'s per-row tile count is a function of *available width* only, not
of how many total items it holds, so growing the list from 15 to 24 icons
does not change how many fit per row; whatever was true before this plan is
still true after.
  - Per-row math: `n` tiles cost `n·48 + (n−1)·8` logical px. 6 tiles = 328px,
    7 tiles = 384px.
  - On the "Definition of visual done" reference devices
    (`docs/specs/design-language.md`), content width is device width minus
    the sheet's 32px horizontal padding: SE-class (375pt) → 343px content,
    Pixel-class (~412dp) → 380px content. Both comfortably fit 6 (328 ≤ 343,
    328 ≤ 380) and both fall short of 7 (384 > 343, 384 > 380) — so six
    -across already holds on both named reference devices, unchanged by
    this plan, with no code needed.
  - The only real devices where a 7th tile *would* fit are the largest
    current phones (~428-430pt logical width, e.g. Pro-Max-class iPhones,
    398px content ≥ 384px). That is a minor deviation from the mock on the
    largest screens only, and it *shortens* the sheet, which is the
    underlying goal ("stays within thumb's reach") — not a regression
    against it.
  - **Explicitly rejected: constraining the `Wrap` to a fixed 328px width
    to force exactly six.** This codebase already regression-tests a
    320pt-wide viewport for sheet overflow
    (`test/features/settings/exit_confirm_sheet_test.dart:89-94`,
    `tester.view.physicalSize = const Size(320, 640)`). At 320pt, content
    width is 320 − 32 = 288px — **less than the 328px six tiles need.** A
    hard-coded 328px `SizedBox` around the icon `Wrap` would overflow
    exactly the width this project already treats as a real target,
    trading a cosmetic mock-fidelity gain on the largest phones for a
    genuine `RenderFlex` overflow on the smallest. The existing
    unconstrained `Wrap` has no such failure mode — it always reflows to
    whatever fits, never overflows. **No layout code changes in this
    plan.**
  - Also worth recording: `testChoreApp`'s default test surface is
    800×2400 logical px (`test/test_utils/pump_app.dart:135`) — far wider
    than any phone, where roughly 13 tiles fit per row. That means
    six-across is not something a standard widget test can observe without
    first pinning `tester.view.physicalSize` to a realistic width (as
    `exit_confirm_sheet_test.dart` already does for its own concern). Given
    the finding above — that six-across already holds on real target
    devices with zero code change, and that pinning it further is where
    the actual risk lives — this plan leaves visual verification to the
    existing "Definition of visual done" screenshot review
    (`docs/specs/design-language.md`, last section) rather than adding a
    brittle physicalSize-pinned layout test for a property that isn't
    changing.

**4. `potted_plant` has no bundled-Flutter equivalent — same situation as
two existing identifiers, resolved the same way.** Checked directly against
the SDK's icon font (`packages/flutter/lib/src/material/icons.dart`, stable
channel): `bathtub`, `delete`, `child_care`, `pedal_bike`, `description`,
`celebration`, `thermostat`, `fitness_center` all exist as `IconData`
constants verbatim. `potted_plant` does not — it's Material *Symbols* only,
same gap `categoryIcon`'s doc comment already documents for `skillet` and
`nutrition` ("closest visual equivalent instead"). `yard` (outdoor
garden/lawn) is already taken by the existing Garden category, so this
plan maps `potted_plant` to `Icons.local_florist` (a flower-in-bloom glyph)
— visually closer to "a plant" than the tree-shaped `Icons.nature` or the
lawn-shaped `Icons.grass`/`Icons.yard`, and not already used by any other
identifier. The doc comment on `categoryIcon` is updated from "two seed
identifiers" to "three," naming the new substitution alongside the
existing two.

**5. Filled, not outlined — following existing precedent, not fixing it.**
`docs/specs/design-language.md` says "Material Symbols outlined style
throughout (`Icons.*_outlined` where a variant exists)," but all 15
existing `categoryIcon` cases already use the filled constant (e.g.
`Icons.cleaning_services`, not `Icons.cleaning_services_outlined`) despite
an outlined variant existing for every one of them (checked directly
against the SDK). `categoryIcon`'s own doc comment states this is
deliberate: "Icons are always looked up at regular weight." All nine new
identifiers also have outlined variants available, but this plan follows
the established (if spec-inconsistent) filled convention for consistency
with the other 15 — retrofitting the outlined/filled question across all
24 icons is a separate, unrelated change, out of scope for "add nine
icons," and not requested by this ticket.

**6. `delete` as an identifier name is a household-bins category icon, not
a UI delete action — worth a doc note so a future reader isn't confused.**
Material's `delete` glyph is a trash can, which is exactly the visual the
"bins" category wants; it happens to share its name with the app's actual
delete actions elsewhere, but `IconData` values are freely reused across
unrelated contexts in Flutter and this causes no collision. Documented
inline at the new switch case.

## Open product decisions

**None.** The nine icons, their meanings, and their append order are fixed
by the design canvas (`famdo_design.txt` §1d) and the ticket; this plan
does not reopen them. The one identifier needing a substitute
(`potted_plant`, Design note 4) follows the codebase's own existing,
documented pattern for exactly this situation — not a new decision.

---

## File map

- Modify: `lib/features/categories/category_icons.dart` — append 9
  identifiers to `categoryIconIdentifiers`.
- Modify: `lib/app/theme.dart` — append 9 cases to `categoryIcon`'s switch;
  update its doc comment's substitution count/list.
- Modify: `test/app/theme_test.dart` — new test group pinning the
  `categoryIcon`/`categoryIconIdentifiers` sync invariant.
- Modify: `test/features/settings/category_edit_test.dart` — new test:
  full 24-icon grid renders, a new icon is selectable and persists.
- Modify: `docs/specs/ui-foundation-chores.md` — the spelled-out identifier
  list in the Theme section (currently lines 73-77).
- Modify: `docs/backlog.md` — G-5 row records the icons half as done and
  points at this plan; the colour half stays explicitly open.

---

### Task 1: Add the 9 icons + the sync-invariant test (this is the task that makes the change LIVE)

**Files:**
- Modify: `lib/features/categories/category_icons.dart`
- Modify: `lib/app/theme.dart`
- Modify: `test/app/theme_test.dart`

**Interfaces:**
- Consumes: `categoryIcon` (`lib/app/theme.dart:439`),
  `categoryIconIdentifiers` (`lib/features/categories/category_icons.dart:12`)
  — both already public, no signature change.
- Produces: nothing new consumed by later tasks; Task 2's widget test reads
  the same two symbols, unchanged in shape.

This task's steps are written as a genuine red-then-green sequence, but
**steps 1-3 are verification-only and must not be committed on their own**
— committing the list update without the switch cases would ship exactly
the broken, duplicate-icon picker state the ticket warns about. Only the
combined end state (test + identifiers + switch cases together) gets
committed, in Step 6.

- [ ] **Step 1: Add the invariant test against the CURRENT (15-entry) list**

In `test/app/theme_test.dart`, add the import:

```dart
import 'package:chore_app/features/categories/category_icons.dart';
```

Add a new top-level group, after the existing `categoryTone` group (i.e.
just before the file's closing `}` around line 227):

```dart
  group('categoryIcon <-> categoryIconIdentifiers invariant', () {
    test(
      'every picker identifier maps to its own distinct, non-default icon '
      '(backlog G-5a: an identifier missing its switch case silently '
      'falls through to Icons.label_outlined -- a working-looking picker '
      'that quietly offers duplicate icons)',
      () {
        final seen = <IconData>{};
        for (final identifier in categoryIconIdentifiers) {
          final icon = categoryIcon(identifier);
          expect(
            icon,
            isNot(Icons.label_outlined),
            reason:
                '"$identifier" falls through to categoryIcon\'s default '
                'branch -- it is missing a dedicated switch case',
          );
          expect(
            seen.add(icon),
            isTrue,
            reason:
                '"$identifier" maps to the same IconData ($icon) as an '
                'earlier identifier in the list -- two picker tiles would '
                'render identically',
          );
        }
      },
    );
  });
```

- [ ] **Step 2: Run it against the current code (characterization, not RED)**

Run:
`flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/app/theme_test.dart`
Expected: PASS, including the new test — this proves the checker is
correct against the current 15-entry list before it's asked to catch
anything, exactly like the reference precedent in
`docs/plans/2026-08-08-rotation-reorder.md` Task 1.

- [ ] **Step 3: Append the 9 identifiers ONLY, then confirm RED**

In `lib/features/categories/category_icons.dart`, append inside the list
literal, immediately after `'shopping_bag',`:

```dart
  'bathtub',
  'delete',
  'potted_plant',
  'child_care',
  'pedal_bike',
  'description',
  'celebration',
  'thermostat',
  'fitness_center',
```

Run:
`flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/app/theme_test.dart`
Expected: **FAIL** — the new test's first assertion
(`isNot(Icons.label_outlined)`) fails on `'bathtub'` (the first new
identifier with no switch case yet), reporting exactly the fallthrough
this task exists to prevent. Do not proceed to Step 4 without seeing this
failure; if it passes instead, the test in Step 1 is not actually checking
what it claims to.

- [ ] **Step 4: Add the 9 switch cases and update the doc comment**

In `lib/app/theme.dart`, replace the `default:` line and everything above
it back to the `case 'shopping_bag':` line (currently lines 469-471) is
unaffected — insert the 9 new cases immediately before the existing
`default:` branch:

```dart
    case 'shopping_bag':
      return Icons.shopping_bag;
    case 'bathtub':
      return Icons.bathtub;
    case 'delete':
      // The "bins" category's trash-can glyph -- shares its identifier
      // name with the app's actual delete actions elsewhere, which is a
      // naming coincidence in Material's icon set, not a collision:
      // IconData values carry no behavior, only a glyph.
      return Icons.delete;
    case 'potted_plant':
      // No bundled-Flutter equivalent (Material Symbols only, same gap as
      // skillet/nutrition below) -- local_florist is the closest visual
      // match not already taken by 'yard' (outdoor garden).
      return Icons.local_florist;
    case 'child_care':
      return Icons.child_care;
    case 'pedal_bike':
      return Icons.pedal_bike;
    case 'description':
      return Icons.description;
    case 'celebration':
      return Icons.celebration;
    case 'thermostat':
      return Icons.thermostat;
    case 'fitness_center':
      return Icons.fitness_center;
    default:
      return Icons.label_outlined;
```

Then update the function's doc comment (currently lines 435-438):

```dart
/// Two seed identifiers (`skillet`, `nutrition`) have no equivalent in
/// Flutter's bundled Material Icons font (they only exist as Material
/// Symbols, a separate icon set this app doesn't depend on); those map to
/// the closest visual equivalent instead ([Icons.kitchen], [Icons.eco]).
```

becomes:

```dart
/// Three seed identifiers (`skillet`, `nutrition`, `potted_plant`) have no
/// equivalent in Flutter's bundled Material Icons font (they only exist as
/// Material Symbols, a separate icon set this app doesn't depend on);
/// those map to the closest visual equivalent instead ([Icons.kitchen],
/// [Icons.eco], [Icons.local_florist]).
```

- [ ] **Step 5: Run the test to verify GREEN**

Run:
`flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/app/theme_test.dart`
Expected: PASS, all tests including the invariant one — all 24 identifiers
now map to 24 distinct, non-default icons.

- [ ] **Step 6: Format, analyze, commit as one change**

Run: `dart format lib/features/categories/category_icons.dart lib/app/theme.dart test/app/theme_test.dart`
Run: `flutter analyze --fatal-infos --fatal-warnings lib/features/categories/category_icons.dart lib/app/theme.dart test/app/theme_test.dart`
Expected: both clean.

```bash
git add lib/features/categories/category_icons.dart lib/app/theme.dart test/app/theme_test.dart
git commit -m "feat: add nine category icons (backlog G-5a)"
```

This is the commit that makes the nine new icons live: after it, the
picker offers 24 working, distinct icons.

---

### Task 2: Widget-level proof — the full grid renders and a new icon is selectable and persists

**Files:**
- Modify: `test/features/settings/category_edit_test.dart`

**Interfaces:**
- Consumes: `testChoreApp`, `openManageCategories`, `activeCategories`
  (`test/test_utils/pump_app.dart`,
  `test/features/settings/settings_test_utils.dart`) — the exact same
  helpers the file's two existing tests already use; `categoryIconIdentifiers`
  (Task 1) for the exhaustive render check.

Task 1 proves the pure-function mapping is complete; this task proves the
picker widget actually wires all 24 identifiers to tappable, semantic-id
-addressable tiles and that saving a new one round-trips through the real
database — the same shape of proof `category_edit_test.dart`'s existing
`'yard'`-selection assertion (line 57) already gives the 15 old icons.

- [ ] **Step 1: Add the import**

At the top of `test/features/settings/category_edit_test.dart`, add:

```dart
import 'package:chore_app/features/categories/category_icons.dart';
```

- [ ] **Step 2: Write the new test**

Append a third `testChoreApp(...)` block to the file, after the existing
`'add flow creates a category...'` test (after its closing `);` at line
134):

```dart
  testChoreApp(
    'the icon grid renders all 24 identifiers, and picking one of the new '
    'nine (backlog G-5a) persists',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await openManageCategories(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.categories.add'));
      await tester.pumpAndSettle();

      // Every identifier in the real list has a rendered, tappable tile --
      // if any were missing its semantic id, this loop catches it directly,
      // independent of Task 1's pure-function check.
      for (final identifier in categoryIconIdentifiers) {
        expect(
          find.bySemanticsIdentifier('settings.categories.icon.$identifier'),
          findsOneWidget,
          reason: 'missing icon tile for "$identifier"',
        );
      }

      final nameField = find.descendant(
        of: find.bySemanticsIdentifier('settings.categories.name'),
        matching: find.byType(TextField),
      );
      await tester.enterText(nameField, 'Bathroom');
      await tester.tap(
        find.bySemanticsIdentifier('settings.categories.icon.bathtub'),
      );
      await tester.tap(find.bySemanticsIdentifier('settings.categories.save'));
      await tester.pumpAndSettle();

      expect(find.text('Bathroom'), findsOneWidget);

      final categories = await activeCategories(
        database,
        await currentHouseholdId(database),
        CategoryKind.chore,
      );
      final created = categories.firstWhere((c) => c.name == 'Bathroom');
      expect(created.icon, 'bathtub');

      handle.dispose();
    },
  );
```

- [ ] **Step 3: Run it to verify it fails against pre-Task-1 code, then passes now**

Run:
`flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/settings/category_edit_test.dart`

Expected on today's tree (Task 1 already landed): PASS immediately — this
task is confirmatory, not red-then-green, since Task 1's commit already
made the picker complete. (If run against a tree *without* Task 1, the
first `expect` inside the `for` loop would fail at `identifier ==
'bathtub'` with `findsOneWidget` returning `findsNothing`, since the tile
wouldn't exist in `categoryIconIdentifiers` yet — that ordering is not
exercised here because Task 1 is already committed first.)

- [ ] **Step 4: Format, analyze, commit**

Run: `dart format test/features/settings/category_edit_test.dart`
Run: `flutter analyze --fatal-infos --fatal-warnings test/features/settings/category_edit_test.dart`
Expected: both clean.

```bash
git add test/features/settings/category_edit_test.dart
git commit -m "test: cover the full 24-icon grid and a new-icon save round-trip"
```

---

### Task 3: Update the spec's spelled-out identifier list

**Files:**
- Modify: `docs/specs/ui-foundation-chores.md`

- [ ] **Step 1: Update the Theme section**

The line currently reading (around lines 73-77):

```
`Icons`-by-name lookup: a `categoryIcon(String identifier)` function mapping
the Material Symbols identifiers used in seeds (cleaning_services, skillet,
local_laundry_service, yard, pets, build, directions_car, nutrition, egg,
set_meal, bakery_dining, ac_unit, local_cafe, home, shopping_bag) to
`IconData` constants, falling back to `Icons.label_outlined` for unknown
ids. Icons are always drawn in the category's color at regular weight — the
"flat, not colorful-emoji" decision.
```

Replace with:

```
`Icons`-by-name lookup: a `categoryIcon(String identifier)` function mapping
`categoryIconIdentifiers` (`lib/features/categories/category_icons.dart`) --
the seven chore-seed and eight shopping-seed identifiers (cleaning_services,
skillet, local_laundry_service, yard, pets, build, directions_car,
nutrition, egg, set_meal, bakery_dining, ac_unit, local_cafe, home,
shopping_bag) plus nine picker-only additions with no seeded category
(bathtub, delete, potted_plant, child_care, pedal_bike, description,
celebration, thermostat, fitness_center; backlog G-5a) -- to `IconData`
constants, falling back to `Icons.label_outlined` for unknown ids. Icons
are always drawn in the category's color at regular weight — the "flat,
not colorful-emoji" decision.
```

- [ ] **Step 2: Commit**

```bash
git add docs/specs/ui-foundation-chores.md
git commit -m "docs: record the nine G-5a icon identifiers in the theme spec"
```

---

### Task 4: Update the backlog row

**Files:**
- Modify: `docs/backlog.md`

- [ ] **Step 1: Update the G-5 row**

The row currently reading (line 309):

```
| **G-5** | More category icons and colours (F17) | User request, round 1. Icon set unchanged at 15 entries | S |
```

Replace with:

```
| **G-5** | More category icons and colours (F17) | **Icons half DONE** (`docs/plans/2026-08-18-category-icons.md`, G-5a): the picker grew from 15 to 24 identifiers, per the design canvas (`famdo_design.txt` §1d). **Colours half still open** — a palette replacement with a data migration, not a simple extension; tracked separately, not started | S |
```

- [ ] **Step 2: Commit**

```bash
git add docs/backlog.md
git commit -m "docs: record G-5a (category icons) done in the backlog"
```

---

### Task 5: Full verification pass

**Files:** none (verification only).

- [ ] **Step 1: Format the whole repo**

Run: `dart format .`
Expected: no files needing changes beyond what earlier tasks already
formatted (a clean diff).

- [ ] **Step 2: Analyze**

Run: `flutter analyze --fatal-infos --fatal-warnings`
Expected: `No issues found!`

- [ ] **Step 3: Full test suite**

Run:
`flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY=`
Expected: all tests PASS, including every file touched in Tasks 1 and 2.
Running the full suite (not just the two touched files) matters here
specifically because `categoryIcon`/`categoryIconIdentifiers` are consumed
from several other call sites (`manage_categories_screen.dart`,
`category_picker.dart`, `shopping_suggestions_list.dart`,
`shopping_category_header.dart`, `category_badge.dart`) that this plan
does not modify but that render whatever a category's stored `icon` string
resolves to — an additive change shouldn't affect them, and this step
confirms that rather than assuming it.

- [ ] **Step 4: Manual visual check (Definition of visual done)**

Per `docs/specs/design-language.md`'s "Definition of visual done": open the
category edit sheet on a simulator/emulator at iPhone SE-class and
Pixel-class widths, light + dark, text scale 1.0 and 2.0. Confirm: the icon
grid reads six-across at both reference widths (per Design note 3 — no
code change should be needed for this to already be true), the sheet
scrolls as a whole rather than clipping the now-4-row grid, and none of
the nine new icons render as the fallback label glyph.

- [ ] **Step 5: Commit if Step 1 changed anything**

```bash
git add -A
git commit -m "chore: format after category icons work"
```

(Skip this step entirely if `dart format .` in Step 1 made no changes.)
