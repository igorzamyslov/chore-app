# Handover: wave 7

*Written 2026-08-30 by the agent that orchestrated wave 7, for whoever scopes
the next one. Same rule as the wave-4, wave-5 and wave-6 handovers: every claim
here was verified against source, CI output, or a build artifact — and where it
wasn't, it says so explicitly.*

---

## 1. Where things stand

Wave 7 ran as four streams on `integration/wave-7` (PR #46), each merged only
after a line-by-line review and a green `gh pr checks` at the reviewed SHA.

**Schema moved v12 → v13.** Three additions, all additive, no data rewrite:
five `settings` columns, the synced `chores.reminder_minutes`, and the
device-scoped `reminder_snoozes` table. **The next migration is v14.**

Nothing was released and `main` is untouched. Everything is on
`integration/wave-7` awaiting the human's single reviewed merge. Base was
`main` at `59cd398` (the wave-7 planning commit); `origin/main` did **not**
move during this wave — re-checked before every merge, because it moved
mid-flight under wave 5.

**The wave implements slices 1–6 of `docs/specs/notifications-n2.md`. Slice 7
(the notification actions: `reminder.done`, `reminder.snooze`, `evening.done`,
payload `v:2`, the isolate snooze path) was deliberately not started** — it is
the only part standing on ground F-1's GATE 3 has never verified, and the spec
is built so that a negative GATE 3 leaves AC1 and two thirds of AC2 untouched.

---

## 2. What shipped

| Row | What landed |
| --- | --- |
| **N2 slices 1–3** | Schema v13, the pure planning core (`lib/domain/reminder_planner.dart`), Rule D inside `digest_projection.dart`, and `applyPlans` as ONE enqueued write over all three id ranges. **Nothing user-visible** — correct and stated at the top of the plan. |
| **N2 slice 4** | The chore form's reminder row (switch + time card, pre-filled at 18:00 from `defaultReminderMinutes`), `reminderMinutes` threaded through `ChoreService`, the Settings ceiling sub-line, and a `chore_reminder` Maestro flow. **This is what makes AC1 live.** |
| **N2 slices 5–6** | Quiet hours and the evening re-reminder, both settings surfaces, the §12 row-order guard, and the corrections to §11/§12 of the spec itself. Makes the isolate-free half of AC2 live. |
| **G-15** | The category icon grid is six equal flexible columns spanning the sheet, sharing `ColorSwatchPicker.columns`. |
| **G-16** | Two-letter initials measured against the real shipped font for the first time; default avatar radius 12 → 16 (24px → 32px). |

### The id budget, because it is now exactly spent

| Range | Ids | Count | Owner |
| --- | --- | --- | --- |
| `digestNotificationIdBase` | 1001–1024 | 24 | the digest horizon, unchanged |
| `reminderNotificationIdBase` | 2001–2033 | 33 | per-chore reminders |
| `eveningNotificationIdBase` | 3001–3007 | 7 | the evening horizon |

**Total is exactly 64 and there is no slack left.** iOS caps an app at 64
pending notifications. Anything new must take ids from one of these three
ranges by amending spec §3.1. The guard that used to assert
`digestHorizonSlots <= 32` was **replaced, not deleted**: the three counts now
sum to ≤ 64 and the three ranges are asserted pairwise disjoint, both computed
from the constants rather than from literals.

---

## 3. Verification status — read this before trusting §2

**Proven by CI at a named SHA:** everything in §2. Each stream's PR was green
at the exact head SHA I reviewed, and `integration/wave-7` was re-verified
green after every merge. `pgtap` ran **real SQL** (2m51s–3m23s) on every state
carrying the Supabase migration — a Dart-only diff short-circuits to a ~5s
green that is NOT server verification, and that distinction is checked here
rather than assumed.

**Proven by hand-dispatched iOS E2E:** the `ios` job never runs on a PR. It was
dispatched by hand on `integration/wave-7` and passed.

**NOT verified, and no CI job can change that** — spec §13.3 lists these and
they are all still open:

1. That a per-chore reminder actually arrives, and **how far
   `inexactAllowWhileIdle` drifts in Doze**. This is the one that could change
   a decision: if the drift makes "bins out Tuesday evening" useless, exact
   alarms have to be re-argued against Play policy.
2. **GATE 4** (a reminder armed by the main isolate and re-armed by the
   background isolate on the same id does not double-fire) and with it
   **GATE 3**, which N2 no longer depends on but which remains open.
3. That the two new Android channels (`reminders_v1`, `evening_v1`) are created
   with localized names, that the digest channel is unaffected, and that muting
   one leaves the others working.
4. That the iOS `reminderActions` / `eveningActions` categories register.
5. A real overnight quiet-hours deferral, including one across a DST boundary.
   The DST tests are deliberately weak on CI: the runner is UTC, so nothing
   shifts. They are written as calendar-component assertions so they stay
   *correct* in both timezones, but they cannot demonstrate the bug they guard.

**Additionally unverified, and new this wave:** the visual results of G-15 and
G-16 on a real screen. Both rows were opened *because* a device look found what
widget tests could not see, so the same caveat applies to their fixes.

---

## 4. Recorded claims that turned out to be WRONG

*The pattern is now four waves old and worth stating once more: claims about
INTENT held; claims about EXISTING CODE did not.*

1. **Spec §12: "the existing 'Daily summary' section".** There is no such
   section. theme-v2 merged the digest rows into the **Preferences** group, and
   `settingsDigestSectionTitle` is an **orphan key** — present in both ARBs and
   all three generated files, referenced by no widget. Corrected in the spec,
   with the repair the text invites explicitly **forbidden**: creating the
   section would move the digest rows, which are the landmark §5.1's
   discoverability argument is anchored to, inverting D12.
2. **Spec §11: `digestDoneActionLabel` "is reused".** No such key. The shipped
   one is `notificationActionDone`. The *intent* — one key, three surfaces —
   was sound and is unaffected.
3. **G-16's own obligation was aimed at the wrong end of the range.** It asked
   for a legibility check "at 16px and text scale 2.0". Margin only *grows*
   with text scale for this shape, so scale 2.0 is the safest case. The single
   configuration that actually overflowed was the default radius at ordinary,
   **unscaled** text.
4. **"Six across" was never true in any widget test.** A `Wrap` fits
   `floor((W+8)/56)` tiles per row, so the column count tracked the surface
   width — thirteen on the 800px test surface. The wave-6 check that cleared
   G-15 was measuring a 13-column grid, and six-across held only in the
   360–415dp band that happened to include the reporter's phone.
5. **The plan-authored constant `cornerReachPerFontSize = 0.99150` was wrong**
   (it is 1.05998), and its reasoning had two independent errors: the worst
   two-letter pair may **repeat a glyph** (`'WW'`, not `'WM'`), and the
   quantity that matters against a circular ring is the ink box's far **corner**
   measured from the centre, not half the ink width — the ink is not centred in
   the advance run.
6. **A plan test that could not pass:** `expect(find.text('Daily summary'),
   findsNothing)`, proposed as proof that no second section exists. The string
   is *also* `settingsDigestToggleTitle`, the digest toggle row's own label, so
   it goes red on a correct implementation.
7. **A plan test that could not fail:** the D4 ceiling tiebreak. Its two
   fixture keys were **correlated** — the occurrence with the lower occurrence
   id also had the lower chore id — so ordering by either produced the same
   answer, and the test could not fail for the property it names.

---

## 5. Process findings

### The vacuous-test count is now seven, and the detection method has changed

Wave 6 found four tests that could not fail. Wave 7 found three more, and the
important thing is *how*:

- The **avatar fit check** (and its wave-6 replacement, also vacuous): a `Text`
  laid out inside the ring reports its own constraint back, so it passed at any
  geometry. Deleted, not patched.
- The **D4 tiebreak** test, above. Found **only by running the inversion** — a
  batch of five inversions was applied and only four went red. Nobody would
  have predicted the fifth from reading it.
- A **`applyPlans` "one write, not three"** test that could not discriminate:
  `_enqueueNotificationWrite` is FIFO and synchronous, so three chained
  sub-writes leave the same end state as one. What actually distinguishes them
  is the *gap another kind of write can land in* — the replacement lands a
  `cancelAll()` inside that gap and asserts the result is empty.

**The rule this wave adds: run every inversion; do not reason about whether it
would fail.** Two of the three above would have survived a careful reading.

### An inversion that fails at `analyze` is not evidence

This bit three separate streams this wave — an orphaned import, a deleted
method's last caller, and `avoid_redundant_argument_values` firing on an
argument that became the default. In each case the tests **never ran**, so the
inversion proved nothing. Invert inside a method body, and check *which step*
went red before counting it.

### A measurement nobody can reproduce is how an unfalsifiable check ships

G-16 was the third attempt at the same assertion. What broke the cycle was
committing `tool/measure_avatar_font.py`, which reads the shipped TTF's own
sfnt tables and brute-forces every ordered pair rather than reasoning about
which is worst. The number in the test is now re-derivable in one command. The
shipped test additionally carries a deliberately **failing** configuration (the
chip-forced radius, which genuinely cannot fit two glyphs), so the inequality
is demonstrated going both ways on every CI run.

### The partition test is the shape to copy

Spec §0.1's invariant — every open occurrence is announced by the digest **xor**
by an individual reminder, on every date — is made executable by walking each
date against an **independently computed oracle set** and asserting
`|digest counted| + |reminders armed| == |oracle|`. Double-counting makes the
sum too big; a hole makes it too small; one assertion catches both. Crucially
it carries **vacuity guards** asserting the fixture actually arms something and
actually has a non-silent slot — without those, a fixture that armed nothing
would satisfy the identity trivially, which is exactly how the seven dead tests
above passed.

### A spec's design is authoritative; its citations are hypotheses

Recorded in the spec itself as new §16.1. Every decision in §1, every rule in
§2–§7, the partition, the id budget and all the binding copy survived contact
with the tree unchanged. What did not survive was incidental scaffolding — a
section name, a key name — written from memory in passages whose actual subject
was something else. The check is a grep, and it is cheap.

### An agent can die with its work complete and its report lost

The foundation stream was killed mid-report by an expired OAuth token. Its work
was intact — but "intact" had to be *established*, not assumed, because its
last action was restoring from a deliberately-inverted state. What settled it:
`git diff <last-pre-inversion-commit> <head>` was **empty**, proving the restore
was byte-exact rather than approximately right, and CI was green at that exact
SHA. The report was then recovered by resuming the agent. **If a stream dies
mid-inversion, diff against the pre-inversion commit before trusting the
branch** — a partial restore is the one failure mode that looks like success.

---

### Two more process findings, added after the last merge

#### A red that looked like total collapse was the emulator's own launcher

The final accumulated state failed `android` with **15 of 15 flows failing at
their first assertion** — the most alarming possible signature, and one that
reads as "the app no longer starts". It was not ours. The Maestro debug
artifacts' `screen-hierarchy` dump at the failure instant carries
`android:id/aerr_close` / `aerr_wait` and the title **"Quickstep isn't
responding"** — the emulator's launcher had ANR'd, and its modal dialog owned
the foreground window for the whole 17-minute run. Our package does not appear
in the dump for that reason alone. `checks` was green at the same SHA, both
halves had passed `android` on their own bases, and a re-run of the identical
SHA passed 15/15.

The distinguishing evidence cost one `gh run download` and two greps. Filed as
**G-18**, because the signature is indistinguishable at a glance from a real
regression and the next person should not bisect their own code first. It is
the same lesson **A-6** records from the other direction: a blank or blocked
app window has several unrelated causes and only one of them is ours.

#### A merge that GitHub calls CLEAN can still need verifying

Slice 4 branched before slices 5–6 merged, so **its green was against a
superseded tree** — the same trap section 8 records for `origin/main` moving
mid-wave. Both streams had touched `digest_section.dart`,
`settings_screen.dart` and all five l10n files, and GitHub reported the merge
`MERGEABLE`/`CLEAN`. A textual auto-merge of *generated* l10n is exactly what
made a wave-3 PR unmergeable, so it was checked rather than trusted: all eight
new ARB keys present in **both** locales, `flutter gen-l10n` a zero diff (which
is what proves the auto-merged generated files match a real regeneration rather
than merely merging without markers), both streams' widgets present in the two
shared source files, and `dart format` clean. Then CI re-run on the combined
tree, which is the only green that counts.

#### One line of the wave's own binding constraints was wrong

The constraints handed to every stream said `find.bySemanticsIdentifier` lives
in `test/test_utils/pump_app.dart`. It does not — it is a **Flutter built-in**
(`flutter_test/src/finders.dart`). Only `testChoreApp` is local. Harmless here,
but it is the same error class §4 catalogues, this time in the orchestration
brief rather than in a spec, and it survived three waves unchallenged.

---

## 6. What is open

- **Slice 7 — the notification actions.** `reminder.done`, `reminder.snooze`,
  `evening.done`, payload `v:2` (whose decoder must keep accepting `v:1`, since
  a pending notification survives an app upgrade), the snooze write path in the
  background isolate, and **GATE 4**. Deliberately not started. See backlog
  **G-6**, which now carries the full remaining scope.
- **F-1 GATE 3** — unchanged by this wave, still needs a human with a phone. N2
  no longer depends on it, by construction (§10.1), but it remains open.
- **Two things slice 7 must be handed, both recorded at their call sites:**
  `reminderOverflowCountProvider` passes `snoozedUntilByOccurrenceId: const {}`
  because `activeSnoozes()` is a `Future` and the provider is synchronous —
  inert while nothing writes `reminder_snoozes`, wrong the moment slice 7 does;
  and `ReminderSnoozeRepository`'s garbage collection uses
  `DateTime.now().toUtc()` rather than `clockProvider`.
- **A bounded partition window, and it is a deliberate deviation from §9.2.**
  That section says `applyDigestPlans` may survive "only if nothing outside the
  scheduler calls them". Two callers remain: `DigestPrepromptBanner._enable`
  and the background isolate's `rewriteDigestHorizon`. `cancelDigest` was
  removed outright, but this one was kept because §10.1 limits the isolate to
  the digest, and routing it through `applyPlans` would make the already
  unverified GATE 3 depend on a 64-call rewrite instead of 24 — strictly worse.
  **The consequence is real:** that path writes digest counts *without* Rule D,
  so until the next recompute an occurrence can be both counted by the digest
  and individually reminded, violating §0.1's "never both". It always errs
  toward *reporting* a chore rather than hiding one, which is the same trade
  §10.1 makes explicitly for snooze. Slice 7's author needs to know this.
- **G-13** — the 12sp category-label 4.5:1 contrast gap. Untouched.
- **G-17** — chip avatars cannot fit two-letter initials and silently ignore
  their `radius`. Opened by the G-16 work; the remedies are product calls, not
  geometry.
- **G-18** — the emulator system-UI hang, above.
- **Everything in §3's "NOT verified" list**, which for this wave is unusually
  large: N2 is a notifications feature and **no CI job puts a real notification
  on a real device.** Green CI here means the planning is right, not that a
  reminder arrives.

---

## 7. Housekeeping

**None performed, and none was in scope.** Five worktrees and their branches
from wave 6 are still present (`chore-app-w6-a6`, `-icons`, `-integration`,
`-palette`, `-repeat`), as are this wave's four (`chore-app-w7-foundation`,
`-icons`, `-reminders`, `-evening`) plus `chore-app-orchestrator`. Deleting
branches or worktrees was a hard stop this wave, so they were left alone. They
are safe to remove once `main` takes this merge; the wave-6 set has been
mergeable since `132c1c4`.

---

## 8. If you read only one thing

The wave's most reusable output is not the feature. It is the **partition
test** in `test/application/digest_plan_builder_test.dart` and the shape it
demonstrates: an invariant stated in the spec (§0.1), made executable by
walking every date against an independently computed oracle and asserting
`|counted| + |armed| == |open|`, with **vacuity guards** proving the fixture
actually exercises both halves. Seven tests in this repo have now been found
that could not fail. Every one of them would have been caught by asking the two
questions that test answers by construction: *what concrete change makes this
go red*, and *does my fixture actually reach the case I am asserting about*.
