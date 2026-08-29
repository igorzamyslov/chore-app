# G-4 Ring Avatars + G-5b Twelve-Colour Palette — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Widen the shared category/member colour palette from eight to twelve, and turn the member avatar from a filled circle into initials-on-neutral inside a coloured ring — with member colours unique per household.

**Architecture:** Additive, not destructive. The design's twelve `RING` hexes turn out to be the eight existing colours' *already-shipped light-theme renders* plus four new ones (see "The premise, re-verified" below), so this is an extension of `CategoryRepository.seedColors` into a new `CategoryRepository.palette`, four new hand-picked entries in `theme.dart`'s tone table, and a render-time change to `MemberAvatar` and `ColorSwatchPicker`. **No schema migration. No stored-colour rewrite. Schema stays at v12.**

**Tech Stack:** Flutter, Riverpod, drift, gen_l10n, very_good_analysis.

---

## Refresh pass, 2026-08-29 (wave 6 execution)

This plan was written 2026-08-18, before wave 5 landed. Every file it targets
was re-read as it now stands and every numeric claim was recomputed. What
changed:

**Line numbers that moved** (all cited references below are corrected in place):
`member_edit_sheet.dart` grew — `_firstFreeColor` is at **188-194** (not
116-121), the `colors:` argument at **228** (not 156), the sheet's doc comment
at **28-33** (not 21-23), the colour section in `build` at **224-232** (not
152-159), and the name listener at **102-103 / 115** (not 62/66).
`members_screen_test.dart`'s recolor test is at **197-247** (not 163-214), its
`CircleAvatar` block at **231-246** (not 195-211), and its
`members.edit.color.2` tap at **216** (not 181). `theme.dart`'s `_categoryTones`
is at **488-506** (not 489-506). `docs/backlog.md` shifted by ten: G-4 is at
**318** (not 308), G-5 at **319** (not 309), the "Not planned" list at **170**
(not 160), the ownership note at **311** (not 301). `member_avatar.dart`'s
one-letter derivation is at **40-43** (not 41-44). Everything else the plan
cited — the ARB anchors at `app_en.arb:976-979` and `app_de.arb:212`,
`category_edit_sheet.dart:82-86, 129, 23`, `manage_members_screen.dart:144`,
`join_flow_steps.dart:56-70, 29-33, 186`, `chore_occurrence_tile.dart:353`,
`category_edit_test.dart:60, 126-129` — is still exactly where the plan said.

**Claims re-verified and still true:** the eight light renders match the
canvas byte-for-byte; `#1E7A6E` is byte-for-byte `_lightPrimary`;
`theme-v2.md` contains no picker/swatch exemption (grepped for "swatch",
"picker", "exempt" — only one unrelated hit); no Maestro flow references any
`color.N` id; no golden tests exist; nothing outside this plan's file set
asserts a palette size or a swatch count; the bootstrap member really does hold
`seedColors.first`; the plum's HSL lightness really is **0.4216**, so without an
explicit light row `categoryTone` returns `#993D80`; the four dark fallbacks
really are `#D491C1` / `#DAA98B` / `#AE9BCA` / `#A8C3A2` and the violet's light
fallback really is `#654A8C`.

**Three numeric claims that were WRONG and are corrected below:**

1. *"Dark renders, worst case: `#B9A8D1` at 7.70."* The true dark worst case is
   `#B4A5E8` (Kitchen, pre-existing) at **7.63**. `#B9A8D1` is 7.70, second
   worst. Every render still clears 3:1 on every ground in both themes, which is
   the only bar the tests assert, so nothing downstream changes.
2. *"The palette's own tightest existing pairs are ΔE 7.8 in light … and 9.3 in
   dark … Every colour this plan adds sits further from its nearest neighbour
   than that."* **False, and self-contradictory:** both of those pairs *involve
   the colours this plan adds* (`#6B57B0` vs the new `#7A5AA8`; `#F0AF95` vs the
   new `#DFB49A`). The eight existing colours' own tightest pairs are ΔE **25.8**
   light (`#6B57B0` vs `#5A73AD`) and **17.8** dark (`#B4A5E8` vs `#A4B8E5`).
   The honest statement is the opposite of the plan's: **this plan tightens the
   palette's minimum separation from 25.8 to 7.8 in light and from 17.8 to 9.3
   in dark.** Both floors remain well above the ~2.3 just-noticeable difference
   and above the ~5 at-a-glance threshold, and the two-letter initials — not the
   ring colour — are what carries identity for a viewer who cannot separate two
   purples. Kept, with the rationale corrected rather than the colour changed:
   `#7A5AA8` is the design canvas's own choice and overriding it on a ΔE
   argument would re-open a decision the canvas closed. R1's substitution stands
   on the *semantic-role collision* argument, which is untouched by this.
3. The Self-review notes listed `#84E1D5` among the pre-fix dark fallbacks. That
   is the fallback for the **rejected** teal `#1E7A6E`, left over from the
   pre-R1 draft; the plum's is `#D491C1`. Corrected.

**Two plan-authored test snippets that do not compile or cannot pass, fixed
below:**

- Task 5's preview assertion does
  `tester.widget<MemberAvatar>(find.bySemanticsIdentifier('members.edit.avatar').first)`.
  That id wraps a `Row`, not the avatar, so the cast fails at runtime. Corrected
  to a `find.descendant(... matching: find.byType(MemberAvatar))`.
- Task 3's "two letters fit inside the smallest avatar" assertion compares the
  glyph width against the ring's *inner* diameter using arithmetic derived from
  Inter (~1.35 em for two uppercase glyphs). **That property cannot be asserted
  in a widget test in this repo at all**, which took three CI measurements to
  establish and is recorded here so nobody re-derives it:
  - There is no `flutter_test_config.dart` anywhere and nothing calls
    `FontLoader`, so `flutter test` draws the Ahem-style `FlutterTest` font.
    **Measured: `'WM'` at 11px/w600 is 21.87px — 1.99 em per glyph.** The same
    21.87 comes back whether the family is inherited from the theme or set
    explicitly to `'Inter'`.
  - Adding a `FontLoader('Inter')` over the bundled TTFs in `setUpAll` did
    **not** change that number. The fonts are declared under pubspec `fonts:`
    rather than `assets:`, so `rootBundle.load` hands the loader nothing usable
    and it silently no-ops — no exception, no effect.
  - So in the test font `'WM'` wants 21.87px inside a 21px ring, wraps, and the
    paragraph reports its own constraint (21.0). A containment check against
    that box therefore passes regardless of the avatar's geometry (**vacuous**),
    and a strict inner-diameter check fails on correct code (**false**).
  The test now asserts only what is font-independent — the 24px box, the ring
  width, the 11px floor, the text-scale cap, and that nothing throws — and says
  so in a comment at the top of the file. The plan's *arithmetic* stands and the
  production code is correct: Inter really does fit ~15px of glyphs in 21px of
  room. It is the *measurement* that this harness cannot perform, so glyph fit
  stays a visual-QA gate (`design-language.md`, definition of visual done).
  Backlogged as **G-14**.

---

## The premise, re-verified — and what it overturns

> ### READ THIS BEFORE COMPARING THE DESIGN CANVAS TO ANY COLOUR CONSTANT
>
> **`CategoryRepository.seedColors` holds STORED values. The design canvas
> draws RENDERED values. They are different numbers for the same colour, on
> purpose, and comparing the two produces a false "nothing matches" result.**
>
> This plan was originally commissioned as a palette *replacement* with a v13
> data migration, on the strength of the observation that not one of the
> canvas's twelve `RING` hexes appears in `seedColors`. That observation is
> true and the conclusion drawn from it is wrong. `seedColors` is the stored
> ARGB column value; the canvas is a picture of the **light theme**, so its
> hexes are what `categoryTone(context, storedValue)` *returns* under
> `appLightTheme`. The correct comparison is against the `light` column of
> `_categoryTones` in `lib/app/theme.dart` — and there, eight of the twelve
> match byte-for-byte, in order.
>
> Anyone re-checking this plan's premise, or comparing a future design canvas
> to the palette, must map through `categoryTone` first. Diffing raw
> `seedColors` against a canvas will always look like a total mismatch, and
> will always suggest a migration that spec `theme-v2.md` §1.3 forbids.

Three verified facts:

**1. The design's first eight hexes ARE the app's existing light-theme renders,
in the same order.**

`RING` (from `famdo_design.html:496`):

```
#4E7E54 #6B57B0 #B96A4C #3F8697 #A86485 #8E7833 #5A73AD #77716A  ← existing light renders
#1E7A6E #96562F #7A5AA8 #4C6B45                                   ← genuinely new
   ↑
   substituted to #9A3D80 — see "R1" below; #1E7A6E is the app's own accent
```

`_categoryTones` in `lib/app/theme.dart:488-506` maps
`0xFF6D9F71 → light 0xFF4E7E54`, `0xFF8C7BC9 → light 0xFF6B57B0`, … through all
eight, in exactly that order. Byte-for-byte identical, verified. The design is
not proposing different colours; it is showing the *rendered* form of the eight
we already ship, and adding four. "Not one hex matches" was true only against
the *stored canonical* values, which the design never displays.

**2. Rewriting stored colours is forbidden by a binding spec, for a reason that
still applies.** `docs/specs/theme-v2.md` §1.3: *"They are stored as ARGB ints
and **must never be rewritten** — sync would replicate the rewrite to every
device."*

**3. That reason is load-bearing, not decorative.** `members` and `categories`
are synced tables (`lib/data/sync/row_mappers.dart:36-47`, `:66-77` push
`color`). A migration that rewrote colours would be wrong either way:

- *Without* `sync_dirty`: `SyncRepository.applyPulledMember`
  (`lib/data/repositories/sync_repository.dart:222-227`) is
  `insertOnConflictUpdate` gated only on the local row being clean, so the very
  next pull replaces the migrated row with the server's old colour. The
  migration is silently undone on every linked household.
- *With* `sync_dirty`: every member and category row on every device goes dirty
  at once and re-pushes. LWW is on `updated_at` (spec `sync-backend.md` §8.3),
  which a migration does not bump, so the winner is undefined and colours flap
  by upgrade order.

Additionally, every migration shipped so far (v2…v12, `app_database.dart:59-190`)
is column-add or index-add; each one's comment says "no data rewrite". A
row-rewriting migration would be the first, and it would be introduced to solve
a problem that does not exist.

**Therefore this plan EXTENDS the palette instead of replacing it.** Consequences,
all of them good:

- Every existing member and category keeps the exact colour it has. No "nearest
  colour" rule is needed at all — the mapping from old to new is the identity —
  so there is nothing to define perceptually, nothing non-deterministic, and no
  collision risk from two members landing on the same nearest colour.
- No v13. `schemaVersion` stays 12; `test/data/db/schema_migration_test.dart`
  is untouched.
- The existing `members.edit.color.0…7` and `settings.categories.color.0…7`
  semantic ids keep their exact current meaning; indices 8-11 are appended. See
  "Semantic ids" below.
- The design's contrast claim is *kept*, not forfeited: it is delivered by
  `categoryTone`'s per-theme table (which the design canvas, being light-only,
  never had to think about), not by what happens to be in the `color` column.

**What is genuinely new work** is therefore: four more colours in the picker,
four more tone-table rows (with dark renders the design does not supply), the
ring avatar, and the uniqueness rule.

### Contrast, verified numerically

The design claims all twelve clear 3:1 against paper and ground. Computed
(WCAG relative luminance) against the three light grounds `#F6F1E9` / `#FFFDF9` /
`#EFE8DD` and the three dark grounds `#161311` / `#211C18` / `#1C1815`:

- Light renders, worst case: `#B96A4C` at **3.30**. All twelve ≥ 3.0. The four
  new ones are the *best* of the twelve (5.15, 4.70, 4.48, 4.94) — they improve
  the palette's floor rather than lowering it.
- Dark renders, worst case: `#B4A5E8` at **7.63** (Kitchen — pre-existing, not
  one of the four added). All twelve ≥ 7.6.

Perceptual separation was checked too, in CIELAB (ΔE76). **Corrected 2026-08-29
— the original text here was backwards.** The eight existing colours' tightest
pairs are ΔE **25.8** in light (`#6B57B0` vs `#5A73AD`) and **17.8** in dark
(`#B4A5E8` vs `#A4B8E5`). Widening to twelve *tightens* that: the closest pair
in the finished palette is ΔE **7.8** in light (`#6B57B0` purple vs the newly
added `#7A5AA8` violet) and **9.3** in dark (`#F0AF95` vs the newly added
`#DFB49A`). Both new floors sit well above the ~2.3 just-noticeable difference
and the ~5 at-a-glance threshold, so twelve remains distinguishable — but the
claim that every added colour is *better* separated than the existing worst pair
was simply false, and the two purples are the closest thing in the palette.

This is survivable precisely because of R2: colour is never the only carrier of
member identity. The two-letter initials, not the ring, are what separate two
similar purples for a viewer who cannot tell them apart. The canvas's `#7A5AA8`
is kept rather than substituted — R1's substitution rests on a *semantic-role
collision* (`#1E7A6E` means "selected"), which is a correctness argument;
"these two purples are close" is a taste argument against a colour the design
deliberately chose, and is not grounds to override it.

Note a pre-existing condition this plan does **not** fix and does not worsen:
theme-v2 §1.3 justifies the tone map with a *4.5:1* bar for 12sp category
labels, but only 3 of the 8 shipped light renders actually reach 4.5:1. That is
true today, on `main`, before this plan. 3:1 is the correct bar for a *ring*
(a UI edge, not text), which is what G-4 introduces. Raising category label
contrast is out of scope; flag it to the backlog, do not fix it here.

### The nullable text column: NOT added

The design's storage note says "one nullable text column on `members`". The
feature as drawn needs none: initials derive from `name`, the ring reads the
existing `color` column. The only conceivable use is an initials override
("Anna Maria" → "AM"), which the design does not otherwise describe, does not
draw a control for, and does not mention in any of its four `g4notes`.

Against that speculative use, the cost is concrete and large: `members` is a
*synced* table, so a column there is not one drift `addColumn` — it is a
Supabase migration (`supabase/migrations/`), an RLS UPDATE grant alongside
`name`/`color`/`role` (spec `sync-backend.md` §8.3), both directions of
`row_mappers.dart`, and pull/push test coverage. **Decision: leave it out.**
Schema is unchanged in both databases. If an initials override is ever wanted,
it is its own ticket with its own spec.

### Semantic ids

`spec theme-v2.md` §0 forbids removing, renaming, or moving any `semantic(...)`
id. Nothing is removed or moved here. `ColorSwatchPicker` emits
`'$semanticIdPrefix.$index'`, and because the twelve are `[...seedColors,
...four]`, **indices 0-7 still address exactly the colours they address today**;
8-11 are new. Verified: no Maestro flow references either id family (grepped
`e2e/**`; `members_and_acting.yaml` and `category_edit_persists.yaml` contain no
`color` reference). The only two references anywhere are widget tests —
`test/features/settings/members_screen_test.dart:216`
(`members.edit.color.2`) and `test/features/settings/category_edit_test.dart:60`
(`settings.categories.color.1`) — and both keep meaning the same colour.

### More than twelve members

With uniqueness and twelve colours, a thirteenth member has nothing free.
Blocking member creation over a colour would be absurd, so **the rule relaxes
instead of the roster**: when every palette colour is already taken by another
active member, the member edit sheet passes an *empty* taken-map, every swatch
is enabled, and duplicates are permitted. Uniqueness is UI guidance, never a
database constraint — a constraint would also be wrong under sync, where two
devices can concurrently claim the same colour and the loser's save must not
fail.

---

## Resolved product decisions

Two user-visible choices that could not be derived from the design canvas.
**Both are now settled** and the tasks below implement the settled answer; they
are recorded here with their reasoning because the canvas draws something
different in each case, and a future reader comparing plan to canvas will
otherwise think the plan is wrong.

### R1 — slot 9 is substituted: `#1E7A6E` → `#9A3D80` plum

**The problem, verified:** `RING[8]` is `#1E7A6E`, which is byte-for-byte
`_lightPrimary` (`lib/app/theme.dart:42`) and the `primary` role in theme-v2
§1.1. Its dark render would sit in the same hue family as `_darkPrimary`
`#63C9B8`.

**Why this is disqualifying and not merely unattractive:** in this UI the accent
*means* "interactive / selected" — it is the FAB, the filled button, the
selected chip, the accent-bordered card. A member ring or category dot drawn in
precisely that colour reads as a **selection state, not an identity**, and it
does so most confusingly on exactly the surfaces where selection is also being
expressed (the assignee chips in the chore form, the acting-member switcher,
the swatch grid itself). Shipping eleven colours instead would needlessly lose a
colour and contradict the design's stated twelve.

**The substitute: `#9A3D80`** — a muted plum at hue 317°, HSL S 0.43, L 0.42,
which puts it inside the palette's own saturation range (the existing eleven run
0.06–0.52). Chosen by searching hue/saturation/lightness space under four
constraints and taking the best-separated muted result:

