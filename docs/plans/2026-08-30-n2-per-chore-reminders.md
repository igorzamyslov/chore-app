# N2 slice 4 — Per-chore reminders, end to end

> **For agentic workers:** REQUIRED SUB-SKILL: use `superpowers:subagent-driven-development`
> (recommended) or `superpowers:executing-plans` to implement this plan
> task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a chore carry its own reminder time, set from the chore form, so
important chores remind individually at their own time instead of being buried
in the 08:00 digest — `docs/specs/notifications-n2.md` **AC1**, satisfied by
this slice alone.

**Architecture:** One nullable synced column (`chores.reminder_minutes`, D1)
already exists after slice 1; slices 2 and 3 already arm and Rule-D-exclude from
it. This slice is therefore **the write path plus the copy**: a new
`ChoreFormReminderRow` widget in the rewritten fill-in-the-blank chore form, a
`reminderMinutes` parameter threaded through `ChoreService`, four localized
strings, and the Settings ceiling sub-line. No planning, no scheduling and no
isolate work is created here.

**Tech Stack:** Flutter 3.44.8, Riverpod, drift, gen_l10n (`app_en.arb`
template + `app_de.arb`), `flutter_local_notifications`, `very_good_analysis`.

---

## Global Constraints

Copied from `docs/specs/notifications-n2.md` and from the repo's standing rules.
Every task's requirements implicitly include this section.

- **Never run `flutter`, `dart`, `supabase` or `docker` yourself if you are a
  planning agent.** The implementer runs them; the global SDK lock is shared.
- Tests run as
  `flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= <file>`.
- Analysis runs as `flutter analyze --fatal-infos --fatal-warnings`. Public
  members need doc comments (`public_member_api_docs` is ON).
- **Every user-visible string goes through gen_l10n.** `lib/l10n/app_en.arb` is
  the template and needs an `@`-description per key; `lib/l10n/app_de.arb`
  carries informal *du*, and uses "Gerät", never "Handy". `app_de.arb` has **no**
  `@`-blocks (verified: it is a flat key→string map).
- **ICU plurals in BOTH locales. No ICU `zero{}` branch anywhere** — CLDR has no
  distinct zero category in en or de, so it never fires; a zero case gets its own
  key.
- `semantic()` is `Widget semantic(String id, {required Widget child})` in
  `lib/app/semantics.dart` — **named** `child`.
- **Never hand-roll a `ProviderScope` pump in a widget test — it HANGS.** Use
  `testChoreApp` / `testFreshChoreApp` from `test/test_utils/pump_app.dart`, or,
  for a leaf widget with no providers, the established bare-`MaterialApp` pattern
  shown in Task 2. `openSettingsTab` lives in
  `test/features/settings/settings_test_utils.dart`.
- **G-14: `flutter test` draws the Ahem-style `FlutterTest` font.** Widget tests
  cannot measure whether text physically fits. Never write an assertion that
  pretends otherwise, and never write a "fit check" that computes its own
  constraint and asserts against it — wave 6 found four tests that could not fail,
  one of them exactly that shape.
- **Every test in this plan states its expected RED failure mode.** After green,
  the implementation must be **inverted** and shown to break **at the test step**.
  A failure at `flutter analyze` is not a valid red — if inverting a change only
  breaks the analyzer, the test is not testing anything.
- **Do not regress the chore form's two shipped properties**
  (`lib/features/chores/chore_form_screen.dart`): the `PopScope` unsaved-changes
  guard (`canPop: !_isDirty`), and the Save button living in the `Scaffold`'s
  `bottomNavigationBar` wrapped in a `Padding` whose bottom is
  `MediaQuery.viewInsetsOf(context).bottom`. Task 4 adds an explicit regression
  test for the first and an explicit presence assertion for the second.
- **Reminders are one-shot notifications, not alarms** (§2.6). No string in this
  slice may promise alarm-like behaviour, guaranteed delivery, or exact timing.
- Constants come from `lib/domain/reminder_planner.dart` (slice 2):
  `defaultReminderMinutes = 1080` (18:00), `reminderCeiling` (**derived**, never
  written as `33`), `reminderArmWindowDays = 14`.

---

## Task 0 — refresh pass (implementation, 2026-08-30)

This plan was written **before** slices 1–3 existed. They have since merged into
`integration/wave-7` at `96933dd`, so every interface below is now real code and
was re-verified against it rather than against the spec. Everything the
"Dependencies" table promises **landed as promised**; what was stale was
citations and one omitted parameter. Corrections, and why each matters:

1. **`e2e/flows/chore_reminder.yaml` is the wrong path.** `e2e/flows/` holds no
   flow files at all — it holds `config.yaml` plus four feature subdirectories
   (`chores/`, `settings/`, `shell/`, `shopping/`). A flow dropped at the top
   level would still be picked up (`config.yaml` globs `"**"`) but would be the
   only one out of place. Task 6 now creates
   **`e2e/flows/chores/chore_reminder.yaml`**, and its `runFlow` path is
   `../../common/onboard_fresh.yaml`, matching its siblings.
2. **`notification_scheduler.dart:581` is the wrong line.** The claim it
   supports is true — the scheduler does resolve its own copy — but
   `_applyDigestPlansNow` is declared at **`:636`** and its
   `lookupAppLocalizations(localeResolver())` call is at **`:644`**. (`:571` is a
   different call site.) The conclusion stands: `reminderBodyDueToday`,
   `reminderBodyStillOpen`, `notificationChannelRemindersName` /
   `...Description` are all present in **both** ARBs already, so Task 1 Step 3
   passes and this slice adds none of them.
3. **`buildNotificationPlans` takes a fifth parameter the plan's Task 5 snippet
   omits**: `Map<String, DateTime> snoozedUntilByOccurrenceId = const {}`. See
   the amended Task 5 Step 6 for what that costs and why it is accepted.
4. **Line-number drift in every ARB and screen citation** (the files have grown
   since): `app_en.arb`'s `choreForm*` block starts at **526** (plan says ~492)
   and `settingsDigestToggleDeniedHint` is at **1023** (plan says ~989);
   `app_de.arb`'s `choreFormRepeatToggleLabel` is at **131** (~124) and its
   `settingsDigestToggleDeniedHint` at **213** (~206); the chore form's service
   calls are at **621** / **635** (620/634). All are "insert next to X" hints,
   so none changes an instruction — they are corrected so the next reader does
   not trust the numbers.
5. **The "Note (not a decision)" below mis-glosses the German.**
   `settingsPreferencesSectionTitle` is **"Präferenzen"** in `app_de.arb:272`,
   not "Einstellungen". The note's substantive claim is confirmed: there is no
   "Daily summary" *section*; the digest rows live in the Preferences group
   (`settings_screen.dart:107-135`), and `settingsDigestSectionTitle` is an
   orphan key referenced nowhere in `lib/`. A concurrent stream owns fixing §12.
6. **The semantic-id inventory below is missing two ids** that exist in `lib/`:
   `chore_form.assignee.<id>.drag` and `chore_form.assignee.<id>.remove`. The
   claim they support — that this slice renames, removes or reorders no existing
   id — is still true; the list was just short.
7. **Task 1 Step 5 (`flutter analyze` + the full `flutter test test/` as a local
   baseline) is REFUSED.** The Flutter tool lock is global to this machine and
   several wave-7 streams run concurrently; the standing rule for this wave is
   that CI is the gate and local full-suite runs are noise. The baseline is
   taken from CI on the first pushed commit instead.

**Verified present and correct, needing no change:** `chores.reminderMinutes`
(`tables.dart:417`), the repository's `int? reminderMinutes` /
`Value<int?> reminderMinutes` pair, both sync mappers, every §3.1 constant with
`reminderCeiling` derived rather than literal, `applyQuietHours`,
`ReminderPlan`, and — the one this slice actually depends on —
**`NotificationPlanSet.reminderOverflowCount`** (`digest_plan_builder.dart:62`),
forwarded verbatim from `ReminderPlanResult.overflowCount`, which is produced at
`planReminders`' single truncation site. OPD-1's Option A landed exactly as
agreed.

---

## Dependencies: what slices 1–3 hand you

Slices 1, 2 and 3 are planned in parallel and land **first**. Treat the following
as existing interfaces defined by the spec. **Do not re-specify or re-build them.**

