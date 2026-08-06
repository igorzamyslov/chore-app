# Spec: Design Language & UX Rules

*How the app should look and feel: clean and welcoming, but functional
first. Every rule here is binding for UI work; deviations need a reason in
the PR/commit message.*

## Feel

A household tool, not an enterprise dashboard: calm, warm, a little
friendly — never cluttered, never gamified-loud. The user opens it for 10
seconds, sees what matters (what's due, what to buy), acts, leaves.

## Foundations

*Color source, typography and shape below are amended by
`docs/specs/theme-v2.md` §7 (amendments 1, 3, 2) — that spec's §1–§3 are now
the binding detail; the bullets here are kept for context and for the rules
theme-v2 does NOT touch.*

- ~~**Material 3**, `ColorScheme.fromSeed(0xFF26A69A)` (calm teal-green),
  light + dark from the same seed~~ — **retired** (spec `theme-v2.md` §7.1):
  two hand-authored warm light/dark `ColorScheme`s (spec `theme-v2.md` §1),
  `ThemeMode.system` unchanged.
- **Typography**: ~~M3 defaults only~~ — **Inter**, bundled, with an
  explicit type scale (spec `theme-v2.md` §2, §7.3), referenced via
  `Theme.of(context).textTheme` — still never hardcoded font sizes.
  Hierarchy through style roles (titleMedium for tile titles, bodySmall for
  metadata), not through bold everywhere.
- **Spacing**: 4dp grid. Allowed values: 4, 8, 12, 16, 24, 32. Screen edge
  padding 16. Vertical rhythm between sections 24.
- **Shape**: ~~M3 defaults (12dp cards/sheets). No custom radii.~~ — cards
  16dp, FAB 20dp squircle, sheets/dialogs 24dp (spec `theme-v2.md` §3, §7.2).
- **Motion**: standard M3 transitions ONLY (also mandated by
  testing-strategy determinism). No custom animation code.
- **Icons**: Material Symbols outlined style throughout (`Icons.*_outlined`
  where a variant exists). Category icons tinted in the category color;
  all other icons use onSurface/onSurfaceVariant. Never two icon styles in
  one view.

## Color usage rules

*The overdue bullet below is amended by `docs/specs/theme-v2.md` §7.4 — see
that spec for the current binding rule.*

- The seed palette does the work; **category color is an accent, not a
  background** — used for the category icon + chip text/outline, never for
  whole tiles (keeps the list calm and readable).
- ~~Overdue = `colorScheme.error` for the due-label text only — signal, not
  alarm. No red tiles, no badges with counts screaming at the user.~~ —
  **relaxed** (spec `theme-v2.md` §7.4, design option C): overdue MAY tint
  its tile's container (`errorContainer` ground, `error` left edge, `error`
  due-chip) — still signal, not alarm: no counts, no shouting, and color is
  still never the only carrier (see the next bullet).
- Color is never the only carrier of meaning: overdue also says
  'Overdue · Tue' in text; categories also show name; checked items also
  strikethrough.
- Contrast: stick to onSurface/onSurfaceVariant roles (M3 guarantees
  ratios); never place text on category colors directly.

## Interaction rules (the common-UX-rules contract)

1. **Primary action per screen, thumb-reachable**: chores → FAB 'Add
   chore'; shopping → pinned quick-add row. One primary action, visually
   dominant; everything else is secondary.
2. **The most frequent action gets the biggest target**: completing a
   chore / checking an item is the leading 48dp control on every tile.
   ALL touch targets ≥ 48×48dp (M3 minimum) — enforce with padding, not
   hope.
3. **Destructive actions**: never in primary position; styled with error
   color; chore delete confirms via dialog (it erases a pending occurrence
   and hides history); shopping-item delete doesn't confirm (cheap,
   low-stakes) — prefer undo-snackbars over confirms when we add them
   (backlog, not v1).
4. **Progressive disclosure**: forms show the simple case first (one-off
   chore = title + save); recurrence, assignment details reveal on demand.
   Smart defaults everywhere: start date = today, weekly pre-selects
   today's weekday, interval = 1.