| Check | Requirement | `#9A3D80` |
| --- | --- | --- |
| Light contrast, worst of the three light grounds | ≥ 3.30 (the palette's floor) | **5.15** |
| Dark contrast, worst of the three dark grounds | ≥ 7.63 (the palette's floor) | **7.90** (dark render `#D9A0C9`) |
| ΔE from nearest of the other eleven, light | comfortably clear of JND | **21.7** (nearest: `#A86485` rose) |
| ΔE from nearest of the other eleven, dark | comfortably clear of JND | **10.3** (nearest: `#E7AEC6` rose) |
| ΔE from `_lightPrimary` `#1E7A6E` | far | **78.1** |
| ΔE from `_darkPrimary` `#63C9B8` | far | **62.7** |
| ΔE from `error` `#B44A2E` | far — red is the error role, also semantically loaded | **57.0** |

Both contrast figures are held to the same bar applied to the other three new
colours, in both themes. **Record the substitution wherever the canvas is
cited** (Task 6 does this): the canvas draws teal in slot 9 and the app ships
plum, and that divergence must not read as a transcription error.

### R2 — two letters, as the design draws

The canvas renders two letters (`Anna→AN`, `Igor→IG`, `Mia→MI`, `Leo→LE`;
`famdo_design.html:626-630`). Today the app renders one
(`member_avatar.dart:40-43`). **Two letters ship.**

**Why it is a floor and not a preference:** `design-language.md`'s colour-usage
rules say colour is never the only carrier of meaning. For a colour-blind user
the initials are the *only* channel that separates one member from another, and
one letter halves that channel — "Anna" and "Alex" are indistinguishable at one
letter and separate cleanly at two. The unique ring colour carries identity for
everyone who can see it; the initials must carry it for everyone else.

**The derivation rule, stated explicitly** (the canvas shows `Mia→MI`, i.e. the
first two *letters of one name*, NOT the initials of two names):

- Trim the display name, take its **first two characters**, uppercase them.
- A one-character name yields one character (`"J" → "J"`) — never padded.
- A blank or whitespace-only name yields `"?"`, unchanged from today.
- A name containing a space is not special-cased: `"Anna Maria" → "AN"`, not
  `"AM"`. Word-initials would be a different rule that the canvas does not draw;
  if it is ever wanted it is its own ticket. The one edge this creates —
  a name whose second character is a space, e.g. `"J Smith" → "J "` — is handled
  by trimming the result, giving `"J"`.

**Legibility, verified by arithmetic and then enforced by test — and it forced a
size change.** Two uppercase Latin glyphs occupy about `1.35 × fontSize` in
Roboto/Inter. Usable width inside the ring is about `0.9 × (2·radius − 2·ringWidth)`:

| radius | box | ring | usable width | font | glyph width | verdict |
| --- | --- | --- | --- | --- | --- | --- |
| 10 (today's default) | 20px | 1.5 | 15.3px | 11 | 14.9px | fits with 0.4px to spare — **too tight** |
| **12 (new default)** | 24px | 1.5 | 18.9px | 11 | 14.9px | 4.0px margin — comfortable |
| 21 (members row) | 42px | 2.6 | 33.1px | 15.1 | 20.4px | comfortable |
| 33 (sheet preview) | 66px | 3.0 | 54.0px | 23.8 | 32.1px | comfortable |

So **the chore-tile avatar grows from radius 10 to radius 12** (20px → 24px).
Per the standing instruction, the fix for a legibility shortfall is a bigger
tile avatar, never a drop to one letter — disambiguation is the point of the
feature. `MemberAvatar`'s default radius is the only thing that changes;
`chore_occurrence_tile.dart:353` is its sole user.

**Text scale 2.0 forced a second change.** Today `MemberAvatar` passes
`TextScaler.noScaling`, so at 2.0 the initials would stay 11px while every
surrounding label doubles — no overflow, but the avatar becomes the least
legible thing on screen for precisely the user who asked for larger text. The
avatar therefore now **scales as a whole** (box, ring and font together) by
`MediaQuery.textScalerOf(context).scale(1)`, clamped to `[1.0, 1.6]`. The clamp
keeps a 2.0-scale avatar from bursting `ListTile` leading slots and chip rows;
scaling the box rather than the text alone means the glyphs can never overflow
the ring. At scale 2.0 the tile avatar is radius 19.2 with a 13.8px font and
18.7px of glyphs inside 30.2px of usable width.

A font floor of **11px** (Material's smallest label size) applies, so two
letters never render below the legibility threshold at any radius.

---

## Global Constraints

- **Never run `flutter`, `dart`, `supabase`, or `docker` commands outside the
  test invocations named in this plan.** Tests run as:
  `flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= <file>`
- **Schema stays at v12.** No drift migration, no Supabase migration, no
  `schemaVersion` bump, no change to
  `test/data/db/schema_migration_test.dart`.
- **No stored colour is ever rewritten** (spec `theme-v2.md` §1.3).
- **No `semantic(...)` id may be removed, renamed, or moved** (spec
  `theme-v2.md` §0). Adding ids is fine.
- **All user-visible strings via gen_l10n**: a key in `lib/l10n/app_en.arb`
  *with an `@key` description block*, and the same key in `lib/l10n/app_de.arb`
  (informal du-form; "Gerät", never "Handy"). No hardcoded strings.
- **Lints are strict**: `very_good_analysis`, run with `--fatal-infos`. Every
  public member needs a doc comment (`public_member_api_docs` is on).
- **Widget tests must use the shared bootstrap.** `testChoreApp` and
  `testFreshChoreApp` come from `test/test_utils/pump_app.dart`.
  > **`openSettingsTab` is NOT in `pump_app.dart`.** It, along with
  > `openManageMembers`, `openManageCategories` and `openChoreHistory`, is
  > defined in **`test/features/settings/settings_test_utils.dart`**
  > (`openSettingsTab` at line 13). A widget test needing both must import both
  > files. This has been mis-stated repeatedly in briefs for this repo; verified
  > by grep, and recorded here so the written plan is the thing that is right.

  Address widgets with
  `find.bySemanticsIdentifier` inside a `tester.ensureSemantics()` handle. **A
  hand-rolled `ProviderScope` pump hangs and takes the whole suite with it — do
  not write one.**
- **Reference tests to copy structure from** (read these before writing new
  tests; do not invent a shape from memory):
  - `test/features/settings/members_screen_test.dart` — the recolor test at
    lines 197-247 is the closest analogue for anything touching the member
    sheet's colour picker and the avatar.
  - `test/features/settings/category_edit_test.dart` — lines 40-135 for the
    category sheet's picker and its DB round-trip assertions.
  - `test/app/theme_test.dart` — lines 130-185 for the tone-table assertions
    and the `_pumpAndGetContext(tester, appLightTheme | appDarkTheme)` helper.
  - `test/features/chores/chore_form_avatars_test.dart` — for
    `find.byType(MemberAvatar)` descendant assertions.
- **Both themes.** Any colour assertion must be made against `appLightTheme`
  *and* `appDarkTheme`.

---

## File structure

**Modified**

| File | Responsibility after this plan |
| --- | --- |
| `lib/data/repositories/category_repository.dart` | Keeps `seedColors` (the 8 used to seed default categories — an unchanged contract) and gains `palette` = those 8 plus 4, the user-pickable set. |
| `lib/app/theme.dart` | `_categoryTones` gains 4 rows so all twelve resolve through the hand-picked table, never the HSL fallback. |
| `lib/app/color_swatch_picker.dart` | `PickerTile` gains a `shape`; `ColorSwatchPicker` renders swatches as tone-coloured rings, six per row, and supports disabled ("taken") swatches badged with the owner's initials. |
| `lib/features/members/member_avatar.dart` | Ring avatar; exports `previewMember` for callers that only have a name+colour. |
| `lib/features/settings/member_edit_sheet.dart` | Uses `palette`, shows a 66px live preview avatar, disables colours taken by other members, shows the uniqueness hint. |
| `lib/features/settings/category_edit_sheet.dart` | Uses `palette` (no uniqueness). |
| `lib/features/settings/join_flow_steps.dart` | `memberForAvatar` delegates to the shared `previewMember`. |
| `lib/features/settings/manage_members_screen.dart` | Member row avatar radius 16 → 21 (the design's 42px). |
| `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb` | Two new keys. |
| `docs/specs/theme-v2.md`, `docs/specs/members-management.md`, `docs/backlog.md` | Spec amendments. |

**No new production files.** New test files: `test/app/palette_test.dart`,
`test/app/color_swatch_picker_test.dart`,
`test/features/members/member_avatar_test.dart`.

---

### Task 1: Twelve-colour palette with hand-picked tones in both themes

**Files:**
- Modify: `lib/data/repositories/category_repository.dart:25-36`
- Modify: `lib/app/theme.dart:483-521` (the `_categoryTones` map at 488-506 and the two doc comments at 483 and 513)
- Test (create): `test/app/palette_test.dart`

**Interfaces:**
- Consumes: `categoryTone(BuildContext, int)` from `lib/app/theme.dart`;
  `appLightTheme` / `appDarkTheme` from the same file.
- Produces: `CategoryRepository.palette` — `static const List<int>`, 12 entries,
  `palette[i] == seedColors[i]` for `i < 8`. `CategoryRepository.seedColors`
  keeps its current 8 entries and its current meaning (default-category
  seeding) — do not change it.

**LIVE:** this task makes twelve colours resolvable, but nothing user-visible
changes yet; the pickers still read `seedColors`. Task 2 makes them live.

- [ ] **Step 1: Write the failing test**

Create `test/app/palette_test.dart`. Model the pump helper on
`test/app/theme_test.dart` — read that file first and reuse its
`_pumpAndGetContext` shape rather than inventing one.

```dart
/// The twelve-colour palette (spec `docs/specs/theme-v2.md` §1.3, design
/// canvas frames 1b/1d) must resolve through the hand-picked tone table in
/// BOTH themes -- never through `categoryTone`'s HSL fallback, which exists
/// only for colours arriving from sync or an imported archive.
library;

import 'package:chore_app/app/theme.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<BuildContext> _pumpAndGetContext(
  WidgetTester tester,
  ThemeData theme,
) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return captured;
}

/// WCAG 2.1 contrast ratio between two opaque colours.
double _contrastRatio(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  const expectedLight = <Color>[
    Color(0xFF4E7E54), Color(0xFF6B57B0), Color(0xFFB96A4C),
    Color(0xFF3F8697), Color(0xFFA86485), Color(0xFF8E7833),
    Color(0xFF5A73AD), Color(0xFF77716A),
    // Slot 8 is plum, NOT the canvas's #1E7A6E -- see R1: that hex is
    // `_lightPrimary`, so a ring drawn in it reads as "selected".
    Color(0xFF9A3D80),
    Color(0xFF96562F), Color(0xFF7A5AA8), Color(0xFF4C6B45),
  ];
  const expectedDark = <Color>[
    Color(0xFF93C297), Color(0xFFB4A5E8), Color(0xFFF0AF95),
    Color(0xFF8ACBD9), Color(0xFFE7AEC6), Color(0xFFDBC585),
    Color(0xFFA4B8E5), Color(0xFFC8C4BE), Color(0xFFD9A0C9),
    Color(0xFFDFB49A), Color(0xFFB9A8D1), Color(0xFFB4CBAE),
  ];

  test('the palette is twelve colours, extending seedColors in order', () {
    expect(CategoryRepository.palette, hasLength(12));
    expect(
      CategoryRepository.palette.sublist(0, 8),
      CategoryRepository.seedColors,
      reason:
          'indices 0-7 must keep addressing exactly the colours they address '
          'today: the members.edit.color.N / settings.categories.color.N '
          'semantic ids are indexed and must not change meaning',
    );
    expect(CategoryRepository.palette.toSet(), hasLength(12));
  });

  testWidgets('every palette colour has a hand-picked LIGHT render', (
    tester,
  ) async {
    final context = await _pumpAndGetContext(tester, appLightTheme);
    for (var i = 0; i < CategoryRepository.palette.length; i++) {
      expect(
        categoryTone(context, CategoryRepository.palette[i]),
        expectedLight[i],
        reason: 'palette index $i',
      );
    }
  });

  testWidgets('every palette colour has a hand-picked DARK render', (
    tester,
  ) async {
    final context = await _pumpAndGetContext(tester, appDarkTheme);
    for (var i = 0; i < CategoryRepository.palette.length; i++) {
      expect(
        categoryTone(context, CategoryRepository.palette[i]),
        expectedDark[i],
        reason: 'palette index $i',
      );
    }
  });

  testWidgets('every LIGHT render clears 3:1 on every light ground', (
    tester,
  ) async {
    final context = await _pumpAndGetContext(tester, appLightTheme);
    final scheme = Theme.of(context).colorScheme;
    final grounds = <Color>[
      scheme.surface,
      scheme.surfaceContainerLow,
      scheme.surfaceContainerHigh,
    ];
    for (final stored in CategoryRepository.palette) {
      final tone = categoryTone(context, stored);
      for (final ground in grounds) {
        expect(
          _contrastRatio(tone, ground),
          greaterThanOrEqualTo(3),
          reason:
              'light tone $tone on $ground '
              '(ring is a UI edge: 3:1, design canvas frame 1b)',
        );
      }
    }
  });

  testWidgets('every DARK render clears 3:1 on every dark ground', (
    tester,
  ) async {
    final context = await _pumpAndGetContext(tester, appDarkTheme);
    final scheme = Theme.of(context).colorScheme;
    final grounds = <Color>[
      scheme.surface,
      scheme.surfaceContainerLow,
      scheme.surfaceContainerHigh,
    ];
    for (final stored in CategoryRepository.palette) {
      final tone = categoryTone(context, stored);
      for (final ground in grounds) {
        expect(
          _contrastRatio(tone, ground),
          greaterThanOrEqualTo(3),
          reason: 'dark tone $tone on $ground',
        );
      }
    }
  });
}
```

- [ ] **Step 2: Run it and confirm the expected RED**

```
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/app/palette_test.dart
```

Expected: **compile error**, `The getter 'palette' isn't defined for the class
'CategoryRepository'`. That is the first RED.

After Step 3a below (adding `palette` but *not* the tone rows), re-running gives
the second, more interesting RED, and you should see it before Step 3b:
- the LIGHT test fails at `palette index 8` — the plum's HSL lightness is
  0.4216, a hair over the fallback's 0.42 ceiling, so `categoryTone` returns
  `Color(0xFF993D80)` instead of `Color(0xFF9A3D80)`. A one-unit miss, and a
  good one: it proves the assertion is reading the real render path.
- the LIGHT test then fails at `palette index 10` — `#7A5AA8` has HSL lightness
  0.506, well above the ceiling, so the fallback returns `Color(0xFF654A8C)`.
  (Indices 9 and 11 pass by luck: their lightness is already under the ceiling,
  so the fallback is a no-op.)
- the DARK test fails at `palette index 8` and would fail at 9, 10, 11 —
  the fallback returns `#D491C1`, `#DAA98B`, `#AE9BCA`, `#A8C3A2`, none of which
  are the hand-picked values.

That two-stage RED is the point: it proves the four new colours genuinely need
table rows rather than silently riding the degradation path meant for unknown
colours.

- [ ] **Step 3a: Add `palette` to `CategoryRepository`**

In `lib/data/repositories/category_repository.dart`, immediately after the
existing `seedColors` declaration (which is unchanged), add:

```dart
  /// The twelve colours a user can pick for a category or a member (design
  /// canvas frames 1b/1d; spec `docs/specs/theme-v2.md` §1.3).
  ///
  /// The first eight ARE [seedColors], in order and by construction, so the
  /// indexed `members.edit.color.N` / `settings.categories.color.N` semantic
  /// ids keep addressing exactly the colours they addressed before this list
  /// existed. The four appended values are new.
  ///
  /// Kept separate from [seedColors] because the two answer different
  /// questions: [seedColors] is "what colour does the Nth seeded default
  /// category get", a contract the seeding loop below depends on; this is
  /// "what may the user choose". Widening the picker must not silently
  /// re-colour anybody's seeded categories.
  ///
  /// Every entry is a STORED ARGB value and is never rewritten (spec §1.3 --
  /// `members`/`categories` are synced tables, so a rewrite would replicate).
  /// `categoryTone` maps each to its per-theme render at draw time.
  static const List<int> palette = [
    ...seedColors,
    // Plum, NOT the design canvas's `#1E7A6E`. That hex is byte-for-byte
    // `_lightPrimary`, the accent that means "interactive / selected"
    // everywhere in this UI, so a member ring drawn in it would read as a
    // selection state rather than as an identity. Substituted deliberately;
    // see `docs/plans/2026-08-18-palette-and-ring-avatars.md` R1.
    0xFF9A3D80, // plum
    0xFF96562F, // rust
    0xFF7A5AA8, // violet
    0xFF4C6B45, // moss
  ];
```

- [ ] **Step 3b: Add the four tone rows**

In `lib/app/theme.dart`, extend `_categoryTones` (currently ending at the
`0xFFA9A9A9` row, line 505) with four entries, and update the map's doc comment
so it no longer says "eight":

```dart
  0xFFA9A9A9: (light: Color(0xFF77716A), dark: Color(0xFFC8C4BE)), // Other
  // The four added for the twelve-colour picker (G-5b, design canvas frames
  // 1b/1d). Unlike the eight above -- whose STORED value is a mid-tone and
  // whose light render is a darkened variant -- these four are stored as the
  // design's own hex, so `light` is the identity. `dark` is that hue and
  // saturation at HSL lightness 0.74, the mean of the eight rows above.
  0xFF9A3D80: (light: Color(0xFF9A3D80), dark: Color(0xFFD9A0C9)), // plum
  0xFF96562F: (light: Color(0xFF96562F), dark: Color(0xFFDFB49A)), // rust
  0xFF7A5AA8: (light: Color(0xFF7A5AA8), dark: Color(0xFFB9A8D1)), // violet
  0xFF4C6B45: (light: Color(0xFF4C6B45), dark: Color(0xFFB4CBAE)), // moss
```

Note the plum's light render must be an explicit row even though it looks like
an identity mapping: its HSL lightness is 0.4216, just over the fallback's 0.42
ceiling, so without a row `categoryTone` would silently return `#993D80`.

Also change the map's doc comment (line 483) from "The eight
`CategoryRepository.seedColors` (shared by categories and members)" to "The
twelve `CategoryRepository.palette` entries (shared by categories and
members)", and the same phrase in `categoryTone`'s doc comment (line 513).

- [ ] **Step 4: Run the tests and confirm GREEN**

```
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/app/palette_test.dart
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/app/theme_test.dart
```

Expected: both PASS. `theme_test.dart` still loops over `seedColors.length`
(8) against its 8-entry expectation lists, and `seedColors` is unchanged, so it
is unaffected. If it fails with a `RangeError`, you changed `seedColors`
instead of adding `palette` — revert and redo Step 3a.

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/category_repository.dart lib/app/theme.dart test/app/palette_test.dart
git commit -m "Widen the shared colour palette to twelve, tone-mapped for both themes"
```

---

### Task 2: The pickers offer twelve, drawn as tone-coloured rings, six across

**Files:**
- Modify: `lib/app/color_swatch_picker.dart` (whole file)
- Modify: `lib/features/settings/member_edit_sheet.dart:188-194, 228` and `:28-33` (doc comment)
- Modify: `lib/features/settings/category_edit_sheet.dart:82-86, 129` and `:23` (doc comment)
- Test (create): `test/app/color_swatch_picker_test.dart`

**Interfaces:**
- Consumes: `CategoryRepository.palette` (Task 1), `categoryTone` from
  `lib/app/theme.dart`, `semantic(String, {required Widget child})` from
  `lib/app/semantics.dart`.
- Produces:
  - `PickerTile({required bool isSelected, required VoidCallback? onTap,
    required Widget child, ShapeBorder shape = const CircleBorder(), Key? key})`
    — `onTap` is now nullable and `shape` is new; both default to today's
    behaviour, so the category sheet's icon grid is unaffected.
  - `ColorSwatchPicker({required List<int> colors, required int selected,
    required ValueChanged<int> onSelected, required String semanticIdPrefix,
    Key? key})` — signature unchanged in this task; Task 4 adds `taken`.

**LIVE:** this is the task that ships G-5b. After it, both sheets show twelve
colours, in the design's ring form, six per row, in both themes.

Two behaviour changes are folded in here because they are the same edit:

1. **Swatches render `categoryTone(context, value)`, not the raw stored ARGB.**

   > **DELETE A FALSE COMMENT WHILE YOU ARE HERE.**
   > `lib/app/color_swatch_picker.dart:93-96` currently reads: *"Deliberately
   > the raw stored swatch, NOT `categoryTone` (spec `docs/specs/theme-v2.md`
   > §1.3 explicitly exempts the swatch picker itself)"*. **There is no such
   > exemption.** `theme-v2.md` was grepped for "swatch", "picker" and "exempt";
   > none of those words occurs anywhere in the file, and §1.3 says nothing
   > about pickers. A comment that invents a spec exemption is worse than no
   > comment: it launders a choice into a rule and defeats the next reader who
   > tries to check it. It is corrected here rather than filed as follow-up.

   Rendering the tone is now *required*, not merely permitted: the swatch is a
   ring and the avatar it previews is a ring, so a raw mid-tone swatch beside a
   toned avatar would visibly disagree, and four of the twelve stored values are
   dark-theme-hostile when drawn raw.
2. **Fixed six-per-row layout** (design: "Both grids stay six across"),
   replacing `Wrap`. Use chunked `Row`s of `Expanded`, not a `GridView` — the
   picker lives inside a `SingleChildScrollView` in both sheets, where an
   unbounded-height `GridView` throws.
   > **Added 2026-08-29:** put a `Center` inside each `Expanded`. `Expanded`
   > hands its child a *tight* horizontal constraint, which `SizedBox(width: 48)`
   > inside `PickerTile` would resolve to the full column width -- stretching the
   > 48x48 tile into a 55x48 lozenge on a phone-width sheet. `Center`
   > shrink-wraps it back to 48 while the `Expanded` still divides the row into
   > six equal columns.

- [ ] **Step 1: Write the failing test**

Create `test/app/color_swatch_picker_test.dart`:

```dart
/// `ColorSwatchPicker` renders the twelve-colour palette (spec
/// `docs/specs/theme-v2.md` §1.3) as theme-rendered rings, six per row.
library;

import 'package:chore_app/app/color_swatch_picker.dart';
import 'package:chore_app/app/theme.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpPicker(
  WidgetTester tester,
  ThemeData theme, {
  required int selected,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ColorSwatchPicker(
            colors: CategoryRepository.palette,
            selected: selected,
            onSelected: (_) {},
            semanticIdPrefix: 'test.color',
          ),
        ),
      ),
    ),
  );
}

