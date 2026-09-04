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

## Task 0 corrections (refresh pass, 2026-08-30, before any code changed)

Every citation below was re-checked against the branch's actual code, and the
font was re-measured from scratch rather than trusted. Six corrections; five
of them change what ships.

**C1 — G-15's diagnosis is right but understates the defect.** A `Wrap` does
not merely fail to stretch: its column count is a function of the available
width. It fits `n` tiles where `56n - 8 <= W`. At the shared widget-test
surface (`test/test_utils/pump_app.dart:135`, 800 logical px, content width
768) that is **13 tiles per row**, not six. So "six across" was never true in
any widget test, at any point — it is true only in the narrow band
`328 <= W < 384`, i.e. sheet widths 360-415dp. Igor's ~412dp phone sits at the
top of that band, which is why he saw six across *and* a gap. Task 1 asserts
both properties, and the column-count one needs no view pinning.

**C2 — `'WM'` is NOT the worst two-letter pair; `'WW'` is.** The plan argued
"`'W'` is the widest capital, `'M'` the second widest, therefore `'WM'` is the
worst pair". A pair may repeat a glyph, so the worst pair is `'WW'`. Measured
reach: `'WW'` **1.05998 em** vs `'WM'` **1.01426 em**. The pre-existing test
case `'Wm'` inherited the same mistake. Separately, `'M'` is not even the
second-widest capital once extended Latin is counted: `Œ` (2076) and `Æ` (2075)
both beat `M` (1889).

**C3 — the horizontal half-extent was computed wrong.** The plan used
ink-width / 2 (0.9224 em for `'WM'`). The ink is not centred in the advance
run — `'W'` has a 50-unit left bearing and `'M'` a 150-unit right bearing — so
the correct quantity is `max(centre - xMinInk, xMaxInk - centre)`, which is
0.94678 em for `'WM'`. The plan's own text flagged this as "a second-order
effect"; it is not, at a margin measured in fractions of a pixel.

**C4 — the plan's ink-height claim is false for characters this app will
actually see.** "Every plain capital's ink is `yMin=0, yMax=1490` — no
descenders" holds for `W M Æ Œ` but not for `O`/`Q` (overshoot to 1510, `Q`'s
tail to −129) and not for any accented capital: `Ö` reaches `yMax=1939`. This
app ships a German locale; `'ÖW'` (reach 1.04393 em) is a realistic pair, not a
curiosity. The vertical half-extent the plan used (capHeight / 2) is
nevertheless correct *for unaccented capitals* — but only by a coincidence the
plan did not verify and this pass did: Inter SemiBold's `ascender - descender`
is `1984 - 494 = 1490`, exactly its `sCapHeight`, so with `height: null` a
plain capital's ink is exactly centred in the paragraph box.

**C5 — the combined constant, and therefore the fix, changes.**
`cornerReachPerFontSize` is **1.05998**, not 0.99150 (+6.9%). Consequences:
the radius-12 default overflows by **1.160px**, not 0.407px; and the plan's
chosen radius 14 leaves **+0.590px** — less than one logical pixel, which is
not "real optical padding" and would still read as touching. The new default is
**16**, not 14; see the rewritten diagnosis below for why 16 rather than 15.

**C6 — the plan's own fit test could not have caught a regression.** Its Step 2
says outright that the test "computes purely from the formulas above using
literal `14.0`, independent of what `MemberAvatar`'s constructor default
currently is". A test that hard-codes the value it is supposed to be guarding
would pass unchanged if someone put the default back to 12. That is a fifth
unfalsifiable test in this family. Fixed: the test reads the default off
`const MemberAvatar(...).radius`.

**C7 — a defect this plan did not know about, and cannot fix: the two
`FilterChip` avatars.** Material lays a chip's avatar out with
`BoxConstraints.tightFor(contentSize)`
(`packages/flutter/lib/src/material/chip.dart:1883-1885`), where `contentSize`
is `max(_kChipHeight - padding.vertical + labelPadding.vertical, labelHeight +
labelPadding.vertical)` ~ **24px** at text scale 1. So at
`assignment_fields.dart:117` and `:233` the `radius` argument has **no effect
on the rendered box at all** — and `centerLayout`'s
`assert(sizes.content >= boxSize.height)` (chip.dart:1958) makes it impossible
to hand the avatar a taller box. Two glyphs at the 11px legibility floor need
an outer diameter of at least `2 * (1.05998 * 11 + 1.5)` = **26.32px**; a
Material chip gives 24. No radius fixes this, and the remedies that would (drop
the avatar from the chip — the member's full name is already the chip's label;
one letter in chips only; a hand-rolled chip) are product decisions outside
G-16's scope. This plan therefore pins those two sites to an explicit
`radius: 12` so they render **exactly** as they do today (the new default would
only thicken the ring inside the same forced 24px box, making them 0.75px
worse), documents the exclusion at the call site and in the fit test, and files
a new backlog row.

