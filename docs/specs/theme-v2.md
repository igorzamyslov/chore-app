# Spec: Theme v2 — "warm paper" / "lamp on in the kitchen"

*Status: BINDING for all UI work from 2026-08-06. Source of truth: the
Claude Design project `Famdo Light + Dark`
(<https://claude.ai/design/p/401f8c45-5659-4f30-9760-847eb7965636>), files
`Famdo Light + Dark.dc.html` (canvas, tokens, rationale) and
`Famdo Screen.dc.html` (per-screen layout). This spec transcribes that
design into binding Flutter terms; where the two disagree, this spec wins,
because it is the one that names Flutter roles.*

*This spec AMENDS `docs/specs/design-language.md`. Every amendment is
listed in §7 with its reason. design-language.md remains binding for
everything §7 does not overturn.*

## 0. The one rule that outranks the design

**The design is a visual language, not a feature list.** It was drawn from
a subset of the app's screens and does not show every control that exists
(filter bar, banners, sync-state rows, join flow, category management,
member management…). Therefore:

- **No existing feature may be removed to match a mockup.** If the design
  omits a control the app has, restyle it in the new language and keep it.
- **No `semantic(...)` id may be removed, renamed, or moved to a different
  widget.** The 12 Maestro flows and 636 widget tests address the UI
  through those ids; they are API. Adding new ids is fine.
- **No l10n key may be deleted**, and no user-facing string may be
  hardcoded — new copy needs new ARB keys in EN + DE (du-form).
- When the design implies a behavior change (not just a look), it is out of
  scope for the theme waves and belongs in its own spec.

## 1. Palette

Two hand-authored `ColorScheme`s. `ColorScheme.fromSeed` is **retired** —
the tonal-palette algorithm cannot express a warm neutral ramp with a
low-chroma teal accent, which is the entire point of this design.

### 1.1 ColorScheme roles

| Role | Light | Dark |
| --- | --- | --- |
| `surface` (ground) | `#F6F1E9` | `#161311` |
| `surfaceContainerLow` (cards) | `#FFFDF9` | `#211C18` |
| `surfaceContainerHigh` (inset rows) | `#EFE8DD` | `#1C1815` |
| `outlineVariant` (hairline) | `#E3DACB` | `#332C25` |
| `outline` (control edges) | `#CFC4B2` | `#4A4137` |
| `onSurface` | `#241F19` | `#F0E9DF` |
| `onSurfaceVariant` | `#5A5147` | `#B6AA9C` |
| `primary` | `#1E7A6E` | `#63C9B8` |
| `onPrimary` | `#FFFDF9` | `#0E2622` |
| `primaryContainer` | `#DDEDE8` | `#1D3833` |
| `onPrimaryContainer` | `#0E2622` | `#B9D8D0` |
| `error` | `#B44A2E` | `#E58A6C` |
| `onError` | `#FFF6F2` | `#2A120A` |
| `errorContainer` | `#FBEDE7` | `#241812` |
| `onErrorContainer` | `#B44A2E` | `#E58A6C` |
| `inverseSurface` (snackbar) | `#2B2620` | `#EFE7DC` |
| `onInverseSurface` | `#F3EDE4` | `#231E19` |
| `inversePrimary` | `#6FC7B7` | `#1E7A6E` |
| `scrim` | `#241F19` @ 42% | `#0A0806` @ 64% |

`secondary`/`tertiary` mirror `primary` (this design has no second accent);
`surfaceContainer`, `surfaceContainerHighest`, `surfaceDim`, `surfaceBright`
interpolate between `surface` and `surfaceContainerHigh` — pick values on
the same warm ramp, never Flutter's defaults, or M3 widgets will punch grey
holes in the warm ground.

### 1.2 `FamdoColors` — the roles M3 has no slot for

A `ThemeExtension<FamdoColors>` registered on both themes, read as
`Theme.of(context).extension<FamdoColors>()!`. Never read these off a
global constant — that would break the light/dark switch.

| Field | Light | Dark | Used by |
| --- | --- | --- | --- |
| `primaryOutline` | `#B9D8D0` | `#2C544C` | accent-bordered cards, selected chips |
| `errorOutline` | `#EBD2C6` | `#43291D` | overdue tile border |
| `errorChip` | `#F4DDD3` | `#3A241A` | overdue due-chip ground |
| `onMemberColor` | `#FFFFFF` | `#1A1612` | initials on a member avatar |
| `navBarBackground` | `#F1EBE1` | `#1B1714` | bottom tab bar |
| `categoryTones` | see §1.3 | see §1.3 | category + member colors |

Shadows (`lift`, `fabShadow`, `sheetShadow`) also live here as
`List<BoxShadow>`; the design's elevation is edge + ambient, never M3's
tint-based elevation, so **every `Card`/`Material` stays `elevation: 0`**
and gets its depth from a 1px `outlineVariant` border plus these shadows.

### 1.3 Category + member tone mapping

The 8 seeded colors in `CategoryRepository.seedColors` are used for both
categories and members. They are stored as ARGB ints and **must never be
rewritten** — sync would replicate the rewrite to every device. The theme
maps them at render time:

| Seed (stored) | Light render | Dark render |
| --- | --- | --- |
| `#6D9F71` Cleaning | `#4E7E54` | `#93C297` |
| `#8C7BC9` Kitchen | `#6B57B0` | `#B4A5E8` |
| `#D98E73` Laundry | `#B96A4C` | `#F0AF95` |
| `#5FA8B8` Garden | `#3F8697` | `#8ACBD9` |
| `#C98CA7` Pets | `#A86485` | `#E7AEC6` |
| `#B8A15F` Maintenance | `#8E7833` | `#DBC585` |
| `#7B93C9` Errands | `#5A73AD` | `#A4B8E5` |
| `#A9A9A9` Other | `#77716A` | `#C8C4BE` |

Reason: 12sp category labels drawn in the raw seed clear 4.5:1 on neither
ground. The map darkens on paper and lightens on the dark ground.

API: `Color categoryTone(BuildContext context, int storedArgb)`. A color
that is not one of the eight (possible via sync from a future picker, or an
imported archive) falls back to an HSL lightness clamp — light: lightness
clamped to ≤ 0.42; dark: clamped to ≥ 0.70 — so unknown colors degrade
gracefully instead of becoming unreadable.

**Avatars are the exception**: a member avatar is a filled circle in the
tone color with `onMemberColor` initials, so the tone map applies to the
fill and `onMemberColor` to the text. Do not re-derive avatar text color
with `estimateBrightnessForColor` any more — the tone map already
guarantees the pairing.

## 2. Typography

**Inter**, bundled as static TTFs (Regular 400 / Medium 500 / SemiBold 600 /
Bold 700) under `assets/fonts/`, declared in `pubspec.yaml`. Not
`google_fonts` — that fetches at runtime, which breaks the offline-first
promise and F-Droid's reproducibility. Inter is SIL OFL 1.1; ship
`assets/fonts/Inter-LICENSE.txt` and credit it in the About screen's
licenses page (Flutter's `LicenseRegistry` — register it at startup).

The design's weights 550/650 do not exist as static cuts: **550 → `w600`,
650 → `w600`**.

`TextTheme` (the app's only source of sizes — widgets reference roles,
never literals):

| Role | Size | Weight | Letter-spacing | Used for |
| --- | --- | --- | --- | --- |
| `headlineMedium` | 32 | 600 | −0.9 | Welcome wordmark |
| `headlineSmall` | 21 | 600 | −0.5 | App bar titles |
| `titleLarge` | 19 | 600 | −0.4 | Progress line, dialog title |
| `titleMedium` | 15.5 | 600 | −0.15 | Chore tile titles |
| `titleSmall` | 15 | 500 | −0.1 | Settings rows, shopping items |
| `bodyLarge` | 15 | 400 | 0 | Sheet rows, field values |
| `bodyMedium` | 14 | 400 | 0 | Dialog body, descriptions |
| `bodySmall` | 12.5 | 400 | 0 | Tile metadata, sub-labels |
| `labelLarge` | 13.5 | 600 | 0 | Buttons, segmented controls |
| `labelMedium` | 11.5 | 600 | 0 | Due chips |
| `labelSmall` | 10.5 | 700 | +1.2 | Section headers, group titles (uppercase) |

Uppercase section headers are produced by the widget
(`Text(label.toUpperCase())`) — never by an ARB string that is already
uppercase, because German capitalization rules differ and the translator
must see the natural-case source.

## 3. Shape, spacing, elevation

- **Cards** (`DepthCard`, group cards, aisle cards): radius **16**,
  `surfaceContainerLow`, `elevation: 0`, 1px `outlineVariant` border,
  `lift` shadow on raised cards (progress card, quick-add, welcome create
  card) and no shadow on plain list cards.
- **Sheets**: radius 24 on the top corners, drag handle 34×4 in
  `outlineVariant`, `sheetShadow`.
- **Dialogs**: radius 24, 1px `outlineVariant` border, 24 padding.
- **Inset rows / segmented tracks / quiet sections**: radius 12–16,
  `surfaceContainerHigh`.
- **Chips**: radius 20 (full pill). Selected = `primaryContainer` fill +
  `primaryOutline` border + `onSurface` text. Unselected =
  `surfaceContainerLow` fill + `outlineVariant` border +
  `onSurfaceVariant` text.
- **FAB**: 58×58, radius **20** (squircle, not a circle), `primary` fill,
  `fabShadow`.
- **Buttons**: filled = radius 14, height 48, `primary`/`onPrimary`,
  `labelLarge`. Text buttons keep `primary` ink.
- **Spacing** stays on the 4dp grid (design-language.md §Foundations). The
  design's 11/13/18/22px paddings round to the nearest grid value; do not
  transcribe them literally.

## 4. Per-screen structure

Each item below is a wave deliverable. Semantic ids in `code` already exist
and must survive; ids marked *(new)* are to be added.

### 4.1 Chores (wave T2)

1. **Day progress card** *(new)* — raised card at the top of the list:
   uppercase date (locale-formatted, `intl`), `titleLarge` "N of M done
   today", `bodySmall` sub-line ("K still to go" / "That's everything —
   nice work"), and a 58dp progress ring on the right (`CustomPainter`,
   `outlineVariant` track + `primary` arc + centered percentage).
   - **M** = still-pending occurrences due today or overdue **plus**
     occurrences completed today. **N** = occurrences completed today.
   - No animation on the arc (see §7, motion rule holds).
   - Semantic id `chores.progress` *(new)*; the ring is decorative, the
     card carries a screen-reader label of the same sentence.
2. **Section headers** — `labelSmall` uppercase in `onSurfaceVariant`
   (`error` for Overdue), a 1px `outlineVariant` rule filling the
   remaining width, then the item count. Replaces the current
   whitespace-only header.
3. **Occurrence tile** — the complete control becomes a **26dp ring inside
   a 48dp tap target** (`outline` border when open; filled `primary` with
   an `onPrimary` check when done), keeping id
   `chores.occurrence.<id>.complete`. Metadata row: a 7dp category dot +
   category name in `categoryTone`, then the member avatar + first name.
   Due text moves to a trailing **chip** (`surfaceContainerHigh` /
   `onSurfaceVariant`). The note line stays. `more_vert` keeps id
   `chores.occurrence.<id>.menu`.
4. **Overdue treatment (design option C)** — tile ground
   `errorContainer`, border `errorOutline`, a 3dp `error` left edge, and
   the due chip in `errorChip`/`error`. The text still says how late it
   is: color is never the only signal.
5. **Paused / Done today** — `surfaceContainerHigh` rows with a leading
   icon, a count in the header, and a chevron; expanded children are
   hairline-separated rows inside the same card. Existing ids stay.
6. **Empty state** — 76dp `primaryContainer` tile with a
   `primaryOutline` border and an `add_task` glyph, `titleLarge` headline,
   then one `bodyMedium` line naming what the + button does.

### 4.2 Settings (wave T3)

The flat `ListView` becomes **labelled groups**, each a `labelSmall`
uppercase header followed by one card whose rows are hairline-separated:

| Group | Rows |
| --- | --- |
| Household | Members, Categories |
| Preferences | Language, Appearance, Daily summary (+ time, + permission hint) |
| Account | sync state / sign-in, invite |
| Data | Export, Reset (only row in `error`, last) |
| About | version, licenses, donate |

Rows show their **current value on the right** (`English`, `System`,
`08:00`) instead of hiding it behind the tap; a row has either a value, a
switch, or a chevron — never two. About stays a real group (the design's
version footer omits licenses/donate, which the MIT+F-Droid release
requires).

### 4.3 Shopping (wave T4)

1. **Quick-add** becomes a raised pill card (`surfaceContainerLow`,
   `primaryOutline` border, `lift`): leading search glyph, the field, and a
   42dp filled `primary` submit square with `add`. Existing ids stay.
2. **Suggestion chips** sit directly under it (already implemented — only
   restyled to §3's chip spec).
3. **Aisles**: one card per category, header above it (category icon +
   uppercase name, both in `categoryTone`, plus a hairline rule); items are
   hairline-separated rows inside that one card — not one card per item.
   The check control is a 23dp ring in a 48dp target.
4. **In the cart** collapses to one `surfaceContainerHigh` row with the
   count and an inline Clear action.

### 4.4 Chore form (wave T5)

- Fields become **filled cards with a permanently visible uppercase
  label** above the value (`primaryOutline` border when focused,
  `outlineVariant` otherwise). No floating labels.
- Interval unit and assignment mode become **segmented controls** on a
  `surfaceContainerHigh` track (selected = `surfaceContainerLow` +
  `primary` ink).
- Weekdays become a row of circular toggles (selected = `primary` fill).
- The anchor choice becomes **two explanatory radio cards** naming the
  actual interval (selected = `primaryContainer` + `primaryOutline`).
- Rotation chips show turn order on the chip ("1. Anna", "2. Ben").
- Category chips carry the category dot in `categoryTone`.

### 4.5 Welcome + overlays (wave T5)

- **Welcome**: create is a raised `primaryOutline` card with the name field
  already visible and a filled 48dp "Get started"; join is a quiet
  secondary row with a chevron; the offline promise is `bodySmall` at the
  bottom. Ids `welcome.create`, `welcome.create.name` and the Enter-submit
  behavior are unchanged — the E2E suite depends on both.
- **Action sheet**: full-width rows, 22dp icons, 48dp height; delete last,
  in `error`.
- **Delete dialog**: a 44dp `errorContainer` icon tile above the title;
  title = the consequence; body = one line; actions Cancel + filled
  destructive.
- **Snackbar**: `inverseSurface` ground, `inversePrimary` leading check and
  UNDO label, radius 14, floating above the tab bar. Must keep
  `showAppSnackbar`'s `persist: false` fix.
- **Bottom tab bar**: `navBarBackground` with a top hairline; the active
  destination gets a 62×30 `primaryContainer` pill behind a filled icon,
  label in `primary`; inactive in `onSurfaceVariant`. The hand-rolled bar
  and its `shell.tab.*` ids stay exactly as they are.

## 5. Accessibility

- Every interactive target stays ≥ 48×48dp — the design's 26dp ring and
  23dp checkbox are *visual* sizes inside a 48dp `InkWell`/`IconButton`.
- Contrast: every pairing in §1 was authored to clear 4.5:1 for text and
  3:1 for UI edges. Any new pairing must be checked, not assumed.
- Text scale 2.0 is a release gate (design-language.md §Definition of
  visual done). The progress ring and the due chips are the two known
  overflow risks — the ring gets a fixed size and its percentage text
  `TextScaler.noScaling` (it is decorative and duplicated in the sentence
  beside it); due chips wrap.

## 6. Verification

- All 636 existing tests stay green; tests asserting on removed widget
  *types* (e.g. `IconButton` with `Icons.circle_outlined`) are updated to
  assert on the semantic id instead — never deleted.
- All 12 Maestro flows stay green locally **and** in CI before any wave
  merges.
- Visual QA per design-language.md: light + dark, text scale 1.0 and 2.0,
  on a Pixel-class emulator, before the release tag.

## 7. Amendments to `design-language.md`

Each one is a deliberate, reasoned break, per that spec's own "deviations
need a reason" clause:

1. **Seed → hand-authored schemes.** `ColorScheme.fromSeed(0xFF26A69A)`
   cannot express warm neutrals with a low-chroma accent. The accent
   remains the product's own teal, deepened/lifted per ground.
2. **Card radius 12 → 16**, FAB → 20 squircle. Serves the "cosy, not
   enterprise" brief the spec itself asks for.
3. **Typography: M3 defaults → Inter with an explicit type scale.** The
   underlying rule — *widgets never hardcode sizes, they reference
   `textTheme` roles* — is unchanged and still binding.
4. **Overdue may tint its container.** The old rule ("error color for the
   due-label text only… no red tiles") is relaxed to the design's option C:
   `errorContainer` ground + `error` left edge + `error` chip. This was
   explored against two quieter alternatives and chosen deliberately. The
   companion rule — *color is never the only signal* — is untouched and
   still requires the "N days late" text.
5. **Section headers gain a hairline rule and a count.** The old "no
   divider lines — whitespace separates" applies to *rows*; headers now
   need to read as structure rather than as more list items.
6. **Chips: selected state uses `primaryContainer` + `primaryOutline`**,
   not `secondaryContainer` — this design has no secondary accent.
7. **Elevation is edge + ambient shadow, never M3 surface tint.** All cards
   stay `elevation: 0`.

Unchanged and still binding: the 4dp grid, Material Symbols outlined icons,
48dp targets, category color as accent only (a dot and a label — never a
tinted tile), **no custom animation** (E2E determinism), l10n for every
string, inline validation that never loses input, and the per-screen
definition of visual done.