/// The decorated box each swatch draws its ring with.
Iterable<BoxDecoration> _swatchDecorations(WidgetTester tester) => tester
    .widgetList<Container>(find.byType(Container))
    .map((c) => c.decoration)
    .whereType<BoxDecoration>()
    .where((d) => d.border != null);

void main() {
  testWidgets('renders all twelve palette colours', (tester) async {
    await _pumpPicker(
      tester,
      appLightTheme,
      selected: CategoryRepository.palette.first,
    );
    expect(_swatchDecorations(tester), hasLength(12));
  });

  testWidgets('swatch rings use categoryTone, not the raw stored value', (
    tester,
  ) async {
    // Index 2 is stored as 0xFFD98E73 and renders as 0xFFB96A4C in light --
    // the two differ, so this distinguishes toned from raw.
    const stored = 0xFFD98E73;
    await _pumpPicker(tester, appLightTheme, selected: stored);
    final context = tester.element(find.byType(ColorSwatchPicker));
    final expected = categoryTone(context, stored);
    expect(expected, isNot(const Color(stored)));

    final borders = _swatchDecorations(
      tester,
    ).map((d) => (d.border! as Border).top.color).toList();
    expect(borders, contains(expected));
    expect(borders, isNot(contains(const Color(stored))));
  });

  testWidgets('swatch rings use the DARK tone under the dark theme', (
    tester,
  ) async {
    const stored = 0xFFD98E73;
    await _pumpPicker(tester, appDarkTheme, selected: stored);
    final context = tester.element(find.byType(ColorSwatchPicker));
    final expected = categoryTone(context, stored);
    expect(expected, const Color(0xFFF0AF95));

    final borders = _swatchDecorations(
      tester,
    ).map((d) => (d.border! as Border).top.color).toList();
    expect(borders, contains(expected));
  });

  testWidgets('lays the twelve out six per row', (tester) async {
    await _pumpPicker(
      tester,
      appLightTheme,
      selected: CategoryRepository.palette.first,
    );
    final handle = tester.ensureSemantics();
    final firstRowY = tester.getCenter(
      find.bySemanticsIdentifier('test.color.0'),
    ).dy;
    for (var i = 1; i < 6; i++) {
      expect(
        tester.getCenter(find.bySemanticsIdentifier('test.color.$i')).dy,
        firstRowY,
        reason: 'index $i belongs on the first row',
      );
    }
    expect(
      tester.getCenter(find.bySemanticsIdentifier('test.color.6')).dy,
      greaterThan(firstRowY),
      reason: 'index 6 starts the second row',
    );
    handle.dispose();
  });

  testWidgets('the selected swatch is marked by a check, not colour alone', (
    tester,
  ) async {
    await _pumpPicker(
      tester,
      appLightTheme,
      selected: CategoryRepository.palette[3],
    );
    expect(find.byIcon(Icons.check), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it and confirm the expected RED**

```
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/app/color_swatch_picker_test.dart
```

Expected FAILs, all four meaningful:
- *"renders all twelve"*: currently the swatch `Container` has
  `border: null` when unselected, so `_swatchDecorations` finds 1, not 12 —
  `Expected: an object with length of <12> Actual: length <1>`.
- *"uses categoryTone, not the raw stored value"*: the raw path is in force.
- *"six per row"*: `Wrap` packs by available width, not by count.
- *"check"* passes already — it is a regression guard for
  `design-language.md`'s "colour is never the only carrier" rule, deliberately
  green from the start. Keep it.

- [ ] **Step 3: Rewrite the picker**

Replace the body of `lib/app/color_swatch_picker.dart` below its `library;`
directive. Add `import 'package:chore_app/app/theme.dart';` for `categoryTone`.

```dart
/// A 48dp-minimum tappable tile (design-language: touch targets >= 48dp,
/// enforced with sizing, not hope). Used by both the category edit sheet's
/// icon grid and [ColorSwatchPicker].
class PickerTile extends StatelessWidget {
  /// Creates a picker tile wrapping [child].
  const PickerTile({
    required this.isSelected,
    required this.onTap,
    required this.child,
    this.shape = const CircleBorder(),
    super.key,
  });

  /// Whether this tile is the current selection; drawn with a filled
  /// background when true.
  final bool isSelected;

  /// Called when the tile is tapped. `null` renders the tile inert (no ink,
  /// no callback) -- used by [ColorSwatchPicker] for a colour another
  /// member has already taken.
  final VoidCallback? onTap;

  /// The tile's content, centered within the 48x48 tappable area.
  final Widget child;

  /// The tile's ink and selection shape. Circular by default (the icon
  /// grid); [ColorSwatchPicker] passes a rounded rectangle to match the
  /// design canvas's swatch.
  final ShapeBorder shape;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: isSelected ? colorScheme.secondaryContainer : Colors.transparent,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: SizedBox(width: 48, height: 48, child: Center(child: child)),
      ),
    );
  }
}

/// The colour picker: [colors] drawn as rings, six per row (design canvas
/// frames 1b/1d). The selected swatch is marked two ways -- an outer glow
/// AND a checkmark -- so selection never rides on colour alone
/// (`docs/specs/design-language.md` colour-usage rules).
///
/// Each swatch is wrapped with `semantic('$semanticIdPrefix.$index', ...)`
/// so callers with different id schemes (the category edit sheet's
/// `settings.categories.color.*`, the member edit sheet's
/// `members.edit.color.*`) can both use this widget unmodified. Those ids
/// are INDEXED and are API (spec `docs/specs/theme-v2.md` §0): pass a
/// [colors] list whose leading entries keep their historical positions.
class ColorSwatchPicker extends StatelessWidget {
  /// Creates a colour swatch picker over [colors].
  const ColorSwatchPicker({
    required this.colors,
    required this.selected,
    required this.onSelected,
    required this.semanticIdPrefix,
    super.key,
  });

  /// How many swatches share a row (design: "both grids stay six across so
  /// the sheet height does not grow past a thumb's reach").
  static const int columns = 6;

  /// The fixed palette of stored ARGB colours to choose from, in display
  /// order. Each is rendered through `categoryTone`, not drawn raw.
  final List<int> colors;

  /// The currently-selected colour; must be one of [colors] for its swatch
  /// to render as selected (a value outside [colors] simply selects none).
  final int selected;

  /// Called with the newly-tapped swatch's colour.
  final ValueChanged<int> onSelected;

  /// Prefix combined with each swatch's index to form its semantic id.
  final String semanticIdPrefix;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var start = 0; start < colors.length; start += columns) {
      final end = start + columns > colors.length
          ? colors.length
          : start + columns;
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: start == 0 ? 0 : 8),
          child: Row(
            children: [
              for (var index = start; index < end; index++)
                Expanded(
                  child: semantic(
                    '$semanticIdPrefix.$index',
                    child: _ColorSwatch(
                      // The THEME-RENDERED tone, not the raw stored ARGB.
                      // The swatch is a ring and so is the avatar it
                      // previews, so the two must agree; and four of the
                      // twelve stored values are unreadable drawn raw on
                      // the dark ground. (A comment here once claimed
                      // theme-v2 §1.3 exempted this widget from the tone
                      // map. It does not -- the spec says nothing about
                      // the picker.)
                      tone: categoryTone(context, colors[index]),
                      isSelected: colors[index] == selected,
                      onTap: () => onSelected(colors[index]),
                    ),
                  ),
                ),
              // Pad a short final row so its swatches keep the same width
              // as every full row above them.
              for (var filler = end; filler < start + columns; filler++)
                const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.tone,
    required this.isSelected,
    required this.onTap,
  });

  final Color tone;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(14)),
    );
    return PickerTile(
      isSelected: false,
      onTap: onTap,
      shape: shape,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          border: Border.all(color: tone, width: 2.5),
          boxShadow: isSelected
              ? [
                  // The design's double glow: a surface-coloured gap, then
                  // the tone again, so the selected swatch reads as picked
                  // from across the grid.
                  BoxShadow(
                    color: colorScheme.surface,
                    spreadRadius: 2,
                  ),
                  BoxShadow(color: tone, spreadRadius: 4),
                ]
              : null,
        ),
        child: isSelected ? Icon(Icons.check, color: tone, size: 20) : null,
      ),
    );
  }
}
```

- [ ] **Step 4: Point both sheets at `palette`**

In `lib/features/settings/member_edit_sheet.dart`: change line 156's
`colors: CategoryRepository.seedColors` to
`colors: CategoryRepository.palette`, and in `_firstFreeColor` (lines 188-194)
replace both `seedColors` references with `palette`:

```dart
  int _firstFreeColor() {
    final usedColors = _currentMembers.map((m) => m.color).toSet();
    const palette = CategoryRepository.palette;
    return palette.firstWhere(
      (color) => !usedColors.contains(color),
      orElse: () => palette[_currentMembers.length % palette.length],
    );
  }
```

Update the file's `showMemberEditSheet` doc comment (lines 28-33) to say
`[CategoryRepository.palette]` rather than `[CategoryRepository.seedColors]`.

Make the identical change in `lib/features/settings/category_edit_sheet.dart`
(`_firstFreeColor` at lines 82-86, the `colors:` argument at line 129, and the
doc comment at line 23), substituting `_currentCategories` for
`_currentMembers`.

Leave `lib/features/settings/join_flow_steps.dart:29-33` on `seedColors`
**unchanged**: the join chooser picks a colour for a member being claimed in an
existing household, and staying inside the eight keeps a joining device's
choice identical to what an older client would have picked. Note it in the
commit message.

- [ ] **Step 5: Run the affected tests**

```
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/app/color_swatch_picker_test.dart
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/settings/category_edit_test.dart
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/settings/members_screen_test.dart
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/settings/join_household_sheet_test.dart
```

Expected: the new file PASSES. The three existing files also PASS unchanged —
verify, don't assume, and here is why each survives:
- `category_edit_test.dart:60` taps `settings.categories.color.1`, still
  `palette[1] == seedColors[1]`.
- `category_edit_test.dart:126-129` asserts a new category gets
  `seedColors[7]` — `_firstFreeColor` now scans `palette`, but indices 0-6 are
  taken by the seven seeded chore categories, so it still returns index 7,
  which is still `seedColors[7]`.
- `members_screen_test.dart:209-216` taps index 2 and expects
  `seedColors[2] == palette[2]`.
- `join_household_sheet_test.dart:291-293` is on the untouched `seedColors`
  path.

`members_screen_test.dart` also asserts on `CircleAvatar.backgroundColor` at
lines 231-246; that assertion is still valid at the end of *this* task and is
updated in Task 3.

- [ ] **Step 6: Commit**

```bash
git add lib/app/color_swatch_picker.dart lib/features/settings/member_edit_sheet.dart lib/features/settings/category_edit_sheet.dart test/app/color_swatch_picker_test.dart
git commit -m "Both colour pickers offer the twelve, drawn as toned rings six across

The join-flow chooser deliberately stays on the eight seedColors so a
joining device picks what an older client would have picked."
```

---

### Task 3: `MemberAvatar` becomes a ring

**Files:**
- Modify: `lib/features/members/member_avatar.dart` (whole file)
- Modify: `lib/features/settings/join_flow_steps.dart:56-70`
- Modify: `test/features/settings/members_screen_test.dart:231-246`
- Test (create): `test/features/members/member_avatar_test.dart`

**Interfaces:**
- Consumes: `categoryTone` from `lib/app/theme.dart`.
- Produces:
  - `MemberAvatar({required Member member, double radius = 12, Key? key})` —
    same field names, **default radius 10 → 12** (R2), rendering changed.
    **`CircleAvatar` is no longer used**; the avatar is a `Container` with a
    circular `BoxDecoration`.
  - `Member previewMember({required String name, required int color})` — a
    throwaway `Member` for callers that have only a name and a colour.
  - `String memberInitials(String name)` — the two-letter rule (R2), exported
    so the taken-swatch badge in Tasks 4-5 cannot drift from the avatar.

**LIVE:** this is the task that ships G-4's ring.

**Every surface that renders a `MemberAvatar`** and therefore changes
appearance (grepped; this list is exhaustive):

| Call site | Radius |
| --- | --- |
| `lib/features/chores/chore_occurrence_tile.dart:353` (assignee line) | 10 → **12** (the default; R2) |
| `lib/features/chores/chore_form/assignment_fields.dart:117, :233, :288` | 12 |
| `lib/features/stats/chore_history_screen.dart:87` | 12 |
| `lib/features/stats/stats_share_card.dart:131` (rendered to a shared image) | 12 |
| `lib/features/chores/acting_member_sheet.dart:53` (app-bar button), `:66`, `:110` | 14 |
| `lib/features/chores/mark_done_for_sheet.dart:52` | 14 |
| `lib/features/settings/manage_members_screen.dart:144` | 16 → 21 in Task 5 |
| `lib/features/settings/join_flow_steps.dart:186` | 16 |

The ring width scales as `radius / 8`, clamped to `[1.5, 3.0]`, which
reproduces the design's own two stated values exactly: the 42px sheet-row
avatar (radius 21) gets 2.6 ≈ its 2.5px ring, and the 66px preview (radius 33)
clamps to 3.0px, the design's 3px. The font scales as `radius * 0.72` with an
**11px floor** (R2), landing on the design's 15px at radius 21 and 23px at
radius 33. The whole avatar scales with the viewer's text scale, clamped to
`[1.0, 1.6]` — see R2 for the arithmetic behind all three constants.

- [ ] **Step 1: Write the failing test**

Create `test/features/members/member_avatar_test.dart`:

```dart
/// The member avatar is a ring, not a fill (G-4, design canvas frame 1b):
/// two-letter initials on the neutral surface inside a ring in the member's
/// theme-rendered colour, legible from the 24px chore tile to the 66px
/// edit-sheet preview, and at text scale 2.0.
library;

import 'package:chore_app/app/theme.dart';
import 'package:chore_app/features/members/member_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester,
  ThemeData theme, {
  required String name,
  required int color,
  double radius = 12,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Center(
            child: MemberAvatar(
              member: previewMember(name: name, color: color),
              radius: radius,
            ),
          ),
        ),
      ),
    ),
  );
}

BoxDecoration _decoration(WidgetTester tester) =>
    tester
            .widget<Container>(
              find.descendant(
                of: find.byType(MemberAvatar),
                matching: find.byType(Container),
              ),
            )
            .decoration!
        as BoxDecoration;

void main() {
  const stored = 0xFFD98E73; // renders 0xFFB96A4C light / 0xFFF0AF95 dark

  testWidgets('is a ring on the neutral surface, not a filled circle', (
    tester,
  ) async {
    await _pump(tester, appLightTheme, name: 'Mia', color: stored);
    final context = tester.element(find.byType(MemberAvatar));
    final scheme = Theme.of(context).colorScheme;
    final decoration = _decoration(tester);

    expect(decoration.shape, BoxShape.circle);
    expect(
      decoration.color,
      scheme.surfaceContainerHigh,
      reason: 'the ground is neutral; the colour lives in the ring',
    );
    expect(
      (decoration.border! as Border).top.color,
      categoryTone(context, stored),
    );
    expect(find.byType(CircleAvatar), findsNothing);
  });

  testWidgets('shows the first TWO letters, drawn in the ring colour', (
    tester,
  ) async {
    await _pump(tester, appLightTheme, name: 'Mia', color: stored);
    final context = tester.element(find.byType(MemberAvatar));
    // R2: the design's rule is the first two LETTERS of the display name
    // ('Mia' -> 'MI'), not the initials of two words.
    expect(find.text('MI'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('MI')).style!.color,
      categoryTone(context, stored),
    );
  });

  test('the initials rule handles every name shape', () {
    expect(memberInitials('Mia'), 'MI');
    expect(memberInitials('Anna'), 'AN');
    expect(memberInitials('Igor'), 'IG');
    expect(memberInitials('Leo'), 'LE');
    // Two words are NOT special-cased: first two letters, not word initials.
    expect(memberInitials('Anna Maria'), 'AN');
    // A one-character name yields one character, never padded.
    expect(memberInitials('J'), 'J');
    // A space as the second character is trimmed away rather than drawn.
    expect(memberInitials('J Smith'), 'J');
    expect(memberInitials('  mia  '), 'MI');
    expect(memberInitials('   '), '?');
    expect(memberInitials(''), '?');
  });

  testWidgets('uses the DARK tone under the dark theme', (tester) async {
    await _pump(tester, appDarkTheme, name: 'Mia', color: stored);
    expect(
      (_decoration(tester).border! as Border).top.color,
      const Color(0xFFF0AF95),
    );
  });

  testWidgets('ring width tracks radius and reproduces the design values', (
    tester,
  ) async {
    // 42px row avatar (design: 2.5px ring).
    await _pump(tester, appLightTheme, name: 'Mia', color: stored, radius: 21);
    expect(
      (_decoration(tester).border! as Border).top.width,
      closeTo(2.5, 0.2),
    );
    // 66px sheet preview (design: 3px ring).
    await _pump(tester, appLightTheme, name: 'Mia', color: stored, radius: 33);
    expect((_decoration(tester).border! as Border).top.width, 3);
    // 24px chore tile: thinner, so the two letters still have room.
    await _pump(tester, appLightTheme, name: 'Mia', color: stored, radius: 12);
    expect((_decoration(tester).border! as Border).top.width, 1.5);
  });

  testWidgets('two letters fit inside the smallest avatar without overflow', (
    tester,
  ) async {
    // R2: the default radius is 12 (a 24px box) precisely so two glyphs fit
    // with margin. 'WM' is about the widest two-letter pair in the alphabet.
    //
    // CORRECTED 2026-08-29: this asserted the glyph box against the ring's
    // INNER diameter using Inter's advance width (~1.35em for two uppercase
    // glyphs). Widget tests never load Inter -- there is no
    // flutter_test_config.dart in this repo -- so text falls back to the
    // `FlutterTest` font, where every glyph is a FULL em. 'WM' at the 11px
    // floor is 22px wide there against a 21px inner diameter, so the old
    // assertion failed on a correct implementation. Containment within the
    // avatar's own box is the property that actually matters (the glyphs
    // never escape the widget) and it does not depend on the font's advance.
    await _pump(tester, appLightTheme, name: 'Wm', color: stored);
    expect(tester.takeException(), isNull);
    final textRect = tester.getRect(find.text('WM'));
    final avatarRect = tester.getRect(find.byType(MemberAvatar));
    expect(
      avatarRect.contains(textRect.topLeft) &&
          avatarRect.contains(textRect.bottomRight),
      isTrue,
      reason:
          'two glyphs must stay inside the avatar at the default radius '
          '(measured in the FlutterTest font, whose 1em-per-glyph advance is '
          'far wider than the bundled Inter actually renders)',
    );
    expect(
      tester.widget<Text>(find.text('WM')).style!.fontSize,
      greaterThanOrEqualTo(11),
      reason: 'R2: 11px is the legibility floor for two uppercase glyphs',
    );
  });

  testWidgets('the whole avatar grows with text scale, capped at 1.6x', (
    tester,
  ) async {
    await _pump(tester, appLightTheme, name: 'Mia', color: stored);
    final base = tester.getSize(find.byType(MemberAvatar));
    expect(base.width, 24);

    await _pump(
      tester,
      appLightTheme,
      name: 'Mia',
      color: stored,
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    final scaled = tester.getSize(find.byType(MemberAvatar));
    expect(
      scaled.width,
      closeTo(24 * 1.6, 0.01),
      reason:
          'text scale 2.0 clamps to 1.6 -- the initials must keep pace with '
          'surrounding text, without bursting ListTile leading slots',
    );
    // The glyphs grew too, and still fit.
    expect(
      tester.getSize(find.text('MI')).width,
      lessThan(scaled.width - 2 * (_decoration(tester).border! as Border).top.width),
    );
  });

  testWidgets('a blank name shows ?', (tester) async {
    await _pump(tester, appLightTheme, name: '   ', color: stored);
    expect(find.text('?'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it and confirm the expected RED**

```
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/members/member_avatar_test.dart
```

Expected: **compile error**, `The function 'previewMember' isn't defined`. After
Step 3 defines it but before the render changes, the RED becomes
`Bad state: No element` from `_decoration` — today's `MemberAvatar` builds a
`CircleAvatar`, and there is no `Container` under it at all.

- [ ] **Step 3: Rewrite `member_avatar.dart`**

Replace everything below the `library;` directive:

```dart
import 'package:chore_app/app/theme.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:flutter/material.dart';

/// Builds a throwaway [Member] carrying only [name] and [color] -- the two
/// fields [MemberAvatar] reads -- for callers that do not have a real row:
/// the member edit sheet's live preview (the member may not exist yet) and
/// the join chooser (which has a `ClaimableMember`). Every other field is an
/// inert placeholder; never write one of these to the database.
Member previewMember({required String name, required int color}) => Member(
  id: '',
  householdId: '',
  name: name,
  color: color,
  role: MemberRole.member,
  createdAt: '',
  updatedAt: '',
  syncDirty: false,
);

/// The badge for [name]: its first two characters, uppercased, or `?` when
/// the name is blank (G-4 / plan decision R2).
///
/// Two characters, not one, because for a colour-blind viewer the initials
/// are the ONLY channel separating one member from another -- "Anna" and
/// "Alex" collide at one letter and separate at two
/// (`docs/specs/design-language.md`: colour is never the only carrier).
///
/// The rule is the first two LETTERS OF THE NAME, matching the design
/// canvas ('Mia' -> 'MI'), NOT the initials of two words: "Anna Maria" is
/// "AN", not "AM". The trailing trim handles a name whose second character
/// is a space ("J Smith" -> "J").
///
/// Shared with the member edit sheet's taken-swatch badge, so a disabled
/// swatch always shows exactly what that member's avatar shows.
String memberInitials(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    return '?';
  }
  final head = trimmed.length < 2 ? trimmed : trimmed.substring(0, 2);
  return head.trim().toUpperCase();
}

/// A member's avatar: their two-letter initials (or `?` for a blank name)
/// on the neutral surface, inside a ring in [member]'s colour (G-4, design
/// canvas frame 1b).
///
/// A ring rather than a fill so the same avatar is legible at 24px in a
/// chore tile and 66px in the member edit sheet: the initials always sit on
/// `surfaceContainerHigh` against `categoryTone`, a pairing the tone table
/// guarantees at >= 3:1 in both themes (`test/app/palette_test.dart`),
/// instead of on a fill whose legibility varied with the colour.
///
/// [radius] defaults to 12 (the chore tile's compact inline size -- 24px,
/// sized so two glyphs fit inside the ring with margin); pass a larger
/// value for a more prominent context (the members list at 21, the
/// acting-member app-bar button, the switcher sheet, the edit sheet's
/// 33-radius preview).
class MemberAvatar extends StatelessWidget {
  /// Creates an avatar for [member].
  const MemberAvatar({required this.member, this.radius = 12, super.key});

  /// The member this avatar represents.
  final Member member;

  /// The avatar's unscaled radius, in logical pixels. The rendered radius
  /// is this times the viewer's text scale, capped at 1.6x.
  final double radius;

  /// The cap on text-scale growth. Uncapped, a 2.0-scale avatar bursts
  /// `ListTile` leading slots and the chore form's chip rows.
  static const double _maxTextScale = 1.6;

  @override
  Widget build(BuildContext context) {
    final tone = categoryTone(context, member.color);
    final initials = memberInitials(member.name);
    // The whole avatar scales -- box, ring and glyphs together -- rather
    // than the text alone. Scaling the text inside a fixed box would
    // overflow the ring; not scaling at all would leave 11px initials
    // beside 22px labels for the viewer who asked for larger text.
    final scale = MediaQuery.textScalerOf(
      context,
    ).scale(1).clamp(1.0, _maxTextScale);
    final scaledRadius = radius * scale;
    // radius / 8 reproduces the design's own two stated ring widths: 2.6 at
    // its 42px row avatar (radius 21, drawn 2.5) and 3.0 at its 66px preview
    // (radius 33, drawn 3). The 1.5 floor keeps the 24px chore-tile avatar
    // from being mostly ring.
    final ringWidth = (scaledRadius / 8).clamp(1.5, 3.0);
    // 0.72 likewise lands on the design's 15px and 23px at those two sizes;
    // the 11px floor is Material's smallest label size, below which two
    // uppercase glyphs stop being readable.
    final fontSize = (scaledRadius * 0.72).clamp(11.0, double.infinity);
    return Container(
      width: scaledRadius * 2,
      height: scaledRadius * 2,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        shape: BoxShape.circle,
        border: Border.all(color: tone, width: ringWidth),
      ),
      child: Text(
        initials,
        // The scale is already applied to `fontSize` above; letting the
        // Text scale again would double-apply it.
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: tone,
        ),
      ),
    );
  }
}
```

`FamdoColors.onMemberColor` becomes unreferenced by this widget. **Do not
delete it** — it is in the theme-v2 §1.2 table and asserted by
`test/app/theme_test.dart:66`. Task 6 records its new status in the spec.

- [ ] **Step 4: Fold `join_flow_steps.memberForAvatar` into `previewMember`**

In `lib/features/settings/join_flow_steps.dart`, replace the
`memberForAvatar` function (lines 56-70) with a delegation, keeping the public
name so its call site at line 186 is untouched:

```dart
/// [MemberAvatar] takes a full [Member]; the chooser step only has a
/// [ClaimableMember] (id/name/colour). Delegates to [previewMember], the
/// shared placeholder builder.
Member memberForAvatar(ClaimableMember member) =>
    previewMember(name: member.name, color: member.color);
```

Add `import 'package:chore_app/features/members/member_avatar.dart';` if the
file does not already have it (it does — it uses `MemberAvatar` at line 186).
The `ClaimableMember.memberId` that the old code put in `Member.id` is dropped;
it was never read, because `MemberAvatar` only reads `name` and `color`.

- [ ] **Step 5: Update the one existing test that asserts the old fill**

In `test/features/settings/members_screen_test.dart`, replace lines 231-246
(the `CircleAvatar` lookup and its `backgroundColor` expectation) with a ring
assertion. Keep the `MemberAvatar` assertion above it at lines 225-231 as-is.
While there, fix the stale comment at line 204: it says the bootstrap 'Me'
member's colour "isn't part of the seed palette", but
`HouseholdRepository.createLocalHousehold` gives it `seedColors.first`.

```dart
      final avatarFinder = find.descendant(
        of: find.bySemanticsIdentifier('members.row.${me.id}'),
        matching: find.byType(MemberAvatar),
      );
      final decoration =
          tester
                  .widget<Container>(
                    find.descendant(
                      of: avatarFinder,
                      matching: find.byType(Container),
                    ),
                  )
                  .decoration!
              as BoxDecoration;
      // G-4: the avatar is a RING in the member's theme-rendered tone on a
      // neutral ground -- it was a filled circle before that wave, and this
      // assertion checked `CircleAvatar.backgroundColor`.
      expect(
        (decoration.border! as Border).top.color,
        categoryTone(tester.element(avatarFinder), newColor),
      );
```

Remove the now-unused `CircleAvatar` reference; leave the `categoryTone` import
in place.

- [ ] **Step 6: Run the avatar tests and every suite that renders one**

```
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/members/member_avatar_test.dart
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/settings/members_screen_test.dart
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/settings/join_household_sheet_test.dart
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/chores/chore_form_avatars_test.dart
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/chores/acting_member_widget_test.dart
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/chores/acting_member_pinning_test.dart
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/chores/chore_form/assignment_fields_test.dart
```

Expected: all PASS. The five chore-side suites only ever use
`find.byType(MemberAvatar)`, so they are indifferent to the internals — verify
that rather than trusting it.

- [ ] **Step 7: Commit**

```bash
git add lib/features/members/member_avatar.dart lib/features/settings/join_flow_steps.dart test/features/members/member_avatar_test.dart test/features/settings/members_screen_test.dart
git commit -m "Member avatars are a coloured ring around initials, not a fill"
```

---

### Task 4: `ColorSwatchPicker` learns a disabled "taken" state

**Files:**
- Modify: `lib/app/color_swatch_picker.dart`
- Modify: `test/app/color_swatch_picker_test.dart`

**Interfaces:**
- Consumes: `PickerTile`'s nullable `onTap` (Task 2).
- Produces:
  - `class TakenSwatch { const TakenSwatch({required this.initials,
    required this.semanticsLabel}); final String initials; final String
    semanticsLabel; }`
  - `ColorSwatchPicker(..., Map<int, TakenSwatch> taken = const {})` — an
    entry marks that colour inert and badges it with `initials`.

The picker takes already-localised strings rather than importing
`AppLocalizations`: it lives in `lib/app/` and is shared by the category sheet
(which has no owners) and the member sheet (which does). Task 5 builds the map.

**Not live yet** — no caller passes `taken` until Task 5.

- [ ] **Step 1: Write the failing test**

Append to `test/app/color_swatch_picker_test.dart`, and add
`import 'package:flutter/gestures.dart';` only if needed (it is not):

```dart
  testWidgets('a taken swatch is inert and shows the owner initials', (
    tester,
  ) async {
    const taken = 0xFFD98E73;
    var picked = -1;
    await tester.pumpWidget(
      MaterialApp(
        theme: appLightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ColorSwatchPicker(
              colors: CategoryRepository.palette,
              selected: CategoryRepository.palette.first,
              onSelected: (value) => picked = value,
              semanticIdPrefix: 'test.color',
              taken: const {
                taken: TakenSwatch(
                  initials: 'AN',
                  semanticsLabel: 'Taken by Anna',
                ),
              },
            ),
          ),
        ),
      ),
    );
    final handle = tester.ensureSemantics();

    // Index 2 is the taken colour; its badge is drawn and its tap is inert.
    expect(find.text('AN'), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier('test.color.2'));
    await tester.pump();
    expect(picked, -1, reason: 'a taken swatch must not fire onSelected');

    // A free swatch still works.
    await tester.tap(find.bySemanticsIdentifier('test.color.3'));
    await tester.pump();
    expect(picked, CategoryRepository.palette[3]);

    handle.dispose();
  });

  testWidgets('an empty taken map leaves every swatch tappable', (
    tester,
  ) async {
    var picked = -1;
    await tester.pumpWidget(
      MaterialApp(
        theme: appLightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ColorSwatchPicker(
              colors: CategoryRepository.palette,
              selected: CategoryRepository.palette.first,
              onSelected: (value) => picked = value,
              semanticIdPrefix: 'test.color',
            ),
          ),
        ),
      ),
    );
    final handle = tester.ensureSemantics();
    await tester.tap(find.bySemanticsIdentifier('test.color.2'));
    await tester.pump();
    expect(picked, CategoryRepository.palette[2]);
    handle.dispose();
  });
```

- [ ] **Step 2: Run it and confirm the expected RED**

```
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/app/color_swatch_picker_test.dart
```

Expected: **compile error**, `The named parameter 'taken' isn't defined` and
`Undefined class 'TakenSwatch'`. The "empty taken map" test compiles only once
the parameter exists, and is the guard that the category sheet's behaviour is
untouched.

- [ ] **Step 3: Implement**

Add above `ColorSwatchPicker` in `lib/app/color_swatch_picker.dart`:

```dart
/// A palette colour that is already spoken for, and how to say so.
///
/// Member colours are unique per household (G-4, design canvas frame 1b:
/// "Taking one that is used shows it disabled with the owner's initials on
/// it"), so the member edit sheet marks colours other members hold. The
/// category picker has no such rule and passes none.
class TakenSwatch {
  /// Creates a taken-swatch badge.
  const TakenSwatch({required this.initials, required this.semanticsLabel});

  /// The owner's initials, drawn on the swatch -- so the disabled state is
  /// carried by a glyph and not by colour alone
  /// (`docs/specs/design-language.md` colour-usage rules).
  final String initials;

  /// The already-localised screen-reader label, e.g. "Taken by Anna".
  final String semanticsLabel;
}
```

Add the field to `ColorSwatchPicker`:

```dart
  /// Colours that are unavailable, keyed by stored ARGB value. An entry
  /// renders its swatch inert and badged; the default (`const {}`) makes
  /// every colour selectable.
  final Map<int, TakenSwatch> taken;
```

with `this.taken = const {},` in the constructor, and pass it through in
`build`:

```dart
                    child: _ColorSwatch(
                      tone: categoryTone(context, colors[index]),
                      isSelected: colors[index] == selected,
                      taken: taken[colors[index]],
                      onTap: () => onSelected(colors[index]),
                    ),
```

In `_ColorSwatch`, add `final TakenSwatch? taken;` to the constructor and
fields, then change `build`'s tail:

```dart
    final isTaken = taken != null;
    return PickerTile(
      isSelected: false,
      // Inert, not merely ignored: a null onTap also removes the ink
      // splash, so the swatch does not look pressable.
      onTap: isTaken ? null : onTap,
      shape: shape,
      child: Semantics(
        label: taken?.semanticsLabel,
        enabled: !isTaken,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            border: Border.all(color: tone, width: 2.5),
            boxShadow: isSelected
                ? [
                    BoxShadow(color: colorScheme.surface, spreadRadius: 2),
                    BoxShadow(color: tone, spreadRadius: 4),
                  ]
                : null,
          ),
          child: switch (taken) {
            final TakenSwatch owner => Text(
              owner.initials,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: tone,
              ),
            ),
            null when isSelected => Icon(Icons.check, color: tone, size: 20),
            null => const SizedBox.shrink(),
          },
        ),
      ),
    );
```

- [ ] **Step 4: Run and confirm GREEN**

```
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/app/color_swatch_picker_test.dart
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/settings/category_edit_test.dart
```

Expected: both PASS. The category sheet passes no `taken`, so nothing changes
for it.

- [ ] **Step 5: Commit**

```bash
git add lib/app/color_swatch_picker.dart test/app/color_swatch_picker_test.dart
git commit -m "Colour swatches can be marked taken, badged with the owner's initials"
```

---

### Task 5: Member colours are unique, and the sheet previews the avatar

**Files:**
- Modify: `lib/features/settings/member_edit_sheet.dart`
- Modify: `lib/features/settings/manage_members_screen.dart:144`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`
- Modify: `test/features/settings/members_screen_test.dart` (add two tests)

**Interfaces:**
- Consumes: `TakenSwatch` and `ColorSwatchPicker.taken` (Task 4),
  `previewMember` and `MemberAvatar` (Task 3), `CategoryRepository.palette`
  (Task 1).
- Produces: no new public API.

**LIVE:** this ships G-4's uniqueness rule and the sheet preview.

- [ ] **Step 1: Add the two l10n keys**

In `lib/l10n/app_en.arb`, after the `@memberEditColorLabel` block (line 979).
NOTE: this ARB is American-spelling (`"memberEditColorLabel": "Color"`), so the
new string says "color", not the plan's original "colour":

```json
  "memberEditColorUniqueHint": "Your color is how you show up on every chore, in the digest and in Chore history. Two people can't take the same one.",
  "@memberEditColorUniqueHint": {
    "description": "G-4: explanatory line under the member edit sheet's colour picker, saying what the colour is for and that member colours are unique per household. Shown for every member, whether adding or editing."
  },
  "memberEditColorTakenBy": "Taken by {memberName}",
  "@memberEditColorTakenBy": {
    "description": "G-4: screen-reader label for a colour swatch another household member already holds, so it is disabled. The swatch itself shows that member's initials.",
    "placeholders": {
      "memberName": {
        "type": "String",
        "example": "Anna"
      }
    }
  },
```

In `lib/l10n/app_de.arb`, after `"memberEditColorLabel": "Farbe",` (line 212) —
informal du-form:

```json
  "memberEditColorUniqueHint": "Deine Farbe zeigt dich bei jeder Aufgabe, in der Zusammenfassung und im Verlauf. Zwei Personen können nicht dieselbe nehmen.",
  "memberEditColorTakenBy": "Schon von {memberName} belegt",
```

- [ ] **Step 2: Write the failing tests**

Append to `test/features/settings/members_screen_test.dart`, inside the same
`void main()`. Model them on the existing recolor test at lines 197-247 — read
it first.

```dart
  testChoreApp(
    'a colour another member holds is disabled and badged with their initial',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = HouseholdRepository(database);
      // 'Me' (the bootstrap member) holds palette[0]; give Anna palette[3].
      await repo.addMember(
        householdId,
        name: 'Anna',
        color: CategoryRepository.palette[3],
      );
      final me = await soleBootstrapMember(database);

      await openManageMembers(tester);
      await tester.tap(find.bySemanticsIdentifier('members.row.${me.id}'));
      await tester.pumpAndSettle();

      // Anna's initial badges her swatch, and tapping it does nothing.
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('members.edit.color.3'),
          matching: find.text('AN'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsIdentifier('members.edit.color.3'));
      await tester.tap(find.bySemanticsIdentifier('members.edit.save'));
      await tester.pumpAndSettle();

      final unchanged = await (database.select(
        database.members,
      )..where((tbl) => tbl.id.equals(me.id))).getSingle();
      expect(
        unchanged.color,
        CategoryRepository.palette.first,
        reason: "tapping Anna's colour must not recolour Me",
      );

      handle.dispose();
    },
  );

  testChoreApp(
    "the member's own current colour stays selectable while editing",
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final me = await soleBootstrapMember(database);

      await openManageMembers(tester);
      await tester.tap(find.bySemanticsIdentifier('members.row.${me.id}'));
      await tester.pumpAndSettle();

      // 'Me' holds palette[0]; it must show the check, not a taken badge.
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('members.edit.color.0'),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
      // The live preview avatar is present and reads the picked colour.
      // CORRECTED 2026-08-29: `members.edit.avatar` wraps the Row, not the
      // avatar, so `tester.widget<MemberAvatar>` on that finder throws.
      final preview = tester.widget<MemberAvatar>(
        find.descendant(
          of: find.bySemanticsIdentifier('members.edit.avatar'),
          matching: find.byType(MemberAvatar),
        ),
      );
      expect(preview.member.color, CategoryRepository.palette.first);
      expect(preview.radius, 33);

      handle.dispose();
    },
  );
```

Add whatever imports the file is missing (`HouseholdRepository`,
`CategoryRepository`, `MemberAvatar`) — check the existing import block first
rather than adding duplicates.

- [ ] **Step 3: Run and confirm the expected RED**

```
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/settings/members_screen_test.dart
```

Expected FAILs:
- *"disabled and badged"*: `Expected: exactly one matching candidate / Actual:
  _TextFinder: found 0 widgets` — there is no badge, because the sheet passes
  no `taken` map. The tap then recolours `Me` to `palette[3]`, so the
  `unchanged.color` expectation also fails.
- *"own colour stays selectable"*: `Bad state: No element` on
  `find.bySemanticsIdentifier('members.edit.avatar')` — the sheet has no
  preview avatar at all today.

- [ ] **Step 4: Implement the sheet changes**

In `lib/features/settings/member_edit_sheet.dart`:

Add imports for `color_swatch_picker.dart` (already present),
`package:chore_app/features/members/member_avatar.dart`.

Add the taken-map builder next to `_firstFreeColor`:

```dart
  /// The palette colours held by OTHER active members, mapped to their
  /// owner's badge (G-4: member colours are unique per household).
  ///
  /// The member being edited is excluded, so their own current colour stays
  /// selectable. If every palette colour is already held, this returns an
  /// EMPTY map: with twelve colours a thirteenth member has nothing free,
  /// and relaxing the rule is strictly better than refusing to add a person
  /// over a colour. Uniqueness is UI guidance and never a database
  /// constraint -- under sync two devices can claim the same colour
  /// concurrently, and the loser's save must not fail.
  Map<int, TakenSwatch> _takenColors(AppLocalizations l10n) {
    final editingId = widget.member?.id;
    final owners = <int, Member>{};
    for (final member in _currentMembers) {
      if (member.id != editingId) {
        owners.putIfAbsent(member.color, () => member);
      }
    }
    if (owners.length >= CategoryRepository.palette.length) {
      return const {};
    }
    return {
      for (final entry in owners.entries)
        entry.key: TakenSwatch(
          // The SHARED rule from member_avatar.dart, not a local copy: a
          // badged swatch must read as exactly that member's avatar.
          initials: memberInitials(entry.value.name),
          semanticsLabel: l10n.memberEditColorTakenBy(entry.value.name),
        ),
    };
  }
```

`_currentMembers` uses `ref.read`; change it to `ref.watch` so the taken map
and the preview both rebuild when the roster changes:

```dart
  List<Member> get _currentMembers =>
      ref.watch(membersProvider).value ?? const <Member>[];
```

(`_firstFreeColor` calls it from `initState`, where `watch` is illegal. Move
the roster read there to `ref.read(membersProvider).value ?? const <Member>[]`
inline inside `_firstFreeColor`, and leave the getter for `build`.)

In `build`, replace the colour section (currently lines 224-232) with the
preview row, the picker, and the hint:

```dart
          semantic(
            'members.edit.avatar',
            child: Row(
              children: [
                MemberAvatar(
                  member: previewMember(
                    name: _nameController.text,
                    color: _color,
                  ),
                  radius: 33,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    l10n.memberEditColorLabel,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ColorSwatchPicker(
            colors: CategoryRepository.palette,
            selected: _color,
            onSelected: (value) => setState(() => _color = value),
            semanticIdPrefix: 'members.edit.color',
            taken: _takenColors(l10n),
          ),
          const SizedBox(height: 12),
          semantic(
            'members.edit.colorHint',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.memberEditColorUniqueHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
```

Delete the standalone `Text(l10n.memberEditColorLabel, ...)` that preceded the
picker — the label now lives in the preview row. Its l10n key is still used, so
no key is removed.

The name field already calls `setState` via `_onNameChanged`
(lines 102-103 and 115), so the preview's initial updates live as the user types. Verify
that listener is still wired; do not add a second one.

- [ ] **Step 5: Bring the members-list avatar to the design's 42px**

In `lib/features/settings/manage_members_screen.dart:144`:

```dart
        leading: MemberAvatar(member: member, radius: 21),
```

- [ ] **Step 6: Run and confirm GREEN**

```
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/settings/members_screen_test.dart
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/settings/join_household_sheet_test.dart
```

Expected: PASS, including the pre-existing recolor test at lines 197-247 —
index 2 is free in that test's single-member household, so it stays enabled.

- [ ] **Step 7: Run the whole suite and the analyzer**

```
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY=
flutter analyze --fatal-infos --fatal-warnings
```

Expected: all green. If gen_l10n output is stale (`memberEditColorUniqueHint`
undefined), the build_runner/gen_l10n step the repo already uses must run —
follow the project's existing generation workflow; do not hand-edit
`lib/l10n/app_localizations*.dart`.

- [ ] **Step 8: Commit**

```bash
git add lib/features/settings/member_edit_sheet.dart lib/features/settings/manage_members_screen.dart lib/l10n/ test/features/settings/members_screen_test.dart
git commit -m "Member colours are unique per household, with a live avatar preview in the sheet"
```

---

### Task 6: Amend the specs and close the backlog rows

**Files:**
- Modify: `docs/specs/theme-v2.md` §1.2, §1.3
- Modify: `docs/specs/members-management.md` (the avatar and colour bullets, lines 53-65)
- Modify: `docs/specs/design-language.md` (colour-usage rules)
- Modify: `docs/backlog.md` (G-4 at line 318, G-5 at 319, the "Not planned" list at 170, the ownership note at 311)

No test cycle: documentation only. It is a task rather than a fold-in because a
reviewer should be able to reject the spec wording while accepting the code.

- [ ] **Step 1: Amend `docs/specs/theme-v2.md` §1.3**

- Retitle the table "The 12 `CategoryRepository.palette` colours" and add the
  four rows, marking that for these four the stored value *is* the light
  render:

  | `#9A3D80` plum | `#9A3D80` | `#D9A0C9` |
  | `#96562F` rust | `#96562F` | `#DFB49A` |
  | `#7A5AA8` violet | `#7A5AA8` | `#B9A8D1` |
  | `#4C6B45` moss | `#4C6B45` | `#B4CBAE` |

- **Record the slot-9 substitution beside that table**, because the design
  canvas draws something else and the divergence must not read as a
  transcription slip: *"The canvas's ninth colour is `#1E7A6E`. That is
  byte-for-byte `_lightPrimary` — the accent that means 'interactive /
  selected' throughout this UI — so a member ring or category dot drawn in it
  reads as a selection state rather than an identity, most confusingly on the
  surfaces where selection is also being expressed. It is substituted with
  `#9A3D80` plum, which clears the same contrast bar in both themes (light 5.15,
  dark 7.90) and sits further from its nearest palette neighbour (ΔE 21.7 light
  / 10.3 dark) than the palette's own tightest existing pairs (7.8 / 9.3). See
  `docs/plans/2026-08-18-palette-and-ring-avatars.md` R1."*
- Note that the plum needs an explicit `light` row despite looking like an
  identity mapping: its HSL lightness of 0.4216 just exceeds the fallback's 0.42
  ceiling, so without the row it would silently render `#993D80`.
- Change "A color that is not one of the eight" to "not one of the twelve".
- Replace the "**Avatars are the exception**" paragraph with: *"**Avatars are a
  ring, not a fill** (G-4): two-letter initials drawn in `categoryTone` on
  `surfaceContainerHigh`, inside a border in the same tone, width `radius / 8`
  clamped to `[1.5, 3.0]`, font `radius * 0.72` with an 11px floor. The whole
  avatar scales with the viewer's text scale, capped at 1.6x.
  `FamdoColors.onMemberColor` is retained in §1.2 (it is theme API and asserted
  by `test/app/theme_test.dart`) but is no longer read by any widget."*
- Add: *"The swatch picker renders `categoryTone`, not the raw stored value —
  the swatch is a ring previewing an avatar ring, and four of the twelve stored
  values are unreadable drawn raw on the dark ground. An earlier code comment
  in `color_swatch_picker.dart` asserted this spec exempted the picker; it never
  did."*
- Record the verified contrast floor: *"All twelve clear 3:1 against `surface`,
  `surfaceContainerLow` and `surfaceContainerHigh` in both themes (light floor
  3.30, dark floor 7.70; `test/app/palette_test.dart`). The §1.3 rationale's
  4.5:1 figure describes the 12sp category **label**, which only 3 of the 8
  original light renders in fact reach — a pre-existing gap this wave neither
  introduced nor closed. Raising it is backlog work."*
- Leave "must never be rewritten" exactly as it stands; add a sentence noting
  that G-5b widened the palette **without** rewriting any stored value, and why
  a rewrite is not merely discouraged but incorrect: an undirty rewrite is
  reverted by the next pull (`SyncRepository.applyPulledMember`), and a dirty
  one races across devices with no `updated_at` bump to order it.

- [ ] **Step 2: Amend `docs/specs/members-management.md`**

- Line 53-55: the row avatar is *"a ring in the member's colour around their
  two-letter initials on the neutral surface"*, at radius 21. State the
  initials rule verbatim: the first two characters of the trimmed display name,
  uppercased (`"Mia" → "MI"`); a one-character name gives one character;
  `"Anna Maria"` gives `"AN"`, not `"AM"` — these are name-initials, not
  word-initials; a blank name gives `"?"`. Two characters rather than one
  because for a colour-blind viewer the initials are the only channel that
  separates members, and the chore-tile avatar was enlarged from 20px to 24px
  to fit them rather than the rule being weakened.
- Line 63-65: the picker offers `CategoryRepository.palette` (twelve), and
  **member colours are unique per household**: a colour another active member
  holds is disabled and badged with that member's initial. The rule relaxes to
  allow duplicates once the roster exceeds the palette size. It is UI guidance,
  never a database constraint.
- Add: the edit sheet shows a live 66px preview avatar (`members.edit.avatar`)
  and the uniqueness hint (`members.edit.colorHint`).
- Add: **no column was added to `members`.** The design canvas suggested a
  nullable text column; the feature needs none, and `members` is synced, so a
  column there is a Supabase migration + RLS grant + both row mappers.

- [ ] **Step 3: Amend `docs/specs/design-language.md`**

Under "Color usage rules", add: *"Member identity colour is a **ring**, never a
fill (spec `theme-v2.md` §1.3, G-4) — the same 'accent, not background' rule
category colour already follows. Because colour is never the only carrier, the
ring is always accompanied by two-letter initials, which are the sole
differentiator for a colour-blind viewer; that is why the tile avatar is sized
to fit two glyphs rather than one. The disabled swatch in the member colour
picker likewise carries its state with the owner's initials, not with colour
alone. No palette colour may equal a semantic role colour: `primary` means
'interactive / selected' and `error` means 'wrong', so an identity drawn in
either would be read as a state (this is why palette slot 9 is plum and not the
canvas's `#1E7A6E`)."*

- [ ] **Step 4: Update `docs/backlog.md`**

- G-4 (line 318): mark shipped, replace "photo or colour-as-border (F15)" with
  the ring outcome, and link this plan.
- G-5 (line 319): split — the **colour** half (G-5b, twelve colours) is
  shipped by this plan; the **icon** half (the nine new Material Symbols named
  in the design canvas, frame 1d) is NOT and stays open. Say so explicitly so
  nobody reads the row as done.
- Line 170's "Not planned, and deliberately so" list: remove G-4; keep G-5
  with a note that only its colour half is done.
- Line 311's ownership note: record that G-4 and G-5b now have a design and a
  plan.
- Add a new backlog row for the one thing this plan deliberately left: raising
  12sp category-label contrast to 4.5:1 in the light theme, a gap that predates
  this wave (only 3 of the original 8 light renders reach it).
- Record the trap that produced this plan's original wrong premise, so it is not
  re-derived: **a design canvas shows RENDERED colours, `seedColors` holds
  STORED ones; compare through `categoryTone` or every canvas will look like a
  total mismatch and suggest a forbidden migration.**

- [ ] **Step 5: Commit**

```bash
git add docs/specs/theme-v2.md docs/specs/members-management.md docs/specs/design-language.md docs/backlog.md
git commit -m "Record the twelve-colour palette and the ring avatar in the specs"
```

---

## Self-review notes

- **Spec coverage.** Design frame 1b: ring avatar (Task 3), twelve curated
  user-picked colours (Tasks 1-2), uniqueness with a disabled owner-badged
  swatch (Tasks 4-5), storage note (resolved to "no column", documented in
  Task 6). Frame 1d colour half: same twelve, six across (Task 2). **The nine
  new category ICONS from frame 1d are out of scope** — the ticket scoped me to
  "the colour half of icons+colours" — and Task 6 Step 4 makes sure the backlog
  says so.
- **Two deliberate divergences from the canvas**, both resolved above, both
  recorded in the specs by Task 6 so neither reads as a transcription error:
  slot 9 is `#9A3D80` plum rather than the canvas's `#1E7A6E` (R1), and the
  chore-tile avatar is 24px rather than the canvas's stated 16px, because the
  canvas's own two-letter initials do not fit at 16px (R2). In both cases the
  canvas's *intent* is preserved and only its literal value moves.
- **Verified against the codebase, not memory.** Every line number cited was
  read. `openSettingsTab` / `openManageMembers` are in
  `test/features/settings/settings_test_utils.dart`, *not* `pump_app.dart` (the
  ticket said otherwise); the Global Constraints section corrects this. No
  Maestro flow touches the colour ids (grepped `e2e/`), so the widened index
  range breaks no E2E flow. There are no golden tests in this repo.
- **Type consistency.** `CategoryRepository.palette`, `TakenSwatch`,
  `previewMember`, `memberInitials`, `PickerTile.shape`,
  `ColorSwatchPicker.taken` are each defined once, in the task named in that
  task's `Produces` block, and used under exactly that name afterwards. In
  particular the taken-swatch badge calls `memberInitials` rather than
  reimplementing it, so a badge can never disagree with the avatar beside it.
- **Every RED is non-vacuous.** Each is a compile error or a specific
  wrong-value/missing-widget failure, with the actual pre-fix value stated
  (`#654A8C` for the clamped violet, `#D491C1`/`#DAA98B`/`#AE9BCA`/`#A8C3A2`
  for the four fallback darks — the earlier `#84E1D5` here was the *rejected*
  teal's fallback, left over from the pre-R1 draft). No test in this plan passes
  before its fix
  exists, except the deliberately-green `Icons.check` regression guard in
  Task 2, which is labelled as such.
