# Repeat Form as One Sentence (G-2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the chore form's five unrelated repeat controls (interval
field, unit segmented control, weekday chip row, monthly-mode row, two anchor
cards) with **one fill-in-the-blank sentence** whose holes are tap targets,
where controls irrelevant to the chosen unit **do not exist**, the anchor moves
below a hairline under the label "Counting from", and a plain preview line
naming three real dates is always visible.

**Architecture:** One new shared formatter (`recurrenceSentence`) that both the
form and — prospectively — the paused rows call, plus one new sentence widget
that renders a whole localized ARB message with widget-shaped holes punched
into it via sentinel splitting. `RepeatControls` is rewritten around them.
The recurrence engine's semantics are unchanged **except** for the one model
gap in OPD-1.

**Tech Stack:** Flutter 3.44.8 / Dart SDK `^3.12.2`, `flutter_riverpod ^2.6.1`,
drift + SQLite, `package:intl`, gen_l10n, `package:clock`.

**Source ticket:** backlog `G-2` "Repeat-form structural redesign (F14)"
(`docs/backlog.md`), which is stage 2 of field feedback **G3**
(`docs/feedback/2026-08-01-field-feedback.md` §G3): *"make the pattern directly
editable (weekday picker for weekly, day-of-month picker for monthly) instead
of deriving everything from the start date."* Stage 1 (copy + plurals) shipped;
this is the structure.

**Design source:** the design canvas frame `1a`, and specifically the **live
prototype logic** in `famdo_design.html` — `sentence()`, `nextDates()`,
`domLabel`, `ordinalLabel`, and the `g2notes` array. Where the text extract and
the markup disagree, the markup is the specification.

**Specs touched:**
- `docs/specs/ui-foundation-chores.md` — "Form screen (create + edit)" repeat
  bullets and the Semantic-IDs list (binding; Task 9 amends it).
- `docs/specs/theme-v2.md` §4.4 (binding; Task 9 amends it — see the §0
  conflict called out in Analysis §6).
- `docs/specs/recurrence-engine.md` §2 (binding; Task 3 amends it — the new
  `monthlyDayOfMonth` field, and the alignment invariant that keeps old clients
  converged, Analysis §2a).

---

## Global Constraints

- **Do not edit `docs/backlog.md` or anything under `docs/feedback/`.** Other
  agents work in those files concurrently. Report G-2 as closable in the final
  summary instead of editing the row.
- **Run every test as**
  `env -u GIT_DIR -u GIT_INDEX_FILE flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= <path>`
  — exactly as `lefthook.yml` does. Without the two dart-defines six unrelated
  tests fail and read as regressions. Do not run more than 2 concurrent
  `flutter test` processes.
- **Do not hand-roll a widget test.** Use `testChoreApp` from
  `test/test_utils/pump_app.dart` and `find.bySemanticsIdentifier`, and call
  `tester.ensureSemantics()` first. A hand-rolled `ProviderScope` pump that
  closes the database in `tearDown` **hangs** rather than fails (flutter_test's
  pending-Timer leak check runs before tear-downs, so drift's stream-cleanup
  timer never drains), taking the whole suite and the pre-commit hook with it.
  **Reference tests to copy the shape from — read them, do not write from
  memory:**
  - `test/features/chores/chore_form_recurrence_test.dart` — the canonical
    "which repeat controls exist for which unit" test, including its
    `_fieldFor(identifier)` descendant-`TextField` helper and its
    assert-via-repository-read save check.
  - `test/features/chores/chore_form_repeat_copy_test.dart` — the canonical
    "the copy composes correctly as the user types" test (G3 stage 1).
  - `test/features/chores/chore_form_validation_test.dart` — interval-error +
    recovery.
  - `test/features/chores/chore_form_edit_test.dart` — edit round-trip prefill.
  - `test/features/chores/chore_form_unsaved_changes_test.dart` — the
    `PopScope` dirty guard.
  - `test/features/chores/theme_and_scale_test.dart` — text-scale-2.0 and
    dark-theme smoke, the release gate this plan is most likely to break.
- `semantic()` is `Widget semantic(String id, {required Widget child})` —
  **NAMED** child. Positional will not compile.
- **All user-visible strings via gen_l10n.** `lib/l10n/app_en.arb` is the
  template and needs an `@`-description per key; `lib/l10n/app_de.arb` is
  informal du-form. ICU `plural` must appear in **both** locales. **No ICU
  `zero{}` branch** — CLDR has no distinct zero category in en or de, so a
  `zero{}` arm is silently unreachable; if a zero case needs different words,
  it is a *separate key* selected in Dart. Generated `app_localizations*.dart`
  are committed — run `flutter gen-l10n` and commit the output.
  **`app_de.arb` uses literal `ä/ö/ü/ß`, never `\u` escapes** (closed
  2026-08-17, commit `102d4c3`).
- **No `semantic(...)` id may be deleted.** Every id this plan touches is
  enumerated in Analysis §6 with its fate. Two of them
  (`chore_form.repeat.toggle`, `chore_form.repeat.unit.day`) are live in three
  Maestro flows and are **E2E API**.
- **No l10n key may be deleted** (`theme-v2.md` §0). A key that stops being
  used is *retired in place*: keep it, and rewrite its `@`-description to say
  it was retired, by what, and on what date — the exact pattern
  `choreFormAnchorScheduleSubtitle` already uses in `app_en.arb`.
- Strict lints: `very_good_analysis` with `--fatal-infos`. Every public member
  needs a doc comment — including every new top-level function, every new
  public class, and every new named parameter's behaviour in the enclosing
  doc.
- `lib/domain/` is **`dart:core`-only** by convention (see the headers of
  `recurrence.dart`, `plain_date.dart`, `digest_planner.dart`). Task 3 must add
  no imports there. `package:intl` and `AppLocalizations` therefore cannot be
  used in `lib/domain/` — which is why the formatter lives under
  `lib/features/chores/`, not in the domain.
- TDD, one commit per task: write the failing test → run it → **confirm it
  fails for the stated reason** → implement → run → commit. Each task below
  names its expected RED failure mode. A test that passes before its fix exists
  is vacuous — if that happens, the test is wrong, not the plan.
- Never add `Co-Authored-By:` or any co-author trailer to commit messages.
- Every codebase claim below was verified against source on `main` at
  `0bee683`. If you find one that is wrong, **say so** rather than working
  around it.

---

## Analysis (why this design)

### 1. The design's headline structural claim does NOT hold — verified

> *"The plain-language sentence you asked for is the **same** string the paused
> rows and chore tiles already render, so one formatter serves three places."*

**The "already render" half is false.** There is no shared recurrence
formatter, and neither of the two named surfaces renders a recurrence string at
all:

- `lib/features/chores/chore_paused_section.dart` — `_PausedRow`'s subtitle is
  a `Wrap` of exactly two things: a `CategoryBadge` (when categorized) and
  `Text(l10n.choresPausedBadge)`. It never reads `chore.recurrence`. The file
  does not import `recurrence.dart`.
- `lib/features/chores/chore_occurrence_tile.dart` — `_MetadataRow` renders a
  category dot + name, the assignee avatar + first name, and a `_DueChip`
  carrying `futureDueText`/`overdueDueText`, which are **relative due-date**
  strings ("Today", "In 3 days", "Fri, Jul 31"), not recurrence prose. It
  imports `plain_date.dart` only, never `recurrence.dart`.

A repo-wide grep for `recurrenceLabel|recurrenceDescription|describeRecurrence|recurrenceSummary|repeatLabel|recurrenceText`
across `lib/` and `test/` returns **nothing**. Outside `chore_form/`, no widget
in `lib/features/` imports `recurrence.dart` at all.

**Where prose about a recurrence actually exists today:** exactly one place,
and it is inside the form — `AnchorRow._subtitle`/`_scheduleSubtitle` in
`lib/features/chores/chore_form/repeat_section.dart`, a private method that
switches over unit/anchor/monthlyMode and picks one of eight ARB messages
(`choreFormAnchorScheduleSubtitleDay`, `…Week`, `…MonthDayOfMonth`,
`…MonthNthWeekday`, `…MonthLastWeekday`, `choreFormAnchorCompletionSubtitleDay`,
`…Week`, `…Month`). `MonthlyModeRow._label` is a second, smaller one
(`monthlyDayOfMonthLabel`, `monthlyNthWeekdayLabel`, `monthlyLastWeekdayLabel`).

**Verdict, and what this plan does about it.** The claim is wrong as *reporting*
and right as *design*. Building the preview line as a fresh formatter beside
`AnchorRow._scheduleSubtitle` would produce exactly the drift the ticket warns
about: two switches over the same enums, rendering the same rule in two
wordings, guaranteed to diverge on the first copy change. So Task 1 **extracts**
`AnchorRow`'s private switch into a public `recurrenceSentence()` in a new
`lib/features/chores/recurrence_sentence.dart`, with zero behaviour change and
its existing tests still green; Task 4 grows it to also produce the preview.
The form then has **one** formatter serving both the anchor subtitles and the
preview. Adopting it in the paused rows — the third place — is a real,
user-visible change to the chores list and is **OPD-3**, not something to
smuggle in.

