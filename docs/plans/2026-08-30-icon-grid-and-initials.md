# Icon grid width + initials fit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix backlog **G-15** (the category icon picker's six-tile row does
not span the sheet's width on a real Android phone) and **G-16** (two-letter
member-avatar initials touch the ring at the smallest avatar size), both
found by Igor on a real device on the first look at wave 6 — and both shipped
past tests that were structurally incapable of catching them (`docs/backlog.md`
rows G-14/G-15/G-16, `docs/handover-2026-08-29-wave-6.md` §5).

**Architecture:** G-15 is a pure layout defect: `_IconGrid`
(`lib/features/settings/category_edit_sheet.dart`) lays its tiles out with a
`Wrap`, which sizes a row to the sum of its children and never stretches to
fill the parent — so it is fixed by copying the `Row` + `Expanded`
six-equal-column pattern the sibling `ColorSwatchPicker`
(`lib/app/color_swatch_picker.dart`) already uses correctly. G-16 is a text
metrics defect that **`flutter test` cannot observe directly** (backlog
G-14: widget tests draw the Ahem-style `FlutterTest` font, ~1 em per glyph,
not the real Inter) — it is fixed by measuring the real, shipped
`assets/fonts/Inter-SemiBold.ttf` offline (a small Python script reading the
font's own binary tables, run once during planning, **not** part of the
implementation or its CI) and using those real numbers in a pure-Dart
(non-widget) arithmetic test that can genuinely fail.

**Tech Stack:** Flutter (Material 3), Riverpod, drift — unchanged. No new
dependencies. No schema change (still v12; the next migration is v13 and
belongs to another workstream — do not touch it).

## Global Constraints

- **Never run `flutter`, `dart`, `supabase`, or `docker` commands** outside
  the exact test invocations named in this plan. Tests run as:
  `flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= <file>`
  — omitting the defines fails six unrelated tests that will read as
  regressions.
- **Schema stays at v12.** No drift migration, no `schemaVersion` bump.
- **No `semantic(...)` id may be removed, renamed, or moved.** Every id this
  plan touches (`settings.categories.icon.*`, `members.edit.avatar`, the
  member-row/tile avatars) is unchanged by both fixes — confirmed per-task
  below. Adding ids is fine; this plan adds none.
- **`semantic()` signature:** `Widget semantic(String id, {required Widget child})`
  (`lib/app/semantics.dart`) — always a named `child:`.
- **Never hand-roll a `ProviderScope` pump.** Use `testChoreApp` /
  `testFreshChoreApp` from `test/test_utils/pump_app.dart`. `openSettingsTab`,
  `openManageCategories`, `openManageMembers`, `openChoreHistory` are in
  **`test/features/settings/settings_test_utils.dart`**, not `pump_app.dart`.
- **All user-visible strings via gen_l10n** (`lib/l10n/app_en.arb` +
  `app_de.arb`, informal du-form). Neither task in this plan adds or changes
  any user-visible string — both fixes are pure layout/geometry.
- **Lints are strict:** `very_good_analysis`, `flutter analyze --fatal-infos
  --fatal-warnings`. Every public member needs a doc comment
  (`public_member_api_docs`). `avoid_redundant_argument_values` is live and
  already load-bearing in this file family — `test/features/members/
  member_avatar_test.dart:221-222` records that `radius: 12` was left
  implicit for exactly this reason; Task 2 hits the same rule from the other
  direction (an explicit argument that becomes redundant once the default
  changes) and must remove it at every affected call site, not just avoid
  adding new ones.
- **Colour/contrast:** unaffected — neither fix touches colour.
- **Every test added must be shown capable of failing** — after it goes
  green, invert the implementation and confirm the SAME test fails at the
  `flutter test` step (not `analyze`, which only proves the file parses).
  Both tasks include this inversion explicitly.
- **Device-only:** neither fix's *visual* correctness (does the icon block
  really look flush on a physical screen; do the initials really look
  clear of the ring to a human eye) is provable by any test in this repo.
  Both tasks say plainly what their tests prove and what they don't, and
  what's left to `docs/specs/design-language.md`'s "Definition of visual
  done" gate.

---

## Diagnosis

### G-15 — why the icon grid doesn't fill the width, verified against the actual layout code

`_IconGrid.build()` (`lib/features/settings/category_edit_sheet.dart:236-274`)
renders `categoryIconIdentifiers` (24 entries) inside a bare `Wrap(spacing: 8,
runSpacing: 8, ...)`, each child a `PickerTile`, whose `build()`
(`lib/app/color_swatch_picker.dart:45-57`) is a hard-coded
`SizedBox(width: 48, height: 48, ...)`. A `Wrap`'s row width is **the sum of
its children's sizes**, full stop — it has no stretch behaviour and no way to
consume more of its parent's width than its children ask for. Six tiles cost
exactly `6×48 + 5×8 = 328` logical px, a constant, regardless of how wide the
sheet actually is.