| From | Interface | Spec |
|---|---|---|
| Slice 1 | `chores.reminder_minutes INTEGER NULL`, schema v13, `Chore.reminderMinutes` (`int?`) | §8.2 |
| Slice 1 | `ChoreRepository.createChore` / `updateChore` carry `reminderMinutes` | §14.1 "repository methods" |
| Slice 1 | `row_mappers.dart` `choreRow` / `choreFromRow` round-trip it | §8.2 |
| Slice 2 | `lib/domain/reminder_planner.dart`: `defaultReminderMinutes`, `reminderCeiling`, `reminderArmWindowDays`, `applyQuietHours`, `ReminderPlan` | §3.1, §9.1 |
| Slice 2 | `buildNotificationPlans({now, settings, pending, recipientMemberId}) → NotificationPlanSet` in `lib/application/digest_plan_builder.dart` | §9.1 |
| Slice 2 | Rule D inside `lib/domain/digest_projection.dart` | §2.4 |
| Slice 3 | `NotificationScheduler.applyPlans(NotificationPlanSet)`, `cancelAll()` | §9.2 |
| Slice 3 | ARB keys the scheduler resolves itself: `reminderBodyDueToday`, `reminderBodyStillOpen`, `notificationChannelRemindersName` / `...Description` | §11 |

**Why the notification-body keys are not this slice's, despite the ticket saying
"the l10n":** `NotificationScheduler` resolves its own copy internally — verified
at `lib/application/notification_scheduler.dart:636`, `_applyDigestPlansNow` calls
`lookupAppLocalizations(localeResolver())` and reads
`l10n.notificationChannelDigestName` itself. `applyPlans` cannot compile without
`reminderBodyDueToday` et al., so those keys land with slice 3. Task 1 verifies
they are present; this slice owns only the four keys the **form and Settings**
render.

---

## Product decisions taken during planning (both CLOSED 2026-08-30)

The spec records no open questions and closed both of its own (OQ1, OQ2) before
planning. These two are **not** re-litigations of those. They are interfaces this
slice needs that §3.2, §11 and §12 leave genuinely undefined, found by grepping
the shipped code against the spec. Both were put to the coordinator and **both
were resolved as recommended before implementation began**; they are recorded
here as closed rather than deleted, so the reasoning survives and nobody
re-opens them from the options alone. **No task in this plan is blocked.**

### OPD-1 — Where does the ceiling sub-line's *count* come from? **CLOSED: Option A.**

**`NotificationPlanSet` gains `int reminderOverflowCount` — how many
reminder-eligible occurrences did not get a slot.** Slice 4 **consumes** it and
does not construct it: the field lives in slice 1–3's territory (spec §9.1) and
its author is adding it. Do not re-specify its semantics, and do not define them
any differently from that one sentence.

**The decisive reason is the rejection of B, not the appeal of A.** Two copies of
§2.3's arming rule is a guaranteed divergence, and this project has already been
bitten by exactly that shape: the G-2 work found a "shared" recurrence formatter
that did not actually exist and had to build one, precisely so a second parallel
implementation could not drift from the first. **The thing that computed the
overflow is the thing that should report it.** C was rejected because it costs a
one-line explanation of a genuinely subtle behaviour, which is a worse trade than
a small field.

The options as they stood:

§3.2 requires a sub-line "naming how many chores stayed in the summary and what
the limit is", and §11 specifies `settingsRemindersCeilingHint` as "an ICU plural
over the number of chores that did not fit, with the limit as a second
placeholder". **No interface exposes that number.** §9.1 defines
`NotificationPlanSet` as "three lists of exactly `digestHorizonSlots`,
`reminderCeiling` and `eveningHorizonSlots` entries" — and a full reminder list
tells you the ceiling binds, but not by how much. The overflow count is
genuinely underivable from the stated interface.

- **Option A (recommended): `NotificationPlanSet` gains one field,
  `int reminderOverflowCount`** — the number of §2.3-step-5 survivors beyond
  `reminderCeiling`, `0` when the ceiling does not bind. It is computed for free
  by the code that already sorts and truncates, it needs no second traversal, and
  it keeps §2.3's arming rule in exactly one place. Cost: one named addition to
  slice 2's type, which must be agreed with slice 2's owner.
- **Option B: slice 4 computes the count independently**, in a Riverpod provider
  over `pendingOccurrencesProvider`. **Rejected.** It requires re-implementing
  §2.3 steps 1–5 (roll-forward, snooze override, quiet-hours shift, past-drop,
  14-day window) a second time. Two implementations of the arming rule that can
  disagree is precisely the class of bug §0.1's partition exists to forbid, and
  the sub-line would then be able to lie about a set it did not compute.
- **Option C: drop the sub-line from slice 4** and ship it with slice 5 or 6.
  Costs nothing in AC1 terms — AC1 is Tasks 1–4 — but leaves the ceiling silent
  in the first release that can reach it.

**Taken: A.** **Never take B**, and in particular never implement Task 5 by
duplicating §2.3.

### OPD-2 — Which row hosts the ceiling sub-line, and what happens when it collides? **CLOSED: Option A.**

**Host it on `settings.digest.toggle`'s sublabel; the permission-denied hint
wins; show it only while the digest is on.** The reasoning, recorded:

- **It belongs on the digest row** because it is a statement *about the digest* —
  "these chores stay in the daily summary". Anywhere else it would have to
  explain its own context before it could say anything.
- **Hidden when the digest is off** is not merely tidy: §2.5 makes the sentence
  actually **false** in that state (coverage is reminders-only, there is no
  summary for these chores to stay in), and a false sub-line is worse than none.
- **Denied-hint wins on severity.** If the OS permission is denied, nothing fires
  at all; layering an overflow message on top would be noise about a smaller
  problem while the larger one goes unsaid.

The options as they stood:

§3.2 places the sub-line "under the Settings reminders section". §11 states
there is deliberately **no** `settingsRemindersSectionTitle`, and §12's binding
row order lists seven rows, **none of which is about reminders**. So the
sub-line's host row is unspecified. Three further facts, all verified in the
shipped code:

1. `SettingsRow.sublabel` is a single `String?`
   (`lib/features/settings/settings_group.dart`). One row cannot show two
   sub-lines.
2. `settings.digest.toggle`'s sublabel is **already** occupied whenever the digest
   is on and the OS permission is denied
   (`settingsDigestToggleDeniedHint`, `digest_section.dart:48`).
3. The sub-line's claim — "these chores stay in the daily summary" — is **false
   when the digest is off**. §2.5 says so outright: "when the user turns the
   digest off... coverage is reminders-only."

- **Option A (recommended): host it on `settings.digest.toggle`'s sublabel, with
  explicit precedence** — permission-denied hint wins over the ceiling hint (a
  hard delivery failure outranks a cadence downgrade), and the ceiling hint is
  shown **only while `settings.digestEnabled` is true**. When the digest is off,
  show nothing: turning it off is a deliberate act whose consequence §2.5 already
  declares not a defect, and a sub-line under an off switch would be claiming a
  summary that is not being sent. This satisfies §12's "sub-lines on rows that
  already have them" literally, and adds no id.
- **Option B: a new non-interactive hint row** below the digest rows, shaped like
  `DigestPermissionHint`. Contradicts §12's letter ("they are sub-lines on rows
  that already have them") and adds an eighth row to a binding seven-row order.
- **Option C: defer to slice 5**, hosting it on the quiet-hours or evening rows
  once they exist. Those rows are not about the ceiling either, and it delays a
  true statement for no gain.

**Taken: A**, with the precedence and the digest-enabled gate written into the
widget's doc comment (Task 5 Step 5).

### Note (not a decision) — a spec/code mismatch, escalated separately and being acted on

§12 and §5.1 speak of "the existing 'Daily summary' section" and of rows joining
it. **There is no such section.** The digest rows sit inside the **Preferences**
group (`settingsPreferencesSectionTitle`, "Preferences"/"Präferenzen") at
`lib/features/settings/settings_screen.dart:107-135`, below the Language and
Appearance rows. The key `settingsDigestSectionTitle` ("Daily summary" /
"Tägliche Zusammenfassung") exists in both ARBs and is **referenced nowhere in
`lib/`** — verified by grep. §12's binding row order is still satisfiable exactly
as written (the digest rows are contiguous and last in that group), so this
blocks nothing in slices 4–6. **Escalated and being acted on:** the coordinator
has taken this to the slice 5–6 author, who is mid-flight in that territory, to
have §12 corrected at the spec. It is kept here so the trail survives — a spec
making a false claim about shipped code is the error class that has recurred in
every round of this project, and the note is the evidence of how it was caught.
Whoever plans slice 6 should know that
"widening the section header" (§12) means either adopting the unused key as a
real header or widening "Preferences", not editing an existing "Daily summary"
header.