`recurrence_sentence.dart` goes in `lib/features/chores/`, not
`lib/features/chores/chore_form/`, precisely so `chore_paused_section.dart`
(its sibling) can import it without reaching into a form-private directory.

### 2. The scope claim is *mostly* true — but the monthly day-of-month hole cannot be expressed

> *"Recurrence keeps its current shape — interval, unit, weekday set, monthly
> mode, anchor — so this is a form rewrite, not a schema change."*

Checked field by field against `lib/domain/recurrence/recurrence.dart` and
`lib/data/db/tables.dart`:

| Design hole | Current model | Verdict |
| --- | --- | --- |
| interval chip | `Recurrence.interval` | ✅ form-only |
| unit chip | `Recurrence.unit` | ✅ form-only |
| weekday chips (weeks) | `Recurrence.weekdays` (`Set<int>`, ISO 1..7) | ✅ form-only |
| monthly mode row | `Recurrence.monthlyMode` | ✅ form-only |
| ordinal chip ("third") | `Recurrence.monthlyOrdinal` (1..4, −1) | ✅ **model can express it; the form just doesn't** — `buildRecurrence` derives it from `startDate` via `nthWeekdayOrdinalOf`. Making it directly editable is pure form work. |
| monthly weekday chip ("Tuesday") | `Recurrence.monthlyWeekday` (ISO 1..7) | ✅ same — derived from `startDate.weekday` today |
| **day-of-month chip ("1st…31st")** | **nothing** | ❌ **cannot be expressed** |
| **"last day" token** | **nothing** | ❌ **cannot be expressed** |
| anchor cards | `Recurrence.anchor` | ✅ form-only |

**The gap, precisely.** `MonthlyMode.dayOfMonth` carries **no day field**. The
engine reads the day off the start date:

```dart
// lib/domain/recurrence/recurrence_engine.dart, _monthCandidate
final maxDay = PlainDate.daysInMonth(year, month);
final targetDay = startDate.day < maxDay ? startDate.day : maxDay;
return PlainDate(year, month, targetDay);
```

So the design's `dom` token — a day the user picks *in the sentence*,
independent of the start date — has nowhere to live. And there is no
representation of "last day" at all: `31` is not it, because in a 31-day month
`31` means the 31st, which is the last day only by coincidence. (The prototype
encodes "last day" as the sentinel `32`; that is a JS array-index hack, not a
proposed wire format — see §5.)

**But this is not a database migration.** `Chores.recurrence` is a nullable
`TEXT` column carrying `jsonEncode(rule.toJson())` through
`RecurrenceConverter` (`lib/data/db/converters.dart`), and the Supabase side is
`recurrence text` (`supabase/migrations/20260731120000_initial_schema.sql:64`)
— opaque on both ends. Adding a JSON key needs **no drift migration and no
schema version bump**: the "next migration is v13" note in `docs/backlog.md`
stays untouched, and `Recurrence.fromJson` reads a missing key as `null` (old
rows keep deriving from the start date, unchanged) as long as the new field is
declared `int?` and type-checked with `is! int?`, matching how
`monthly_ordinal` is already read.

**The one real hazard, and it is a cross-device one.** A client that writes
`"monthly_day_of_month": 20` syncs that string to Supabase verbatim. A
household member still on v0.7.1 pulls the row, `fromJson` ignores the unknown
key, and that device computes the due date from `startDate.day` instead — two
phones in one household silently disagreeing about when the chore is due, with
no error anywhere. Silent cross-device divergence is the failure class this
project hunts hardest, so it does not get to stand as a noted cost. §2a works
out how far it can be closed.

### 2a. Closing the cross-version divergence — alignment, and what is left over

**The mechanism that closes it.** The old client's day-of-month branch is
exactly a clamp of `startDate.day`:

```dart
final maxDay = PlainDate.daysInMonth(year, month);
final targetDay = startDate.day < maxDay ? startDate.day : maxDay;   // = min(startDate.day, maxDay)
```

The new client, given `monthlyDayOfMonth: D`, computes `min(D, maxDay)`. These
are the **same expression** whenever `startDate.day == D`. So if the form keeps
the start date *aligned* to the chosen day — picking "the 20th" also moves the
chore's start date onto a 20th — an un-updated device computes **byte-identical
due dates for the whole infinite series**. Divergence is not merely bounded, it
is zero.

This is not OPD-1 option (b) in disguise. Under (b) `startDate.day` would be
the only store, so the Start date field and the sentence's day chip would be
two controls fighting over one value. Under alignment, `monthlyDayOfMonth` is
**authoritative** and `startDate.day` is a redundant mirror maintained solely
for old-client convergence; if the two ever disagree, the new client obeys the
field and ignores the mirror. And the side effect is *visible* — the Start date
field sits in the same form and updates in front of the user — which was the
whole objection to (b).

**What alignment costs, and it is not free.** `scheduleOccurrences` filters to
`isOnOrAfter(startDate)` and `firstDueDate` reads the first element, so moving
the start date can drop or add the first occurrence. Task 6 therefore aligns
*forward*: it picks the nearest date **on or after** the current start date
whose day is `D`, so the first occurrence never lands in the past. Moving the
start date by up to ~30 days also shifts the whole month series for
`interval > 1`, which is a real change to what the user asked for — but it is
the change they asked for, rendered honestly in a field they can see and
override.

**The residual: "last day" (`D == -1`) alone.** This is the one token with no
exact `startDate` expression, and the reason is precisely the clamp: since
`daysInMonth <= 31` always, `min(31, maxDay) == maxDay`, so a start date on a
**31st** makes an old client compute the last day of every month, exactly
right. But the 31st only exists in 31-day months, so alignment can only be
exact when the start date may sit in one — and forcing that can shift the
series by a month, which for `interval > 1` changes the schedule materially.
So the plan does **not** force it. The residual is therefore:

| Start month's length | Aligned `startDate.day` | Old client computes | Divergence |
| --- | --- | --- | --- |
| 31 (Jan, Mar, May, Jul, Aug, Oct, Dec) | 31 | last day, every month | **none** |
| 30 (Apr, Jun, Sep, Nov) | 30 | 30th, or 28th/29th in Feb | **≤ 1 day, old client early** |
| 28/29 (Feb) | 28 or 29 | 28th/29th | **≤ 3 days, old client early** |

**Bound, and what the user observes.** Residual divergence is confined to
"last day" rules, is at most **3 days**, and is **always in the safe direction**
— the un-updated device shows the chore due *earlier* than the updated one,
never later, so nothing is silently missed. What a user would observe: on the
old phone the January chore reads "due Jan 28" while the new phone reads "due
Jan 31". It converges permanently the moment that device updates, and it never
occurs at all for a household on one version, for every non-"last day" rule, or
for a start date in a 31-day month. Task 6 prefers a 31-day-month alignment
when choosing "last day" would not distort the series, which shrinks the
residual further in the common case.

**This is exactly what G3 stage 2 asked for.** The feedback's own words:
*"day-of-month picker for monthly… instead of deriving everything from the
start date. That is a recurrence-engine + form redesign."* The feedback
predicted an engine change; the design's "no schema change" line did not.
Reporting it, per the ticket, rather than adding it quietly: **OPD-1.**

### 3. Two more conflicts between the design and the current model

**(a) nth-weekday + completion anchor throws.** `Recurrence.validated` rejects
it outright:

```dart
if (anchor == RecurrenceAnchor.completion) {
  throw ArgumentError.value(anchor, 'anchor',
      'nthWeekday mode is not supported with a completion anchor');
}
```

`docs/specs/recurrence-engine.md` §2 lists it as a validation rule, and
`nextAfterCompletion`'s doc says month + completion is `dayOfMonth` only. The
design shows the anchor as two always-present cards under the sentence, with
the monthly weekday row available whenever the unit is months — so
"every 2 months on the third Tuesday" + "after you mark it done" is reachable
in the drawn UI and would throw at save. Today's form dodges this by *silently*
resetting `_monthlyMode` to `dayOfMonth` in `_onAnchorChanged` — a silent state
change, which is precisely the thing the new design exists to stop. **OPD-2.**

**(b) The design forbids an empty weekday set; the model allows it.** The
prototype's `toggleDay` refuses to deselect the last chip
(`set('dayset', next.length ? next : [i])`). The model treats an empty set as
"derive from `startDate.weekday`" (`_effectiveWeekdays`), and the form surfaces
that with the `_PatternFollowsStartDateHint` caption. Forcing at least one
selected weekday is the whole point of G3 stage 2 — it removes the hidden
start-date dependency — and it is expressible in the current model (a non-empty
set is always valid), so it is **not** an OPD; this plan implements it. The
wrinkle it creates is handled explicitly:

- Opening the form on an **existing** chore whose stored rule has an empty
  weekday set pre-selects `startDate.weekday` so the sentence is complete. That
  pre-selection happens *before* `_captureInitialSnapshot()`, so the form is
  **not** dirty on open — otherwise every edit of such a chore would trigger
  the `PopScope` discard dialog on a plain back-tap, which is a regression of
  C4. Task 7 tests exactly this.
- Saving such a chore without touching anything then writes `weekdays: {N}`
  where it previously wrote `{}`. That is a *behaviour-preserving* rewrite —
  `_effectiveWeekdays` already resolved `{}` to `{startDate.weekday}` — so no
  due date moves. It does mean `ChoreService.updateChore` sees
  `recurrenceChanged == true` and regenerates the pending occurrence; since the
  regenerated date is identical, this is invisible. Stated so a reviewer does
  not read it as a bug.

### 4. Composition of the sentence widget — three approaches weighed

The hard constraint is l10n.

**Why fragment concatenation fails here — read this before "simplifying" the
sentinel machinery away.** The obvious implementation is a `Row`/`Wrap` of
`[Text(l10n.repeatEvery), intervalChip, unitChip, Text(l10n.on), …]`, gluing
short localized fragments together in a fixed widget order. It cannot work,
for four independent reasons, any one of which is fatal:

1. **German inflects the frame by the unit's gender.** "Every day / week /
   month" is *jeden* Tag (m.), *jede* Woche (f.), *jeden* Monat (m.) in the
   accusative. A single reusable "Repeat every" fragment has no correct German
   translation, because the correct word depends on a *different* fragment that
   the translator cannot see.
2. **It inflects again by number.** *jede Woche* (1) vs *alle 2 Wochen* (N):
   the frame word changes with the interval, so the fragment would need an ICU
   plural whose branch depends on a value rendered in a neighbouring widget.
   Gender × number is a 2-dimensional table the fragment cannot express.
3. **Word order is not translatable across a fixed widget order.** A hardcoded
   widget sequence bakes English syntax into the tree. A translator handed
   fragments cannot move a hole, cannot merge two of them, and cannot put the
   preposition anywhere but where an English speaker left it.
4. **Fragments are untranslatable in isolation on principle.** "on" alone has
   no German translation — *am*, *an*, *auf*, *um* — because the right one
   depends on the noun that follows it in a different fragment.

The whole-sentence-with-holes approach dissolves all four: the translator
receives one complete sentence per shape, chooses their own gender/number
wording inside it, and may place the holes anywhere. That is why the ARB keys
in Task 2 are whole sentences and why the German framing was chosen to sidestep
the article entirely. **Any change that splits them back into fragments is a
regression, not a simplification.**

**Approach A — `Text.rich` with `WidgetSpan` holes.** Literal runs become
`TextSpan`s, holes become `WidgetSpan(alignment: PlaceholderAlignment.middle,
child: chip)`. Typographically the most correct: real inline line-breaking,
natural inter-word spacing. **Rejected:** a 36–44px chip inside a WidgetSpan
against 17px text makes line height jump, and `WidgetSpan` + `TextScaler` is a
known source of unbounded-height and overflow exceptions. Text scale 2.0 is a
release gate here (`theme-v2.md` §5, `theme_and_scale_test.dart`), and this is
the single most likely way to fail it.

**Approach B — `Wrap` of `Text` words and chip widgets, driven by a
sentinel-split whole-sentence ARB message. ← CHOSEN.** The ARB message carries
the entire sentence with ICU placeholders. The widget calls it passing a unique
control-character sentinel for each hole, splits the returned string on those
sentinels, splits each literal run on whitespace into one `Text` per word, and
emits the chip widget wherever its sentinel was. The result is a
`Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8)`.