The design canvas is unambiguous about what "six across" is supposed to mean:
`docs/design/2026-08-18-famdo-features.dc.html:330` (icons) and `:342`
(colours) both use `display:grid;grid-template-columns:repeat(6,1fr)` — six
**equal, flexible** columns that together span the row, not six fixed-size
boxes that happen to fit inside it. `ColorSwatchPicker`
(`lib/app/color_swatch_picker.dart:124-174`), the sibling picker **in the
same file** as `PickerTile`, already implements exactly that: it chunks its
palette into rows of six and wraps each cell in
`Expanded(child: Center(child: ...))` (`:136-163`), with an explicit comment
at `:138-143` explaining why (`Expanded` forces the column width, `Center`
keeps the swatch itself a fixed visual size inside it). `_IconGrid` is the one
picker in this family that never got that treatment — that gap is the entire
defect. Confirmed by reading both files side by side; `_IconGrid` and
`ColorSwatchPicker` were extracted into `color_swatch_picker.dart` together
(the file's own doc comment says so) but only one of the two kept the
stretch-to-width behaviour.

**This is not what the previous plan checked.** `docs/plans/2026-08-18-
category-icons.md:116-173` (the plan that grew the icon set from 15 to 24)
did the arithmetic correctly for a *different* question — "do six tiles fit
without a seventh sneaking onto the row" (`6×48+5×8=328` vs `7×48+6×8=384`,
compared against two reference devices' content widths) — and concluded
`Wrap` needed no change because forcing a fixed `328px` width would overflow
the smallest tested viewport (320pt, `exit_confirm_sheet_test.dart:89-94`).
That reasoning is correct **on its own terms** — a hard-coded 328px box would
indeed overflow at 320pt — but it never asked whether the row *fills* the
sheet, which is a different property a `Wrap` cannot deliver at any width: on
a real ~412dp Android phone (content width 412−32=380px, the exact reference
device `docs/specs/design-language.md` already names), the Wrap's block sits
at a fixed 328px, leaving a 52px gap on the right — "the block is narrower
than the sheet," exactly as reported. The fix this plan uses (`Row` +
`Expanded`, matching `ColorSwatchPicker`) has no width at which it can either
overflow OR leave a gap: it always divides the available width into exactly
six columns, which is what the canvas's `1fr` actually specifies.

The reason no widget test caught this either: `test/test_utils/pump_app.dart:
135` pins every widget test's default surface to `800×2400` — content width
768px, more than double any real phone. The old plan's own self-review
(`docs/plans/2026-08-18-category-icons.md:161-173`) noted this but framed it
as "six-across isn't *observable* without pinning a realistic width," not as
"nothing here has ever asserted a row spans its container, at any width." No
existing test does; Task 1 adds one that does, at a real Android width.

### G-16 — measured, not asserted, against the real shipped font

**What was measured, and how.** `docs/backlog.md` row G-14 (and
`test/features/members/member_avatar_test.dart:74-103`) already establishes
that `flutter test` draws the Ahem-style `FlutterTest` font — a "square whose
size equals the font size" — never the real Inter, so no widget test in this
repo can measure a real glyph's advance or ink extent. What **can** measure
it: the actual font files are already committed at `assets/fonts/Inter-*.ttf`
and declared under pubspec `fonts:` (`pubspec.yaml:112-122`) — `MemberAvatar`
renders its initials at `FontWeight.w600`, i.e. `Inter-SemiBold.ttf`. A TrueType
font's own binary tables (`head`, `hhea`, `OS/2`, `cmap`, `hmtx`, `glyf`) state
its real units-per-em, ascent/descent, and — critically — each glyph's exact
advance width and ink bounding box. Reading those tables needs no Flutter
text-layout pipeline at all, so it sidesteps G-14 entirely rather than working
around it.

This plan's diagnosis pass read `assets/fonts/Inter-SemiBold.ttf` with a
~150-line offline Python script (`struct`-based sfnt/cmap/glyf parsing, no
third-party font library — none is installed in this environment) run via
plain `python3`, not `flutter`/`dart` — it never touches the shared SDK lock
this plan is otherwise barred from. The script and its raw output are not
part of the implementation; the **numbers** below are, and every one was
read directly off the shipped font, not assumed:

| fact | value |
| --- | --- |
| `unitsPerEm` | 2048 |
| every plain capital's ink | `yMin=0`, `yMax=1490` (cap height 1490/2048 = **0.727539 em**) — no descenders |
| widest capital (advance) | `'W'` = 2089 units (**1.0200 em**) |
| 2nd-widest capital (advance) | `'M'` = 1889 units (**0.9224 em**) |
| `'WM'` combined ink span | x = 50 → 3828 of a 3978-unit two-glyph advance run → ink width 3778/2048 = **1.844726 em** |