**C8 — the bound needs `letterSpacing` pinned to be a guarantee.**
`MemberAvatar`'s `TextStyle` sets only size/weight/colour, so `letterSpacing`
is inherited from whatever ambient `DefaultTextStyle` the avatar lands in — and
this theme ships roles from −1.5 to +1.2 (`labelSmall`). Flutter adds
letterSpacing after *every* glyph, so an ambient +1.2 would eat 1.2px of a
1.789px margin. `MemberAvatar` now pins `letterSpacing: 0`. (`height` needed no
pinning: no role in `lib/app/theme.dart` sets one — checked.)

Not a correction, but recorded: the plan's Task 1 Step 5 inversion (revert to
`Wrap`) is valid, but at the 800px test surface the reverted `Wrap` gives
13-across, so the inversion is demonstrated inside the method body as the
execution rules require.


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

*(Rewritten by the Task 0 refresh pass; see corrections C2-C8 above. The
original text's method was right and its numbers were not.)*

**What was measured, and how.** `docs/backlog.md` row G-14 establishes that
`flutter test` draws the Ahem-style `FlutterTest` font, so no widget test in
this repo can measure a real glyph's advance or ink extent. What can: the
shipped font files themselves, `assets/fonts/Inter-*.ttf`, declared under
pubspec `fonts:` (`pubspec.yaml:112-122`). `MemberAvatar` draws at
`FontWeight.w600`, i.e. `Inter-SemiBold.ttf`. A TrueType file's own binary
tables (`head`, `hhea`, `OS/2`, `cmap`, `hmtx`, `loca`, `glyf`) state its
units-per-em, its vertical metrics, and every glyph's exact advance width and
ink bounding box. Reading them needs no Flutter text pipeline, so it sidesteps
G-14 rather than working around it. This pass re-read the font with a
`struct`-based sfnt parser under plain `python3` (no third-party font library
is installed; `python3` does not touch the shared Flutter SDK lock), and
brute-forced every ordered pair over A-Z, 0-9 and the Latin-1/Latin-Extended
capitals the `cmap` covers, rather than reasoning about which pair "must" be
worst.

| fact | value |
| --- | --- |
| `unitsPerEm` | 2048 |
| `hhea` ascender / descender / lineGap | 1984 / −494 / 0 |
| `OS/2` sTypo\*, usWin\*, and `fsSelection` bit 7 (USE_TYPO_METRICS) | identical values, bit set — every metric source agrees |
| `OS/2` `sCapHeight` | 1490 |
| paragraph box height with `height: null` | (1984+494)/2048 = **1.20996 em** |
| box centre above the baseline | (1984−494)/2 = 745 units = **0.36377 em** |
| widest advances | `W` 2089, `Œ` 2076, `Æ` 2075, `M` 1889 |
| **worst ordered pair** | **`'WW'`** — reach **1.05998 em** (half-width 0.99561, half-height 0.36377) |
| runners-up | `'ÆW'` 1.05677, `'ŒŒ'` 1.02977, `'ÖW'` 1.04393, `'WM'` 1.01426 |

Because `ascender − descender` (1490) equals `sCapHeight` exactly, an
unaccented capital's ink is precisely vertically centred in a `height: null`
paragraph box — so for `'WW'` the half-height is `capHeight / 2`. That is a
measured coincidence of this font, not a general truth, and it does **not**
hold for accented capitals (`Ö` reaches 1939, giving half-height 0.57715 em);
`'ÖW'` is nevertheless still below `'WW'`.

**The geometric quantity that matters.** `MemberAvatar`'s root is a `Container`
whose `BoxDecoration` border contributes `EdgeInsets.all(ringWidth)` of
padding, so the `Text` is laid out and centred inside a box concentric with the
avatar. The ink's farthest point from that shared centre is the corner of its
bounding box, `sqrt(a² + b²)`, and the ring's inner edge is a **circle** at
`scaledRadius − ringWidth`. `docs/plans/2026-08-18-palette-and-ring-avatars.md`
(R2) compared an assumed `1.35 × fontSize` glyph width against a per-axis
"usable width" of a rectangle, and so never checked the diagonal at all.

`MemberAvatar`'s own formulas (`lib/features/members/member_avatar.dart`):

```
scaledRadius = radius × clamp(textScale, 1.0, 1.6)
ringWidth    = clamp(scaledRadius / 8, 1.5, 3.0)
fontSize     = clamp(scaledRadius × 0.72, 11.0, ∞)
innerRadius  = scaledRadius − ringWidth
cornerReach  = 1.05998 × fontSize
```

Margin (`innerRadius − cornerReach`) is monotonically non-decreasing in text
scale for every fixed radius (verified numerically over the whole 1.0-1.6 range
at 0.001 steps, not argued), so the two ends bound it:

| radius | scale | fontSize | ringWidth | innerRadius | cornerReach | margin | margin / innerRadius |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **12 — today's default** | **1.0** | 11 (floored) | 1.5 | 10.500 | 11.660 | **−1.160 OVERFLOW** | −11.0% |
| 12 | 1.6 | 13.824 | 2.4 | 16.800 | 14.653 | +2.147 | 12.8% |
| 14 — the original plan's choice | 1.0 | 11 (floored) | 1.75 | 12.250 | 11.660 | **+0.590** | 4.8% |
| 15 | 1.0 | 11 (floored) | 1.875 | 13.125 | 11.660 | +1.465 | 11.2% |
| **16 — the new default** | **1.0** | 11.52 | 2.0 | 14.000 | 12.211 | **+1.789** | **12.8%** |
| 16 | 1.6 | 18.432 | 3.0 | 22.600 | 19.538 | +3.062 | 13.6% |
| 21 | 1.0 | 15.12 | 2.625 | 18.375 | 16.027 | +2.348 | 12.8% |
| 33 | 1.0 | 23.76 | 3.0 | 30.000 | 25.185 | +4.815 | 16.0% |

**Exactly one shipped configuration overflows: the default radius at ordinary,
unscaled text.** That matches the report precisely — found on an ordinary
device look, at the smallest and most common avatar, *not* under accessibility
scaling. Text scale 2.0, the end of the range the wave-6 obligation was written
around, is in fact the safest end for this shape: margin only grows with scale.
The obligation was pointed at the wrong end of the range, which is a second
reason the check that "passed" told nobody anything.

**Decision: two letters ship, and the default radius goes 12 → 16.** Not 14,
and not 15, for a reason that comes out of the code's own formulas rather than
a threshold picked by hand. `fontSize` is clamped up to its 11px floor for
every `scaledRadius < 11/0.72 = 15.28`. While that clamp is active the glyphs
are *larger than the design's own size relationship asks for* — which is the
entire mechanism behind G-16. Radius 16 is the smallest integer radius at which
nothing is clamped, and at that point the headroom falls out automatically at
`1 − 1.05998×0.72/0.875` = **12.8% of the inner radius — exactly the headroom
the 42px (radius 21) and 66px (radius 33) avatars already have**, the two sizes
the design canvas pins and that shipped without complaint. So "does it look
right" transfers from sizes Igor has already accepted, rather than resting on a
number this plan invented. Radius 15 would clear the ring (+1.465px), but only
while still sitting on the clamp, i.e. still in the regime that produced the
bug.

The 11px floor is **not** lowered (`docs/specs/design-language.md` /
G-4 / R2: two uppercase glyphs stop being legible below it), and R2's argument
for two letters is untouched — the initials remain the only channel separating
members for a colour-blind viewer, and the closest palette pair sits at ΔE 7.8.
One letter would have been the right call only if no safe growth existed. One
does.

**What the chip sites cost, stated plainly (correction C7).** At
`assignment_fields.dart:117` and `:233` the avatar is a `FilterChip`'s `avatar:`
and Material force-sizes it to ~24px whatever `radius` says. Two glyphs at the
11px floor need 26.32px. Those two sites are therefore **outside the fit
guarantee this task establishes**: they are pinned to `radius: 12` so they keep
rendering exactly as they do today, the exclusion is named at the call site and
in the test, and a new backlog row records the remedy as a product decision.
The user-visible cost is real but bounded: in those two chips the member's full
name is the chip's own label, so identity does not rest on the initials there.

**What this plan's tests prove, and what they do not.** The fit test is an
analytical bound computed from `MemberAvatar`'s own exported formulas and the
real Inter metrics; it knows nothing about anti-aliasing, hinting, sub-pixel
rounding, or Skia's exact centring. It is reproducible by anyone re-running the
same table read against `assets/fonts/Inter-SemiBold.ttf`. It can fail — the
shipped test contains a configuration that *does* fail the fit inequality (the
chip-forced radius 12), asserted as such, so the test demonstrates its own
discrimination in every CI run rather than only under a temporary inversion.
It cannot replace a look at a real screen; that stays
`docs/specs/design-language.md`'s "Definition of visual done" gate.

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

- [x] **Step 1: Write the failing tests** — two, not one. The plan's single
gap-at-412dp test shipped as written (RED at exactly `52.0`). A second test
was added because correction C1 made a sharper property available: six
flexible columns put the seventh icon on the second row at **every** width,
which needs no pinned surface and was RED at the default 800px surface with
the seventh icon on row one (`Expected: a value greater than <1997.0>,
Actual: <1997.0>`). The 412dp test also asserts the insets match at both
ends, which is what separates "equal columns" from "pushed right".

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

- [x] **Step 2: Run test to verify it fails** — via CI, both RED as above.

Run: `flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/settings/category_edit_test.dart`

Expected: **FAIL** on the new test, with a message reporting a gap near
`52.0px` (`Expected: a value less than <20> Actual: <52.0>` or similar) —
this confirms the test genuinely observes the reported defect against
today's `Wrap`, not just against a hypothetical. Every other test in the
file stays green.

- [x] **Step 3: Replace `_IconGrid`'s `Wrap` with `ColorSwatchPicker`'s
      six-equal-column pattern** — shipped as specified, with one change: the
column count reuses `ColorSwatchPicker.columns` rather than declaring a
second private `_columns`, so "both grids stay six across" is one fact rather
than two that can drift apart. `_tile` also drops its unused `BuildContext`
parameter.

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

- [x] **Step 4: Run test to verify it passes** — CI green.

Run: `flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/settings/category_edit_test.dart`

Expected: **PASS**, all tests in the file, including the new one (gap
reported near `7.7px`, comfortably under the 20px threshold) and the
existing "renders every identifier" test (unaffected — it only checks
presence and one tap-to-save round trip).

- [x] **Step 5: Invert to confirm the new test can fail on purpose** — done inside `build()`'s body, both grid tests RED at the test step, then reverted.

Temporarily revert `_IconGrid.build()` to the original `Wrap` (spacing: 8,
runSpacing: 8, one `semantic(...)`-wrapped `PickerTile` per identifier, no
`Row`/`Expanded`/chunking) and rerun the same command from Step 4.

Expected: **FAIL** again on the new "spans the sheet width" test, with the
same ~52px-gap message as Step 2 — confirming the test is not vacuous at the
`flutter test` step (not merely at `analyze`, which the reverted code would
still pass). Then restore the Step 3 implementation and confirm Step 4's
PASS again before moving on.

- [x] **Step 6: Commit**

```bash
git add lib/features/settings/category_edit_sheet.dart test/features/settings/category_edit_test.dart
git commit -m "Make the category icon grid span the sheet width (G-15)"
```

---

## Task 2: G-16 — two-letter initials fit inside the ring at every avatar size the widget controls

*(Rewritten by the Task 0 refresh pass. Superseded: the old Step 1-9, which
bumped the default to 14 on the strength of the 0.99150 constant, hard-coded
that 14 in the test, and did not know about the chip constraint.)*

**Files:**
- Modify `lib/features/members/member_avatar.dart` — export the two geometry
  formulas as pure functions, pin `letterSpacing: 0`, bump the default
  `radius` 12 → 16, update the doc comments.
- Modify `lib/features/chores/mark_done_for_sheet.dart`,
  `lib/features/chores/acting_member_sheet.dart` (x3),
  `lib/features/settings/join_flow_steps.dart` — drop the explicit `radius`
  arguments that `avoid_redundant_argument_values` now rejects (`14` in the
  first two files, `16` in the third — the plan's original list missed
  `join_flow_steps.dart`, which becomes redundant at the new default).
- Modify `lib/features/chores/chore_form/assignment_fields.dart` — pin the two
  `FilterChip` avatars to an explicit `radius: 12` (correction C7): status quo,
  with the reason at the call site.
- Modify `docs/specs/members-management.md`, `docs/backlog.md`.
- Test: `test/features/members/member_avatar_test.dart`.

**Interfaces produced:** `double memberAvatarRingWidth(double scaledRadius)`
and `double memberAvatarFontSize(double scaledRadius)` — pure, no
`BuildContext`, called by `MemberAvatar.build` and by the fit test.
`MemberAvatar`'s constructor signature is unchanged apart from its `radius`
default. No `semantic()` id is added, removed or moved by this task.

- [x] **Step 1 (RED).** Extract the two formulas; add the analytical fit test.
  The test must (a) read the default off `const MemberAvatar(...).radius`
  rather than hard-coding it, (b) enumerate every radius `lib/` uses where the
  widget controls its own box, at scale 1.0 and 1.6, (c) carry the chip-forced
  radius 12 as an explicitly-asserted **failing** configuration, so the shipped
  test demonstrates it can discriminate. Push; CI must go red with
  `radius 16.0 at scale 1.0 ... reaches 12.211 ... inner edge is only 10.500px`
  — i.e. the default is still 12 and the enumeration is driven by it.

- [x] **Step 2 (GREEN).** Bump the default to 16, pin `letterSpacing: 0`, fix
  the call sites listed above, update the four widget tests that hard-code the
  24px box / 1.5px ring, update the spec and the backlog. Push; CI green.

- [ ] **Step 3 (inversion).** Raise `memberAvatarFontSize`'s floor from 11.0 to
  12.5 inside the function body — a stand-in for "someone raised the legibility
  floor without growing the ring". CI must fail at the *test* step on the
  `(16, 1.0)` case. Revert; CI green again.

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