Why it wins: the translator owns the **whole** sentence and can move the holes
anywhere in it (German's trailing "am" lands where German wants it); every hole
is a plain box in a flex line, so making it a genuine 36–44px tap target is
trivial and there is no baseline arithmetic; at text scale 2.0 the `Wrap`
simply wraps, which is what the release gate needs. It is also what the
prototype does — its sentence row is `display:flex; flex-wrap:wrap; gap:8px`.

Its one cost: inter-word spacing becomes the uniform `Wrap.spacing` rather than
the font's own space glyph. At 8px against Inter at 17px this is visually
indistinguishable, and punctuation stays attached to its word because the split
is on whitespace only.

**Approach C — hardcode the widget order per unit and pull short fragments
("Repeat every", "on", "on the") from the ARB.** **Rejected outright:** it is
fragment concatenation, forbidden by the plan's rules, and it hard-codes
English word order into the widget tree.

**Sentinel mechanics (be precise here — this is where a from-memory
implementation would introduce a defect).** Use four distinct **Unicode
noncharacters** — `U+FDD0`, `U+FDD1`, `U+FDD2`, `U+FDD3`, written in Dart as
`'﷐'` etc. — one per hole *position*, so a split can tell *which* hole it
found rather than relying on order. These code points are permanently reserved
as noncharacters and can never legitimately appear in translated copy, which
neither the private-use area nor the interlinear-annotation block (`U+FFF9`…)
can promise. Split with a capturing
`RegExp('([﷐-﷓])')` and walk the result, mapping each captured
sentinel back to its hole. Assert in the widget (via `assert`, not a runtime
throw) that every sentinel handed in was found exactly once in the rendered
string — a translator who drops a placeholder would otherwise silently delete a
control from the form.

### 5. Encoding "last day" — `-1`, not `32`

If OPD-1 lands option (a), the last-day token needs a value. Use **`-1`**, not
the prototype's `32`:

- `Recurrence.monthlyOrdinal` **already** uses `-1` to mean "last" in this exact
  class, documented in its field comment and in `recurrence-engine.md` §2. One
  class, one convention for "last".
- `32` is a valid-looking day number that would pass any naive `1..31` range
  check and land in the database as garbage if a future writer forgot the
  sentinel. `-1` cannot be mistaken for a day.
- The prototype's `32` exists only because its `DOM_CHOICES` array cycles by
  index; it is not a proposed wire format.

Validation to add in `Recurrence.validated`: `monthlyDayOfMonth` must be `null`
or in `1..31` or exactly `-1`; and it must be `null` unless
`unit == month && monthlyMode == dayOfMonth`. `null` keeps today's meaning —
derive from `startDate.day` — which is what every existing persisted rule
means.

Clamping is unchanged and already correct: `_monthCandidate` clamps the target
day to `PlainDate.daysInMonth(year, month)`, so a 31st in February lands on the
28th/29th. Per `g2notes`, the preview *shows* this happening and the UI does not
explain it.

### 6. Every `semantic()` id this plan touches, and what happens to it

`theme-v2.md` §0 is binding and says: **"No `semantic(...)` id may be removed,
renamed, or moved to a different widget."** This plan moves one. That is a real
conflict with a binding spec, not an oversight — and theme-v2 §0 itself provides
the exit: *"When the design implies a behavior change (not just a look), it is
out of scope for the theme waves and belongs in its own spec."* G-2 is that
spec. Task 9 records the amendment in `theme-v2.md` §4.4 explicitly. **The
Maestro flows must be updated in the same commit that moves the id (Task 8),
never in a follow-up** — E2E is the merge gate and it runs in GitHub CI.

| Id | Today | After | Consequence |
| --- | --- | --- | --- |
| `chore_form.repeat.toggle` | `SwitchListTile` in `RepeatToggle` | **unchanged** | none. Live in `e2e/flows/settings/chore_history.yaml`, `e2e/flows/chores/skip_undo_journey.yaml`, `e2e/flows/chores/recurring_complete_advances.yaml`. |
| `chore_form.repeat.interval` | wraps a `LabelledFieldCard` containing a `TextField` | wraps the interval **hole** in the sentence, still a `TextField` (**OPD-4**) | **Kept, moved.** It stays a `TextField`, so `test/features/chores/chore_form_validation_test.dart` and `chore_form_repeat_copy_test.dart` keep working through `find.descendant(of: …, matching: find.byType(TextField))` — only the widget above it changes. |
| `chore_form.repeat.unit.<day\|week\|month>` | three `ButtonSegment` labels, tappable directly | three entries in the menu opened by the new unit chip | **Kept, moved to a different widget.** `chore_form.repeat.unit.day` is tapped **directly** by three Maestro flows; each now needs `tapOn: chore_form.repeat.unit` inserted before it (Task 8). This is the single highest-risk change in the plan. |
| `chore_form.repeat.unit` | **does not exist** | new: the unit chip that opens the menu | new id, allowed. |
| `chore_form.repeat.weekday.<1..7>` | `_WeekdayToggle`, 48dp | **unchanged widget, unchanged id** — only its parent moves under the sentence | none. `WeekdayChips` is reused as-is; only the min-one-selected rule changes, and that lives in the form's `_toggleWeekday`, not in the widget. |
| `chore_form.repeat.monthly_mode.<day_of_month\|nth_weekday>` | two `RepeatRadioCard`s | two segments/chips in the mode row below the sentence | **Kept.** Their **labels** change from "On the 15th"/"On the 3rd Tuesday" (derived) to the design's "A day of the month"/"A weekday" (mode names) — the concrete day now lives in the sentence's own chip. `chore_form_recurrence_test.dart` asserts on these ids, not their text, so it survives; `chore_form_repeat_copy_test.dart` asserts on the text and must be rewritten (Task 7). |
| `chore_form.repeat.anchor.<schedule\|completion>` | two `RepeatRadioCard`s in the middle of the block | two `RepeatRadioCard`s **below a hairline**, under a "Counting from" label | **Kept**, same widget type, same ids. Position and the section header change — and per **OPD-2** `…anchor.completion` is **absent** (not disabled) while monthly weekday mode is active, the same "does not apply, does not exist" rule the weekday chips already follow. |
| `chore_form.repeat.monthly_day` | **does not exist** | new: the day-of-month hole | new id. |
| `chore_form.repeat.monthly_ordinal` | **does not exist** | new: the ordinal hole | new id. |
| `chore_form.repeat.monthly_weekday` | **does not exist** | new: the monthly weekday hole | new id. |
| `chore_form.repeat.preview` | **does not exist** | new: the always-visible preview line | new id. Makes the preview assertable by both widget tests and E2E. |
| `chore_form.save` | `bottomNavigationBar` `FilledButton` | **unchanged** | **Do not regress the keyboard-inset fix.** The `Padding(EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom))` around the `SafeArea` in `chore_form_screen.dart` exists because `Scaffold` applies `resizeToAvoidBottomInset` to its **body only** — without it the save button sits behind the keyboard and vanishes from the accessibility tree entirely (verified on a Pixel emulator 2026-08-06). `test/features/chores/chore_form_keyboard_save_test.dart` guards it. Likewise leave the `PopScope` guard and `_isDirty` intact — extend `_isDirty` for any new state field. |

### 7. Retired l10n keys (kept, never deleted)

- `choreFormPatternFollowsStartDate` — "Follows the start date — change the
  start date to change the day." Its whole reason to exist was the hidden
  start-date dependency this ticket removes. Once the weekday set is always
  non-empty and the monthly day/ordinal/weekday are directly picked, nothing
  derives from the start date and the caption would be a lie. Retire it in
  place with a dated `@`-description; delete `_PatternFollowsStartDateHint`
  from `repeat_controls.dart`.
- `monthlyDayOfMonthLabel`, `monthlyNthWeekdayLabel`, `monthlyLastWeekdayLabel`
  — the derived monthly-mode chip labels, replaced by the mode-name labels.
  Retire in place. (`recurrenceSentence` may still use the *shapes* of the
  anchor-subtitle keys; those stay live.)
- `choreFormUnitDay`/`Week`/`Month` (the non-plural forms) are **already**
  unused today — `UnitRow._label` calls only the `…Plural` variants. Leave them
  exactly as they are; this plan does not touch them.

### 8. Ordinal words: "3rd Tuesday", not "third Tuesday" — a deliberate deviation

The design writes the ordinal chip as `third`. This plan renders it as `3rd`
(en) / `3.` (de) via the existing `localizedOrdinal(n, localeName)` in
`recurrence_builder.dart`. Reasons, in order of weight:

1. It is what the app **already** says. `monthlyNthWeekdayLabel` renders
   "On the 3rd Tuesday" / "Am 3. Dienstag" today, and
   `choreFormAnchorScheduleSubtitleMonthNthWeekday` does the same in the anchor
   card. Spelling it out in the sentence while the preview beside it says "3rd"
   is exactly the drift this ticket is trying to prevent.
2. German. "am dritten Dienstag" needs the weak adjective ending, which varies
   with case and would have to be baked into five hand-written strings; "am 3.
   Dienstag" is correct with no declension at all. `localizedOrdinal`'s doc
   comment already explains why the ordinal is computed in Dart and
   interpolated rather than expressed in ICU (gen_l10n has no `selectordinal`).
3. It costs zero new ARB keys.

The one exception is `-1`, which has no numeral form: it needs a new
`choreFormOrdinalLast` key ("last" / "letzten"). Same for the day-of-month
sentinel: `choreFormDayOfMonthLast` ("last day" / "letzten Tag").

If Igor wants the spelled-out words, that is a copy change against five new
key-pairs and does not alter any structure in this plan.

### 9. The multi-weekday semantic, and why the preview is load-bearing

Settled by the ticket and by `g2notes`, restated so the preview test asserts
the right thing: **the week repeats every N weeks, and inside an active week
the chore is due on each selected day.** "Every 2 weeks on Tue and Fri" is two
chores a fortnight, not one alternating. This is exactly what
`_weekOccurrences` already does (`startMonday.addDays(7 * k * interval)`, then
every selected weekday within that week), so the engine needs no change — but
the sentence alone is ambiguous to a reader, which is why the design mandates
three real dates.

On the **completion** anchor, `nextAfterCompletion` instead computes
`completedOn + interval * 7` days and rolls **forward** 0..6 days to the next
day in the set. There is no "three real dates" to show, because the series
depends on when the user ticks — so the preview for the completion anchor is
prose only, matching the prototype's `sentence()` branch for `anchor === 'done'`.
Task 5's test pins both readings by asserting the exact rendered date strings.

---

## Product decisions — ALL RESOLVED 2026-08-18

*Resolved by Igor after independent verification of the three findings in
Analysis §1–§3 (`Recurrence` has no day-of-month field; `validated()` throws at
`recurrence.dart:124-126`; `recurrence` is a JSON `TextColumn`). Each decision
below carries an **obligation** — a thing the plan must actually design, not
merely note. The obligations are binding on the tasks that reference them.*

### OPD-1 — The monthly day-of-month hole needs a `Recurrence` field that does not exist — **ACCEPTED: add it**

**Decision: add `monthlyDayOfMonth` (`int?`; `1..31`, or `-1` = last day).**
Deriving the day from `startDate.day` is exactly the implicit behaviour this
redesign exists to retire — nobody understands that the start date silently
sets the monthly day — and dropping the hole guts a third of the design. It is
not a migration (Analysis §2).

**Obligation — the divergence must be mitigated, not merely disclosed.**
Worked out in full in **Analysis §2a**; the binding conclusions are:

1. **The form keeps `startDate.day` aligned to the chosen day.** Since the old
   client computes `min(startDate.day, daysInMonth)` and the new one computes
   `min(D, daysInMonth)`, `startDate.day == D` makes the two **identical for
   the whole infinite series** — divergence is zero, not bounded, for every
   `D` in `1..31`. `monthlyDayOfMonth` is authoritative; `startDate.day` is a
   redundant mirror kept for old clients, and the new client ignores it if
   they ever disagree.
2. **Alignment moves forward only** — the nearest date on or after the current
   start date whose day is `D` — so `firstDueDate` never lands in the past.
   The move is visible in the Start date field in the same form.
3. **The residual is "last day" alone**, at most **3 days**, and always with
   the old client **early**, never late — so nothing is silently missed. It is
   zero when the start date sits in a 31-day month, ≤1 day for a 30-day month,
   ≤3 days for February. Task 6 prefers a 31-day-month alignment when that does
   not distort the series.
4. **This must be stated in `recurrence-engine.md`** (Task 9) so the next
   reader meets it in the spec rather than in a bug report.

### OPD-2 — Monthly "a weekday" mode cannot coexist with the completion anchor — **ACCEPTED: keep the reset, but the user must learn why at the moment it happens**

**Decision: the completion anchor is not offered as a choice the user can make
and lose.** Applying the design's own rule — *fields that do not apply do not
exist* — rather than inventing a second one for this case. A disabled card is
not a pattern this design uses anywhere.

**Obligation — the mechanism, which Task 6 implements:**

1. While the unit is months **and** the monthly mode is "a weekday", the
   "Counting from" section renders **only** the fixed-schedule card, plus one
   `bodySmall` line stating why: an nth-weekday pattern is a position in the
   calendar, so there is nothing for a completion date to count from.
   (New ARB key `choreFormCountingFromWeekdayOnly`.)
2. The user therefore never selects the completion anchor here and never has a
   selection silently reverted.
3. The **converse** move — the user is on the completion anchor, then switches
   the monthly mode to "a weekday" — still has to change the anchor. It must
   announce itself in the same breath: the "Counting from" section collapses to
   the one card **and** shows the same line, on the same frame the sentence
   rewrites. No snackbar, no dialog; the explanation is in the section whose
   contents changed.
4. **`Recurrence.validated`'s throw must be unreachable by construction, not by
   hope.** `buildRecurrence` is the single funnel to a persisted rule: it must
   assert that `monthlyMode == nthWeekday` implies `anchor == schedule`, and
   Task 7 adds a widget test that drives the form through the converse move and
   saves, asserting the persisted rule is valid rather than that no exception
   was thrown.

### OPD-3 — Does the sentence reach the paused rows and the chore tiles? — **ACCEPTED: form + paused rows, NOT the tiles**

**Decision: two places, not three.** A paused row answers *"what was this
doing?"*, which is exactly what recurrence prose is for, and today it says only
"Paused". A pending tile answers *"when is this due?"* and already carries a
due-date chip; adding prose to every tile spends density on the most-opened
screen for information the user did not come there for.

**Record this explicitly (Task 9):** the design's "one formatter serves three
places" was an assumption that did not survive contact with the code — there
were **zero** places, and **two** is the right number. Task 10 is no longer
conditional; it ships.

### OPD-4 — Does the interval stay typeable? — **ACCEPTED: keep the `TextField`**

**Decision: keep it typeable.** A bounded picker would forbid legitimate rules
like "every 90 days"; the prototype's cap of 6 is a prototype affordance, not a
requirement. This also preserves `validateInterval`, `IntervalError`,
`choreFormIntervalTooSmallError`, the spec's test-matrix item 7, and the two
existing test files that reach `chore_form.repeat.interval` by descendant
`TextField`.

**Obligation — it must read as a hole in the sentence, not as a form input
parked inside a paragraph.** Task 5 implements:

1. **Size.** The field is wrapped in the same `_SentenceChip` container as every
   other hole — `BoxConstraints(minWidth: 40, minHeight: 40)`, identical fill,
   border, radius and ink — so it is a 40px target inside the 36–44px band and
   is visually a sibling of the unit chip, not a `LabelledFieldCard`. No
   floating label, no helper text, no underline: `InputBorder.none` with the
   chip's own border doing the work.
2. **Width.** It sizes to its content (an `IntrinsicWidth` over a 1–3 character
   field), so "2" and "90" both sit tight in the sentence and the surrounding
   words do not jump apart. A hard `maxLength: 3` keeps it from growing without
   bound mid-sentence.
3. **Text scale 2.0.** The chip's `minHeight` is a floor, not a fixed height —
   the container grows with the text, and the `Wrap` re-flows the sentence
   around it. Task 7's `theme_and_scale_test.dart` check covers this; if it
   overflows, the fix is the constraint, never a smaller tap target.
4. **Empty state.** An empty field mid-sentence reads as broken in a way a chip
   never does, so the inline `errorText` path stays live and the preview line
   falls back to the last valid interval (`int.tryParse(...) ?? 1`, the
   behaviour `RepeatControls` already has) rather than disappearing.
## Tasks

*Tasks 1–5 are invisible to the user. **Task 6 is the flip** — the form changes
under the user there, and Tasks 7 and 8 must land with it or the suite and the
E2E gate go red.*

### Task 1 — Extract the recurrence formatter, with zero behaviour change

- [ ] Create `lib/features/chores/recurrence_sentence.dart` (note: **not**
      under `chore_form/`, so `chore_paused_section.dart` can import it —
      Analysis §1).
- [ ] Move the entire body of `AnchorRow._subtitle` / `_scheduleSubtitle` from
      `lib/features/chores/chore_form/repeat_section.dart` into a public
      `String recurrenceSentence(...)` there, taking `AppLocalizations l10n`,
      `String localeName`, and the rule's fields (or a `Recurrence` plus the
      `PlainDate startDate` — pick one and document it; the fields are more
      convenient for the form, which holds them loose).