`'W'` and `'M'` are the two widest capitals Inter SemiBold ships (checked
against all 26 advance widths, not assumed) — confirming
`test/features/members/member_avatar_test.dart:236` ("the widest two-letter
pair") already picked the objectively-worst case, `'Wm' → 'WM'`, for the
right reason.

**The geometric quantity that actually matters, and why the original
arithmetic missed it.** `docs/plans/2026-08-18-palette-and-ring-avatars.md:
344-373` (R2) modelled fit as a 1-D comparison: an assumed
`1.35 × fontSize` glyph width against `0.9 × (2·radius − 2·ringWidth)`
"usable width." Two independent problems, found by using the real numbers:

1. The assumed `1.35×` ratio is for the *pair*, but "usable width" was
   compared against a **rectangle**, when the ring is a **circle** — a text
   box's farthest visible pixels from the avatar's centre are at its
   *corners*, not its edge midpoints, and a corner reaches further than
   either half-width or half-height alone (`√(a²+b²) > max(a,b)`). Nothing
   in R2's table checked the diagonal.
2. Using the real measured ink box (1.844726 em wide × 0.727539 em tall for
   `'WM'`), the corner-to-centre distance works out to a strikingly clean
   `fontSize × √((1.844726/2)² + (0.727539/2)²) ≈ 0.99150 × fontSize` — i.e.
   the worst-case pair's farthest ink reaches almost exactly one `fontSize`
   from the avatar's centre. That is the number to compare against the
   ring's **inner radius** (`scaledRadius − ringWidth`), not against R2's
   per-axis "usable width."

**Applying `cornerReach = 0.9915 × fontSize` against `innerRadius =
scaledRadius − ringWidth(scaledRadius)` at every real call site.** Every
`MemberAvatar(...)` construction in `lib/` was enumerated
(`grep -rn "MemberAvatar("`): the unnamed default (`chore_occurrence_tile.dart:
353`, `assignment_fields.dart:117,233,288`, `stats_share_card.dart:131`,
`chore_history_screen.dart:87` — radius 12 today), `radius: 14`
(`mark_done_for_sheet.dart:52`, `acting_member_sheet.dart:53,66,110`),
`radius: 16` (`join_flow_steps.dart:181`), `radius: 21`
(`manage_members_screen.dart:145`), `radius: 33`
(`member_edit_sheet.dart:280-284`). `MemberAvatar`'s own formulas
(`lib/features/members/member_avatar.dart:117-129`) are:

```
scaledRadius = radius × clamp(textScale, 1.0, 1.6)
ringWidth    = clamp(scaledRadius / 8, 1.5, 3.0)
fontSize     = clamp(scaledRadius × 0.72, 11.0, ∞)
innerRadius  = scaledRadius − ringWidth
```

Margin (`innerRadius − cornerReach`) is monotonically non-decreasing in
`textScale` for every fixed `radius`: `innerRadius` grows with `scaledRadius`
at a rate (0.875×, or faster once `ringWidth` hits its 3.0 cap) that is
always ≥ the rate `cornerReach` grows once `fontSize` is off its 11px floor
(0.9915 × 0.72 ≈ 0.714×), and `cornerReach` doesn't move at all while
`fontSize` is still floored — so checking the two ends of the scale range,
1.0 and 1.6 (`MemberAvatar._maxTextScale`), bounds the whole range:

| radius | scale | fontSize | ringWidth | innerRadius | cornerReach | margin |
| --- | --- | --- | --- | --- | --- | --- |
| **12 (today's default)** | **1.0** | 11 (floored) | 1.5 | 10.5 | 10.907 | **−0.407 — OVERFLOW** |
| 12 | 1.6 | 13.824 | 2.4 | 16.8 | 13.706 | +3.09 |
| **14** | **1.0** | 11 (floored) | 1.75 | 12.25 | 10.907 | **+1.343** |
| 14 | 1.6 | 16.128 | 2.8 | 19.6 | 15.99 | +3.61 |
| 16 | 1.0 | 11.52 | 2.0 | 14.0 | 11.424 | +2.576 |
| 21 | 1.0 | 15.12 | 2.625 | 18.375 | 14.991 | +3.384 |
| 33 | 1.0 | 23.76 | 3.0 (capped) | 30.0 | 23.559 | +6.441 |

**Exactly one real, shipped configuration overflows: the default (radius 12)
at ordinary, unscaled text** — the opposite end of the range from where the
wave-6 obligation looked ("a legibility check at 16px and text scale 2.0";
scale 2.0/1.6 is in fact the *safest* end of the range for this shape, since
margin only grows with scale). This matches the report precisely: found on
an ordinary device look, not under accessibility text scaling, at the
smallest/most common avatar. Every other shipped radius already has real
margin — most tightly `radius: 14` at unscaled text, +1.343px — which is
useful: it's an already-shipped, already-live size.

**Decision: (a) — two letters ship, given real optical padding, by growing
the default radius from 12 to 14.** This is not a font shrink (the standing
rule against that is respected: `fontSize` stays floored at 11px, unchanged);
it enlarges the ring, and it does so by reusing a radius the codebase already
ships and tests pass at (`mark_done_for_sheet.dart`, `acting_member_sheet.dart`
already draw `radius: 14` avatars in production). No other call site needs
to change — 16/21/33 already had margin and match the design canvas's
explicit 42px/66px pixel values for the two named frames (1b), which this
plan does not alter.

**Why not (b), one letter.** The overflow is small (0.407px, i.e. under a
device pixel at most real-world 2×+ DPRs) and is fully closed by growing the
ring to an already-shipped, already-tested size at zero legibility or
accessibility cost — R2's argument for two letters (Anna/Alex collide at one
letter; initials are the *only* channel separating members for a colour-blind
viewer, since `#6B57B0`/`#7A5AA8` sit at only ΔE 7.8) is untouched by this
fix and remains fully valid. One letter would only be the right call if no
safe growth were available or acceptable; here one plainly is.

**What this plan's tests can and cannot prove, stated plainly (the standing
instruction from G-14).** The new arithmetic test in Task 2 proves, by
direct computation against `MemberAvatar`'s own formulas and the real Inter
metrics above, that the worst-case two-letter pair's ink corner stays inside
the ring's inner radius at every currently-shipped `(radius, scale)`
combination, with a stated margin. It is an **analytical bound**, not a
render: it does not know about anti-aliasing, hinting, sub-pixel rounding, or
whether Skia's actual text-layout algorithm centres the ink exactly the way
this plan's idealised model assumes (it doesn't correct for the ~0.03em
left/right bearing asymmetry of `'W'`/`'M'`, for instance — a second-order
effect against a ≥1.3px margin). It **can** fail — see each task's inversion
step — and it is reproducible by anyone who re-runs the same TTF-table read
against `assets/fonts/Inter-SemiBold.ttf`. It cannot replace an actual look
at a real screen; that remains `docs/specs/design-language.md`'s "Definition
of visual done" gate, unchanged by this plan, and is the one thing here that
stays device-only.

---

## Open product decisions

None. Both G-15 and G-16 are bug corrections with resolutions fully derivable
from the design canvas (already committed, `docs/design/2026-08-18-famdo-
features.dc.html`) and from measurement against the shipped code and font —
neither needs a call only a human product owner could make. The one
design-adjacent judgement the ticket explicitly delegated to this plan
(one letter vs. two, and the resulting avatar size) is resolved above with
its supporting measurement, not left open.

---

## Task 1: G-15 — the icon grid spans the sheet width, six equal columns per row

**Files:**
- Modify: `lib/features/settings/category_edit_sheet.dart:226-275` (`_IconGrid`)
- Test: `test/features/settings/category_edit_test.dart`

**Interfaces:**
- Consumes: `categoryIconIdentifiers` (`lib/features/categories/category_icons.dart`,
  unchanged, 24 entries), `categoryIcon(String)` (unchanged), `PickerTile`
  (`lib/app/color_swatch_picker.dart`, unchanged — `isSelected`, `onTap`,
  `child`, `shape` (defaults to `CircleBorder`)), `semantic(String id,
  {required Widget child})` (`lib/app/semantics.dart`, unchanged).