---

## File structure

| File | Status | Responsibility |
|---|---|---|
| `lib/features/chores/chore_form/reminder_row.dart` | **create** | `ChoreFormReminderRow`: the switch + revealed time card + Rule-D hint. Stateless, no providers, no persistence. |
| `lib/features/chores/chore_form_screen.dart` | modify | Holds `int? _reminderMinutes`, seeds it on load, tracks it for dirtiness, writes it on save. |
| `lib/application/chore_service.dart` | modify | Passes `reminderMinutes` through `createChore` / `updateChore` to the repository. |
| `lib/features/settings/digest_section.dart` | modify | `DigestToggleTile` gains `reminderOverflowCount`, renders the ceiling sub-line. |
| `lib/features/settings/settings_screen.dart` | modify | Feeds the overflow count in. |
| `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb` | modify | Four new keys. |
| `test/features/chores/chore_form/reminder_row_test.dart` | **create** | Leaf-widget states. |
| `test/application/chore_service_reminder_test.dart` | **create** | Service→repository pass-through. |
| `test/features/chores/chore_form_reminder_test.dart` | **create** | End-to-end form: default, persist, load, clear, dirty guard. |
| `test/features/settings/reminders_ceiling_test.dart` | **create** | Ceiling sub-line present/absent/precedence. |
| `e2e/flows/chores/chore_reminder.yaml` | **create** | Maestro: set a reminder, reopen, see it persisted (§13.3's carve-out). |

The row is its own file rather than another block inside `chore_form_screen.dart`
because that screen is already 652 lines and every other form control
(`repeat_section.dart`, `start_date_field.dart`, `assignment_fields.dart`,
`title_notes_fields.dart`) already lives in `chore_form/`. Following the
established pattern is also what makes Task 2 independently testable before the
screen is touched at all.

### Where the row sits in the form, and why

The form as wave 6 left it renders, in `ListView` order:

```
TitleField → NotesField → chore_form.category → RepeatToggle
  → [RepeatControls: the fill-in-the-blank sentence, weekday chips,
     monthly-mode row, "Counting from" anchor cards, date preview]
  → StartDateField → AssignmentFields
```

**The reminder row goes directly after `StartDateField` and directly before
`AssignmentFields`.** The form reads *what* (title, notes, category) → *when*
(repeat, start date) → *who* (assignment). A reminder time is a **when** fact and
it is downstream of the due date it is derived from — §2.3 arms it at the
occurrence's projected due date — so it belongs at the end of the *when* block,
after the date those projections start from. It must not go between `RepeatToggle`
and `RepeatControls` (that pair is one control), and it must not go last: the
reminder applies to one-off chores too, and burying it under the rotation
reorder list would read as an assignment property.

**Semantic ids:** two new ids, `chore_form.reminder.toggle` and
`chore_form.reminder.time` (§12, verbatim). **No existing `chore_form.*` id is
renamed, removed, reordered or re-wrapped by this slice.** The complete set in
`lib/` today is `chore_form.` + `title`, `notes`, `category`, `category.none`,
`category.<id>`, `repeat.toggle`, `repeat.interval`, `repeat.unit`,
`repeat.unit.<unit>`, `repeat.weekday.<n>`, `repeat.monthly_mode.<mode>`,
`repeat.monthly_day`, `repeat.monthly_ordinal`, `repeat.monthly_weekday`,
`repeat.anchor.<anchor>`, `repeat.preview`, `start_date`, `assignment.<mode>`,
`assignee.<id>`, `assignee.add`, `save`, `discard.confirm`,
`discard.keepEditing`. The E2E suite uses only `chore_form.title`,
`chore_form.repeat.toggle`, `chore_form.repeat.unit`,
`chore_form.repeat.unit.day` and `chore_form.save`; Maestro selects by
identifier, not by tree position, so inserting a row above `AssignmentFields`
cannot move any of them.

---

## Task 1: Verify the slice 1–3 ground before writing anything

This task writes no code and makes no commit. It exists because slices 1–3 are
being planned in parallel: if any of these is missing, **stop and report** rather
than inventing the interface.

**Files:** none.

**Interfaces:**
- Consumes: everything in the "Dependencies" table above.
- Produces: a go/no-go, plus the resolved answer to OPD-1.

- [ ] **Step 1: Confirm the column and the model field exist**

Run:
```bash
grep -n "reminderMinutes" lib/data/db/tables.dart lib/data/repositories/chore_repository.dart lib/data/sync/row_mappers.dart
```
Expected: `IntColumn get reminderMinutes => integer().nullable()();` in
`tables.dart`, and `reminderMinutes` named parameters on `ChoreRepository`'s
`createChore` and `updateChore`. If `tables.dart` has it but the repository does
not, slice 1 is incomplete — stop and report.

- [ ] **Step 2: Confirm the planner constants exist and are derived**

Run:
```bash
grep -n "defaultReminderMinutes\|reminderCeiling\|reminderArmWindowDays" lib/domain/reminder_planner.dart
```
Expected: `defaultReminderMinutes = 1080`, `reminderArmWindowDays = 14`, and
`reminderCeiling` written as `n2NotificationIdBudget - eveningHorizonSlots`,
**not** as the literal `33` (§3.1).

- [ ] **Step 3: Confirm slice 3 shipped the notification-body copy**

Run:
```bash
grep -n "reminderBodyDueToday\|reminderBodyStillOpen\|notificationChannelReminders" lib/l10n/app_en.arb lib/l10n/app_de.arb
```
Expected: present in both files. If missing from `app_de.arb` only, add the
German now (informal *du*, "Gerät" never "Handy") — a key present in the template
and absent from `de` is a silent English fallback. If missing from both,
`NotificationScheduler.applyPlans` cannot have compiled; slice 3 is incomplete —
stop and report.

- [ ] **Step 4: Confirm the agreed `reminderOverflowCount` field landed**

Run:
```bash
grep -n "class NotificationPlanSet" -A 30 lib/application/digest_plan_builder.dart
```
Expected: an `int reminderOverflowCount` field — how many reminder-eligible
occurrences did not get a slot. **This was agreed with slice 2's owner (OPD-1,
closed as Option A); slice 4 consumes it and does not build it.** If it is
absent, slice 2 is incomplete — chase its owner and, meanwhile, ship Tasks 1–4
and 6 (AC1 does not depend on the sub-line). **Do not unblock yourself by
re-deriving the count from §2.3** — that is Option B, which was rejected
precisely because two copies of the arming rule will diverge.

- [ ] **Step 5: Baseline the suite — REFUSED as written (Task 0, correction 7)**

Do **not** run `flutter analyze` and the full `flutter test test/` locally. The
Flutter tool lock is global to this machine and several wave-7 streams share it,
so a full local run serializes behind them and reads as a hang; the standing
rule for this wave is that CI is the gate. Take the baseline from CI instead:
open the draft PR on the first commit and read `gh pr checks`. A red baseline
still belongs to whoever made it red — the difference is only where you look.

Every later step in this plan that says "run `flutter test <file>` / `flutter
analyze`" means the same thing: commit, push, and read that job in CI. The TDD
loop is unchanged — the RED commit is pushed first and CI must fail with the
stated mode.

---

## Task 2: `ChoreFormReminderRow` and its three strings

The leaf widget, tested on its own before the screen is touched.

**Files:**
- Create: `lib/features/chores/chore_form/reminder_row.dart`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`
- Test: `test/features/chores/chore_form/reminder_row_test.dart`

**Interfaces:**
- Consumes: `semantic(String id, {required Widget child})` from
  `lib/app/semantics.dart`; `defaultReminderMinutes` from
  `lib/domain/reminder_planner.dart`; `AppLocalizations` from
  `lib/l10n/app_localizations.dart`.
- Produces:
  `ChoreFormReminderRow({required int? minutes, required ValueChanged<int?> onChanged, Key? key})`
  — `minutes == null` means the reminder is off; `onChanged(null)` turns it off,
  `onChanged(<0..1439>)` sets a time. Task 4 is its only caller.

- [ ] **Step 1: Add the three ARB keys to the template**

In `lib/l10n/app_en.arb`, next to the other `choreForm*` keys (they run from
line 526), add:

```json
  "choreFormReminderToggle": "Remind me about this chore",
  "@choreFormReminderToggle": {
    "description": "Label of the chore form's per-chore reminder switch (spec docs/specs/notifications-n2.md §2.1). Names what the user gets, not the mechanism. Deliberately not 'Alarm' or 'Notify me at': §2.6 makes these one-shot notifications rewritten when the app runs, and the copy must not promise alarm-like behaviour the feature cannot deliver."
  },
  "choreFormReminderTime": "Reminder time",
  "@choreFormReminderTime": {
    "description": "Micro-label of the chore form's reminder time card, revealed when choreFormReminderToggle is on. Parallel to settingsDigestTimeLabel ('Notification time'), which is the same control one screen over."
  },
  "choreFormReminderHint": "This chore won't be counted in the daily summary",
  "@choreFormReminderHint": {
    "description": "Sub-line under the chore form's reminder time card. The one place Rule D (spec docs/specs/notifications-n2.md §2.4, decision D2) is explained to the person it affects: a chore with an armed reminder is omitted from that date's digest counts, so nobody is told twice. Copy is quoted verbatim in the spec's §11 and is binding."
  },
```

- [ ] **Step 2: Add the three German strings**

In `lib/l10n/app_de.arb`, next to `choreFormRepeatToggleLabel` (line 131), add —
no `@`-blocks, that file carries none:

```json
  "choreFormReminderToggle": "An diese Aufgabe erinnern",
  "choreFormReminderTime": "Erinnerungszeit",
  "choreFormReminderHint": "Diese Aufgabe taucht dann nicht in der Tageszusammenfassung auf",
```

`choreFormReminderHint`'s German is quoted verbatim in spec §11 and must not be
reworded.

- [ ] **Step 3: Write the failing test**

Create `test/features/chores/chore_form/reminder_row_test.dart`. The
bare-`MaterialApp` pump below is the pattern this directory already uses
(`repeat_section_test.dart`) — a leaf widget reads no providers, so no
`ProviderScope` is involved and nothing can hang.

```dart
/// Widget-level tests for `ChoreFormReminderRow`, the chore form's
/// per-chore reminder row (spec `docs/specs/notifications-n2.md` §2.1,
/// §12).
library;

import 'package:chore_app/app/theme.dart';
import 'package:chore_app/domain/reminder_planner.dart';
import 'package:chore_app/features/chores/chore_form/reminder_row.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<int?> pumpRow(
    WidgetTester tester, {
    required int? minutes,
    required void Function(int?) onChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appLightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChoreFormReminderRow(minutes: minutes, onChanged: onChanged),
        ),
      ),
    );
    return minutes;
  }

  testWidgets('off: switch is off, no time card, no Rule D hint', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpRow(tester, minutes: null, onChanged: (_) {});

    expect(
      find.bySemanticsIdentifier('chore_form.reminder.toggle'),
      findsOneWidget,
    );
    final toggle = tester.widget<Switch>(
      find
          .descendant(
            of: find.bySemanticsIdentifier('chore_form.reminder.toggle'),
            matching: find.byType(Switch),
          )
          .first,
    );
    expect(toggle.value, isFalse);
    expect(
      find.bySemanticsIdentifier('chore_form.reminder.time'),
      findsNothing,
    );
    expect(
      find.text("This chore won't be counted in the daily summary"),
      findsNothing,
    );

    handle.dispose();
  });

  testWidgets('on: switch is on, time card shows, Rule D hint shows', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpRow(tester, minutes: defaultReminderMinutes, onChanged: (_) {});

    final toggle = tester.widget<Switch>(
      find
          .descendant(
            of: find.bySemanticsIdentifier('chore_form.reminder.toggle'),
            matching: find.byType(Switch),
          )
          .first,
    );
    expect(toggle.value, isTrue);
    expect(
      find.bySemanticsIdentifier('chore_form.reminder.time'),
      findsOneWidget,
    );
    // Rule D (D2) explained where it applies -- the single place the user
    // is told their chore leaves the digest's counts.
    expect(
      find.text("This chore won't be counted in the daily summary"),
      findsOneWidget,
    );

    handle.dispose();
  });

  testWidgets('flipping the switch on reports the 18:00 default', (
    tester,
  ) async {
    final reported = <int?>[];
    await pumpRow(tester, minutes: null, onChanged: reported.add);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    // The pre-fill is a CONSTANT, not a settings column (spec §2.1).
    expect(reported, [defaultReminderMinutes]);
  });

  testWidgets('flipping the switch off reports null', (tester) async {
    final reported = <int?>[];
    await pumpRow(
      tester,
      minutes: defaultReminderMinutes,
      onChanged: reported.add,
    );

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    // One nullable fact (D1): off IS null, there is no separate flag that
    // could disagree with a retained time.
    expect(reported, [null]);
  });
}
```

- [ ] **Step 4: Run the test to verify it fails**

Run:
```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  test/features/chores/chore_form/reminder_row_test.dart
```
Expected **RED**: the file fails to resolve
`package:chore_app/features/chores/chore_form/reminder_row.dart` — "Target of URI
doesn't exist" / "Undefined class 'ChoreFormReminderRow'". This is a
compile-stage red for a file that does not exist yet, which is the only honest
red available for a brand-new widget; Step 7's inversion is what proves the
assertions bite.

- [ ] **Step 5: Write the widget**

Create `lib/features/chores/chore_form/reminder_row.dart`:

```dart
/// The chore form's per-chore reminder row (spec
/// `docs/specs/notifications-n2.md` §2.1).
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/domain/reminder_planner.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// A switch that, when on, reveals a time card and a one-line explanation
/// of Rule D.
///
/// [minutes] is the chore's `reminder_minutes` — minutes since local
/// midnight, or `null` for no individual reminder. Opt-in and time are
/// **one** nullable fact (decision D1), so there is no state in which this
/// row holds a time it is not using: turning the switch off reports `null`,
/// and turning it on reports the [defaultReminderMinutes] constant.
///
/// The visual shape follows the form's two existing families: the switch is
/// a zero-inset `SwitchListTile` like `RepeatToggle`, and the time card
/// copies `StartDateField`'s labelled card (a `surfaceContainerLow` fill,
/// radius 14, a permanently-visible uppercase micro-label above the value,
/// a trailing glyph) rather than inventing a third.
///
/// The picker opens in [TimePickerEntryMode.input] for the same two reasons
/// `DigestTimeTile` does: a time can be typed directly, and the dial's
/// freeform gestures are not deterministically driveable from a test.
///
/// Says nothing about *guaranteed* delivery, deliberately: §2.6 makes these
/// one-shot notifications rewritten whenever the app runs, and Android
/// scheduling stays `inexactAllowWhileIdle`. The UI must not promise
/// alarm-like behaviour it cannot deliver.
class ChoreFormReminderRow extends StatelessWidget {
  /// Creates the reminder row.
  const ChoreFormReminderRow({
    required this.minutes,
    required this.onChanged,
    super.key,
  });

  /// The chore's reminder time as minutes since local midnight, or `null`
  /// when the chore has no individual reminder.
  final int? minutes;

  /// Called with the new value: `null` to turn the reminder off, otherwise
  /// minutes since local midnight.
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final current = minutes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        semantic(
          'chore_form.reminder.toggle',
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.choreFormReminderToggle),
            value: current != null,
            onChanged: (enabled) =>
                onChanged(enabled ? defaultReminderMinutes : null),
          ),
        ),
        if (current != null) ...[
          const SizedBox(height: 8),
          semantic(
            'chore_form.reminder.time',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _pick(context, current),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Uppercase is typography, not content: the
                            // natural-case label stays as the
                            // accessibility label so TalkBack does not
                            // shout it, and so the translator sees a
                            // natural-case source (German capitalization
                            // rules differ).
                            Semantics(
                              label: l10n.choreFormReminderTime,
                              child: ExcludeSemantics(
                                child: Text(
                                  l10n.choreFormReminderTime.toUpperCase(),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                            Text(
                              _timeOf(current).format(context),
                              style: theme.textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.schedule_outlined,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              l10n.choreFormReminderHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }

  TimeOfDay _timeOf(int value) =>
      TimeOfDay(hour: value ~/ 60, minute: value % 60);

  Future<void> _pick(BuildContext context, int current) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _timeOf(current),
      initialEntryMode: TimePickerEntryMode.input,
    );
    if (picked != null) {
      onChanged(picked.hour * 60 + picked.minute);
    }
  }
}
```