- [ ] `AnchorRow` now calls it. **No ARB key changes, no copy changes, no
      widget changes.**
- [ ] Doc comment must state that this is the single formatter for recurrence
      prose in the app, name its callers, and say why a second one is a
      regression.

**RED:** write the new unit test *first*, at
`test/features/chores/recurrence_sentence_test.dart`, asserting the exact
current strings for en and de across all eight shapes (day, week 1 weekday,
week N weekdays, month day-of-month, month nth-weekday, month last-weekday, and
the three completion shapes). Load localizations with
`AppLocalizations.delegate.load(const Locale('de'))` — a plain unit test, no
widget pump needed. It fails to **compile**: `recurrenceSentence` does not
exist. Once it compiles, the strings must match what `chore_form_repeat_copy_test.dart`
already asserts on screen — if any differ, the extraction changed behaviour and
is wrong.

**Also green afterwards, unchanged:** `chore_form_repeat_copy_test.dart`,
`chore_form_recurrence_test.dart`.

### Task 2 — New ARB keys for the sentence and its chips

- [ ] Add to `app_en.arb` (each with an `@`-description) and `app_de.arb`
      (informal du-form, literal umlauts):
  - `choreFormSentenceDay(interval, unit)` — en `"Repeat every {interval} {unit}"`,
    de `"Wiederholung: alle {interval} {unit}"`.
  - `choreFormSentenceWeek(interval, unit)` — en `"Repeat every {interval} {unit} on"`,
    de `"Wiederholung: alle {interval} {unit} am"`. (The weekday chips are the
    next row down, per the design markup — the trailing preposition is
    deliberate, and a translator can drop it.)
  - `choreFormSentenceMonthDayOfMonth(interval, unit, day)` — en
    `"Repeat every {interval} {unit} on the {day}"`, de
    `"Wiederholung: alle {interval} {unit} am {day}"`.
  - `choreFormSentenceMonthWeekday(interval, unit, ordinal, weekday)` — en
    `"Repeat every {interval} {unit} on the {ordinal} {weekday}"`, de
    `"Wiederholung: alle {interval} {unit} am {ordinal} {weekday}"`.
  - `choreFormDayOfMonthLast` — en `"last day"`, de `"letzten Tag"`.
  - `choreFormOrdinalLast` — en `"last"`, de `"letzten"`.
  - `choreFormMonthlyModeDayOfMonth` — en `"A day of the month"`, de
    `"Ein Tag im Monat"`.
  - `choreFormMonthlyModeWeekday` — en `"A weekday"`, de `"Ein Wochentag"`.
  - `choreFormCountingFromLabel` — en `"Counting from"`, de `"Gezählt ab"`.
  - `choreFormCountingFromWeekdayOnly` (**OPD-2**) — en
    `"A weekday pattern is a position in the calendar, so there is nothing for a completion date to count from."`,
    de
    `"Ein Wochentagsmuster ist eine Position im Kalender — es gibt also nichts, wovon ein Erledigungsdatum aus zählen könnte."`
  - `choreFormPreviewNextThree(pattern, first, second, third)` — en
    `"{pattern}. Next {first}, then {second} and {third}."`, de
    `"{pattern}. Als Nächstes {first}, dann {second} und {third}."`
  - `choreFormPreviewCompletionRolledForward(base, weekdays)` — en
    `"{base}, rolled forward to the next {weekdays}."`, de
    `"{base}, weitergeschoben auf den nächsten {weekdays}."`
  - `choreFormPreviewCompletionDependsOnDay(base)` — en
    `"{base} — the next due date depends on the day you do it."`, de
    `"{base} — das nächste Fälligkeitsdatum hängt vom Tag ab, an dem du sie erledigst."`
- [ ] **Do not add** an ICU plural to the four sentence keys. The number is a
      chip and the unit noun is a chip whose own text already comes from the
      existing `choreFormUnitDayPlural`/`WeekPlural`/`MonthPlural`. The German
      colon framing ("Wiederholung: alle …") is chosen precisely so no gendered
      accusative article (*jeden* Tag / *jede* Woche) leaks into the frame —
      record that reasoning in the `@`-descriptions so a future translator does
      not "fix" it back into a broken gendered form.
- [ ] `{interval}`, `{unit}`, `{day}`, `{ordinal}`, `{weekday}`, `{pattern}`,
      `{first}`… are all `type: String`. `{pattern}` and `{base}` receive an
      already-localized whole clause from `recurrenceSentence` — the same
      composition-of-wholes the existing `{weekdays}` placeholder already uses.
- [ ] Run `flutter gen-l10n`; commit the regenerated
      `lib/l10n/app_localizations*.dart`.
- [ ] **No ICU `zero{}` branch anywhere.**

**RED:** none of these is a behaviour change, so this task has no test of its
own. Its verification is that `flutter gen-l10n` succeeds and
`flutter analyze --fatal-infos` is clean. Any key present in `app_en.arb` but
missing from `app_de.arb` fails generation — that is the guard.

### Task 3 — `Recurrence.monthlyDayOfMonth`

- [ ] Add `final int? monthlyDayOfMonth;` to `Recurrence` with a doc comment:
      `MonthlyMode.dayOfMonth` only; `1..31`, or `-1` for "the last day of the
      month"; `null` means "derive from the chore's start date", which is what
      every rule persisted before this field meant.