- Produces: `_IconGrid`'s public contract is unchanged (`selected`,
  `onSelected` constructor params; used only by `_CategoryEditSheetState`
  in the same file). No other file references `_IconGrid` — it is private.
  Every `settings.categories.icon.<identifier>` semantic id is preserved
  verbatim (load-bearing for E2E and for
  `test/features/settings/category_edit_test.dart`'s existing "renders
  every identifier" test).

- [ ] **Step 1: Write the failing test**

Add to `test/features/settings/category_edit_test.dart`, after the existing
`'the icon grid renders every identifier...'` test (i.e. as the new last
test in the file, before the closing `}` of `main()`):

```dart
  testChoreApp(
    'the icon grid spans the sheet width, six equal columns per row '
    '(backlog G-15 -- a Wrap of fixed-size tiles left a visible gap on a '
    'real Android phone)',
    today: today,
    (tester, database) async {
      // Pin to the ~412dp-wide Android reference device
      // `docs/specs/design-language.md` already names for "Definition of
      // visual done" -- the shared test bootstrap's default 800x2400
      // surface (`test/test_utils/pump_app.dart:135`) is wide enough that
      // a fixed 328px block of six 48px tiles looks fine by accident; this
      // narrower, realistic width is where the reported gap actually shows.
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final handle = tester.ensureSemantics();
      await openManageCategories(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.categories.add'));
      await tester.pumpAndSettle();

      // The name field fills the sheet's content width (sheet width minus
      // its 16px left/right padding, `category_edit_sheet.dart:96`) -- use
      // its measured right edge as ground truth for "the sheet's content
      // right edge" rather than assuming the padding arithmetic here too.
      final nameField = find.descendant(
        of: find.bySemanticsIdentifier('settings.categories.name'),
        matching: find.byType(TextField),
      );
      final contentRight = tester.getTopRight(nameField).dx;

      // 'build' is categoryIconIdentifiers[5] (cleaning_services, skillet,
      // local_laundry_service, yard, pets, build) -- the sixth and
      // therefore last tile of the grid's first row.
      final lastTileRight = tester
          .getTopRight(
            find.bySemanticsIdentifier('settings.categories.icon.build'),
          )
          .dx;

      // The design (canvas 1d: `grid-template-columns: repeat(6, 1fr)`)
      // divides the row into six EQUAL, flexible columns spanning the full
      // width, so the last tile sits centred in the last column: at 412dp
      // wide the content is 412-32=380px, each column 380/6=63.3px, and a
      // centred 48px tile is inset (63.3-48)/2=7.7px from the column's (and
      // so the content's) right edge -- comfortably under 20. The OLD
      // `Wrap` of fixed 48px tiles instead always stops dead at
      // 6*48+5*8=328px, a 52px gap here -- nowhere near under 20. 20 is a
      // generous threshold that cleanly separates the two: real numbers of
      // 7.7px (fixed) vs 52px (broken), not a knife's edge.
      expect(
        contentRight - lastTileRight,
        lessThan(20),
        reason:
            'the icon grid must span the sheet the way the colour grid '
            'does (ColorSwatchPicker uses Row+Expanded, color_swatch_'
            'picker.dart:126-163); a Wrap of fixed-size tiles instead '
            'leaves a gap of '
            '${(contentRight - lastTileRight).toStringAsFixed(1)}px',
      );

      handle.dispose();
    },
  );
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/settings/category_edit_test.dart`

Expected: **FAIL** on the new test, with a message reporting a gap near
`52.0px` (`Expected: a value less than <20> Actual: <52.0>` or similar) —
this confirms the test genuinely observes the reported defect against
today's `Wrap`, not just against a hypothetical. Every other test in the
file stays green.

- [ ] **Step 3: Replace `_IconGrid`'s `Wrap` with `ColorSwatchPicker`'s
      six-equal-column pattern**

Replace `lib/features/settings/category_edit_sheet.dart:226-275` (the whole
`_IconGrid` class, from its doc comment through its closing `}`) with:

```dart
/// The icon picker: a six-across grid of [categoryIconIdentifiers], each
/// drawn via `categoryIcon`. The selected tile is marked two ways — a
/// filled background AND a small check badge — so selection never rides on
/// color alone (`docs/specs/design-language.md` color-usage rules).
///
/// Six EQUAL, flexible columns per row (design canvas frames 1b/1d:
/// `grid-template-columns: repeat(6, 1fr)`) — the same `Row` + `Expanded`
/// pattern `ColorSwatchPicker` uses just above in this file family
/// (`color_swatch_picker.dart`), not a `Wrap`: a `Wrap` sizes a row to the
/// sum of its fixed-size children and never stretches to fill the sheet's
/// actual width, which is backlog G-15 (a real Android phone showed the
/// six-tile block narrower than the sheet).
class _IconGrid extends StatelessWidget {
  const _IconGrid({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  /// Icons per row (design canvas: "both grids stay six across"). Matches
  /// `ColorSwatchPicker.columns`.
  static const int _columns = 6;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final identifiers = categoryIconIdentifiers;
    final rows = <Widget>[];
    for (var start = 0; start < identifiers.length; start += _columns) {
      final end = start + _columns > identifiers.length
          ? identifiers.length
          : start + _columns;
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: start == 0 ? 0 : 8),
          child: Row(
            children: [
              for (var index = start; index < end; index++)
                Expanded(
                  // Expanded hands its child a TIGHT horizontal constraint,
                  // which PickerTile's SizedBox(width: 48) would resolve
                  // to the full column width -- stretching the tile into
                  // an oval on a phone-width sheet. Center shrink-wraps it
                  // back to 48 while Expanded still divides the row into
                  // six equal columns spanning the sheet.
                  child: Center(
                    child: _tile(context, colorScheme, identifiers[index]),
                  ),
                ),
              // Pad a short final row so its tiles keep the same column
              // width as every full row above them.
              for (var filler = end; filler < start + _columns; filler++)
                const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }

  Widget _tile(
    BuildContext context,
    ColorScheme colorScheme,
    String identifier,
  ) {
    return semantic(
      'settings.categories.icon.$identifier',
      child: PickerTile(
        isSelected: identifier == selected,
        onTap: () => onSelected(identifier),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              categoryIcon(identifier),
              color: identifier == selected
                  ? colorScheme.onSecondaryContainer
                  : colorScheme.onSurfaceVariant,
            ),
            if (identifier == selected)
              Positioned(
                bottom: 0,
                right: 0,
                child: Icon(
                  Icons.check_circle,
                  size: 14,
                  color: colorScheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

Every `settings.categories.icon.$identifier` semantic id is produced in
exactly the same place in the tree (wrapping the same `PickerTile`, itself
wrapping the same `Stack`) as before — only the container around each tile
changed, from a `Wrap` child to `Expanded → Center`. `ColorSwatchPicker`
itself (`lib/app/color_swatch_picker.dart`) is **not modified** by this
task — the pattern is copied, not extracted into a shared widget, to keep
this a minimal, reviewable fix scoped to the one file backlog G-15 names;
`color_swatch_picker_test.dart` asserts only semantics, positions and
colours (no `Wrap`/`Row` type-checks), so it is unaffected either way.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/settings/category_edit_test.dart`

Expected: **PASS**, all tests in the file, including the new one (gap
reported near `7.7px`, comfortably under the 20px threshold) and the
existing "renders every identifier" test (unaffected — it only checks
presence and one tap-to-save round trip).

- [ ] **Step 5: Invert to confirm the new test can fail on purpose**

Temporarily revert `_IconGrid.build()` to the original `Wrap` (spacing: 8,
runSpacing: 8, one `semantic(...)`-wrapped `PickerTile` per identifier, no
`Row`/`Expanded`/chunking) and rerun the same command from Step 4.

Expected: **FAIL** again on the new "spans the sheet width" test, with the
same ~52px-gap message as Step 2 — confirming the test is not vacuous at the
`flutter test` step (not merely at `analyze`, which the reverted code would
still pass). Then restore the Step 3 implementation and confirm Step 4's
PASS again before moving on.

- [ ] **Step 6: Commit**

```bash
git add lib/features/settings/category_edit_sheet.dart test/features/settings/category_edit_test.dart
git commit -m "Make the category icon grid span the sheet width (G-15)"
```

---

## Task 2: G-16 — two-letter initials fit inside the ring at every real avatar size

**Files:**
- Modify: `lib/features/members/member_avatar.dart` (extract two pure
  geometry functions; bump the default `radius`; update doc comments)
- Modify: `lib/features/chores/mark_done_for_sheet.dart:52`,
  `lib/features/chores/acting_member_sheet.dart:53,66,110` (drop the
  now-redundant explicit `radius: 14`)
- Modify: `docs/specs/members-management.md` (record the second size bump)
- Test: `test/features/members/member_avatar_test.dart`

**Interfaces:**
- Consumes: `categoryTone(BuildContext, int)` (`lib/app/theme.dart`,
  unchanged), `memberInitials(String)` (unchanged), `previewMember(...)`
  (unchanged).
- Produces: two new top-level functions in `member_avatar.dart`,
  `double memberAvatarRingWidth(double scaledRadius)` and
  `double memberAvatarFontSize(double scaledRadius)` — pure, no
  `BuildContext`, used by `MemberAvatar.build()` and by the new test in this
  task. `MemberAvatar`'s public constructor signature is unchanged except
  its `radius` default, `12` → `14`; every existing caller that already
  passes an explicit `radius` is unaffected except the four listed above,
  where `14` is now the default and must be dropped (see Global Constraints
  — `avoid_redundant_argument_values`).

- [ ] **Step 1: Extract the two geometry formulas as pure functions, and
      write the failing analytical fit test against today's default (12)**

In `lib/features/members/member_avatar.dart`, replace lines 121-129 (the
`ringWidth`/`fontSize` computation inside `build()`, from the `// radius / 8
reproduces...` comment through `final fontSize = ...;`) with:

```dart
    final ringWidth = memberAvatarRingWidth(scaledRadius);
    final fontSize = memberAvatarFontSize(scaledRadius);
```

And add these two top-level functions in the same file, directly above
`class MemberAvatar` (i.e. after `memberInitials`'s closing `}` and before
the `MemberAvatar` doc comment at line 75):

```dart
/// The avatar's ring stroke width for an already text-scale-adjusted
/// [scaledRadius]: `scaledRadius / 8` reproduces the design's own two
/// stated ring widths — 2.6 at its 42px row avatar (radius 21, drawn 2.5)
/// and 3.0 at its 66px preview (radius 33, drawn 3) — floored at 1.5 so the
/// ring never gets so thin it disappears at the smallest sizes.
double memberAvatarRingWidth(double scaledRadius) =>
    (scaledRadius / 8).clamp(1.5, 3.0);

/// The avatar's initials font size for an already text-scale-adjusted
/// [scaledRadius]: `scaledRadius * 0.72` lands on the design's 15px and
/// 23px at radius 21/33, floored at 11px — Material's smallest label size,
/// below which two uppercase glyphs stop being legible (G-4/R2). Never
/// lower this floor to make two letters fit a smaller ring; grow the ring
/// instead (G-16) — a smaller glyph at the same border position trades one
/// defect for another wearing a different hat.
double memberAvatarFontSize(double scaledRadius) =>
    (scaledRadius * 0.72).clamp(11.0, double.infinity);
```

Then, in `test/features/members/member_avatar_test.dart`, add this test
(a plain `test(...)`, not `testWidgets` — it calls no Flutter text-layout
code at all, so `flutter_test`'s Ahem substitution, backlog G-14, never
applies to it) after the existing `'the initials rule counts graphemes...'`
test:

```dart
  test(
    'two-letter initials stay inside the ring at every avatar size the app '
    'actually uses, measured against the real shipped font (G-16)',
    () {
      // Real glyph geometry for Inter SemiBold (FontWeight.w600, the
      // avatar's weight), read directly from assets/fonts/Inter-
      // SemiBold.ttf's own binary tables (head/hhea/OS2/cmap/hmtx/glyf) --
      // NOT from a widget test, which draws flutter_test's Ahem-style font
      // and cannot measure this (G-14).
      //
      // 'W' (advance 2089/2048=1.0200em) is the widest capital Inter
      // SemiBold ships, 'M' (1889/2048=0.9224em) the second-widest --
      // checked against all 26 capitals, confirming 'WM' below (matching
      // this file's own 'Wm' test case) really is the worst two-letter
      // pair, not merely assumed to be.
      //
      // The pair's combined ink spans x=50..3828 of a 3978-unit two-glyph
      // advance run: ink width 3778/2048 = 1.844726 em. Every plain
      // capital's ink in this font has yMin=0, yMax=1490 (cap height
      // 1490/2048 = 0.727539 em) -- no descenders, so that is also the
      // pair's ink height. The distance from the ink box's centre to its
      // farthest corner -- the quantity that matters against a CIRCULAR
      // ring, not a same-width rectangle's "usable width" -- is therefore:
      const cornerReachPerFontSize = 0.99150; // sqrt((1.844726/2)^2 + (0.727539/2)^2)

      // Every MemberAvatar(...) construction in lib/, enumerated by
      // `grep -rn "MemberAvatar("`: the shared default (chore_occurrence_
      // tile.dart, assignment_fields.dart x3, stats_share_card.dart,
      // chore_history_screen.dart), radius 16 (join_flow_steps.dart), 21
      // (manage_members_screen.dart), 33 (member_edit_sheet.dart). Text
      // scale 1.0 and 1.6 (MemberAvatar._maxTextScale) bound the whole
      // range: margin is monotonically non-decreasing in scale for every
      // fixed radius here, since innerRadius always grows at least as fast
      // as cornerReach as scaledRadius grows (0.875x once ringWidth is off
      // its floor and unclamped, faster still once ringWidth caps at 3.0,
      // against cornerReach's 0.9915*0.72=0.714x once fontSize is off its
      // 11px floor -- and cornerReach doesn't move at all while fontSize
      // is still floored).
      const defaultRadius = 14.0; // the shared MemberAvatar() default
      for (final testCase in <(double radius, double scale)>[
        (defaultRadius, 1),
        (defaultRadius, 1.6),
        (16, 1),
        (16, 1.6),
        (21, 1),
        (21, 1.6),
        (33, 1),
        (33, 1.6),
      ]) {
        final scaledRadius = testCase.radius * testCase.scale;
        final ringWidth = memberAvatarRingWidth(scaledRadius);
        final fontSize = memberAvatarFontSize(scaledRadius);
        final innerRadius = scaledRadius - ringWidth;
        final cornerReach = cornerReachPerFontSize * fontSize;
        expect(
          cornerReach,
          lessThan(innerRadius),
          reason:
              'radius ${testCase.radius} at scale ${testCase.scale}: the '
              "widest real pair ('WM') reaches "
              '${cornerReach.toStringAsFixed(3)} logical px from the '
              "avatar's centre, but the ring's inner edge is only "
              '${innerRadius.toStringAsFixed(3)}px out -- the initials '
              'would touch or cross the ring',
        );
      }
    },
  );
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/members/member_avatar_test.dart`

Expected: **FAIL** on the new test, at the `(14.0, 1)` case reading
`radius 14.0 at scale 1.0` — wait, this is Step 1: `defaultRadius` is
declared as `14.0` in the test but `MemberAvatar`'s actual default is still
`12` at this point in the plan (not yet changed) — so this step's failure
is expected to name whichever value is inconsistent. Run it exactly as
written above (with `defaultRadius = 14.0`, matching the value Step 3 is
about to ship) and confirm it currently **FAILS at the `(14.0, 1)` case**
with `cornerReach=10.907` NOT `lessThan` `innerRadius=12.25` — no: `10.907 <
12.25` is TRUE, so `(14.0, 1)` alone would already pass even before Step 3's
production change, because this test computes purely from the formulas
above using literal `14.0`, independent of what `MemberAvatar`'s
constructor default currently is. To make this step a genuine, currently-
failing RED (proving the test can fail, per the standing instruction),
temporarily change the test's `defaultRadius` constant to `12.0` (today's
real, unfixed default) before running it the first time:

```dart
      const defaultRadius = 12.0; // TEMPORARY for this step only
```

Then run the same command. Expected: **FAIL**, reason string reporting
`radius 12.0 at scale 1.0: ... reaches 10.907 ... but the ring's inner edge
is only 10.500px out`. This confirms the test genuinely detects the measured
G-16 overflow against the code as it stands today. Change `defaultRadius`
back to `14.0` before continuing to Step 3 (this is the value the shipped
test asserts against — Step 3 makes it true in `lib/`, not the other way
around).

- [ ] **Step 3: Bump the default radius, and drop the callers that become
      redundant**

In `lib/features/members/member_avatar.dart`:

Replace line 92:
```dart
  const MemberAvatar({required this.member, this.radius = 12, super.key});
```
with:
```dart
  const MemberAvatar({required this.member, this.radius = 14, super.key});
```

Replace the doc comment at lines 79-89 (from `/// A ring rather than a fill`
through the closing `/// 33-radius preview).`) with:

```dart
/// A ring rather than a fill so the same avatar is legible at 28px in a
/// chore tile and 66px in the member edit sheet: the initials always sit on
/// `surfaceContainerHigh` against `categoryTone`, a pairing the tone table
/// guarantees at >= 3:1 in both themes (`test/app/palette_test.dart`),
/// instead of on a fill whose legibility varied with the color.
///
/// [radius] defaults to 14 (the chore tile's compact inline size -- 28px;
/// measured against the real shipped Inter font, G-16, at which two
/// glyphs fit inside the ring with margin — the previous default, 12,
/// measurably did not); pass a larger value for a more prominent context
/// (the join chooser at 16, the members list at 21, the acting-member
/// app-bar button, the switcher sheet, the edit sheet's 33-radius preview).
```