- [ ] **Step 6: Run the tests and the analyzer**

Run:
```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  test/features/chores/chore_form/reminder_row_test.dart
flutter analyze --fatal-infos --fatal-warnings
```
Expected: 4 tests PASS, analyzer clean.

- [ ] **Step 7: Invert the implementation and confirm it breaks AT THE TEST STEP**

Temporarily change the switch's `onChanged` to
`onChanged: (enabled) => onChanged(enabled ? defaultReminderMinutes : 0)`.

Re-run the test file. Expected: **"flipping the switch off reports null" FAILS**
with `Expected: [null] Actual: [0]` — a test-step failure, not an analyzer one
(`0` is a valid `int?`, so the analyzer stays clean; this is what makes it a
genuine red). Then revert the inversion and re-run to confirm green.

- [ ] **Step 8: Commit**

```bash
git add lib/features/chores/chore_form/reminder_row.dart \
        lib/l10n/app_en.arb lib/l10n/app_de.arb \
        test/features/chores/chore_form/reminder_row_test.dart
git commit -m "Add the chore form's per-chore reminder row"
```

---

## Task 3: Thread `reminderMinutes` through `ChoreService`

Slice 1's scope is stated as "repository methods" (§14.1) — and
`ChoreService.createChore` / `updateChore`
(`lib/application/chore_service.dart:55` and `:304`) are the **application**
layer, which nothing in §14 assigns. Verified: neither signature carries
`reminderMinutes` today. The chore form calls the service, never the repository
directly — `chore_form_screen.dart:621` and `:635` — and
`docs/specs/occurrence-lifecycle.md` §2 is why. Without this task the form has
nowhere to write.

If Task 1 Step 1 found slice 1 had already added these service parameters, verify
they match the shapes below and skip to Task 4.

**Files:**
- Modify: `lib/application/chore_service.dart:55-77` (create),
  `lib/application/chore_service.dart:304-335` (update)
- Test: `test/application/chore_service_reminder_test.dart`

**Interfaces:**
- Consumes: `ChoreRepository.createChore(..., int? reminderMinutes)` and
  `ChoreRepository.updateChore(..., Value<int?> reminderMinutes)` (slice 1).
- Produces:
  - `ChoreService.createChore({..., int? reminderMinutes})` — defaults to `null`.
  - `ChoreService.updateChore(String choreId, {..., Value<int?> reminderMinutes = const Value.absent()})`
    — `Value.absent()` leaves it untouched; `Value(null)` clears it. This mirrors
    the existing `notes` and `categoryId` parameters exactly.

- [ ] **Step 1: Write the failing test**

Create `test/application/chore_service_reminder_test.dart`:

```dart
/// `ChoreService`'s pass-through of `chores.reminder_minutes` (spec
/// `docs/specs/notifications-n2.md` §2.1, decision D1).
library;

import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late ChoreService service;
  late String householdId;
  final now = DateTime(2026, 8, 30, 9);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final household = await HouseholdRepository(
      database,
    ).createLocalHousehold('Me');
    householdId = household.id;
    service = ChoreService(
      database: database,
      chores: ChoreRepository(database),
      clock: Clock.fixed(now),
    );
  });

  tearDown(() async {
    await database.close();
  });

  Future<int?> storedReminder(String choreId) async {
    final row = await (database.select(
      database.chores,
    )..where((tbl) => tbl.id.equals(choreId))).getSingle();
    return row.reminderMinutes;
  }

  test('createChore defaults reminderMinutes to null', () async {
    final chore = await service.createChore(
      householdId: householdId,
      title: 'Bins',
      startDate: PlainDate(2026, 9, 1),
      assignmentMode: AssignmentMode.anyone,
    );

    expect(await storedReminder(chore.id), isNull);
  });

  test('createChore persists a given reminderMinutes', () async {
    final chore = await service.createChore(
      householdId: householdId,
      title: 'Bins',
      startDate: PlainDate(2026, 9, 1),
      assignmentMode: AssignmentMode.anyone,
      reminderMinutes: 1080,
    );

    expect(await storedReminder(chore.id), 1080);
  });

  test('updateChore with Value.absent leaves the stored reminder alone', () async {
    final chore = await service.createChore(
      householdId: householdId,
      title: 'Bins',
      startDate: PlainDate(2026, 9, 1),
      assignmentMode: AssignmentMode.anyone,
      reminderMinutes: 1080,
    );

    await service.updateChore(chore.id, title: 'Bins out');

    expect(await storedReminder(chore.id), 1080);
  });

  test('updateChore with Value(null) clears the reminder', () async {
    final chore = await service.createChore(
      householdId: householdId,
      title: 'Bins',
      startDate: PlainDate(2026, 9, 1),
      assignmentMode: AssignmentMode.anyone,
      reminderMinutes: 1080,
    );

    await service.updateChore(
      chore.id,
      reminderMinutes: const Value(null),
    );

    // Turning the switch off writes NULL -- there is no separate enabled
    // flag to leave behind (D1).
    expect(await storedReminder(chore.id), isNull);
  });

  test('updateChore sets a new reminder time', () async {
    final chore = await service.createChore(
      householdId: householdId,
      title: 'Bins',
      startDate: PlainDate(2026, 9, 1),
      assignmentMode: AssignmentMode.anyone,
    );

    await service.updateChore(chore.id, reminderMinutes: const Value(1230));

    expect(await storedReminder(chore.id), 1230);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  test/application/chore_service_reminder_test.dart
```
Expected **RED**: "No named parameter with the name 'reminderMinutes'" on
`service.createChore` and `service.updateChore`. (The first test,
`createChore defaults reminderMinutes to null`, would pass on its own — it is
kept as the guard against a non-null default, and Step 5 inverts against it.)

- [ ] **Step 3: Add the parameter to `createChore`**

In `lib/application/chore_service.dart`, add to `createChore`'s parameter list
(after `Recurrence? recurrence,`):

```dart
    int? reminderMinutes,
```

with the doc-comment line, and pass it to the repository inside the transaction:

```dart
      final chore = await chores.createChore(
        householdId: householdId,
        title: title,
        startDate: startDate,
        assignmentMode: assignmentMode,
        notes: notes,
        categoryId: categoryId,
        recurrence: recurrence,
        reminderMinutes: reminderMinutes,
        assigneeMemberIds: assigneeMemberIds,
        createdBy: createdBy,
      );
```

- [ ] **Step 4: Add the parameter to `updateChore`**

Add to `updateChore`'s parameter list (after
`Value<Recurrence?> recurrence = const Value.absent(),`):

```dart
    Value<int?> reminderMinutes = const Value.absent(),
```

and pass it through in the `chores.updateChore(...)` call:

```dart
      await chores.updateChore(
        choreId,
        title: title,
        notes: notes,
        categoryId: categoryId,
        recurrence: recurrence,
        reminderMinutes: reminderMinutes,
        // ...remaining existing arguments unchanged
      );
```

**Do not** add `reminderMinutes` to the `recurrenceChanged` / `startDateChanged`
comparison at `chore_service.dart:324-327`. Those decide whether to **regenerate
the pending occurrence** (`docs/specs/occurrence-lifecycle.md` §2). A reminder
time is a notification fact, not a schedule fact: changing it must not move,
recreate or reassign an occurrence. This is the same distinction D5 draws for
snooze.

- [ ] **Step 5: Run the tests, then invert**

Run:
```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  test/application/chore_service_reminder_test.dart
flutter analyze --fatal-infos --fatal-warnings
```
Expected: 5 tests PASS, analyzer clean.

Now invert: temporarily change `createChore`'s parameter to
`int? reminderMinutes = defaultReminderMinutes` (importing
`lib/domain/reminder_planner.dart`). Re-run. Expected:
**"createChore defaults reminderMinutes to null" FAILS** with
`Expected: null Actual: <1080>` — a test-step failure; the analyzer stays clean
because the default is a valid `int?`. Revert and re-run green.

- [ ] **Step 6: Commit**

```bash
git add lib/application/chore_service.dart \
        test/application/chore_service_reminder_test.dart
git commit -m "Pass reminderMinutes through ChoreService to the repository"
```

---

## Task 4: Wire the row into the chore form — **this task makes AC1 LIVE**