- [ ] Thread it through the const constructor, `Recurrence.validated`,
      `Recurrence.monthlyOnDay`, `toJson` (key `monthly_day_of_month`),
      `fromJson` (`is! int?` check, exactly like `monthly_ordinal`), `==`, and
      `hashCode`.
- [ ] `validated` throws `ArgumentError` when: it is non-null and
      `unit != month`; it is non-null and `monthlyMode != dayOfMonth`; or it is
      not `null`, not `-1`, and not in `1..31`.
- [ ] In `recurrence_engine.dart`, `_monthCandidate`'s `dayOfMonth` branch:
      `null` → today's `startDate.day` behaviour, byte for byte; `-1` →
      `PlainDate.daysInMonth(year, month)`; `1..31` → clamp to
      `daysInMonth`. Update the `scheduleOccurrences` doc comment's **month**
      bullet.
- [ ] `nextAfterCompletion`'s month branch is `completedOn.addMonths(interval)`
      and stays exactly as it is — `addMonths` already clamps. Say so in the
      doc so a reader does not expect the new field to apply there.
- [ ] `lib/domain/` stays **`dart:core`-only** — add no imports.
- [ ] **Document the alignment contract on the field itself** (OPD-1 obligation,
      Analysis §2a): callers are expected to keep `startDate.day` equal to
      `monthlyDayOfMonth` so that a client predating this field computes the
      identical series; the field is authoritative and the engine never reads
      `startDate.day` when it is non-null. State that `-1` is the one value with
      no exact `startDate` mirror, and name the ≤3-day, always-early residual.
      This is a *documented invariant maintained by the form*, not something
      `validated` can enforce — `Recurrence` does not see the start date.

**RED:** extend `test/domain/` recurrence tests (find the existing recurrence
and engine test files and add to them; do not create a parallel suite) with:
(1) a JSON round-trip carrying `monthlyDayOfMonth: -1`; (2) `fromJson` on a map
with **no** `monthly_day_of_month` key yielding `null` and the old behaviour —
this is the back-compat guard and it must pass a rule read from a
pre-existing serialized string; (3) `scheduleOccurrences` for
`monthlyDayOfMonth: 31` starting 2026-01-31 yielding Jan 31, **Feb 28**, Mar 31
(the clamp the preview will show); (4) `monthlyDayOfMonth: -1` starting
2026-01-15 yielding Jan 31, Feb 28, Mar 31; (5) each `validated` rejection; and **(6) the convergence guard** — for
`monthlyDayOfMonth: 20` with `startDate` = 2026-01-20, assert that
`scheduleOccurrences` yields exactly the same first six dates as the **same
rule with `monthlyDayOfMonth: null`** (which is precisely what an un-updated
client computes). Repeat for `D = 31` from 2026-01-31, covering the February
clamp. This is the test that pins Analysis §2a's claim that alignment closes
the divergence to zero; if it ever goes red, the mitigation is broken and the
sync hazard is live again.
**Expected failure:** (1), (3), (4) fail to compile (no such named parameter);
(2) compiles but fails on the `null` getter not existing; (5) and (6) fail to
compile. If (2) passes before the field exists, the test is asserting nothing.
Note (6) would *vacuously* pass if written against two `null` rules — assert the
two rules differ in that field before comparing their series.

### Task 4 — Grow `recurrenceSentence` to produce the preview line

- [ ] Add `String recurrencePreview(...)` to
      `lib/features/chores/recurrence_sentence.dart`, taking the same
      recurrence fields plus `PlainDate startDate` and `PlainDate today`.
- [ ] **Schedule anchor:** compute the pattern clause with the existing
      `recurrenceSentence`, then take the first three occurrences on or after
      `today` from `scheduleOccurrences(rule, startDate)` — it is a lazy
      infinite `Iterable`, so `.where((d) => !d.isBefore(today)).take(3)` is
      correct and terminates. Format each with
      `DateFormat.MMMEd(localeName)` (the same `package:intl` formatter
      `futureDueText` already uses for absolute dates in
      `chore_occurrence_tile.dart` — do **not** invent a second date format).
      Feed all four into `choreFormPreviewNextThree`.
- [ ] **Completion anchor:** no real dates exist (the series depends on when the
      user ticks). Use `recurrenceSentence`'s completion clause as `{base}`,
      then: week unit with **more than one** weekday →
      `choreFormPreviewCompletionRolledForward`; every other case →
      `choreFormPreviewCompletionDependsOnDay`. This mirrors the prototype's
      `sentence()` `anchor === 'done'` branch exactly.
- [ ] Extend `recurrenceSentence` itself to render the new monthly holes:
      explicit day-of-month (`choreFormDayOfMonthLast` for `-1`, otherwise
      `localizedOrdinal(day, localeName)`), and an nth-weekday ordinal that
      reads from the rule's own `monthlyOrdinal`/`monthlyWeekday` rather than
      re-deriving them from `startDate` via `nthWeekdayOrdinalOf`.

**RED:** extend `test/features/chores/recurrence_sentence_test.dart` with, at
minimum: (1) **the multi-weekday reading** — `interval: 2`, `weekdays: {2, 5}`,
schedule anchor, `startDate` = Mon 2026-08-03, `today` = Mon 2026-08-03 →
assert the preview names **Tue 4 Aug, Fri 7 Aug, Tue 18 Aug** (two dates in the
first active week, then a skipped week), which is the whole reason the preview
exists; (2) **the clamp** — `monthlyDayOfMonth: 31` from 2026-01-31 naming
Feb 28; (3) the completion + multi-weekday roll-forward wording; (4) the
completion + day-unit "depends on the day you do it" wording; (5) each of (1)
and (2) again in `de`. **Expected failure:** compile error —
`recurrencePreview` does not exist. Assert on the **exact full string**, not on
`contains` — a `contains` assertion here would pass against a formatter that
drops a date.

### Task 5 — The `RepeatSentence` widget

- [ ] New `lib/features/chores/chore_form/repeat_sentence.dart`.
- [ ] A public `RepeatSentence` `StatelessWidget` taking the current
      interval/unit/monthlyMode/day/ordinal/weekday values plus one callback
      per hole.
- [ ] Picks the ARB message by shape (day / week / month+dayOfMonth /
      month+weekday), calls it with the noncharacter sentinels `U+FDD0`…
      `U+FDD3` (Analysis §4 — one per hole *position*, never reused; the
      month+weekday shape is the four-hole case), splits the returned string
      with a capturing `RegExp`, splits each literal run on whitespace into one
      `Text` per word, and emits the hole widget wherever its sentinel
      appeared.
- [ ] Result is a `Wrap(crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8, runSpacing: 8)`.
- [ ] `assert` that each sentinel handed in was found exactly once — a dropped
      placeholder in a translation would otherwise silently remove a control.
- [ ] Each hole is a `_SentenceChip`: `InkWell` + `Container` with
      `minHeight: 40` and `minWidth: 40` via `BoxConstraints` (inside the
      36–44px band the design mandates), `primaryContainer` fill,
      `famdoColors(context).primaryOutline` border, `primary` ink, radius 11,
      trailing `Icons.unfold_more` at 16 for the holes that open a menu.
      **Reference `RepeatRadioCard` for the exact token names** — do not invent
      colour roles.
- [ ] Every hole wrapped in `semantic()` with its id from Analysis §6, and
      given a `Semantics(button: true)` label naming what it changes, since the
      visible chip text alone ("2", "weeks") is meaningless out of context to a
      screen reader.
- [ ] Menus: `MenuAnchor` or `showMenu` — pick one and use it for all holes.
      Unit menu entries carry `chore_form.repeat.unit.<day|week|month>`.
- [ ] **The interval hole (OPD-4 obligation — it must read as a hole, not as a
      form input parked inside a paragraph):** a `TextField` inside the **same**
      `_SentenceChip` container as every other hole — identical fill, border,
      radius, ink, and `BoxConstraints(minWidth: 40, minHeight: 40)` — with
      `InputBorder.none`, no floating label, no helper text, and no underline,
      so the chip's own border does all the work. Wrapped in
      `semantic('chore_form.repeat.interval', child: …)`, keeping
      `keyboardType: TextInputType.number` and the existing `errorText` path.
      `IntrinsicWidth` so "2" and "90" both sit tight and the surrounding words
      do not jump apart; `maxLength: 3` (with `counterText: ''`) so it cannot
      grow without bound mid-sentence.
- [ ] `minHeight` is a **floor, not a fixed height** — the chip grows with the
      text at scale 2.0 and the `Wrap` re-flows around it. If Task 7's
      text-scale check overflows, the fix is the constraint; **never** shrink a
      tap target below 36px.