And replace the now-stale comment at (originally) lines 121-124, i.e. the
`// radius / 8 reproduces...` block just deleted in Step 1 — already
replaced by the call to `memberAvatarRingWidth`/`memberAvatarFontSize`
above, whose own doc comments carry this explanation now; no further edit
needed here.

Then, since `radius: 14` is now identical to the default and therefore
flagged by `avoid_redundant_argument_values` under `--fatal-infos`, remove
the now-redundant explicit argument at:

`lib/features/chores/mark_done_for_sheet.dart:52`, replace:
```dart
                      leading: MemberAvatar(member: member, radius: 14),
```
with:
```dart
                      leading: MemberAvatar(member: member),
```

`lib/features/chores/acting_member_sheet.dart:53`, replace:
```dart
          child: Center(child: MemberAvatar(member: member, radius: 14)),
```
with:
```dart
          child: Center(child: MemberAvatar(member: member)),
```

`lib/features/chores/acting_member_sheet.dart:66`, replace:
```dart
            : MemberAvatar(member: member, radius: 14),
```
with:
```dart
            : MemberAvatar(member: member),
```

`lib/features/chores/acting_member_sheet.dart:110`, replace:
```dart
                  leading: MemberAvatar(member: member, radius: 14),
```
with:
```dart
                  leading: MemberAvatar(member: member),
```