After this task a user can set "bins out, 18:00" on a chore, and slices 1–3
arm it and exclude it from that day's digest. **AC1 is satisfied here.** Nothing
below this task is required for it.

**Files:**
- Modify: `lib/features/chores/chore_form_screen.dart`
- Test: `test/features/chores/chore_form_reminder_test.dart`

**Interfaces:**
- Consumes: `ChoreFormReminderRow` (Task 2), `ChoreService.createChore` /
  `updateChore` with `reminderMinutes` (Task 3), `Chore.reminderMinutes`
  (slice 1).
- Produces: nothing other tasks consume.

- [ ] **Step 1: Write the failing test**

Create `test/features/chores/chore_form_reminder_test.dart`:

```dart
/// The chore form's per-chore reminder row, end to end (spec
/// `docs/specs/notifications-n2.md` §2.1 / AC1): default off, the 18:00
/// pre-fill, load on edit, clearing to NULL, and the unsaved-changes guard.
library;

import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/reminder_planner.dart';
import 'package:chore_app/features/chores/chore_form/reminder_row.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

void main() {
  final today = DateTime(2026, 8, 30, 9);

  ChoreService serviceFor(AppDatabase database) => ChoreService(
    database: database,
    chores: ChoreRepository(database),
    clock: Clock.fixed(today),
  );

  Future<int?> storedReminder(AppDatabase database, String choreId) async {
    final row = await (database.select(
      database.chores,
    )..where((tbl) => tbl.id.equals(choreId))).getSingle();
    return row.reminderMinutes;
  }

  Finder titleField() => find.descendant(
    of: find.bySemanticsIdentifier('chore_form.title'),
    matching: find.byType(TextField),
  );

  testChoreApp(
    'new chore: reminder off by default, saving writes NULL, and the '
    'pinned Save stays reachable',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('chore_form.reminder.toggle'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('chore_form.reminder.time'),
        findsNothing,
      );

      await tester.enterText(titleField(), 'Bins');
      // The Save button lives in the Scaffold's bottomNavigationBar (C15);
      // adding a row to the BODY must not have moved it into the list.
      expect(find.bySemanticsIdentifier('chore_form.save'), findsOneWidget);
      await tester.tap(find.bySemanticsIdentifier('chore_form.save'));
      await tester.pumpAndSettle();

      final chore = await database.select(database.chores).getSingle();
      expect(chore.reminderMinutes, isNull);

      handle.dispose();
    },
  );

  testChoreApp(
    'new chore: turning the reminder on reveals the time card and saves '
    'the 18:00 default',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      await tester.enterText(titleField(), 'Bins');
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.reminder.toggle'),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('chore_form.reminder.time'),
        findsOneWidget,
      );

      await tester.tap(find.bySemanticsIdentifier('chore_form.save'));
      await tester.pumpAndSettle();

      final chore = await database.select(database.chores).getSingle();
      expect(chore.reminderMinutes, defaultReminderMinutes);

      handle.dispose();
    },
  );

  testChoreApp(
    'new chore: a time picked through the row is what gets saved',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      await tester.enterText(titleField(), 'Bins');
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.reminder.toggle'),
      );
      await tester.pumpAndSettle();

      // Drives the row's own callback rather than Material's time picker:
      // no test in this repo opens `showTimePicker` (the digest time row's
      // tests assert the row and the persisted value only), and inventing
      // a dial/input-field driving technique here would test Flutter, not
      // this form. The picker itself is covered by the E2E flow.
      tester
          .widget<ChoreFormReminderRow>(
            find.byType(ChoreFormReminderRow),
          )
          .onChanged(7 * 60 + 30);
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsIdentifier('chore_form.save'));
      await tester.pumpAndSettle();

      final chore = await database.select(database.chores).getSingle();
      expect(chore.reminderMinutes, 450);

      handle.dispose();
    },
  );

  testChoreApp(
    'edit: an existing reminder loads on, and turning it off saves NULL',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final chore = await serviceFor(database).createChore(
        householdId: householdId,
        title: 'Bins',
        startDate: PlainDate(2026, 8, 30),
        assignmentMode: AssignmentMode.anyone,
        reminderMinutes: defaultReminderMinutes,
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.menu'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chores.menu.edit'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('chore_form.reminder.time'),
        findsOneWidget,
      );

      await tester.tap(
        find.bySemanticsIdentifier('chore_form.reminder.toggle'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chore_form.save'));
      await tester.pumpAndSettle();

      expect(await storedReminder(database, chore.id), isNull);

      handle.dispose();
    },
  );

  testChoreApp(
    'edit: changing only the reminder does not touch the pending '
    'occurrence',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final chore = await serviceFor(database).createChore(
        householdId: householdId,
        title: 'Bins',
        startDate: PlainDate(2026, 8, 30),
        assignmentMode: AssignmentMode.anyone,
      );
      await tester.pumpAndSettle();
      final before = await database.select(database.choreOccurrences)
          .getSingle();

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.menu'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chores.menu.edit'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.reminder.toggle'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chore_form.save'));
      await tester.pumpAndSettle();

      // A reminder time is a notification fact, not a schedule fact: it
      // must not regenerate the occurrence the way a recurrence or
      // start-date change does (docs/specs/occurrence-lifecycle.md §2).
      final after = await database.select(database.choreOccurrences)
          .getSingle();
      expect(after.id, before.id);
      expect(after.dueDate, before.dueDate);
      expect(after.assignedMemberId, before.assignedMemberId);

      handle.dispose();
    },
  );

  testChoreApp(
    'dirty guard: toggling the reminder on and backing out raises the '
    'discard dialog',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final chore = await serviceFor(database).createChore(
        householdId: householdId,
        title: 'Bins',
        startDate: PlainDate(2026, 8, 30),
        assignmentMode: AssignmentMode.anyone,
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.menu'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chores.menu.edit'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.reminder.toggle'),
      );
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('chore_form.discard.confirm'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'dirty guard: toggling the reminder on and back off is pristine again',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.reminder.toggle'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.reminder.toggle'),
      );
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('chore_form.discard.confirm'),
        findsNothing,
      );
      expect(find.bySemanticsIdentifier('chore_form.save'), findsNothing);

      handle.dispose();
    },
  );
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  test/features/chores/chore_form_reminder_test.dart
```
Expected **RED**: the first test fails at
`expect(find.bySemanticsIdentifier('chore_form.reminder.toggle'), findsOneWidget)`
with "Expected: exactly one matching candidate / Actual: _EmptyWidgetFinder: <zero widgets>"
— the row is not in the form yet. Every other test fails at its own first
reminder-related step for the same reason.

- [ ] **Step 3: Add the state field, the initial snapshot entry and the dirty check**

In `lib/features/chores/chore_form_screen.dart`:

Add the import:
```dart
import 'package:chore_app/features/chores/chore_form/reminder_row.dart';
```

Add the field next to `_categoryId` (around line 52):
```dart
  int? _reminderMinutes;
```

Add the snapshot field next to `_initialCategoryId` (around line 81):
```dart
  int? _initialReminderMinutes;
```

Add to `_captureInitialSnapshot`:
```dart
    _initialReminderMinutes = _reminderMinutes;
```

Add to `_isDirty`'s first `if` condition (the unconditional block, alongside
`_categoryId != _initialCategoryId`):
```dart
        _reminderMinutes != _initialReminderMinutes ||
```

It belongs in the **unconditional** block, not in the `_repeatEnabled`-gated one:
a reminder applies to one-off chores too, and unlike the recurrence sub-fields it
is a single nullable scalar, so toggling on and back off returns it to `null`
and reads pristine with no extra bookkeeping. That is D1 paying off a second
time.

- [ ] **Step 4: Seed it when loading an existing chore**

In `_loadExisting`'s `setState` body, next to `_categoryId = chore.categoryId;`:
```dart
      _reminderMinutes = chore.reminderMinutes;
```

It must land **before** `_captureInitialSnapshot()` at the end of
`_loadExisting`, or opening a chore that already has a reminder would read as
dirty on arrival and a plain back-tap would raise the discard dialog — the exact
trap the C4 comment at line 235 already documents for the other fields.

- [ ] **Step 5: Render the row**

In `build`'s `ListView` children, between `StartDateField(...)` and
`AssignmentFields(...)` — i.e. replacing the single `const SizedBox(height: 16)`
that currently separates them with:

```dart
            const SizedBox(height: 16),
            ChoreFormReminderRow(
              minutes: _reminderMinutes,
              onChanged: (value) => setState(() => _reminderMinutes = value),
            ),
            const SizedBox(height: 16),
```