**RED:** `test/features/chores/chore_form/repeat_sentence_test.dart`, driven
through `testChoreApp` (open the form, toggle repeat on) rather than a bare
pump. Assert: (1) with unit = week, `chore_form.repeat.unit` exists and
`chore_form.repeat.monthly_day` does **not**; (2) tapping
`chore_form.repeat.unit` then `chore_form.repeat.unit.month` makes
`chore_form.repeat.monthly_day` appear and `chore_form.repeat.weekday.1`
disappear — *do not exist*, per the design, so assert `findsNothing`, never
"disabled"; (3) the rendered words of the sentence are present as separate
`Text` widgets in order. **Expected failure:** compile error — the widget file
does not exist. (2) will additionally fail against Task 6's form until the flip
lands; if you cannot make (1)–(3) fail first, you are testing the old form.

### Task 6 — **THE FLIP:** rewrite `RepeatControls` around the sentence

**This is the task that makes the change live.** Everything before it is
invisible to the user.

- [ ] `lib/features/chores/chore_form/repeat_controls.dart` becomes, top to
      bottom: `RepeatSentence` → (week only) `WeekdayChips` → (month only) the
      monthly-mode row → a 1px `Divider` hairline → a
      `choreFormCountingFromLabel` section header (11sp, uppercase,
      `onSurfaceVariant`, letter-spacing 0.7, per the design markup) →
      `AnchorRow` → the preview line.
- [ ] Preview line: leading `Icons.event_upcoming` at 18 in `primary`, then
      `recurrencePreview(...)` as `bodySmall`/`onSurfaceVariant`, wrapped in
      `semantic('chore_form.repeat.preview', child: …)`. **Always visible**,
      for every unit and both anchors.
- [ ] Delete `IntervalField` and `UnitRow` from `repeat_section.dart` (the
      widgets — the **ids move into `RepeatSentence`, they are not deleted**).
      Keep `RepeatToggle` and `AnchorRow` in place.
- [ ] Delete `_PatternFollowsStartDateHint` and retire
      `choreFormPatternFollowsStartDate` in the ARB per the Global Constraints
      (keep the key, rewrite its `@`-description with today's date and the
      reason).
- [ ] `MonthlyModeRow`'s labels become `choreFormMonthlyModeDayOfMonth` /
      `choreFormMonthlyModeWeekday`; its `startDate` parameter and its
      `localizedOrdinal`/`weekdayName` calls go away. Retire
      `monthlyDayOfMonthLabel`, `monthlyNthWeekdayLabel`,
      `monthlyLastWeekdayLabel`. Its two ids are unchanged. Consider whether it
      should stay two `RepeatRadioCard`s or become the design's two side-by-side
      chips — the design shows chips; either keeps the ids, so this is a look
      call, not a structural one.
- [ ] In `chore_form_screen.dart`, add state for the new directly-editable
      fields: `int? _monthlyDayOfMonth`, `int _monthlyOrdinal`,
      `int _monthlyWeekday`. Seed them from the start date on first open
      (`startDate.day`, `nthWeekdayOrdinalOf(startDate)`, `startDate.weekday`)
      and from the loaded rule in `_loadExisting`, falling back to the same
      derivation when the stored rule's fields are `null`.
- [ ] **Weekly now requires at least one weekday.** `_toggleWeekday` refuses to
      remove the last selected day. On open (and on switching the unit to
      week), if `_weekdays` is empty, seed it with `{_startDate.weekday}`.
- [ ] **`_captureInitialSnapshot()` must run *after* every seed above**, in both
      the new-chore path and `_loadExisting`. Otherwise opening an existing
      chore whose stored rule has an empty weekday set makes the form dirty on
      arrival and a plain back-tap raises the discard dialog — a C4 regression
      (Analysis §3b).
- [ ] Extend `_isDirty` and `_captureInitialSnapshot` to cover
      `_monthlyDayOfMonth`, `_monthlyOrdinal`, `_monthlyWeekday`, gated on
      `_repeatEnabled` exactly like the existing recurrence sub-fields.
- [ ] `buildRecurrence` in `recurrence_builder.dart` takes the three new values
      instead of deriving them from `startDate`. Keep `nthWeekdayOrdinalOf`
      exported — it is now the *seeding* helper, and say so in its doc.
- [ ] **OPD-2 mechanism — the completion anchor is never offered where it
      cannot apply.** While `unit == month && monthlyMode == nthWeekday`, the
      "Counting from" section renders **only** the schedule card, plus one
      `bodySmall` `choreFormCountingFromWeekdayOnly` line saying why. The
      completion card is *absent*, not disabled — the design has no disabled
      pattern. `chore_form.repeat.anchor.completion` therefore does not exist in
      that state, exactly as `chore_form.repeat.weekday.1` does not exist for
      months; that is the same rule, not a special case.
- [ ] **The converse move must explain itself on the same frame.** A user
      already on the completion anchor who switches the monthly mode to "a
      weekday" still has their anchor changed. `_onMonthlyModeChanged` sets
      `_anchor = RecurrenceAnchor.schedule`, and on that same rebuild the
      section collapses to one card and the explanation line appears beside it.
      No snackbar, no dialog: the explanation lives in the section whose
      contents changed. `_onAnchorChanged`'s existing reset of `_monthlyMode`
      stays as the belt to this braces.
- [ ] **Make `Recurrence.validated`'s throw unreachable by construction.**
      `buildRecurrence` is the single funnel to a persisted rule: add an
      `assert(monthlyMode != MonthlyMode.nthWeekday || anchor == RecurrenceAnchor.schedule)`
      with a message naming OPD-2, so a future refactor that reintroduces the
      combination fails in debug at the funnel rather than as an `ArgumentError`
      thrown out of a save the user already tapped.
- [ ] **OPD-1 alignment (Analysis §2a) — keep `startDate.day` on the chosen
      day.** When the monthly day-of-month hole changes to `D` (1..31), move
      `_startDate` **forward** to the nearest date on or after the current
      `_startDate` whose day is `D`, and `setState` so the Start date field
      visibly updates in the same frame. Never move it backwards —
      `firstDueDate` must not land in the past.
- [ ] For `D == -1` ("last day"), align `_startDate` to the last day of its own
      month; prefer the 31st of a 31-day month when the start date may sit in
      one **without shifting the month series** (i.e. `interval == 1`, where
      every month is an occurrence so the choice of start month does not change
      the schedule). Otherwise accept the ≤3-day, always-early residual from
      Analysis §2a. Comment the branch with that reasoning — a later reader
      will otherwise "tidy" the 31-day preference away.
- [ ] Because alignment writes `_startDate`, it must be reflected in
      `_isDirty` (it already is — `_startDate != _initialStartDate` is checked
      today) and must **not** run during `_loadExisting` seeding, or opening an
      existing chore would move its start date and mark the form dirty on
      arrival. Align only in response to an actual user tap on the day hole.
- [ ] **Do not touch** the `PopScope`, `canPop: !_isDirty`,
      `onPopInvokedWithResult`, or the `bottomNavigationBar` +
      `MediaQuery.viewInsetsOf` padding on `chore_form.save`. All three are
      fixes from earlier rounds with tests guarding them
      (`chore_form_unsaved_changes_test.dart`,
      `chore_form_keyboard_save_test.dart`).

**RED:** Task 5's test (2) — the month/week hole swap through the real form —
now fails against the old `RepeatControls`, which still renders a segmented
control and a radio row. Also expect `chore_form_repeat_copy_test.dart` and
parts of `chore_form_recurrence_test.dart` to go red here; that is Task 7's
subject, and they must **not** be silenced by editing them inside this task.

### Task 7 — Update and extend the widget tests

- [ ] `chore_form_recurrence_test.dart` — its id-based assertions survive; its
      unit taps become two-step (open `chore_form.repeat.unit`, then tap
      `chore_form.repeat.unit.<x>`). Add a case: **saving with an explicitly
      picked monthly day** produces a `Recurrence` with that
      `monthlyDayOfMonth`, asserted by reading the row back through the
      repository — the file's existing pattern.
- [ ] `chore_form_repeat_copy_test.dart` — rewrite around the sentence. The
      unit-pluralization assertion is still exactly right and must survive:
      typing `2` into the interval field re-renders the unit chip as "Months"
      with no re-tap. Replace the `_PatternFollowsStartDateHint` assertions with
      an assertion that the hint is **gone** and the sentence names the day
      directly.
- [ ] `chore_form_validation_test.dart` — per **OPD-4** the interval stays a
      `TextField`, so this file needs only the new descendant path; the
      interval-0 error and its recovery must still pass unchanged in substance.
      Do not weaken it.
- [ ] New (**OPD-2**): **the completion anchor does not exist in monthly
      weekday mode.** Set unit = month, pick the "A weekday" mode, assert
      `chore_form.repeat.anchor.completion` is `findsNothing`,
      `chore_form.repeat.anchor.schedule` is `findsOneWidget`, and the
      `choreFormCountingFromWeekdayOnly` line is visible.