5. **Empty states teach**: icon + one friendly sentence + the action that
   fixes it ('No chores yet — add the first one'). Never a blank screen,
   never an error-looking empty state.
6. **Feedback is immediate**: local writes are fast — UI reflects within a
   frame via streams; no spinners after taps (spinners only for initial
   load). Errors show as inline text where the user is looking, not
   toasts that vanish.
7. **Never lose user input**: validation happens on save, errors inline
   under the exact field, entered values always preserved (recovery is an
   E2E-tested requirement).
8. **Respect the system**: dark mode always; dynamic type up to 2.0 tested
   without overflow; no orientation lock; standard back behavior.
9. **Copy tone**: sentence case (M3), short, concrete, warm but not cutesy
   ('Shopping list is empty', not 'Oops! Nothing here! 🎉'). No jargon —
   'Repeats every 2 weeks on Sat', not 'RRULE'.
   **All user-facing strings go through l10n (ARB keys; English template,
   German first translation)** — no hardcoded copy in widgets, no
   hardcoded weekday/month names (use intl date formatting). String
   concatenation is forbidden where word order differs across languages;
   use placeholders in the ARB template instead.
10. **Density**: comfortable but information-forward — a tile is title +
    one metadata line, max. Anything more belongs behind the tap.

## Component patterns

*Section headers and chips below are amended by `docs/specs/theme-v2.md`
§7.5, §7.6 — see that spec's §3–§4 for the current binding detail.*

- **Occurrence tile**: [48dp complete-circle] Title (titleMedium) /
  metadata row (bodySmall, onSurfaceVariant): category chip · assignee ·
  due text (error color when overdue). Trailing overflow menu (44dp+).
- **Section headers**: labelLarge, onSurfaceVariant, 24 top / 8 bottom
  padding. ~~No divider lines — whitespace separates.~~ — **amended** (spec
  `theme-v2.md` §7.5): headers gain a 1px `outlineVariant` hairline rule
  filling the remaining width, plus an item count; the "no divider lines"
  rule still holds for rows, just not for headers, which now need to read
  as structure rather than as more list items.
- **Chips** (categories, weekdays, members): M3 FilterChip/ChoiceChip
  defaults; ~~selected state uses secondaryContainer, not custom colors~~ —
  **amended** (spec `theme-v2.md` §7.6): selected state uses
  `primaryContainer` fill + `primaryOutline` border (this design has no
  secondary accent); unselected uses `surfaceContainerLow` fill +
  `outlineVariant` border.
- **Sheets**: modal bottom sheets with a drag handle, 16 padding, actions
  right-aligned; the sheet's primary action is a FilledButton.
- **Dialogs**: only for destructive confirms. Title = the consequence
  ('Delete chore?'), body = one line of specifics, actions = 'Cancel' +
  destructive-colored verb ('Delete').

## Depth / cards

*Amended by `docs/specs/theme-v2.md` §7.2, §7.7 — see that spec's §3 for the
current binding detail.*

- List content sits in solid cards, not directly on the plain background:
  `DepthCard` wraps each row/tile in an M3 `surfaceContainerLow` card,
  ~~12dp~~ **16dp** radius (spec `theme-v2.md` §7.2), elevation 0, a 1px
  `outlineVariant` border, `EdgeInsets.symmetric(horizontal: 12, vertical:
  4)` margins. Elevation is edge (that border) plus an ambient shadow
  (`FamdoColors.lift`, on raised cards only) — never M3's surface-tint
  elevation (spec `theme-v2.md` §7.7): every card/sheet/dialog stays
  `elevation: 0`.
- Done/paused sections get one card around the whole `ExpansionTile`
  (header + rows together), not one card per row — the tile already groups
  those rows visually, so per-row cards would double up.
- Headers and empty states stay directly on the plain background — no
  backdrop, no wash.
- **Decision 2026-07-31**: solid cards chosen over a glass-backdrop variant
  after a side-by-side on device; backgrounds stay plain.

## Definition of visual done (per screen)

Screenshot review on iPhone (small: SE-class) + Pixel-class Android, light
+ dark, at text scale 1.0 and 2.0 — no overflows, targets ≥ 48dp, reads
calm at arm's length. This review happens on the simulator/emulator before
a feature is called finished.