Do not touch the `bottomNavigationBar`, the `PopScope`, or the `keyboardDismissBehavior`.

- [ ] **Step 6: Write it on save**

In `_save`, in the `_isEditing` branch, add to the `updateChore` call:
```dart
            reminderMinutes: Value(_reminderMinutes),
```
`Value(...)`, not `Value.absent()`: the form is the whole truth about this field
when it saves, and `Value(null)` is what clears a reminder the user switched off.

In the `else` (create) branch, add to the `createChore` call:
```dart
            reminderMinutes: _reminderMinutes,
```

Add `import 'package:drift/drift.dart' show Value;` — already present at line 22.

- [ ] **Step 7: Run the tests and the analyzer**

Run:
```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  test/features/chores/chore_form_reminder_test.dart
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  test/features/chores/
flutter analyze --fatal-infos --fatal-warnings
```
Expected: 7 new tests PASS, the whole `chores` feature directory PASS (the
unsaved-changes, edit, recurrence and keyboard-save suites must be untouched),
analyzer clean.

- [ ] **Step 8: Invert the implementation and confirm it breaks AT THE TEST STEP**

Two inversions, run one at a time:

1. Remove `_reminderMinutes != _initialReminderMinutes ||` from `_isDirty`.
   Re-run. Expected: **"dirty guard: toggling the reminder on and backing out
   raises the discard dialog" FAILS** — `canPop` stays true, the form pops, and
   `chore_form.discard.confirm` is not found. Analyzer stays clean (the field is
   still read in `_captureInitialSnapshot`), so this is a genuine test-step red.
2. Change `_save`'s edit branch to `reminderMinutes: const Value.absent()`.
   Re-run. Expected: **"edit: an existing reminder loads on, and turning it off
   saves NULL" FAILS** with `Expected: null Actual: <1080>`. Analyzer clean.

Revert both and re-run green.

- [ ] **Step 9: Commit**

```bash
git add lib/features/chores/chore_form_screen.dart \
        test/features/chores/chore_form_reminder_test.dart
git commit -m "Wire the reminder row into the chore form (AC1)"
```

**AC1 is live at this commit.**

---

## Task 5: The Settings ceiling sub-line

**Gated on Task 1 Step 4** having found
`NotificationPlanSet.reminderOverflowCount` (OPD-1, closed as Option A — slice 2
builds it, §9.1; this task only consumes it). If slice 2 has not landed it yet,
chase its owner and do Task 6 meanwhile. **Never** unblock this task by
re-deriving §2.3's arming rule.

Implemented per OPD-2 (closed as Option A): the sub-line is `settings.digest.toggle`'s
sublabel, the permission-denied hint outranks it, and it is shown only while the
digest is enabled.

**Files:**
- Modify: `lib/features/settings/digest_section.dart` (`DigestToggleTile`)
- Modify: `lib/features/settings/settings_screen.dart:112-118`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`
- Test: `test/features/settings/reminders_ceiling_test.dart`

**Interfaces:**
- Consumes: `buildNotificationPlans(...)` →
  `NotificationPlanSet.reminderOverflowCount` (`int` — how many
  reminder-eligible occurrences did not get a slot; `0` when the ceiling does
  not bind). **Owned by slice 2, spec §9.1** — consume it, never redefine or
  rebuild it. Also `reminderCeiling` from `lib/domain/reminder_planner.dart`.
- Produces: `DigestToggleTile({..., int reminderOverflowCount = 0})`.

- [ ] **Step 1: Add the ARB key to the template**

In `lib/l10n/app_en.arb`, next to `settingsDigestToggleDeniedHint` (line 1023):

```json
  "settingsRemindersCeilingHint": "{count, plural, one{1 chore stays in the daily summary — this device can hold {limit} reminders at once.} other{{count} chores stay in the daily summary — this device can hold {limit} reminders at once.}}",
  "@settingsRemindersCeilingHint": {
    "description": "Sub-line under the daily-summary toggle, shown only while more chores have a reminder than the device can arm (spec docs/specs/notifications-n2.md §3.2, decision D4). A pure projection of current state: no stored flag, nothing to dismiss, nothing that can go stale. States the outcome factually and non-alarmingly, because the ceiling costs cadence and never coverage -- the chores it names are still announced, by the daily summary, on their own date. 'stays in the daily summary' matches settingsDigestToggleTitle's own label one line above it. No zero branch: the string is only rendered when count >= 1.",
    "placeholders": {
      "count": { "type": "int" },
      "limit": { "type": "int" }
    }
  },
```

- [ ] **Step 2: Add the German string**

In `lib/l10n/app_de.arb`, next to `settingsDigestToggleDeniedHint` (line 213):

```json
  "settingsRemindersCeilingHint": "{count, plural, one{1 Aufgabe bleibt in der täglichen Zusammenfassung — dieses Gerät kann {limit} Erinnerungen gleichzeitig vormerken.} other{{count} Aufgaben bleiben in der täglichen Zusammenfassung — dieses Gerät kann {limit} Erinnerungen gleichzeitig vormerken.}}",
```

"tägliche Zusammenfassung" is `settingsDigestToggleTitle`'s own German label
("Tägliche Zusammenfassung"), which is the row this sub-line hangs under — the
user must be able to match the words to the switch directly above them. Note that
`choreFormReminderHint`'s German (spec-verbatim) says "Tageszusammenfassung"
instead; that string is binding copy quoted in §11 and is not changed here.
"Gerät", never "Handy".

- [ ] **Step 3: Write the failing test**

Create `test/features/settings/reminders_ceiling_test.dart`:

```dart
/// The Settings ceiling sub-line (spec `docs/specs/notifications-n2.md`
/// §3.2, decision D4): factual, projection-only, shown only while more
/// chores want an individual reminder than the device can arm.
library;

import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/reminder_planner.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'settings_test_utils.dart';