- [ ] **Step 4: Update the existing widget tests' hard-coded numbers**

`test/features/members/member_avatar_test.dart` has three places that
hard-code the *old* default (12 → a 24px box, 1.5 ring width). Update them
to the new default (14 → a 28px box, 1.75 ring width):

The file's top doc comment, line 3: replace `legible from the 24px chore
tile to the 66px` with `legible from the 28px chore tile to the 66px`.

`_pump`'s own default, line 17: replace
```dart
  double radius = 12,
```
with
```dart
  double radius = 14,
```
(this mirrors production exactly, the same way it already did at 12 — see
the "left implicit" comment at the old lines 220-222, which the next edit
updates).

The `'ring width tracks radius and reproduces the design values'` test
(around line 220-224): replace
```dart
    // 24px chore tile (radius 12, the default): thinner, so the two letters
    // still have room. Left implicit because `--fatal-infos` rejects
    // `radius: 12` as redundant against the helper's own default.
    await _pump(tester, appLightTheme, name: 'Mia', color: stored);
    expect((_decoration(tester).border! as Border).top.width, 1.5);
```
with
```dart
    // 28px chore tile (radius 14, the default): thinner than the 21/33
    // rows above, so the two letters still have room (G-16). Left implicit
    // because `--fatal-infos` rejects `radius: 14` as redundant against the
    // helper's own default.
    await _pump(tester, appLightTheme, name: 'Mia', color: stored);
    expect((_decoration(tester).border! as Border).top.width, 1.75);
```

The `'the smallest avatar renders two letters without throwing'` test
(around line 227-244): replace
```dart
    // R2 sized the default radius at 12 (a 24px box) so two glyphs fit with
    // margin -- ~15px of Inter inside 21px of room. That margin is NOT
    // asserted here; see the note at the top of this file for why it cannot
    // be. What IS asserted is font-independent: the widest two-letter pair
    // lays out without an exception, the box is the size R2 specified, and
    // the glyphs never drop below the legibility floor.
    await _pump(tester, appLightTheme, name: 'Wm', color: stored);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(MemberAvatar)), const Size(24, 24));
```
with
```dart
    // G-16 sized the default radius at 14 (a 28px box) so two glyphs fit
    // with real margin, measured against the actual shipped Inter font --
    // see 'two-letter initials stay inside the ring...' below, and the
    // plan's diagnosis, for the arithmetic. That margin is not re-asserted
    // here; this test only checks what is font-independent regardless: the
    // widest two-letter pair lays out without an exception, the box is the
    // size G-16 specified, and the glyphs never drop below the legibility
    // floor.
    await _pump(tester, appLightTheme, name: 'Wm', color: stored);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(MemberAvatar)), const Size(28, 28));
```

The `'the whole avatar grows with text scale, capped at 1.6x'` test (around
line 246-268): replace
```dart
    await _pump(tester, appLightTheme, name: 'Mia', color: stored);
    final base = tester.getSize(find.byType(MemberAvatar));
    expect(base.width, 24);
```
with
```dart
    await _pump(tester, appLightTheme, name: 'Mia', color: stored);
    final base = tester.getSize(find.byType(MemberAvatar));
    expect(base.width, 28);
