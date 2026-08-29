# Handover: wave 6

*Written 2026-08-29 by the agent that orchestrated wave 6, for whoever scopes
the next one. Same rule as the wave-4 and wave-5 handovers: every claim here
was verified against source, CI output, or a build artifact — and where it
wasn't, it says so explicitly.*

---

## 1. Where things stand

Wave 6 ran as four streams on `integration/wave-6` (PR #36), each merged only
after a line-by-line review and a green `gh pr checks` at the reviewed SHA.

**Schema is still at v12.** G-2 needed a new recurrence field and did *not*
get a migration for it — see §2. **The next migration is still v13.**

Nothing was released and `main` is untouched. Everything is on
`integration/wave-6` awaiting the human's single reviewed merge. Base was
`main` at `de3b7c3` (the wave-5 merge, v0.8.0); `origin/main` did **not** move
during this wave — re-checked before each merge, because it moved mid-flight
under wave 5.

Final state vs `main`: **59 files, +5897/-696.**

---

## 2. What shipped

| Row | What landed |
| --- | --- |
| **G-5a** | The category icon picker grew from 15 identifiers to 24. `test/app/theme_test.dart` now pins the `categoryIconIdentifiers` ↔ `categoryIcon` invariant, so an identifier offered by the picker without a `switch` case can no longer fall through to `Icons.label_outlined` and render as a plausible-looking duplicate tile. `potted_plant` maps to `Icons.local_florist`: the design canvas names Material **Symbols**, Flutter ships Material **Icons**, and that identifier is not in the bundled font (verified — 0 hits in the SDK's `icons.dart`; the other eight are present verbatim). |
| **G-5b** | `CategoryRepository.palette` is twelve colours. Both pickers draw them as theme-rendered rings, six across. **Additive, not a replacement:** `palette = [...seedColors, 4 new]`, so indices 0–7 still address exactly the colours they always did and every indexed `members.edit.color.N` / `settings.categories.color.N` id keeps its meaning. No stored value is rewritten. |
| **G-4** | The member avatar is two-letter initials on the neutral surface inside a ring in the member's `categoryTone`, from the 24px chore tile to the 66px edit-sheet preview, scaling with text scale to a 1.6× cap. Member colours are unique per household — a colour another active member holds is drawn inert and badged with their initials. **Photo avatars were never scoped** and did not ship; that would be a synced blob and its own ticket. No column was added to `members`. |
| **G-2** | The repeat block is one readable sentence with inline controls, plus a live preview of the next three dates. `Recurrence.monthlyDayOfMonth` was added so "the 20th of each month" is expressible at all — **in the recurrence JSON, not a drift column**, which is why the schema stayed at v12. `-1` encodes "last day", reusing `monthlyOrdinal`'s existing convention rather than a `32` that a naive 1..31 range check would wave through. |
| **A-6** | See §6 — reported separately, and honestly. |

### The G-2 cross-version contract, because it is the load-bearing part

`Recurrence` is serialized as JSON into an opaque `TEXT` column and synced
verbatim. A household member on a client predating `monthlyDayOfMonth`
ignores the unknown key and evaluates the derived branch,
`min(startDate.day, daysInMonth)`. This client evaluates
`min(monthlyDayOfMonth, daysInMonth)`. The form keeps `startDate.day` aligned
to the chosen day, so those are the **same expression** — divergence is
**zero**, not merely bounded, for every day in 1..31, over the whole infinite
series.

Only the `-1` sentinel keeps a residual, and it is bounded and one-directional:
at most **3 days**, always with the older client **early**, never late, so
nothing is silently missed. Zero in a 31-day month, ≤1 for a 30-day month, ≤3
for February, and gone permanently once that device updates.

The engine's derived branch was deliberately left **byte-for-byte** what it
always was. That identity is the whole mechanism; do not "tidy" it.

### Fixes nobody asked for, found while in the area

- **`memberInitials` split UTF-16 code units.** `substring(0, 2)` cuts a
  non-BMP character's surrogate pair in half — "A🎈" rendered a letter plus a
  tofu box — and cuts a decomposed diacritic into a letter plus a floating
  combining mark. Now `String.characters.take(2)`. This mattered more than it
  looks: the *reason* for two letters is that initials are the only channel
  separating members for a colour-blind viewer once the palette's closest pair
  sits at ΔE 7.8, and a tofu box separates nobody. Pre-existing in spirit —
  the old `substring(0, 1)` broke the same way on a leading emoji.
- **Typing `0` into the repeat interval threw `IntegerDivisionByZeroException`.**
  `int.tryParse(text) ?? 1` was safe for four waves because it only pluralized
  a noun; G-2's preview hands it to the engine. A shared `displayInterval`
  clamps to ≥1. Note the near-miss shape: the fallback was *named* in the
  plan's own OPD-4 without noticing that zero and empty need different
  handling.
- **German copy rendered `31..` and `Aug..`** — German ordinals end in a
  period and `intl` abbreviates most German months with one, so the preview
  frame doubled them. The German frame now adds no periods of its own, with an
  `@`-description warning translators not to "fix" it back.
- **44 `\uXXXX` escapes in `app_de.arb`** (wave 5's account-deletion region)
  converted to literal umlauts — the project's stated rule, and escaped German
  copy cannot be reviewed by the person who approves it. Decoded JSON verified
  byte-identical before and after.
- **`app.loading`** — the bootstrap loading scaffold now carries a semantic id.
  See §5, it is the most transferable finding of the wave.

---

## 3. Verification status — read this before trusting §2

**Proven by CI on the reviewed SHA**, not predicted: every row above.
`integration/wave-6` at **`90bfd35`** — `checks` pass (4m15s) with **1132 tests
passing**, `android` pass (17m20s) with **14/14 Maestro flows**, `pgtap` pass,
`ios` skipping by the workflow's own condition. (The same four were green one
merge earlier at `195e1e8`, before the avatar-test follow-up landed.) Each stream was also green on
its own branch before merge, and every merge was re-verified on the accumulated
tree rather than trusting the stream's green — an earlier green is a different
tree.

`flutter gen-l10n` is a zero diff on the merged tree and `dart format` reports
291 files, 0 changed, so no stream leaked formatter churn or a hand-written
localization file. That `pgtap` is the fast internal skip, not a real SQL run:
wave 6 changed nothing under `supabase/`, and db.yml short-circuits internally
because it is a REQUIRED check and therefore cannot carry a `paths:` filter.
**Do not read that green as server verification** — it is db.yml's own
documented behaviour.

**Proven by deliberate inversion, at the test step:** every stream ran one, and
each was checked to fail at `flutter test` rather than at `analyze` — a failure
at `analyze` means the tests never ran and is not a valid red. Highlights:

- Dropping the plum's identity-looking tone row made the render come back
  `#993D80` instead of `#9A3D80`. A one-unit miss, from HSL lightness 0.4216
  only just clearing the 0.42 unknown-colour ceiling — a wrong colour that
  looks right in a diff. That row is load-bearing and now has a test saying so.
- Cutting `memberInitials` to one character reddened both the avatar render and
  the taken-swatch badge, confirming the badge really does share the avatar's
  rule rather than copying it.

**NOT verified, and no CI job can change it** — these need a device:

- The icon sheet's height at text scale 2.0 now that the grid has a fourth row.
- The ring avatar and twelve-colour pickers on a real screen, in both themes.
- The repeat sentence's line wrapping at large text scales on a narrow phone.
- Anything iOS. `ios` does not run on PRs; use the `workflow_dispatch` button.

**A claim I could not verify at all:** see §5, `famdo_design.txt`.

---

## 4. Recorded claims that turned out to be WRONG

Five this wave. As in wave 5, **none were in code** — all were in documents
describing the code, which is exactly why the refresh pass keeps paying.

1. **"The colour half is a palette replacement with a data migration."**
   (`docs/backlog.md`, G-5 row.) It is an *extension*. `RING[0..7]` are
   byte-for-byte the existing tones, `theme-v2.md` §1.3 forbids rewriting
   stored colours because `members`/`categories` sync, and no migration exists.
   This is the same false premise an implementer refused earlier in this
   project's history; it had been sitting in the backlog ever since, waiting to
   mislead the next reader. Corrected in the row.
2. **"Every colour this plan adds sits further from its nearest neighbour"**
   than the palette's tightest existing pairs of ΔE 7.8/9.3.
   (`docs/plans/2026-08-18-palette-and-ring-avatars.md`.) Self-contradictory —
   **both of those tight pairs are colours the plan adds.** The existing eight
   sit at ΔE 25.8 light / 17.8 dark. The honest statement is the reverse: this
   plan *tightens* the palette's minimum separation by roughly 3×. Two more
   numeric claims in the same plan were also wrong (a dark worst case quoted as
   7.70 when the true floor is 7.63, and a fallback hex left over from a
   pre-substitution draft).
3. **The sentinel-splitting design used JavaScript's `String.split` semantics.**
   (`docs/plans/2026-08-18-repeat-form-sentence.md` §4.) Dart's `split`
   discards the delimiter, capture group or not, so the sentence would have
   rendered with **zero** inline controls. Rewritten to walk `allMatches`.
4. **"Prefer the 31st of a 31-day month" for the `-1` alignment.** Same plan,
   Task 6. Its justification is false: `_monthOccurrences` filters
   `isOnOrAfter(startDate)`, so moving the start date into a later month
   *deletes* earlier occurrences and delays the chore by up to 31 days. It
   would have penalised every household, single-version ones included, to buy
   zero divergence for mixed-version ones.
5. **A-6's cause statement was stated with more confidence than it earned.**
   `e2e.yml` records "the Flutter view permanently fails to present on a fresh
   install" as a finding. It is one of *four* hypotheses the same evidence
   supports equally — see §5. This is the **second** time this row's cause has
   been wrong, and both times it was written up as settled.

Plus one instruction refused as unexecutable rather than wrong:
`Icons.event_upcoming` does not exist in Flutter 3.44.8.

---

## 5. Process findings

### The design canvas is not in the repository

**`famdo_design.txt` is cited by all three wave-6 plans as the source for the
nine icons, the twelve colours and the sentence wording. It does not exist —
not tracked, not untracked, nowhere on disk.** Verified directly.

So the visual decisions this wave implemented are unverifiable and
un-re-derivable from inside the repo. They were treated as recorded decisions
and implemented as written, which is the right call under the wave's rules —
but "closed" and "unverifiable" are different things. Every claim these plans
make *about code* has so far been wrong at some rate; their claims about design
intent are now simply unfalsifiable. **Committing the canvas would fix this
permanently**, and it should happen before wave 7 plans G-7, which sits on top
of what this wave did to member and category legibility.

### Two named safety gates were vacuous

Both found by G-2, both worth generalising:

- **`theme_and_scale_test.dart` never turns the repeat toggle on.** The plan
  named it as the release gate for a repeat-form rewrite; it could not have
  caught anything in that rewrite.
- **The cross-version convergence test group does not red when the engine
  ignores the new field.** It asserts explicit-rule == derived-rule, so a build
  that ignores the field makes them trivially identical and the group passes.
  It is billed as the guard on the sync hazard and **on its own it is not
  one** — it needs "an explicit day overrides the start-date day" beside it.
  Both are now in the suite; neither is redundant.

The transferable rule: **a test whose two sides can collapse into each other is
not a guard.** Check by inverting the thing it claims to protect, and check the
inversion breaks *the test you think it breaks*.

### A third vacuous gate, caught only because a claim was double-checked

The palette stream rewrote a plan-authored assertion that could not have
passed, then reported to me that its replacement was font-independent and
correct. Asked to confirm the underlying font claim, it measured instead of
re-reading — and found **its own replacement was vacuous**.

Widget tests here draw the Ahem-style `FlutterTest` font, not the bundled
Inter: no `flutter_test_config.dart` exists and nothing calls `FontLoader`.
Measured in CI, `'WM'` at 11px/w600 is **21.87px** — 1.99 em per glyph — against
Inter's ~15px. Inside the avatar the text is constrained to the 21px inner
diameter, so it wraps and the paragraph reports *its own constraint* (21.0).
Rect containment against that box therefore passes **whatever the avatar's
geometry is**.

Loading the real Inter does not rescue it: the faces are declared under pubspec
`fonts:` rather than `assets:`, so `rootBundle.load` hands `FontLoader` nothing
usable and it **silently no-ops** — no exception, no effect. So glyph fit is
simply not assertable in a widget test here; containment is vacuous and a
strict inner-diameter check is false on correct code. The file now asserts only
font-independent properties and says why, with the measured numbers. Recorded
as backlog **G-14**.

The production code was never wrong — only the measurement was impossible. The
lesson is the same one §5 keeps repeating from a new angle: **the fix for a
vacuous assertion can itself be vacuous**, and the only way anyone found out
was by measuring a claim that had already been reported as verified.

### An empty accessibility tree was ambiguous, and now is not

The app's `_LoadingScaffold` emitted **zero** accessibility nodes — `Scaffold`
contributes none, and `CircularProgressIndicator`'s `Semantics` has null label
and value, so it is dropped. A white frame with an empty hierarchy was
therefore *byte-identical* whether (a) the Flutter engine never presented and
iOS was still showing the also-white `LaunchScreen.storyboard`, or (b) the
engine presented fine and the household gate never resolved. Those are
completely different bugs, and every artifact-based diagnosis of A-6 so far has
been unable to tell them apart.

`semantic('app.loading')` now marks that state. Nothing taps it; it exists to
be read. Together with a Flutter node count it separates three states: no nodes
(engine never presented), nodes including `app.loading` (presented, stuck in
bootstrap), full tree (presented and built — the fault is the driver's).

**If a reproduction ever lands on `app.loading`, the bug is ours** — something
`bootstrapProvider` awaits on a first-launch-only path — not the simulator's.

### `git branch --merged` is not sufficient evidence of merged-ness

Squash-merged branches never become ancestors of `main`, so they look unmerged
forever. Two of the twenty stale branches (`docs/f1-gate1-confirmed`,
`docs/wave-4-handover`) were in exactly that state. They were confirmed
contained by **content** (byte-identical files vs `main`) plus a merged PR
record. Anything relying on ancestry alone would have reported live work as
abandoned, or — worse, in the other direction — kept branches forever.

### CI fragility worth one line of YAML

`e2e.yml`'s `android` job downloads the Gradle distribution fresh on every run,
with no cache and no retry. A transient GitHub CDN `504` reddened a PR in this
wave one minute in, before a line of app code compiled. Caching `~/.gradle`
would remove a whole class of false reds. **Not done** — outside this wave's
file set, and it is a decision about CI cost, not about this wave's code.

### A dispatched workflow runs the file at the dispatched ref

Worth recording because it is non-obvious and the A-6 stream depended on it:
`workflow_dispatch` requires the workflow to exist on the **default branch**,
but a dispatched run then uses the version of that file **at the ref you
dispatch**. So a workflow cannot be *introduced* on a branch and dispatched
from it, but an existing one can be freely *modified* on a branch and
dispatched there. `e2e.yml`'s own comment records the first half; this is the
second half.

---

## 6. What is open

- **A-6 itself.** Reported in §6a below.
- **The colour separation.** The twelve-colour palette contains two purples,
  `#6B57B0` and `#7A5AA8`, at ΔE 7.8 — well above the ~2.3 JND, so defensible,
  and the canvas colour was kept deliberately rather than substituted (R1's
  earlier substitution rested on a *correctness* argument: `#1E7A6E` is
  byte-for-byte the "selected" accent, so a member ring in it would read as a
  selection state). But it is a visible consequence of shipping the canvas
  faithfully, and it is the colour to change if it reads badly on a device.
- **G-13** — a 12sp category-label 4.5:1 contrast gap, opened by the palette
  stream rather than silently absorbed.
- **The English preview copy.** *"Every 2 weeks on Tuesday, Friday. Next Tue,
  Aug 4, then Fri, Aug 7 and Tue, Aug 18."* — four comma-separated groups whose
  dates carry their own internal commas. It is the plan's recorded copy,
  implemented as written; it reads noisier on a screen than on paper. Igor's
  sentence to change.
- **F-1 GATE 3** — unchanged by this wave, still needs a human with a phone.
- **Device verification** of everything in §3's "NOT verified" list.
- **`famdo_design.txt`** — commit it.

---

## 7. Housekeeping performed

**19 stale worktrees and 19 stale remote branches deleted**, all from completed
waves, each listed with evidence before removal. 17 were proven by ancestry
(`git merge-base --is-ancestor <branch> origin/main`). Two — `docs/f1-gate1-confirmed`
and `docs/wave-4-handover` — were **squash-merged**, so they are not ancestors
of `main` and never will be; they were proven contained by extracting the exact
text each branch added and confirming it appears verbatim in `main` today, plus
a merged PR record (#23, #26). See §5.

**Deliberately kept:** `main`, `integration/wave-6`, the four wave-6 stream
branches, and four scratch branches the palette stream created
(`wave6/palette-font-probe`, `-probe2`, `wave6/palette-ring-avatars-inversion`,
`wave6/palette-verify-base`). Those scratch branches exist because PR #40 went
`CONFLICTING` when G-5a merged, and **GitHub creates no `pull_request` runs for
a conflicting PR** — so the stream had to route its inversion evidence through
side branches. They hold run evidence cited in this wave's reports; delete them
once `main` takes the merge.