- [ ] New (**OPD-2**): **the converse move saves a valid rule.** Set unit =
      month, pick the completion anchor, then switch to "A weekday" mode; assert
      the explanation line appears, then tap save and read the row back —
      assert the persisted `Recurrence` has `anchor == schedule` and
      `monthlyMode == nthWeekday`. Assert on the **persisted rule**, not merely
      that no exception was thrown; a test that only checks for the absence of a
      throw would pass against a form that silently saved nothing.
- [ ] New (**OPD-1**): **picking a monthly day aligns the start date.** Set unit
      = month, day-of-month mode, pick "the 20th"; assert the Start date field
      now shows a date whose day is 20 and that it is **not earlier** than the
      date it showed before.
- [ ] New: **the preview names three real dates and they are the right ones.**
      Fixed clock via `testChoreApp(today: …)`; set interval 2, unit week,
      weekdays Tue + Fri; assert `chore_form.repeat.preview` contains the exact
      three formatted dates from Task 4's unit test. This is the
      multi-weekday-semantics guard at the UI level.
- [ ] New: **the discard guard does not fire on opening an existing chore with
      an empty stored weekday set.** Seed such a chore, open the form, tap back,
      assert no discard dialog and that the list is shown — the C4 regression
      from Analysis §3b.
- [ ] New: **the last weekday cannot be deselected.** Select exactly one day,
      tap it, assert it is still selected.
- [ ] `theme_and_scale_test.dart` — confirm the form still renders at
      `textScaleFactor` 2.0 and in `ThemeMode.dark` with no overflow. This is
      the release gate the `Wrap` approach was chosen to protect; if it fails,
      the sentence's `Wrap` or the chip's `BoxConstraints` is wrong — do not
      "fix" it by shrinking the tap targets below 36px.

**RED:** each new test must fail before its subject exists. The preview test
fails with `findsNothing` on `chore_form.repeat.preview`; the deselect test
fails because today's `_toggleWeekday` happily empties the set; the discard test
fails with the dialog appearing.

### Task 8 — Update the three Maestro flows (must land in the same commit as Task 6)

- [ ] `e2e/flows/settings/chore_history.yaml`,
      `e2e/flows/chores/skip_undo_journey.yaml`,
      `e2e/flows/chores/recurring_complete_advances.yaml` each do
      `tapOn: {id: "chore_form.repeat.unit.day"}` immediately after
      `tapOn: {id: "chore_form.repeat.toggle"}`. Insert
      `tapOn: {id: "chore_form.repeat.unit"}` before each, with a comment
      naming this plan and saying the unit is now a menu, not a segment.
- [ ] Grep the whole `e2e/` tree once more for `chore_form.repeat` before
      declaring this done — three flows is what exists at `0bee683`, not a
      guarantee about the tree you are working in.
- [ ] Do **not** run Maestro locally. Per the project's standing note, the E2E
      gate is GitHub CI; local emulator runs on this machine are noise. Push
      and let CI answer.

**RED:** not applicable — this is the flow-side half of Task 6's change. Its
verification is CI going green on the branch. If CI was green before Task 6 and
red after, and this task is done, read the failure rather than adding waits.

### Task 9 — Amend the binding specs

- [ ] `docs/specs/ui-foundation-chores.md` — rewrite the repeat bullets under
      "Form screen (create + edit)" to describe the sentence, the "does not
      exist" rule for irrelevant controls, the "Counting from" section, and the
      always-visible preview. Remove the `_PatternFollowsStartDateHint` bullet
      (it describes retired behaviour). Add the four new ids to the
      Semantic-IDs list. Amend test-matrix item 8 to name the preview, and item
      7 only if OPD-4 resolved to (a).
- [ ] `docs/specs/theme-v2.md` §4.4 — replace the "Interval unit … become
      segmented controls" and "The anchor choice becomes two explanatory radio
      cards" bullets with the sentence layout. **Explicitly record the §0
      exception:** `chore_form.repeat.unit.<day|week|month>` moved from
      `ButtonSegment` labels to menu entries, why (the design's behaviour
      change, which §0 itself routes to a separate spec), and that the three
      Maestro flows were updated in the same commit. §0's "no id removed" rule
      is otherwise untouched — nothing was deleted.
- [ ] `docs/specs/ui-foundation-chores.md` — also record that the design's
      "one formatter serves three places" did not survive contact with the code:
      there were **zero** places rendering recurrence prose outside the form,
      and **two** (form + paused rows) is the right number. Say why the tile is
      excluded, so nobody "completes" the third place later.
- [ ] `docs/specs/recurrence-engine.md` §2 — add
      `monthlyDayOfMonth` to the model listing, add its two validation rules to
      the `validated` list, add `monthly_day_of_month` to the JSON key list,
      and note the `-1` = "last day" convention alongside `monthlyOrdinal`'s
      identical `-1`. **Record the alignment invariant and its residual in
      full** (Analysis §2a): that the form keeps `startDate.day == monthlyDayOfMonth`
      so a client predating the field computes an identical series; that this
      closes the divergence to zero for `1..31`; and that "last day" retains a
      ≤3-day, always-early residual, zero when the start date sits in a 31-day
      month. The next reader must meet this in the spec, not in a bug report.
- [ ] Do **not** edit `docs/backlog.md` or `docs/feedback/`.

**RED:** not applicable (documentation). Verify by re-reading each amended
section against the shipped code, not against this plan.

### Task 10 — Adopt the sentence in the paused rows

- [ ] `chore_paused_section.dart`'s `_PausedRow` subtitle `Wrap` gains a
      `Text(recurrenceSentence(...))` for chores whose `chore.recurrence` is
      non-null, beside the existing category badge and "Paused" badge.
      `ChoreWithDetails` already carries the whole `Chore`, so the rule and the
      start date are both in hand — verify this rather than assuming it.
- [ ] Do **not** add it to `chore_occurrence_tile.dart`. The tile answers
      "when is this due" and already carries a due chip; recurrence prose there
      spends density on the most-opened screen for something the user did not
      come there for (**OPD-3**).

**RED:** extend `test/features/chores/paused_section_test.dart` — seed a paused
weekly chore, expand the section, assert the row shows the recurrence clause.
Fails with `findsNothing` because the row renders no recurrence text today.

### Task 11 — Whole-branch review

- [ ] `flutter analyze --fatal-infos` clean.
- [ ] Full suite green:
      `env -u GIT_DIR -u GIT_INDEX_FILE flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY=`
- [ ] Read the whole diff line by line before proposing a merge. Specifically
      re-check: no `semantic()` id deleted; no ARB key deleted; the `PopScope`
      guard and the `chore_form.save` keyboard-inset padding untouched;
      `lib/domain/` still imports nothing outside `dart:core`; every retired ARB
      key carries a dated `@`-description saying what retired it.
- [ ] Confirm CI's Maestro run is green on the branch.
- [ ] Report G-2 as closable in the summary. Do not edit `docs/backlog.md`.

---

## Success criteria

1. The repeat block is one sentence with tap-target holes; controls irrelevant
   to the chosen unit are **absent**, not disabled.
2. The anchor sits below a hairline under "Counting from".
3. A preview line naming three real dates is visible for every schedule-anchored
   configuration, and the completion-anchored prose is visible for the rest.
4. **One** formatter renders recurrence prose — `recurrenceSentence` /
   `recurrencePreview` in `lib/features/chores/recurrence_sentence.dart` —
   serving **two** surfaces (the form and the paused rows), not the three the
   design assumed and not the zero that existed. No second switch over
   `RecurrenceUnit` producing user-facing prose exists anywhere in `lib/`.
4a. **Cross-version convergence holds.** The form keeps
   `startDate.day == monthlyDayOfMonth`, and Task 3's test (6) proves a rule
   with an explicit day yields the identical series to the same rule without
   one. The only residual is "last day": ≤3 days, always with the older client
   *early*, never late, and zero when the start date sits in a 31-day month.
4b. **`Recurrence.validated` cannot be reached in a throwing state from the
   UI.** The completion anchor is absent — not disabled — wherever the monthly
   weekday mode is active, the converse switch resets the anchor and explains
   itself on the same frame, and `buildRecurrence` asserts the invariant at the
   single funnel.
5. Nothing in the repeat pattern derives silently from the start date any more:
   the weekday set is always non-empty, and the monthly day / ordinal / weekday
   are directly picked. `choreFormPatternFollowsStartDate` is retired.
6. Every user-visible string is an ARB key present in both locales; German is a
   whole sentence per shape, **never** a concatenation of fragments — for the
   four reasons in Analysis §4, which the plan states so nobody "simplifies"
   them back later.
6a. Every hole in the sentence, the interval `TextField` included, is a 36–44px
   tap target sharing one chip container, and the sentence re-flows rather than
   overflowing at text scale 2.0.
7. All existing tests green; the E2E suite green **in GitHub CI**; text scale
   2.0 and dark theme green.
8. No drift migration, no schema-version bump — the "next migration is v13"
   note in `docs/backlog.md` is still true.