```
and replace
```dart
    expect(
      scaled.width,
      closeTo(24 * 1.6, 0.01),
```
with
```dart
    expect(
      scaled.width,
      closeTo(28 * 1.6, 0.01),
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/members/member_avatar_test.dart`

Expected: **PASS**, every test in the file — including the new analytical
fit test (now with `defaultRadius = 14.0` matching the real, just-changed
production default) and the four updated widget tests.

- [ ] **Step 6: Invert to confirm the new test can fail on purpose**

Temporarily change `memberAvatarFontSize`'s floor from `11.0` to `12.5` (a
stand-in for "someone raised the legibility floor without growing the ring
to match" — the exact class of regression this test exists to catch) and
rerun the same command.

Expected: **FAIL** on the new analytical test, at the `(14.0, 1)` case (new
`fontSize=12.5`, `cornerReach=12.394`, `innerRadius` still `12.25` →
overflow) — confirming the test is not vacuous at the `flutter test` step.
Then revert the floor to `11.0` and confirm Step 5's PASS again.

- [ ] **Step 7: Run the wider regression sweep**

The default-radius change touches every call site that doesn't pass an
explicit `radius`. Run the existing test files that render one, to confirm
no `RenderFlex` overflow or other layout regression from the box growing
24px → 28px (Flutter surfaces an overflow as an uncaught `FlutterError`
during the test, which fails it — no new assertions are needed, only that
these still pass):

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  test/features/members/member_avatar_test.dart \
  test/features/chores/tile_redesign_test.dart \
  test/features/chores/chore_form_avatars_test.dart \
  test/features/chores/mark_done_for_test.dart \
  test/features/chores/acting_member_widget_test.dart \
  test/features/chores/acting_member_pinning_test.dart \
  test/features/settings/members_screen_test.dart \
  test/features/settings/join_household_sheet_test.dart \
  test/features/stats/stats_screen_test.dart \
  test/features/stats/chore_history_screen_test.dart
```

Expected: **PASS**, all files. If any fails with an overflow, that call
site's surrounding layout (e.g. a `ListTile` leading-slot width assumption)
needs its own fix before this task can land — investigate that specific
failure against its own file rather than reverting the radius change, since
the alternative (staying at radius 12) is the measured G-16 defect.

- [ ] **Step 8: Record the second size bump in the spec**

In `docs/specs/members-management.md`, replace the sentence at (originally)
line 73-74:
```
  Two characters rather than one because for a color-blind viewer the
  initials are the only channel that separates members. The chore-tile
  avatar was enlarged from 20px to 24px to fit them; the rule was not
  weakened to fit the old size.
```
with:
```
  Two characters rather than one because for a color-blind viewer the
  initials are the only channel that separates members. The chore-tile
  avatar was enlarged from 20px to 24px to fit them (G-4), and again to
  28px (G-16) after a real Android device showed the initials still
  touching the ring at 24px — measured against the actual shipped Inter
  font (`test/features/members/member_avatar_test.dart`), not re-asserted
  by eye; the rule was not weakened to fit either old size.
```

- [ ] **Step 9: Update the backlog and commit**

In `docs/backlog.md`, mark both rows resolved in place, following this
file's existing convention (see e.g. the A-2b row) — strike the title,
add a `DONE 2026-08-30` note naming this plan and its key facts, keep the
`Was:`/original text and the Files/Size columns:

- **G-15** row: prefix the title cell with `~~The icon picker grid does not
  fill the screen width on Android~~ **CLOSED 2026-08-30**`, and prepend to
  the notes cell: `**DONE 2026-08-30** (docs/plans/2026-08-30-icon-grid-and-
  initials.md): _IconGrid now lays tiles out with Row+Expanded (six equal
  flexible columns, matching ColorSwatchPicker and the design canvas's
  \`repeat(6,1fr)\`) instead of a fixed-size Wrap, which could fit six tiles
  but never stretch them to the sheet's actual width. Proven by a widget
  test pinned to a 412dp-wide Android reference device — the shared 800px
  test-bootstrap width hid the gap. Was:` followed by the original text.
- **G-16** row: prefix the title cell with `~~Two-letter initials touch the
  avatar border at small sizes~~ **CLOSED 2026-08-30**`, and prepend to the
  notes cell: `**DONE 2026-08-30** (docs/plans/2026-08-30-icon-grid-and-
  initials.md): measured the real shipped Inter-SemiBold.ttf directly
  (advance widths + glyf ink bounding boxes, not a widget test — G-14 rules
  those out) and found exactly one overflow, 0.4px, at the default radius-12
  avatar and ordinary (unscaled) text, not at text scale 2.0 as the original
  obligation assumed — margin only grows with scale for this shape. Fixed
  by growing the default radius 12 → 14, an already-shipped size elsewhere
  in the app, giving +1.3px of real margin; two letters kept, no font
  shrink. Was:` followed by the original text.

```bash
git add lib/features/members/member_avatar.dart \
  lib/features/chores/mark_done_for_sheet.dart \
  lib/features/chores/acting_member_sheet.dart \
  test/features/members/member_avatar_test.dart \
  docs/specs/members-management.md \
  docs/backlog.md
git commit -m "Fix two-letter initials touching the avatar ring (G-16)"
```

---

## Self-review notes

- **Spec coverage.** G-15: `_IconGrid` now matches the design canvas's
  `repeat(6,1fr)` for both pickers (Task 1). G-16: the ring/font formulas
  are unchanged in *shape*, only the default radius input changes, and the
  R2/G-4 two-letter rule is fully preserved (Task 2). Neither ticket asked
  for anything beyond these two files' defects; neither task touches
  anything else.
- **Verified against the codebase, not memory.** Every line number cited
  was read this session: `_IconGrid` at `category_edit_sheet.dart:226-275`,
  `ColorSwatchPicker`'s matching pattern at `color_swatch_picker.dart:
  124-174`, every `MemberAvatar(...)` call site via `grep -rn`, the four
  `radius: 14` sites that become redundant, `pump_app.dart:135`'s
  800×2400 default surface, and the exact TTF metrics via a from-scratch
  binary table read of the actually-committed `Inter-SemiBold.ttf` (not
  assumed from general font knowledge).
- **Type consistency.** `memberAvatarRingWidth`/`memberAvatarFontSize` take
  and return `double` throughout, matching `MemberAvatar.radius`'s existing
  type; the test's record type `(double radius, double scale)` matches.
- **No `semantic(...)` id touched.** G-15 preserves every
  `settings.categories.icon.<identifier>` id verbatim (same wrapping order).
  G-16 adds or removes no semantic id at all — it changes only a numeric
  default and two extracted pure functions.
- **Both fixes are independently testable and revertible** — Task 1 does
  not depend on Task 2 or vice versa; either can land alone.
- **Left for a human with a screen**, per Global Constraints: whether the
  now-flush icon grid and the now-28px chore-tile avatar actually *look*
  right on a real device, in both themes, per `docs/specs/design-
  language.md`'s "Definition of visual done" — no test in this repo, before
  or after this plan, can close that gap.