void main() {
  final today = DateTime(2026, 8, 30, 9);

  Future<void> seedReminderChores(AppDatabase database, int count) async {
    final household = await database.select(database.households).getSingle();
    final service = ChoreService(
      database: database,
      chores: ChoreRepository(database),
      clock: Clock.fixed(today),
    );
    for (var i = 0; i < count; i++) {
      await service.createChore(
        householdId: household.id,
        title: 'Chore $i',
        // Inside reminderArmWindowDays (14) and still ahead of `today`'s
        // 09:00, so every one of these is a live candidate.
        startDate: PlainDate(2026, 8, 31),
        assignmentMode: AssignmentMode.anyone,
        reminderMinutes: defaultReminderMinutes,
      );
    }
  }

  testChoreApp(
    'under the ceiling: no sub-line',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await seedReminderChores(database, 3);
      await tester.pumpAndSettle();
      await openSettingsTab(tester);

      expect(find.textContaining('stays in the daily summary'), findsNothing);
      expect(find.textContaining('stay in the daily summary'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'over the ceiling: the sub-line names the overflow and the limit',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await seedReminderChores(database, reminderCeiling + 2);
      await tester.pumpAndSettle();
      await openSettingsTab(tester);

      // Derived, never the literal 33 (spec §3.1): the split must move as
      // one number when it moves at all.
      expect(
        find.text(
          '2 chores stay in the daily summary — this device can hold '
          '$reminderCeiling reminders at once.',
        ),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'digest off: no sub-line, because the claim would be false',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await seedReminderChores(database, reminderCeiling + 2);
      await tester.pumpAndSettle();
      await openSettingsTab(tester);

      await tester.tap(find.bySemanticsIdentifier('settings.digest.toggle'));
      await tester.pumpAndSettle();

      // Spec §2.5: with the digest off, coverage is reminders-only -- the
      // losers are NOT in a daily summary, because there isn't one.
      expect(find.textContaining('stay in the daily summary'), findsNothing);

      handle.dispose();
    },
  );
}
```

- [ ] **Step 4: Run the test to verify it fails**

Run:
```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  test/features/settings/reminders_ceiling_test.dart
```
Expected **RED**: "over the ceiling: the sub-line names the overflow and the
limit" fails with "Expected: exactly one matching candidate / Actual: zero
widgets". The other two tests pass at this point — they are the guards that stop
Step 7's inversion from being papered over.

- [ ] **Step 5: Add the parameter to `DigestToggleTile`**

In `lib/features/settings/digest_section.dart`, add to the constructor and the
class:

```dart
  /// How many reminder-enabled chores did not fit under [reminderCeiling]
  /// and are therefore still counted by the daily summary (spec
  /// `docs/specs/notifications-n2.md` §3.2, decision D4). `0` when the
  /// ceiling does not bind.
  ///
  /// A **pure projection** of state that already exists — no stored flag,
  /// nothing to dismiss, nothing that can go stale — matching the
  /// permission-denied hint's pattern (backlog B-5 / triage T2.6).
  ///
  /// Precedence when both sub-lines would apply: the permission-denied
  /// hint wins. A hard delivery failure ("nothing is arriving at all")
  /// outranks a cadence downgrade ("these arrive in the summary instead"),
  /// and `SettingsRow` shows one sub-line.
  ///
  /// Shown only while [value] is true. With the digest off there is no
  /// daily summary for these chores to stay in, so the sentence would be
  /// false — spec §2.5 records exactly that as the one place the partition
  /// degrades, and it is not a defect to be papered over with copy.
  final int reminderOverflowCount;
```

and replace the `sublabel:` expression with:

```dart
        sublabel: switch ((value, permissionDenied, reminderOverflowCount)) {
          (true, true, _) => l10n.settingsDigestToggleDeniedHint,
          (true, false, final int over) when over > 0 =>
            l10n.settingsRemindersCeilingHint(over, reminderCeiling),
          _ => null,
        },
```

Add `import 'package:chore_app/domain/reminder_planner.dart';`.

- [ ] **Step 6: Feed the count in**

In `lib/features/settings/settings_screen.dart`, pass the projected count:

```dart
                  DigestToggleTile(
                    value: settings.digestEnabled,
                    permissionDenied: !permissionGranted,
                    reminderOverflowCount: ref.watch(
                      reminderOverflowCountProvider,
                    ),
                    onChanged: (enabled) =>
                        settingsRepository.setDigestEnabled(enabled: enabled),
                  ),
```

and add the provider to `lib/app/providers.dart`, next to the other digest
providers:

```dart
/// How many reminder-enabled chores did not fit under `reminderCeiling`
/// (spec `docs/specs/notifications-n2.md` §3.2), for the Settings ceiling
/// sub-line.
///
/// Reads the count `buildNotificationPlans` already computed while sorting
/// and truncating the candidates — deliberately NOT a second traversal
/// applying §2.3's arming rule again. Two implementations of that rule
/// could disagree, and a sub-line that lies about a set it did not compute
/// is worse than no sub-line.
///
/// AMENDED (Task 0, correction 3): `buildNotificationPlans` takes a fifth
/// parameter, `snoozedUntilByOccurrenceId`, which this provider cannot
/// supply — `ReminderSnoozeRepository.activeSnoozes()` is a `Future` and
/// this is a synchronous projection. It is therefore omitted (the
/// parameter defaults to `const {}`). See the shipped provider's own doc
/// comment for the bound on what that costs; the alternative, re-deriving
/// §2.3 here, remains forbidden (OPD-1 Option B).
final reminderOverflowCountProvider = Provider<int>((ref) {
  final settings = ref.watch(settingsProvider).valueOrNull;
  final pending = ref.watch(pendingOccurrencesProvider).valueOrNull;
  if (settings == null || pending == null) {
    return 0;
  }
  return buildNotificationPlans(
    now: ref.watch(clockProvider).now(),
    settings: settings,
    pending: pending,
    recipientMemberId: ref.watch(actingMemberProvider)?.id,
  ).reminderOverflowCount;
});
```

- [ ] **Step 7: Run the tests, then invert**

Run:
```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  test/features/settings/
flutter analyze --fatal-infos --fatal-warnings
```
Expected: 3 new tests PASS, the rest of the settings suite (including
`digest_section_test.dart`'s permission-hint test) PASS, analyzer clean.

Invert: change the `sublabel` switch's second arm's guard from `when over > 0` to
`when over >= 0`. Re-run. Expected: **"under the ceiling: no sub-line" FAILS** —
the sub-line renders with `count: 0`, which is both wrong and would need the
forbidden ICU `zero{}` branch to read correctly. Analyzer stays clean. Revert.

Second inversion: swap the switch's first two arms so the ceiling hint outranks
the denied hint. Re-run `test/features/settings/digest_section_test.dart`.
Expected: the existing permission-hint test FAILS. Revert and re-run green.

- [ ] **Step 8: Commit**

```bash
git add lib/features/settings/digest_section.dart \
        lib/features/settings/settings_screen.dart \
        lib/app/providers.dart \
        lib/l10n/app_en.arb lib/l10n/app_de.arb \
        test/features/settings/reminders_ceiling_test.dart
git commit -m "Show the reminder-ceiling sub-line under the daily summary toggle"
```

---

## Task 6: The E2E flow

§13.3 accepts that no CI job puts a real notification on a real device, and
carves out exactly this: "E2E (Maestro) can and should cover the *settings*
surfaces — ... enabling a chore reminder and seeing it persist".

**Do not run Maestro locally.** Per the repo's standing note, local emulator runs
are noise on this machine and the E2E gate is GitHub CI. Push and let CI run it.

**Files:**
- Create: `e2e/flows/chores/chore_reminder.yaml`

- [ ] **Step 1: Read a sibling flow first**

Run:
```bash
ls e2e/flows/ && cat e2e/common/onboard_fresh.yaml
```
Copy that file's `appId`, its `runFlow` bootstrap convention and its selector
style exactly. Do not invent Maestro syntax from memory — match a flow that
already passes in CI.

- [ ] **Step 2: Write the flow**

Create `e2e/flows/chores/chore_reminder.yaml` following the sibling's structure, driving:
onboard → `chores.add` → type a title into `chore_form.title` → tap
`chore_form.reminder.toggle` → assert `chore_form.reminder.time` is visible →
tap `chore_form.save` → reopen the chore via its row menu and the edit entry →
assert `chore_form.reminder.time` is visible again.

The reopen-and-assert is the whole point: it is the only automated check in this
slice that the value survives a real save/load round-trip on a real Android
build, and it is the half a widget test's in-memory database cannot vouch for.

- [ ] **Step 3: Commit and let CI gate it**

```bash
git add e2e/flows/chores/chore_reminder.yaml
git commit -m "Add an E2E flow for setting a per-chore reminder"
```

Push and read the GitHub CI E2E job's result. If it fails, fix the flow — do not
"fix" it by running Maestro locally.

---

## Self-review against the spec

| Spec requirement | Where |
|---|---|
| §2.1 one row: switch + revealed time picker, pre-filled from `defaultReminderMinutes` | Task 2 |
| §2.1 the pre-fill is a constant, not a settings column | Task 2 Step 5 (reads `defaultReminderMinutes` directly) |
| §2.1 turning the switch off writes `NULL`; no separate enabled flag | Tasks 2, 3, 4 (tested in all three) |
| §2.6 the UI must not promise alarm-like behaviour | Task 2's copy + its `@`-description; no "alarm", "always", "exactly" in any new string |
| §3.2 ceiling sub-line: factual, projection-only, names count and limit | Task 5 |
| §3.2 `reminderCeiling` derived, never `33` | Task 1 Step 2 verifies; Task 5's test asserts against the constant |
| §11 gen_l10n, `@`-descriptions, both locales, ICU plural in both, no `zero{}` | Tasks 2 and 5 |
| §11 `choreFormReminderHint` verbatim (en + de) | Task 2 Steps 1–2 |
| §12 `chore_form.reminder.toggle`, `chore_form.reminder.time` | Task 2 Step 5 |
| §12 sub-lines take no ids, hang on rows that already have them | Task 5 Step 5 (uses `SettingsRow.sublabel`) |
| §13.2 widget: chore-form reminder row states (off / on with time) | Task 2's four tests |
| §13.2 widget: settings ceiling sub-line present and absent | Task 5's three tests |
| §13.3 E2E covers enabling a chore reminder and seeing it persist | Task 6 |
| §14.4 "this slice alone satisfies AC1" | Task 4 |

**Not in this slice, by design:** the reminder notification's own body and
channel copy (slice 3 — the scheduler resolves it internally); quiet hours
(slice 5); the evening re-reminder (slice 6); Snooze and the payload `v:2`
(slice 7). No task here touches `notification_scheduler.dart`,
`reminder_planner.dart`, `digest_projection.dart` or
`digest_action_payload.dart`.
