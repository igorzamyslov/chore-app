# N2 Slices 5 & 6 — Quiet Hours UI + The Evening Re-reminder — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the two settings surfaces that answer the half of Igor's "it arrives, then it's gone" complaint that touches no background isolate — quiet hours (slice 5) and the evening re-reminder (slice 6) — in the one settings group that already holds the digest, in the row order `docs/specs/notifications-n2.md` §12 binds.

**Architecture:** Five new presentational row widgets in two new files, all built on one new reusable `SettingsTimeRow` (which `DigestTimeTile` is refactored onto, so the `showTimePicker` incantation exists once, not four times). They are composed into the *existing* group in `settings_screen.dart` — no new `SettingsGroup`, no new screen. The only non-UI addition is one pure predicate, `isWithinQuietHours`, added to slice 2's `reminder_planner.dart` and made the single wrapping-interval implementation by having `applyQuietHours` delegate to it. Everything else — `applyQuietHours`'s deferral construction, `buildNotificationPlans`, `applyPlans`, the three id ranges — is consumed as already-shipped by slices 1–3.

**Tech Stack:** Flutter, Riverpod, drift, gen_l10n, very_good_analysis (`--fatal-infos`), flutter_test.

---

## Global Constraints

Every task's requirements implicitly include this section.

- **Never** run `flutter`/`dart`/`supabase`/`docker` outside the exact commands this plan gives. Tests run as
  `flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= <file>`.
- Strict lints: `very_good_analysis` with `--fatal-infos`. **Every public member needs a doc comment** (`public_member_api_docs`). All code blocks below already carry them; do not strip them.
- All user-visible strings via gen_l10n: `lib/l10n/app_en.arb` (template, one `@`-description each) and `lib/l10n/app_de.arb` (informal *du*; "Gerät" never "Handy"; no `@`-blocks). After every ARB edit run `flutter gen-l10n` and **commit the regenerated `lib/l10n/app_localizations*.dart`** — they are tracked (`git ls-files lib/l10n` lists all three). A later `flutter gen-l10n` must be a zero diff.
- **No ICU `zero{}` branch anywhere** (spec §11). Nothing in this plan needs a plural at all.
- `semantic()` is `Widget semantic(String id, {required Widget child})` in `lib/app/semantics.dart` — **named `child`**.
- The existing `settings.digest.*` semantic ids are load-bearing for E2E. `DigestTimeTile` is refactored in Task 2; its id `settings.digest.time` must not change.
- Widget tests use `testChoreApp` + `find.bySemanticsIdentifier` from `test/test_utils/pump_app.dart`, and **`openSettingsTab` from `test/features/settings/settings_test_utils.dart`** (NOT pump_app.dart). Never hand-roll a `ProviderScope` pump — it hangs. Every `find.bySemanticsIdentifier` needs a `tester.ensureSemantics()` handle, disposed before the body returns.
- Commit messages: **never** add a `Co-Authored-By:` trailer.
- Spec `docs/specs/notifications-n2.md` is a binding contract. §5.1, §6, §11 and §12 are the sections this plan implements; D7 and D12 are the decisions it must not erode.

### Binding vs authored copy

| Key | EN | Source |
|---|---|---|
| `settingsEveningToggle` | Remind me again in the evening | **BINDING**, §5.1 + §11 verbatim |
| `settingsEveningToggleSubtitle` | Only if something is still open today | **BINDING**, §5.1 + §11 verbatim |
| `settingsEveningInQuietHoursHint` | Inside your quiet hours — not delivering | **BINDING**, §6 + §5.1 verbatim |
| `settingsQuietHoursToggle` | Quiet hours | authored (spec names the key only) |
| `settingsQuietHoursFrom` | From | authored |
| `settingsQuietHoursTo` | To | authored |
| `settingsEveningTime` | Evening time | authored |
| `settingsQuietHoursEmptyWindowHint` | Start and end are the same — no quiet time | authored (OD2) |

The German for the three binding keys is likewise fixed by §11 ("Abends noch mal erinnern" / "Nur wenn heute noch etwas offen ist"); the German for the hint is authored to match the register of the shipped `settingsDigestToggleDeniedHint` ("Wird nicht zugestellt — …"), em dash included.

---

## Three properties this plan is built on — do not "improve" them away

Everything else here is ordinary composition work. These three are the parts that carry the risk, and each is easy to undo by accident in a later tidy-up, so the reason is written down next to the thing.

### P1 — The quiet-hours tests assert a *cardinality*, and that is what makes them non-vacuous

Wave 6 found four tests that could not fail. The shape that produces them is an assertion that restates the implementation: "22:30 is inside a 22:00–07:00 window" is satisfied by an implementation that reports *everything* as inside, which is the single worst quiet-hours bug available (it suppresses every notification the app has). Adding "10:00 is outside" catches that one but is still satisfied by three other wrong implementations.

So the load-bearing assertion in Task 3 is **the size of the inside-set over all 1440 minutes of the day** — 540 for the shipped 22:00–07:00 window. **Why that one number discriminates:**

| Wrong implementation | Its cardinality | Caught? |
|---|---|---|
| Suppress everything | 1440 | ✓ |
| Suppress nothing (or `enabled` ignored the wrong way) | 0 | ✓ |
| Non-wrapping only (`start <= m < end`, the naive reading) | **0** — because `1320 > 420`, the range is empty | ✓ |
| Inclusive at both ends (`<= end` instead of `< end`) | 541 | ✓ |
| Correct | **540** | — |

One integer separates all four from correct, and none of them can produce 540 by coincidence. The boundary probes (`1320` inside, `419` inside, `420` outside) and the far-side-of-midnight probe (`360` inside) are there to name *which* failure occurred when the count is wrong; the count is what guarantees a failure exists to name. Task 3 Step 7 then inverts the implementation and shows the assertion firing, so this is demonstrated rather than asserted.

**Do not weaken this into a handful of representative minutes.** The set is 1440 elements; enumerating it costs microseconds and is the only formulation that closes the space.

### P2 — `isWithinQuietHours` takes a minute-of-day and builds no `DateTime`. That is the point.

The obvious "improvement" is to make it take a `DateTime` for symmetry with `applyQuietHours`, or to compute the window's edges as calendar components. **Do not.** The function answers a question that is purely about minute-of-day — a wrapping interval on a 1440-element ring — and by never constructing a date it has **zero DST exposure by construction**. There is no spring-forward hour it can land in, no nonexistent wall-clock time to normalize, nothing to reason about at all.

That is strictly better than DST-*correct* arithmetic, which is only as good as the next person's reasoning about it. The genuinely DST-sensitive work — building the deferral *target* from calendar components, per the rationale `nextDigestSlot` and `nextLocalMidnight` document — stays where it already is, inside `applyQuietHours`, and this plan does not touch it. One function has the hazard and is tested against both Berlin transitions by slice 2; the other cannot have it.

The seam between them is the exhaustive agreement test in Task 3, which pins that `applyQuietHours` defers exactly the minutes this predicate calls inside, across four windows × 1440 minutes. That is what stops the two drifting apart later.

### P3 — The rows go in Preferences because moving the digest would defeat the requirement it appears to satisfy

Full argument in F1. The short form, because it is the second-order consequence a literal reading of §12 misses: §12's row *ordering* can be satisfied by promoting a new notifications section and moving the digest rows into it — and doing so would look *more* spec-compliant, since it also makes §12's prose about a "Daily summary section" true. But D12's obligation is that the evening row sits **beside the digest time**, where someone hunting for their vanished notification already knows to look. Relocating the digest relocates the landmark the whole discoverability argument is anchored to. **Satisfying the ordering while destroying the anchor is a net loss disguised as compliance.** Task 8 writes this into the spec so the next reader cannot make the mistake from the text alone.

---

## Findings you must know before you start

These were verified against the tree at `28c9c99` by reading the files, not from memory.

### F1 — There is no "Daily summary" settings section. The rows live in **Preferences**.

Spec §12 says "One group — the existing 'Daily summary' section". **That section does not exist.** Verified twice, independently, on 2026-08-30:

```
$ grep -rn 'settingsDigestSectionTitle' lib test e2e | grep -v '^lib/l10n/'
(no output)
$ grep -n 'SettingsGroup(\|label: l10n\|DigestToggleTile' lib/features/settings/settings_screen.dart
107:          SettingsGroup(
108:            label: l10n.settingsPreferencesSectionTitle,
114:                  DigestToggleTile(
```

`lib/features/settings/settings_screen.dart:107-137` renders the digest rows inside the **Preferences** group (`l10n.settingsPreferencesSectionTitle` = "Preferences" / "Präferenzen"), after `LanguageRow` and `AppearanceRow`, from a `settingsAsync.when(data: ...)` spread. theme-v2 merged the digest section into Preferences and left `settingsDigestSectionTitle` ("Daily summary" / "Tägliche Zusammenfassung") behind as an **orphan key**: it exists in both ARBs and in all three generated files, and is referenced by no widget.

**This does not weaken D12 and changes no decision.** §5.1's binding requirement is "the same Settings group as the digest toggle and digest time, directly beneath the digest time row — not in a separate 'Reminders', 'Advanced' or 'More' area, and not on another screen". The Preferences group *is* that group. Two mechanical consequences:

- There is no digest section header to widen, so §12's sentence "The section header's own copy (`settingsDigestSectionTitle`) may be widened from 'Daily summary'" is **moot**. Do not add a header.
- "No new section header" is satisfied by construction: the new rows join the same `settingsAsync.when` list.

**The design question this raises, decided.** Eight notification rows in a group that also holds Language and Appearance is a fair thing to call unwieldy, and the tidier-looking alternative is real: *promote* an actual notifications section (using the orphan key), move the shipped digest rows into it, and put the new rows there — which would additionally make §12's text literally true. **Rejected. Take option (A): everything goes into Preferences, beside the digest, exactly where the digest already is.** Three reasons, in order of weight:

1. **Moving the digest rows would damage the very thing D12 is paying for.** §5.1's argument is that someone hunting for a vanished notification "opens the one group that already holds the notification they know about". Since theme-v2 that group has been Preferences. Relocating the digest rows to make a spec sentence true would move the landmark the discoverability argument is anchored to, for every existing user, in the same release that asks them to find a new row next to it. Tidiness bought at the cost of the feature's stated purpose is a bad trade.
2. **The unwieldy state is opt-in and self-limiting.** Three of the five new rows are conditionally revealed. The shipped state is six rows (Language, Appearance, digest toggle, digest time, evening toggle, quiet toggle) — two more than today. It only reaches nine or ten once a user has deliberately turned both features on, which is exactly when they want to see them.
3. Restructuring a shipped screen is scope this ticket does not have, and it would churn layout that E2E flows traverse.

**§12's row *ordering* does survive contact** — the relative order of the eight ids is implementable verbatim inside Preferences, and Task 6 pins it. What does not survive is the sentence naming the group and the sentence about widening a header. **Task 8 corrects the spec accordingly**, so the next reader is not misled the way this plan nearly was.

### F1b — §11 contains the same error: `digestDoneActionLabel` does not exist

Sweeping the rest of §11/§12 for the same failure mode (per the coordinator's mid-flight instruction to treat every claim about shipped code as a hypothesis) turned up one more:

> §11: "The existing `digestDoneActionLabel` is **reused** for all three Done actions rather than duplicated per surface; amend its `@`-description to say so."

```
$ grep -rn 'digestDoneActionLabel' lib test
(no output)
```

There is no such key. The shipped one is **`notificationActionDone`** (`lib/l10n/app_en.arb:64`, "Done"), threaded to the platform as `NotificationScheduler.initialize({required String doneActionTitle})` (`lib/application/notification_scheduler.dart:128`). The *intent* — one key reused by all three Done actions — is sound and unaffected; only the name is wrong. This is slice 7's copy, not this plan's, but Task 8 fixes it in passing because it is one line in a section Task 8 already edits, and leaving a known-wrong key name in a binding contract is how it reaches slice 7's author as a premise.

### F1c — §12 and §3.3 claims that were checked and are TRUE

Recorded so the next reader knows what has already been verified and need not re-do it:

- `semantic(String id, {required Widget child})` in `lib/app/semantics.dart`, `child` named — **true**.
- `settings.digest.toggle`, `settings.digest.time`, `settings.digest.permission` all exist in `digest_section.dart` — **true**, and the permission row is rendered last in the group, as §12 requires.
- The `settingsDigestToggleDeniedHint` sub-line pattern §3.2/§6 hold up as the model for a projection-only sub-line — **true** (`digest_section.dart:47-49`).
- §3.3's "`test/application/notification_scheduler_test.dart` currently asserts `digestHorizonSlots <= 32`" — **true** (`notification_scheduler_test.dart:163-176`).
- One id-convention wrinkle, flagged for slice 4's author and **not** acted on here: §12 proposes `chore_form.reminder.toggle`, but the shipped chore-form ids mix conventions — `chore_form.category`, `chore_form.save`, and `chore_form.start_date` (snake_case inside a segment). Not this plan's surface; noted only so it is not discovered late.

### F2 — Slice 1's repository method names are not in the spec.

§14 slice 1 says "repository methods" and names none. This plan assumes the five setters below, extrapolated **exactly** from the shipped `SettingsRepository.setDigestEnabled({required bool enabled})` and `SettingsRepository.setDigestTime(int minutesSinceMidnight)` (`lib/data/repositories/settings_repository.dart:74-104`):

```dart
Future<void> setQuietHoursEnabled({required bool enabled});
Future<void> setQuietHoursStart(int minutesSinceMidnight);
Future<void> setQuietHoursEnd(int minutesSinceMidnight);
Future<void> setEveningReminderEnabled({required bool enabled});
Future<void> setEveningReminderTime(int minutesSinceMidnight);
```

And these `DeviceSettings` fields, which drift derives mechanically from §8.1's column names: `quietHoursEnabled`, `quietStartMinutes`, `quietEndMinutes`, `eveningReminderEnabled`, `eveningReminderMinutes`.

**If slice 1 landed different names, only the call sites in Tasks 1, 2, 4 and 5 change — one argument each.** Check `lib/data/repositories/settings_repository.dart` and the generated `DeviceSettings` before starting Task 1, and adjust in place.

### F3 — Assumed slice-2/3 interfaces

- `applyQuietHours({required DateTime candidate, required bool enabled, required int startMinutes, required int endMinutes}) -> DateTime` in `lib/domain/reminder_planner.dart` (spec §6).
- `eveningNotificationIdBase = 3001`, `eveningHorizonSlots = 7` in the same file (spec §3.1).
- `buildNotificationPlans` gates the evening slots on `settings.eveningReminderEnabled` — implied by §8.1's "changes the behaviour of exactly zero installs until someone opens Settings" and by the parallel with `planDigestSlot(enabled:)`, but **not written as a sentence anywhere in the spec**. Task 7 is the test that proves it; if it turns out the gate is missing, that is a slice-2 defect to **report**, not to patch in the UI.

### F4 — Time formatting: there is no window label to format

The ticket flags 24h-vs-12h as a real l10n problem for a time-window label. **§12 removes the problem by construction**: quiet hours is two separate rows (`settings.quietHours.start`, `settings.quietHours.end`), each rendering *one* time. Every time in this plan is rendered by `TimeOfDay(hour: m ~/ 60, minute: m % 60).format(context)` — the `MaterialLocalizations` formatter `DigestTimeTile` already uses, which honours the locale and `MediaQuery.alwaysUse24HourFormat`. **No string concatenation, no "22:00–07:00" composite, no ICU placeholder carrying a pre-formatted time, no en-dash range.** The ARB strings are pure labels ("From", "To"); the value is a widget property.

**The test consequence, which is a real trap:** widget tests pump with no locale override, so the host resolves to a 12-hour locale in CI — `1320` renders "10:00 PM", not "22:00". **Never assert a default time's digits.** Assert persistence against the database instead, and where a test must prove the row re-rendered, pick 9:30 (`570`), whose 12h render ("9:30 AM") and 24h render ("09:30") both contain the substring `9:30`. This is exactly the trick `test/features/settings/digest_section_test.dart:249` already uses.

### F5 — Deliberately NOT in this plan: a Maestro flow

Spec §13.3 says E2E "can and should" cover these settings surfaces — permissive, not binding; §13.2's *required* coverage is widget tests, which Tasks 1–6 provide. No flow in `e2e/flows/` uses `scrollUntilVisible` (grepped: zero hits), and these rows sit below a Preferences group whose height varies with `AccountSectionBody`. Introducing an unverifiable scroll idiom into a suite whose only gate is GitHub CI costs more than it proves. Recorded here as a deliberate deferral for the wave's E2E pass, not an oversight.

---

## Product decisions taken during planning

The spec records no open questions. These two are genuine gaps it missed; both were raised during planning and **both are now RESOLVED by the coordinator**. They are recorded with their reasoning rather than deleted, so nobody re-opens them from the options alone — the same convention §16 of the spec uses.

### OD1 — The permission hint disappears when the digest is off but the evening re-reminder is on — **RESOLVED: widen it (option A)**

`settings_screen.dart:125` gates `DigestPermissionHint` on `settings.digestEnabled && !permissionGranted`, and `DigestToggleTile` grows `settingsDigestToggleDeniedHint` on `value && permissionDenied`. Slice 6 creates a state that has never existed: **a notification that can be ON while the digest is OFF.** A user with the digest off, the evening re-reminder on, and the OS permission denied currently gets *no* signal anywhere in the group — the exact "switch sitting in its ON position while nothing is being delivered" lie that B-5 built both of those surfaces to remove.

The evening toggle cannot carry a denied sub-line of its own: `SettingsRow` renders exactly one `sublabel`, and `settingsEveningToggleSubtitle` is binding copy that §5.1 requires to be visible whenever the row is (it is what tells a scanning user what the row does). So the fix has to be the hint row.

- **(A) Widen the hint's condition to `(settings.digestEnabled || settings.eveningReminderEnabled) && !permissionGranted`.** One boolean. The hint's copy ("Notifications are turned off in system settings.") is already feature-neutral, so no ARB change. §12's "stays last" is untouched — the row does not move.
- **(B) Leave it as-is.** Ships the B-5 lie in a new place.
- **(C) Give the evening toggle its own denied sub-line.** Rejected above on the binding-copy conflict.

**RESOLVED: (A), applied in Task 6.** The coordinator's reasoning, recorded because it is the part a future reader will need: **the hint's condition was written for a digest-only world.** When it shipped, `digestEnabled` and "any notification is on" were the same proposition, so gating on the former was correct. Slice 6 breaks that equivalence for the first time — and it breaks it in exactly the configuration Igor is most likely to run, since he is the user who asked for the evening re-reminder and may well turn the daily lump off once he has it. A denied OS permission would then go unmentioned anywhere in the group. The condition has to widen with the proposition it was standing in for.

### OD2 — `start == end` shows an ON quiet-hours switch that does nothing — **RESOLVED: accept the state, but say so**

§6 states "`start == end` is treated as OFF, not as a 24-hour window". The spec settles the *semantics* and says nothing about the *UI*: a user who sets From 22:00 and To 22:00 sees the switch in ON with no indication that nothing is quiet — structurally the same lie as OD1.

Three ways to handle the state itself, and the coordinator confirmed the first:

- **Accept a zero-length window as valid.** Refusing equal times adds picker friction for a case almost nobody hits, and reading `start == end` as a 24-hour quiet period would **silently suppress every notification** — far more dangerous than doing nothing, and the exact failure §6's rule exists to prevent.
- Reject equal times in the picker. Friction, and a validation error for a state that harms nothing.
- Treat it as 24 hours. Rejected above.

**But the state must not be silent.** My original recommendation was to accept it with no sub-line, on the grounds that it is deliberate and reversible. **The coordinator extended that, and the extension is right:** an ON switch with no effect is precisely the dishonesty this project has now fixed twice — B-5 stopped the digest toggle reading ON while nothing was scheduled, and D-5's divergence banner exists so a device cannot look healthy while it is not. Shipping a third instance *knowingly* would be inconsistent in a way the first two were not. My reasoning weighed the noise of a third sub-line against the rarity of the state and never weighed it against that precedent, which is the argument that actually governs.

So: **one conditional sub-line, no dialog, no validation error, no blocked save.** Implemented in **Task 2, Steps 12–19**.

**Wording** — the register the other lines use is *state — consequence*, em dash, lower-case after:

| | |
|---|---|
| EN | **"Start and end are the same — no quiet time"** |
| DE | **"Anfang und Ende sind gleich — keine Ruhezeit"** |

It leads with the thing the user can fix (either picker) and follows with the honest consequence, matching `settingsEveningInQuietHoursHint` ("Inside your quiet hours — not delivering") and `settingsDigestToggleDeniedHint` ("Not delivering — notifications are off").

**Which row it goes on, and why:** `settings.quietHours.toggle`. B-5's precedent puts the line on the widget that is lying, and the switch is what reads ON while nothing is quiet — not the From row, which is showing a perfectly truthful time.

**Collision check — they cannot collide.** Every conditional sub-line in play after this wave lives on a distinct row, so no severity ordering is ever needed:

| Row | Sub-line | Condition |
|---|---|---|
| `settings.digest.toggle` | `settingsDigestToggleDeniedHint` (shipped) **or** the ceiling hint (slice 4, per that plan's OPD-2, denied wins on severity) | digest on + permission denied / over ceiling |
| `settings.evening.toggle` | `settingsEveningToggleSubtitle` | **unconditional** |
| `settings.evening.time` | `settingsEveningInQuietHoursHint` | evening time inside the window |
| `settings.quietHours.toggle` | `settingsQuietHoursEmptyWindowHint` (this decision) | quiet on + `start == end` |

The only pairing worth checking twice is this line against `settingsEveningInQuietHoursHint`, since both concern the window. **They are mutually exclusive by construction, not by precedence:** `isWithinQuietHours` returns `false` for every minute when `start == end`, so an empty window can never put the evening time "inside" it — and they sit on different rows in any case. **Task 5** asserts that pairing directly (not Task 2, which predates the evening row), so the exclusivity is tested rather than argued.

---

## File structure

**Create**

| Path | Responsibility |
|---|---|
| `lib/features/settings/settings_time_row.dart` | `SettingsTimeRow` — one reusable "label + trailing time + input-mode picker" row. The single home of the `showTimePicker` incantation. |
| `lib/features/settings/quiet_hours_section.dart` | `QuietHoursToggleTile`, `QuietHoursStartTile`, `QuietHoursEndTile`. Slice 5's whole surface. |
| `lib/features/settings/evening_section.dart` | `EveningToggleTile`, `EveningTimeTile`. Slice 6's whole surface. |
| `test/features/settings/quiet_hours_section_test.dart` | Slice 5 widget tests. |
| `test/features/settings/evening_section_test.dart` | Slice 6 widget tests, including the collision sub-line. |
| `test/features/settings/settings_row_order_test.dart` | The §12 order guard (D12's discoverability, made executable) + OD1's hint test. |

**Modify**

| Path | Change |
|---|---|
| `lib/domain/reminder_planner.dart` | Add `isWithinQuietHours`; make `applyQuietHours` delegate its membership test to it. Nothing else in that file is touched. |
| `lib/features/settings/digest_section.dart` | `DigestTimeTile` delegates to `SettingsTimeRow`. Same id, same behaviour. |
| `lib/features/settings/settings_screen.dart` | Compose the five new rows into the existing Preferences group in §12 order; widen the permission hint's condition (OD1-A). |
| `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb` (+ regenerated `app_localizations*.dart`) | Seven new keys. |
| `test/domain/reminder_planner_test.dart` | (Created by slice 2.) Add the `isWithinQuietHours` group. |
| `test/app/digest_reschedule_test.dart` | Add the evening-liveness group at the end, reusing that file's `_awaitBootstrap` / `_disposeAndClose`. |
| `docs/specs/notifications-n2.md` | **Task 8 only.** Correct §12's non-existent "Daily summary" section and §11's non-existent `digestDoneActionLabel` (F1, F1b). Prose only. |

**Which task makes each half LIVE**

- **Quiet hours goes live at Task 1.** The moment the toggle can write `quiet_hours_enabled = true`, slice 2/3's `applyQuietHours` (already inside `buildNotificationPlans`, already applied by `applyPlans`) starts deferring the digest and per-chore reminders across the shipped 22:00–07:00 default. Task 2 only makes the window adjustable. **State this in the Task 1 commit:** from that commit on, a user turning the switch on changes digest delivery — the additive, defaults-OFF behaviour change §6 authorises deliberately.
- **The evening re-reminder goes live at Task 4.** `evening_reminder_enabled` ships `false` (§8.1) and nothing else in the app can set it, so Task 4's toggle is the feature's first and only ON path. **Task 7 proves it end to end** (it does not create it).

---

## Task 1: Quiet-hours toggle row

**Files:**
- Create: `lib/features/settings/quiet_hours_section.dart`
- Create: `test/features/settings/quiet_hours_section_test.dart`
- Modify: `lib/l10n/app_en.arb` (after the `settingsDigestPermissionAction` block, ~line 1003), `lib/l10n/app_de.arb` (after `settingsDigestPermissionAction`, ~line 209)
- Modify: `lib/features/settings/settings_screen.dart:112-135`

**Interfaces:**
- Consumes: `SettingsRow` (`lib/features/settings/settings_group.dart`), `semantic` (`lib/app/semantics.dart`), `SettingsRepository.setQuietHoursEnabled({required bool enabled})` and `DeviceSettings.quietHoursEnabled` (slice 1 — see F2).
- Produces: `QuietHoursToggleTile({required bool value, required ValueChanged<bool> onChanged, Key? key})`, semantic id `settings.quietHours.toggle`.

- [ ] **Step 1: Write the failing test**

Create `test/features/settings/quiet_hours_section_test.dart`:

```dart
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'settings_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'quiet hours ships OFF: the switch is off and no window rows are shown',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      final toggle = tester.widget<Switch>(
        find
            .descendant(
              of: find.bySemanticsIdentifier('settings.quietHours.toggle'),
              matching: find.byType(Switch),
            )
            .first,
      );
      expect(toggle.value, isFalse);

      final row = await database.select(database.settings).getSingle();
      expect(row.quietHoursEnabled, isFalse);

      handle.dispose();
    },
  );

  testChoreApp(
    'turning quiet hours on persists it, and turning it off persists that too',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      await tester.tap(
        find.bySemanticsIdentifier('settings.quietHours.toggle'),
      );
      await tester.pumpAndSettle();
      var row = await database.select(database.settings).getSingle();
      expect(row.quietHoursEnabled, isTrue);
      // The shipped window is what goes live the moment the switch does
      // (spec notifications-n2.md §8.1: 22:00-07:00).
      expect(row.quietStartMinutes, 1320);
      expect(row.quietEndMinutes, 420);

      await tester.tap(
        find.bySemanticsIdentifier('settings.quietHours.toggle'),
      );
      await tester.pumpAndSettle();
      row = await database.select(database.settings).getSingle();
      expect(row.quietHoursEnabled, isFalse);

      handle.dispose();
    },
  );

  testChoreApp(
    'the quiet-hours switch reflects a value written outside the widget',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      await SettingsRepository(database).setQuietHoursEnabled(enabled: true);
      await tester.pumpAndSettle();

      final toggle = tester.widget<Switch>(
        find
            .descendant(
              of: find.bySemanticsIdentifier('settings.quietHours.toggle'),
              matching: find.byType(Switch),
            )
            .first,
      );
      expect(toggle.value, isTrue);

      handle.dispose();
    },
  );
}
```

- [ ] **Step 2: Run the test and confirm it fails AT THE TEST STEP**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/settings/quiet_hours_section_test.dart
```

Expected: all three FAIL inside the test body with `Bad state: No element` / "Found 0 widgets with semantics identifier settings.quietHours.toggle". The file compiles — it references no `AppLocalizations` getter, deliberately, so the red is a missing widget and not a build failure.

- [ ] **Step 3: Add the ARB key**

In `lib/l10n/app_en.arb`, immediately after the `"@settingsDigestPermissionAction"` block and its closing `},`, before the blank line preceding `"settingsExportEntry"`:

```json
  "settingsQuietHoursToggle": "Quiet hours",
  "@settingsQuietHoursToggle": {
    "description": "Title of the settings screen's quiet-hours on/off switch row, directly below the evening re-reminder rows in the Preferences group (spec docs/specs/notifications-n2.md §12). While on, the digest and per-chore reminders that would fall inside the window are deferred to its end rather than dropped (§6)."
  },
```

In `lib/l10n/app_de.arb`, immediately after `"settingsDigestPermissionAction": "Einstellungen öffnen",`:

```json
  "settingsQuietHoursToggle": "Ruhezeiten",
```

- [ ] **Step 4: Regenerate localizations**

```bash
flutter gen-l10n
```

Expected: `lib/l10n/app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_de.dart` gain `settingsQuietHoursToggle`.

- [ ] **Step 5: Write the widget**

Create `lib/features/settings/quiet_hours_section.dart`:

```dart
/// The settings screen's quiet-hours rows, inside the Preferences group
/// (spec `docs/specs/notifications-n2.md` §6 and §12): an on/off switch and,
/// while it is on, the window's start and end time rows.
///
/// Quiet hours DEFER, never drop, for the digest and for per-chore
/// reminders (decision D7) -- the evening re-reminder is the one exception,
/// and its collision with this window is surfaced on the evening time row
/// (`evening_section.dart`), not here.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/features/settings/settings_group.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The 'Quiet hours' on/off switch row.
class QuietHoursToggleTile extends StatelessWidget {
  /// Creates the toggle row.
  const QuietHoursToggleTile({
    required this.value,
    required this.onChanged,
    super.key,
  });

  /// Whether quiet hours are currently enabled.
  final bool value;

  /// Called when the switch is flipped.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return semantic(
      'settings.quietHours.toggle',
      child: SettingsRow(
        icon: Icons.bedtime_outlined,
        label: l10n.settingsQuietHoursToggle,
        switchValue: value,
        onSwitchChanged: onChanged,
      ),
    );
  }
}
```

- [ ] **Step 6: Compose it into the existing group**

In `lib/features/settings/settings_screen.dart`, add the import (alphabetical, after `manage_members_screen.dart`):

```dart
import 'package:chore_app/features/settings/quiet_hours_section.dart';
```

and insert the row into the `settingsAsync.when` data list, between the `if (settings.digestEnabled) DigestTimeTile(...)` entry and the `if (settings.digestEnabled && !permissionGranted)` hint entry:

```dart
                  QuietHoursToggleTile(
                    value: settings.quietHoursEnabled,
                    onChanged: (enabled) => settingsRepository
                        .setQuietHoursEnabled(enabled: enabled),
                  ),
```

Note it is **not** gated on `digestEnabled`: quiet hours govern per-chore reminders too, and §12 puts it in the group unconditionally.

- [ ] **Step 7: Run the tests and confirm green**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/settings/quiet_hours_section_test.dart test/features/settings/digest_section_test.dart
```

Expected: all PASS (the digest file is here as a regression guard — the new row sits in the same list).

- [ ] **Step 8: Invert the implementation and confirm the test catches it**

In `settings_screen.dart`, temporarily replace the toggle's callback with a no-op:

```dart
                    onChanged: (enabled) {},
```

Run the same command. Expected: **"turning quiet hours on persists it…" FAILS at `expect(row.quietHoursEnabled, isTrue)` with `Expected: true / Actual: <false>`** — a failure inside the test body, not at analyze. Then restore the real callback and re-run to green.

- [ ] **Step 9: Format, analyze, commit**

```bash
dart format lib/features/settings/quiet_hours_section.dart lib/features/settings/settings_screen.dart test/features/settings/quiet_hours_section_test.dart lib/l10n/
flutter analyze --fatal-infos --fatal-warnings
git add lib/features/settings/quiet_hours_section.dart lib/features/settings/settings_screen.dart lib/l10n test/features/settings/quiet_hours_section_test.dart
git commit -m "feat(settings): quiet-hours toggle row

N2 slice 5, spec docs/specs/notifications-n2.md §6/§12. This is the commit
that makes quiet hours LIVE: buildNotificationPlans already reads the
column, so from here a user turning the switch on defers the digest and
per-chore reminders across the shipped 22:00-07:00 window. Defaults OFF, so
no existing install changes behaviour."
```

---

## Task 2: Quiet-hours From/To rows, on a shared `SettingsTimeRow`

**Files:**
- Create: `lib/features/settings/settings_time_row.dart`
- Modify: `lib/features/settings/quiet_hours_section.dart`
- Modify: `lib/features/settings/digest_section.dart:57-107`
- Modify: `lib/features/settings/settings_screen.dart`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`
- Modify: `test/features/settings/quiet_hours_section_test.dart`

**Interfaces:**
- Consumes: Task 1's `QuietHoursToggleTile`; `SettingsRepository.setQuietHoursStart(int)` / `setQuietHoursEnd(int)`; `DeviceSettings.quietStartMinutes` / `quietEndMinutes`.
- Produces: `SettingsTimeRow({required String semanticId, required IconData icon, required String label, required int minutesSinceMidnight, required ValueChanged<int> onChanged, String? sublabel, Key? key})`; `QuietHoursStartTile` / `QuietHoursEndTile`, each `({required int minutesSinceMidnight, required ValueChanged<int> onChanged, Key? key})`, ids `settings.quietHours.start` / `settings.quietHours.end`. Second cycle also widens `QuietHoursToggleTile` to `({required bool value, required ValueChanged<bool> onChanged, bool emptyWindow = false, Key? key})`.

**Two TDD cycles, two commits.** Steps 1–11 are the From/To rows. Steps 12–19 are the empty-window sub-line (OD2), which reads the pair those rows introduce and therefore belongs to the same reviewer gate.

- [ ] **Step 1: Write the failing tests**

Append to `test/features/settings/quiet_hours_section_test.dart`, inside `main()`:

```dart
  testChoreApp(
    'the window rows are hidden while quiet hours are off and revealed when '
    'they are turned on',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      // Guard against the reveal assertion below passing for the wrong
      // reason: the rows must be genuinely absent first.
      expect(
        find.bySemanticsIdentifier('settings.quietHours.start'),
        findsNothing,
      );
      expect(
        find.bySemanticsIdentifier('settings.quietHours.end'),
        findsNothing,
      );

      await tester.tap(
        find.bySemanticsIdentifier('settings.quietHours.toggle'),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('settings.quietHours.start'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('settings.quietHours.end'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'picking a quiet-hours start persists it and re-renders the row',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);
      await SettingsRepository(database).setQuietHoursEnabled(enabled: true);
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsIdentifier('settings.quietHours.start'));
      await tester.pumpAndSettle();

      // The picker opens in `TimePickerEntryMode.input`: two
      // `TextFormField`s (hour, minute), deterministically driveable unlike
      // the dial.
      final fields = find.byType(TextFormField);
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.first, '9');
      await tester.enterText(fields.last, '30');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final row = await database.select(database.settings).getSingle();
      expect(row.quietStartMinutes, 9 * 60 + 30);
      // 09:30 is the one time whose 12h render ("9:30 AM") and 24h render
      // ("09:30") share a substring -- these tests pump with no locale
      // override, so the host decides which one appears. Never assert a
      // 22:00-style default's digits.
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('settings.quietHours.start'),
          matching: find.textContaining('9:30'),
        ),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'picking a quiet-hours end persists it independently of the start',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);
      await SettingsRepository(database).setQuietHoursEnabled(enabled: true);
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsIdentifier('settings.quietHours.end'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.first, '9');
      await tester.enterText(fields.last, '30');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final row = await database.select(database.settings).getSingle();
      expect(row.quietEndMinutes, 9 * 60 + 30);
      // The start row must NOT have moved -- this is what proves the two
      // rows are wired to different setters rather than to one.
      expect(row.quietStartMinutes, 1320);

      handle.dispose();
    },
  );
```

- [ ] **Step 2: Run and confirm red AT THE TEST STEP**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/settings/quiet_hours_section_test.dart
```

Expected: the three new tests FAIL in the body — the first at `findsOneWidget` ("Found 0 widgets"), the other two at the `tester.tap` with "Found 0 widgets with semantics identifier settings.quietHours.start". The three Task 1 tests still PASS.

- [ ] **Step 3: Add the ARB keys**

`lib/l10n/app_en.arb`, immediately after the `"@settingsQuietHoursToggle"` block:

```json
  "settingsQuietHoursFrom": "From",
  "@settingsQuietHoursFrom": {
    "description": "Title of the settings row holding the START of the quiet-hours window, revealed under the quiet-hours switch. A bare preposition on purpose: the row shows the chosen time as trailing text via TimeOfDay.format, so the label must not repeat the word 'time' or try to compose a '22:00-07:00' range -- the window is two independent rows precisely so no locale-sensitive range string ever has to be built (spec docs/specs/notifications-n2.md §12)."
  },
  "settingsQuietHoursTo": "To",
  "@settingsQuietHoursTo": {
    "description": "Title of the settings row holding the END of the quiet-hours window, directly below settingsQuietHoursFrom. See that key for why it is a bare preposition. The window wraps midnight in the normal case (22:00 to 07:00)."
  },
```

`lib/l10n/app_de.arb`, immediately after `"settingsQuietHoursToggle": "Ruhezeiten",`:

```json
  "settingsQuietHoursFrom": "Von",
  "settingsQuietHoursTo": "Bis",
```

- [ ] **Step 4: Regenerate localizations**

```bash
flutter gen-l10n
```

- [ ] **Step 5: Create the shared time row**

Create `lib/features/settings/settings_time_row.dart`:

```dart
/// The settings screen's reusable "pick a time" row.
///
/// Extracted so the four time rows the Preferences group now holds -- the
/// digest time, the evening re-reminder time, and the two ends of the
/// quiet-hours window (spec `docs/specs/notifications-n2.md` §12) -- share
/// one picker call rather than four copies of it.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/features/settings/settings_group.dart';
import 'package:flutter/material.dart';

/// A [SettingsRow] whose trailing value is a wall-clock time, opening a
/// time picker on tap.
///
/// The time is rendered with `TimeOfDay.format(context)`, so 12h/24h and
/// the separator follow the viewer's locale and
/// `MediaQuery.alwaysUse24HourFormat` -- never a hand-composed string.
class SettingsTimeRow extends StatelessWidget {
  /// Creates a time row identified by [semanticId].
  const SettingsTimeRow({
    required this.semanticId,
    required this.icon,
    required this.label,
    required this.minutesSinceMidnight,
    required this.onChanged,
    this.sublabel,
    super.key,
  });

  /// The stable identifier this row is wrapped with, for E2E and widget
  /// selectors (see `lib/app/semantics.dart`).
  final String semanticId;

  /// The row's leading glyph.
  final IconData icon;

  /// The row's title.
  final String label;

  /// An optional factual sub-line under [label].
  final String? sublabel;

  /// The currently-chosen time, as minutes since local midnight (0..1439).
  final int minutesSinceMidnight;

  /// Called with the newly-picked time, also as minutes since midnight.
  /// Not called when the picker is dismissed.
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return semantic(
      semanticId,
      child: SettingsRow(
        icon: icon,
        label: label,
        sublabel: sublabel,
        value: _timeOfDay.format(context),
        onTap: () => _pick(context),
      ),
    );
  }

  TimeOfDay get _timeOfDay => TimeOfDay(
    hour: minutesSinceMidnight ~/ 60,
    minute: minutesSinceMidnight % 60,
  );

  Future<void> _pick(BuildContext context) async {
    // Input mode (rather than the default dial) so the picker is reachable
    // by typing a time directly -- also what makes this deterministically
    // driveable from a widget test, unlike the dial's freeform gestures.
    final picked = await showTimePicker(
      context: context,
      initialTime: _timeOfDay,
      initialEntryMode: TimePickerEntryMode.input,
    );
    if (picked != null) {
      onChanged(picked.hour * 60 + picked.minute);
    }
  }
}
```

- [ ] **Step 6: Add the two quiet-hours rows**

Append to `lib/features/settings/quiet_hours_section.dart` (and add `import 'package:chore_app/features/settings/settings_time_row.dart';` to its imports):

```dart
/// The quiet-hours window's START row, revealed while the switch is on.
class QuietHoursStartTile extends StatelessWidget {
  /// Creates the start-time row.
  const QuietHoursStartTile({
    required this.minutesSinceMidnight,
    required this.onChanged,
    super.key,
  });

  /// The window's start, as minutes since local midnight.
  final int minutesSinceMidnight;

  /// Called with the newly-picked start, also as minutes since midnight.
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingsTimeRow(
      semanticId: 'settings.quietHours.start',
      icon: Icons.schedule_outlined,
      label: AppLocalizations.of(context).settingsQuietHoursFrom,
      minutesSinceMidnight: minutesSinceMidnight,
      onChanged: onChanged,
    );
  }
}

/// The quiet-hours window's END row, revealed while the switch is on.
///
/// The window wraps midnight in the normal case (22:00 to 07:00), so this
/// value is routinely SMALLER than the start's; nothing here validates an
/// ordering, deliberately -- `isWithinQuietHours` treats the pair as a
/// wrapping interval (spec `docs/specs/notifications-n2.md` §6).
class QuietHoursEndTile extends StatelessWidget {
  /// Creates the end-time row.
  const QuietHoursEndTile({
    required this.minutesSinceMidnight,
    required this.onChanged,
    super.key,
  });

  /// The window's end, as minutes since local midnight.
  final int minutesSinceMidnight;

  /// Called with the newly-picked end, also as minutes since midnight.
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingsTimeRow(
      semanticId: 'settings.quietHours.end',
      icon: Icons.schedule_outlined,
      label: AppLocalizations.of(context).settingsQuietHoursTo,
      minutesSinceMidnight: minutesSinceMidnight,
      onChanged: onChanged,
    );
  }
}
```

- [ ] **Step 7: Refactor `DigestTimeTile` onto the shared row**

In `lib/features/settings/digest_section.dart`, replace the whole `DigestTimeTile` class body (lines 57-107) with:

```dart
/// The digest fire-time row, opening a time picker on tap.
class DigestTimeTile extends StatelessWidget {
  /// Creates the time row.
  const DigestTimeTile({
    required this.minutesSinceMidnight,
    required this.onChanged,
    super.key,
  });

  /// The currently-chosen fire time, as minutes since local midnight.
  final int minutesSinceMidnight;

  /// Called with the newly-picked time, also as minutes since midnight.
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingsTimeRow(
      // Load-bearing for E2E -- unchanged by this refactor.
      semanticId: 'settings.digest.time',
      icon: Icons.schedule_outlined,
      label: AppLocalizations.of(context).settingsDigestTimeLabel,
      minutesSinceMidnight: minutesSinceMidnight,
      onChanged: onChanged,
    );
  }
}
```

Add `import 'package:chore_app/features/settings/settings_time_row.dart';` to that file's imports. `semantic` may now be unused there — it is not: `DigestToggleTile` and `DigestPermissionHint` still use it, so keep the import.

- [ ] **Step 8: Compose the two rows**

In `settings_screen.dart`, replace the `QuietHoursToggleTile(...)` entry added in Task 1 with:

```dart
                  QuietHoursToggleTile(
                    value: settings.quietHoursEnabled,
                    onChanged: (enabled) => settingsRepository
                        .setQuietHoursEnabled(enabled: enabled),
                  ),
                  if (settings.quietHoursEnabled) ...[
                    QuietHoursStartTile(
                      minutesSinceMidnight: settings.quietStartMinutes,
                      onChanged: settingsRepository.setQuietHoursStart,
                    ),
                    QuietHoursEndTile(
                      minutesSinceMidnight: settings.quietEndMinutes,
                      onChanged: settingsRepository.setQuietHoursEnd,
                    ),
                  ],
```

- [ ] **Step 9: Run and confirm green**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/settings/quiet_hours_section_test.dart test/features/settings/digest_section_test.dart
```

Expected: all PASS. `digest_section_test.dart`'s "time picker round trip" is the guard proving the `DigestTimeTile` refactor is behaviour-preserving.

- [ ] **Step 10: Invert the implementation and confirm the tests catch it**

Two inversions, run after each:

1. In `settings_screen.dart`, drop the `if (settings.quietHoursEnabled)` guard so the two rows always render.
   Expected: **"the window rows are hidden while quiet hours are off…" FAILS at the first `findsNothing`** with "Found 1 widget". Restore.
2. Point `QuietHoursEndTile`'s `onChanged` at `settingsRepository.setQuietHoursStart`.
   Expected: **"picking a quiet-hours end persists it independently of the start" FAILS at `expect(row.quietEndMinutes, 570)`** with `Actual: <420>`. Restore and re-run to green.

- [ ] **Step 11: Format, analyze, commit**

```bash
dart format lib/features/settings test/features/settings/quiet_hours_section_test.dart lib/l10n/
flutter analyze --fatal-infos --fatal-warnings
git add lib/features/settings lib/l10n test/features/settings/quiet_hours_section_test.dart
git commit -m "feat(settings): quiet-hours From/To rows on a shared SettingsTimeRow

N2 slice 5, spec docs/specs/notifications-n2.md §6/§12. Two independent
rows, never a composed range string: each renders its own time through
TimeOfDay.format so 12h/24h follows the locale. DigestTimeTile is refactored
onto the same row and keeps its settings.digest.time id."
```

### Task 2, second cycle: the empty-window sub-line (OD2)

A second TDD cycle and a second commit inside this task, because the sub-line is a function of the From/To pair this task introduces and makes no sense without it — a reviewer approving these rows should see the honesty line in the same breath. No new files.

§6 makes `start == end` mean OFF. Without a sub-line the switch then reads ON while nothing is ever quiet — the third instance of a lie B-5 and D-5 each removed once. See **OD2** above for the decision, the wording, and the collision map.

**How these tests discriminate.** "Sub-line appears when start equals end" is satisfied by a widget that always shows it. The four below pin it from every side: a non-empty window shows nothing (kills always-on), an empty window shows it (the positive), an empty window with quiet hours *off* shows nothing (proves it reads `enabled`, not just the two times), and moving the end time alone makes it vanish with nothing else changed (proves it is a projection with no stored flag).

- [ ] **Step 12: Write the failing tests**

Append to `test/features/settings/quiet_hours_section_test.dart`, inside `main()`:

```dart
  // BINDING only in the sense that it is matched literally -- see the
  // comment in digest_section_test.dart: these tests pump with no locale
  // override, so the template ARB's text is what renders, and reading the
  // same AppLocalizations getter the widget reads would pass no matter
  // what that getter returned.
  const emptyWindowSubline = 'Start and end are the same — no quiet time';

  testChoreApp(
    'no empty-window sub-line while the window has a real length',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);
      await SettingsRepository(database).setQuietHoursEnabled(enabled: true);
      await tester.pumpAndSettle();

      // The shipped 22:00-07:00 defaults.
      expect(find.text(emptyWindowSubline), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'a zero-length window says so on the toggle, and self-clears when '
    'either time moves',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);
      final settings = SettingsRepository(database);
      await settings.setQuietHoursEnabled(enabled: true);
      // Spec §6: start == end is OFF, not a 24-hour window. The switch
      // would otherwise sit in ON with nothing ever deferred.
      await settings.setQuietHoursEnd(1320);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('settings.quietHours.toggle'),
          matching: find.text(emptyWindowSubline),
        ),
        findsOneWidget,
      );

      // Move ONLY the end. A pure projection of the two times: nothing
      // stored, nothing to dismiss.
      await settings.setQuietHoursEnd(420);
      await tester.pumpAndSettle();

      expect(find.text(emptyWindowSubline), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'no empty-window sub-line while quiet hours are off, even with equal '
    'times',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);
      final settings = SettingsRepository(database);
      // Set the equal times while the feature is ON so the rows exist to
      // write through, then turn it off -- the stored times persist.
      await settings.setQuietHoursEnabled(enabled: true);
      await settings.setQuietHoursEnd(1320);
      await tester.pumpAndSettle();
      // Guard: the sub-line must be present BEFORE the switch goes off, or
      // the findsNothing below proves nothing about the disabled case.
      expect(find.text(emptyWindowSubline), findsOneWidget);

      await settings.setQuietHoursEnabled(enabled: false);
      await tester.pumpAndSettle();

      expect(find.text(emptyWindowSubline), findsNothing);

      handle.dispose();
    },
  );
```

- [ ] **Step 13: Run and confirm red AT THE TEST STEP**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/settings/quiet_hours_section_test.dart
```

Expected: "a zero-length window says so on the toggle…" FAILS at `findsOneWidget` with "Found 0 widgets"; "no empty-window sub-line while quiet hours are off…" FAILS at its **guard** `expect(..., findsOneWidget)` for the same reason. The first test PASSES trivially (nothing renders the string yet) — which is exactly why it is not the load-bearing one. Everything from the first cycle still PASSES.

- [ ] **Step 14: Add the ARB key**

`lib/l10n/app_en.arb`, immediately after the `"@settingsQuietHoursTo"` block:

```json
  "settingsQuietHoursEmptyWindowHint": "Start and end are the same — no quiet time",
  "@settingsQuietHoursEmptyWindowHint": {
    "description": "Sub-line under the settings screen's quiet-hours toggle, shown only while the switch is ON and the start and end times are equal. Spec docs/specs/notifications-n2.md §6 treats start == end as OFF rather than as a 24-hour window (the latter would mean 'never notify', which is what the toggle is for), so without this line the switch would sit in its ON position while nothing is ever deferred -- the same dishonesty settingsDigestToggleDeniedHint exists to remove. Leads with the thing the user can change, follows with the consequence, matching the register of the other two sub-lines in this group. A pure projection of the two stored times: no flag, always current, self-clearing the moment either one moves."
  },
```

`lib/l10n/app_de.arb`, immediately after `"settingsQuietHoursTo": "Bis",`:

```json
  "settingsQuietHoursEmptyWindowHint": "Anfang und Ende sind gleich — keine Ruhezeit",
```

- [ ] **Step 15: Regenerate localizations**

```bash
flutter gen-l10n
```

- [ ] **Step 16: Grow the sub-line on the toggle**

In `lib/features/settings/quiet_hours_section.dart`, replace `QuietHoursToggleTile` with:

```dart
/// The 'Quiet hours' on/off switch row.
class QuietHoursToggleTile extends StatelessWidget {
  /// Creates the toggle row.
  const QuietHoursToggleTile({
    required this.value,
    required this.onChanged,
    this.emptyWindow = false,
    super.key,
  });

  /// Whether quiet hours are currently enabled.
  final bool value;

  /// Called when the switch is flipped.
  final ValueChanged<bool> onChanged;

  /// Whether the stored window has zero length (`start == end`), which
  /// spec `docs/specs/notifications-n2.md` §6 treats as OFF rather than as
  /// a 24-hour window.
  ///
  /// When [value] is also true this grows a short factual sub-line, so the
  /// switch's ON position never implies a deferral that isn't happening --
  /// the same reason `DigestToggleTile.permissionDenied` exists (backlog
  /// B-5). Presentation only: it never rewrites either stored time, because
  /// the times remain the record of what the user set.
  ///
  /// A pure projection of the two settings, computed by the caller: always
  /// current, self-clearing the instant either time moves, nothing stored
  /// and nothing to dismiss.
  final bool emptyWindow;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return semantic(
      'settings.quietHours.toggle',
      child: SettingsRow(
        icon: Icons.bedtime_outlined,
        label: l10n.settingsQuietHoursToggle,
        sublabel: value && emptyWindow
            ? l10n.settingsQuietHoursEmptyWindowHint
            : null,
        switchValue: value,
        onSwitchChanged: onChanged,
      ),
    );
  }
}
```

- [ ] **Step 17: Wire the projection**

In `settings_screen.dart`, replace the `QuietHoursToggleTile(...)` entry with:

```dart
                  QuietHoursToggleTile(
                    value: settings.quietHoursEnabled,
                    emptyWindow:
                        settings.quietStartMinutes == settings.quietEndMinutes,
                    onChanged: (enabled) => settingsRepository
                        .setQuietHoursEnabled(enabled: enabled),
                  ),
```

Deliberately a direct comparison rather than a call into `reminder_planner.dart`: "the window has zero length" is a property of the two stored values, not a membership question, and `isWithinQuietHours` already folds `start == end` into its own `false` result — routing through it would make the sub-line depend on a *minute* it has no business picking.

- [ ] **Step 18: Run and confirm green, then invert**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/settings/quiet_hours_section_test.dart test/features/settings/digest_section_test.dart
```

Expected: all PASS.

Then two inversions, running the command after each:

1. In `settings_screen.dart`, replace the `emptyWindow:` argument with `emptyWindow: true`.
   Expected: **"no empty-window sub-line while the window has a real length" FAILS at `findsNothing` with "Found 1 widget"** — the assertion an always-on sub-line cannot survive. Restore.
2. In `quiet_hours_section.dart`, change the sub-line condition from `value && emptyWindow` to `emptyWindow` alone.
   Expected: **"no empty-window sub-line while quiet hours are off, even with equal times" FAILS at its final `findsNothing`**. Restore and re-run to green.

- [ ] **Step 19: Format, analyze, commit**

```bash
dart format lib/features/settings lib/l10n/ test/features/settings/quiet_hours_section_test.dart
flutter analyze --fatal-infos --fatal-warnings
git add lib/features/settings lib/l10n test/features/settings/quiet_hours_section_test.dart
git commit -m "feat(settings): say so when the quiet-hours window is empty

Spec docs/specs/notifications-n2.md §6 treats start == end as OFF, so the
switch would otherwise read ON while nothing is ever deferred -- the third
instance of a lie B-5 removed from the digest toggle and D-5 from the sync
banner. One factual sub-line, a pure projection of the two stored times.
Equal times stay a VALID state: rejecting them adds picker friction, and
reading them as a 24-hour window would silently suppress everything."
```

---

## Task 3: `isWithinQuietHours` — one wrapping-interval implementation

**Files:**
- Modify: `lib/domain/reminder_planner.dart` (slice 2's file)
- Modify: `test/domain/reminder_planner_test.dart` (slice 2's file)

**Interfaces:**
- Consumes: slice 2's `applyQuietHours({required DateTime candidate, required bool enabled, required int startMinutes, required int endMinutes}) -> DateTime`.
- Produces: `bool isWithinQuietHours({required int minuteOfDay, required bool enabled, required int startMinutes, required int endMinutes})` — consumed by `settings_screen.dart` in Task 5.

**Why this exists rather than reusing `applyQuietHours` directly:** the settings UI needs a *boolean over a minute-of-day*, not a shifted `DateTime`. Deriving it by calling `applyQuietHours` with a synthetic date and comparing would work but hides the question inside a date. Deriving it with a second hand-written comparison would give the app two wrapping-interval implementations that can disagree — which is exactly how a user ends up seeing "not delivering" on a notification that delivers. So: one predicate, and `applyQuietHours` delegates its membership test to it. The agreement test in Step 1 is what makes that non-negotiable even if someone later re-inlines it.

**How these tests discriminate** (the ticket's "a test that asserts suppressed-inside is satisfied by suppress-everything" trap): the load-bearing assertion is not "22:30 is inside" but **the cardinality of the whole inside-set over all 1440 minutes**. For 22:00-07:00 that is exactly 540. A suppress-everything implementation gives 1440; a suppress-nothing one gives 0; a non-wrapping-only `start <= m < end` gives 0 (because `start > end`); an inclusive-at-both-ends one gives 541. All four are distinguished by one number. The DST warning does not apply to this function at all: it never constructs a `DateTime`, so it has no DST exposure — the calendar-component construction stays entirely inside `applyQuietHours`, which this task does not touch.

- [ ] **Step 1: Write the failing tests**

Append to `test/domain/reminder_planner_test.dart` (add `import 'package:chore_app/domain/reminder_planner.dart';` if it is not already there):

```dart
  group('isWithinQuietHours (spec notifications-n2.md §6)', () {
    /// Every minute-of-day for which the predicate is true, given a window.
    List<int> insideSet({
      required bool enabled,
      required int startMinutes,
      required int endMinutes,
    }) => [
      for (var m = 0; m < 1440; m++)
        if (isWithinQuietHours(
          minuteOfDay: m,
          enabled: enabled,
          startMinutes: startMinutes,
          endMinutes: endMinutes,
        ))
          m,
    ];

    test('a window that wraps midnight covers exactly its two arcs', () {
      // The shipped default, 22:00-07:00: {0..419} U {1320..1439}.
      final inside = insideSet(
        enabled: true,
        startMinutes: 1320,
        endMinutes: 420,
      );
      // The number that kills "suppress everything" (1440), "suppress
      // nothing" (0), a non-wrapping-only comparison (0) and an
      // inclusive-at-both-ends one (541) in a single assertion.
      expect(inside, hasLength(540));
      expect(inside.first, 0);
      expect(inside.last, 1439);
      // Boundaries, per spec §13.1: exactly at `start` is inside, exactly
      // at `end` is outside.
      expect(inside.contains(1320), isTrue);
      expect(inside.contains(1319), isFalse);
      expect(inside.contains(420), isFalse);
      expect(inside.contains(419), isTrue);
      // The far side of the wrap -- 06:00 is inside a 22:00-07:00 window
      // even though 360 < 1320. This is the assertion a naive
      // `start <= m && m <= end` fails.
      expect(inside.contains(360), isTrue);
    });

    test('a window that does not wrap covers exactly one arc', () {
      final inside = insideSet(
        enabled: true,
        startMinutes: 540,
        endMinutes: 1020,
      );
      expect(inside, hasLength(480));
      expect(inside.first, 540);
      expect(inside.last, 1019);
      expect(inside.contains(1020), isFalse);
      expect(inside.contains(539), isFalse);
    });

    test('start == end is OFF, never a 24-hour window', () {
      expect(
        insideSet(enabled: true, startMinutes: 600, endMinutes: 600),
        isEmpty,
      );
      expect(
        insideSet(enabled: true, startMinutes: 0, endMinutes: 0),
        isEmpty,
      );
    });

    test('disabled quiet hours are never inside, whatever the window', () {
      expect(
        insideSet(enabled: false, startMinutes: 1320, endMinutes: 420),
        isEmpty,
      );
    });

    // The anti-divergence guard: the settings UI's predicate and the
    // scheduler's shift must agree on every minute of the day, or a user
    // sees "Inside your quiet hours -- not delivering" on a notification
    // that delivers (or the reverse). `applyQuietHours` returns its
    // candidate UNCHANGED exactly when the candidate is outside, so the
    // biconditional below is total.
    test('applyQuietHours defers exactly the minutes this predicate '
        'reports as inside, for every minute of the day', () {
      // A mid-January reference date: no DST transition exists on it in any
      // zone CI might run in, so every one of the 1440 wall-clock times
      // below is real and unambiguous. The date is irrelevant to the
      // predicate, which reads only minute-of-day.
      for (final window in const [
        (start: 1320, end: 420), // wrapping, the shipped default
        (start: 540, end: 1020), // non-wrapping
        (start: 0, end: 1), // one-minute window at midnight
        (start: 1439, end: 0), // one-minute window at 23:59
      ]) {
        for (var m = 0; m < 1440; m++) {
          final candidate = DateTime(2026, 1, 15, m ~/ 60, m % 60);
          final shifted = applyQuietHours(
            candidate: candidate,
            enabled: true,
            startMinutes: window.start,
            endMinutes: window.end,
          );
          expect(
            shifted != candidate,
            isWithinQuietHours(
              minuteOfDay: m,
              enabled: true,
              startMinutes: window.start,
              endMinutes: window.end,
            ),
            reason:
                'minute $m, window ${window.start}-${window.end}: '
                'applyQuietHours returned $shifted',
          );
        }
      }
    });
  });
```

- [ ] **Step 2: Add a deliberately wrong stub so the red is an assertion, not a compile error**

A Dart test referencing an undefined function fails to compile, and the tests never run — which is not a valid red. Add the stub first, in `lib/domain/reminder_planner.dart`:

```dart
/// Whether [minuteOfDay] falls inside the quiet-hours window
/// `[startMinutes, endMinutes)` (spec `docs/specs/notifications-n2.md` §6).
///
/// The window WRAPS MIDNIGHT in the normal case (22:00 to 07:00), so this is
/// a wrapping-interval test, never a `start <= m <= end` range comparison.
/// `startMinutes == endMinutes` is OFF, not a 24-hour window -- "never
/// notify" is what the toggle is for.
///
/// Exactly at [startMinutes] is inside; exactly at [endMinutes] is outside.
///
/// This is the single membership test in the app: [applyQuietHours]
/// delegates to it, and `SettingsScreen` reads it to decide whether the
/// evening re-reminder's time collides with the window (§5.1). Two
/// implementations could disagree, and a user would then see "not
/// delivering" on a notification that delivers.
///
/// Deliberately takes a minute-of-day rather than a `DateTime`: it
/// constructs no date and therefore has no DST exposure at all. The
/// DST-sensitive half -- building the deferral target from calendar
/// components -- lives in [applyQuietHours] and is untouched by this.
bool isWithinQuietHours({
  required int minuteOfDay,
  required bool enabled,
  required int startMinutes,
  required int endMinutes,
}) {
  return false;
}
```

- [ ] **Step 3: Run and confirm red AT THE TEST STEP**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/domain/reminder_planner_test.dart
```

Expected: the file compiles and the tests RUN. "a window that wraps midnight covers exactly its two arcs" FAILS with `Expected: an object with length of <540> / Actual: [] which has length of <0>`; "a window that does not wrap…" fails the same way; the `start == end` and `disabled` tests PASS (a stub returning false satisfies them — which is precisely why they are not the load-bearing ones); the agreement test FAILS at the first inside minute.

- [ ] **Step 4: Write the real implementation**

Replace the stub's body:

```dart
  if (!enabled || startMinutes == endMinutes) {
    return false;
  }
  if (startMinutes < endMinutes) {
    return minuteOfDay >= startMinutes && minuteOfDay < endMinutes;
  }
  // Wrapping: the window is the union of the two arcs the midnight
  // boundary splits it into.
  return minuteOfDay >= startMinutes || minuteOfDay < endMinutes;
```

- [ ] **Step 5: Make `applyQuietHours` delegate**

In the same file, find the membership test at the top of `applyQuietHours` (slice 2's "return `candidate` unchanged when quiet hours are off or `candidate` falls outside the window") and replace **only that test** with a call:

```dart
  if (!isWithinQuietHours(
    minuteOfDay: candidate.hour * 60 + candidate.minute,
    enabled: enabled,
    startMinutes: startMinutes,
    endMinutes: endMinutes,
  )) {
    return candidate;
  }
```

**Leave the deferral-target construction below it exactly as slice 2 wrote it** — the calendar-component build is that slice's contract and this task must not restate it.

- [ ] **Step 6: Run and confirm green**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/domain/reminder_planner_test.dart
```

Expected: all PASS, including slice 2's own `applyQuietHours` group (its DST tests are the guard that the delegation did not disturb the construction half).

- [ ] **Step 7: Invert the implementation and confirm the tests catch it**

Replace the wrapping branch with a plain range comparison:

```dart
  return minuteOfDay >= startMinutes && minuteOfDay < endMinutes;
```

(i.e. delete the `if (startMinutes < endMinutes)` split.) Run the same command.

Expected: **"a window that wraps midnight covers exactly its two arcs" FAILS with `Expected: an object with length of <540> / Actual: [] which has length of <0>`**, and the agreement test fails at minute 0 of the wrapping window. Restore the split and re-run to green.

- [ ] **Step 8: Format, analyze, commit**

```bash
dart format lib/domain/reminder_planner.dart test/domain/reminder_planner_test.dart
flutter analyze --fatal-infos --fatal-warnings
git add lib/domain/reminder_planner.dart test/domain/reminder_planner_test.dart
git commit -m "feat(domain): isWithinQuietHours, the one wrapping-interval test

N2 slice 5/6, spec docs/specs/notifications-n2.md §6. applyQuietHours now
delegates its membership test here, so the settings UI's collision sub-line
and the scheduler's deferral can never disagree; an exhaustive 1440-minute
agreement test pins that."
```

---

## Task 4: The evening re-reminder toggle — **this is what makes the feature live**

**Files:**
- Create: `lib/features/settings/evening_section.dart`
- Create: `test/features/settings/evening_section_test.dart`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`
- Modify: `lib/features/settings/settings_screen.dart`

**Interfaces:**
- Consumes: `SettingsRow`, `semantic`, `SettingsRepository.setEveningReminderEnabled({required bool enabled})`, `DeviceSettings.eveningReminderEnabled`.
- Produces: `EveningToggleTile({required bool value, required ValueChanged<bool> onChanged, Key? key})`, semantic id `settings.evening.toggle`.

**D12 is the whole point of this task.** The feature ships OFF (§8.1) and its discoverability is paid for by **placement and wording only** — this row goes *directly beneath the digest time row*, above quiet hours, and its label names the user's problem ("Remind me again in the evening"), not our mechanism. **No prompt, no banner, no first-run hint, now or ever** (§5.1, B-5). Nothing in this task or any later one may add one.

- [ ] **Step 1: Write the failing tests**

Create `test/features/settings/evening_section_test.dart`:

```dart
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'settings_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  // Matched by literal English on purpose: `testChoreApp` pumps the app
  // with no locale override, so the template ARB's text is what renders,
  // and a test that read the same `AppLocalizations` getter the widget
  // reads would pass no matter what that getter returned. Both strings are
  // BINDING copy (spec docs/specs/notifications-n2.md §5.1 / §11) -- if
  // this test has to change, the spec has to change first.
  const toggleLabel = 'Remind me again in the evening';
  const toggleSubtitle = 'Only if something is still open today';

  testChoreApp(
    'the evening re-reminder ships OFF (decision D12)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      final toggle = tester.widget<Switch>(
        find
            .descendant(
              of: find.bySemanticsIdentifier('settings.evening.toggle'),
              matching: find.byType(Switch),
            )
            .first,
      );
      expect(toggle.value, isFalse);

      final row = await database.select(database.settings).getSingle();
      expect(row.eveningReminderEnabled, isFalse);
      expect(row.eveningReminderMinutes, 1200);

      handle.dispose();
    },
  );

  testChoreApp(
    'the row is labelled for the problem, not the mechanism, and carries '
    'its condition as a sub-line whether it is on or off',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      final row = find.bySemanticsIdentifier('settings.evening.toggle');
      expect(
        find.descendant(of: row, matching: find.text(toggleLabel)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text(toggleSubtitle)),
        findsOneWidget,
      );
      // The feature's name in the spec must not become the name of the row.
      expect(find.textContaining('re-reminder'), findsNothing);

      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: row, matching: find.text(toggleSubtitle)),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'turning the evening re-reminder on persists it, and off again',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      await tester.tap(find.bySemanticsIdentifier('settings.evening.toggle'));
      await tester.pumpAndSettle();
      var row = await database.select(database.settings).getSingle();
      expect(row.eveningReminderEnabled, isTrue);

      await tester.tap(find.bySemanticsIdentifier('settings.evening.toggle'));
      await tester.pumpAndSettle();
      row = await database.select(database.settings).getSingle();
      expect(row.eveningReminderEnabled, isFalse);

      handle.dispose();
    },
  );

  testChoreApp(
    'the switch reflects a value written outside the widget',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      await SettingsRepository(
        database,
      ).setEveningReminderEnabled(enabled: true);
      await tester.pumpAndSettle();

      final toggle = tester.widget<Switch>(
        find
            .descendant(
              of: find.bySemanticsIdentifier('settings.evening.toggle'),
              matching: find.byType(Switch),
            )
            .first,
      );
      expect(toggle.value, isTrue);

      handle.dispose();
    },
  );
}
```

- [ ] **Step 2: Run and confirm red AT THE TEST STEP**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/settings/evening_section_test.dart
```

Expected: all four FAIL in the body with "Found 0 widgets with semantics identifier settings.evening.toggle" (or `Bad state: No element` from the `tester.widget<Switch>` casts). The file compiles.

- [ ] **Step 3: Add the ARB keys**

`lib/l10n/app_en.arb`, immediately after the `"@settingsQuietHoursTo"` block:

```json
  "settingsEveningToggle": "Remind me again in the evening",
  "@settingsEveningToggle": {
    "description": "BINDING COPY -- spec docs/specs/notifications-n2.md §5.1 and §11 fix this string verbatim; do not reword without amending the spec. Title of the settings switch that turns on a second daily notification in the evening. It ships OFF (decision D12), so this label is the only thing that leads the person it exists for to it -- someone whose notification 'arrives, then it's gone'. It therefore names their problem, never our mechanism: 'Evening re-reminder' is the feature's name in the spec and must not become the name of the row."
  },
  "settingsEveningToggleSubtitle": "Only if something is still open today",
  "@settingsEveningToggleSubtitle": {
    "description": "BINDING COPY -- spec docs/specs/notifications-n2.md §5.1 and §11 fix this string verbatim. Permanent sub-line under settingsEveningToggle, shown whether the switch is on or off, stating the condition in the same register as the label: the evening notification only fires when at least one chore is due TODAY and still open (overdue ones never count, decision D6, which is what makes it impossible to receive two evenings running about the same chore)."
  },
```

`lib/l10n/app_de.arb`, immediately after `"settingsQuietHoursTo": "Bis",`:

```json
  "settingsEveningToggle": "Abends noch mal erinnern",
  "settingsEveningToggleSubtitle": "Nur wenn heute noch etwas offen ist",
```

- [ ] **Step 4: Regenerate localizations**

```bash
flutter gen-l10n
```

- [ ] **Step 5: Write the widget**

Create `lib/features/settings/evening_section.dart`:

```dart
/// The settings screen's evening re-reminder rows, inside the Preferences
/// group directly beneath the digest time row (spec
/// `docs/specs/notifications-n2.md` §5, §5.1 and §12).
///
/// **Ships OFF (decision D12)**, and its discoverability is paid for by
/// PLACEMENT and WORDING and by nothing else: the row sits in the one group
/// that already holds the notification the user knows about, and its label
/// names their problem ("it arrives, then it's gone") rather than our
/// mechanism. B-5 settled that a returning nudge IS the nagging, so there
/// must never be a prompt, a banner or a first-run hint pointing at this
/// row -- if it cannot be found where it is with the label it has, the fix
/// is the label.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/features/settings/settings_group.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The 'Remind me again in the evening' on/off switch row.
class EveningToggleTile extends StatelessWidget {
  /// Creates the toggle row.
  const EveningToggleTile({
    required this.value,
    required this.onChanged,
    super.key,
  });

  /// Whether the evening re-reminder is currently enabled.
  final bool value;

  /// Called when the switch is flipped.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return semantic(
      'settings.evening.toggle',
      child: SettingsRow(
        icon: Icons.notifications_active_outlined,
        label: l10n.settingsEveningToggle,
        // Unconditional, unlike the digest toggle's permission sub-line:
        // this states what the feature DOES, and a user scanning the group
        // for a vanished notification has to be able to read it before
        // deciding to turn the switch on.
        sublabel: l10n.settingsEveningToggleSubtitle,
        switchValue: value,
        onSwitchChanged: onChanged,
      ),
    );
  }
}
```

- [ ] **Step 6: Compose it in — directly beneath the digest time row**

In `settings_screen.dart` add the import:

```dart
import 'package:chore_app/features/settings/evening_section.dart';
```

and insert the row **between** the `if (settings.digestEnabled) DigestTimeTile(...)` entry and the `QuietHoursToggleTile(...)` entry:

```dart
                  EveningToggleTile(
                    value: settings.eveningReminderEnabled,
                    onChanged: (enabled) => settingsRepository
                        .setEveningReminderEnabled(enabled: enabled),
                  ),
```

Not gated on `digestEnabled`: the evening re-reminder is independent of the digest, and §5.1 requires the row to be findable regardless.

- [ ] **Step 7: Run and confirm green**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/settings/evening_section_test.dart test/features/settings/quiet_hours_section_test.dart test/features/settings/digest_section_test.dart
```

Expected: all PASS.

- [ ] **Step 8: Invert the implementation and confirm the tests catch it**

In `settings_screen.dart`, temporarily make the callback a no-op:

```dart
                    onChanged: (enabled) {},
```

Run the same command. Expected: **"turning the evening re-reminder on persists it, and off again" FAILS at `expect(row.eveningReminderEnabled, isTrue)` with `Expected: true / Actual: <false>`.** Restore and re-run to green.

- [ ] **Step 9: Format, analyze, commit**

```bash
dart format lib/features/settings test/features/settings/evening_section_test.dart lib/l10n/
flutter analyze --fatal-infos --fatal-warnings
git add lib/features/settings lib/l10n test/features/settings/evening_section_test.dart
git commit -m "feat(settings): the evening re-reminder toggle

N2 slice 6, spec docs/specs/notifications-n2.md §5.1/§12, decision D12.
This is the commit that makes the evening re-reminder LIVE: it ships OFF and
nothing else in the app can set evening_reminder_enabled, so this row is its
first and only ON path. Placement (directly beneath the digest time, in the
group that already holds the digest) and wording (the user's problem, not
our mechanism) are the whole of its discoverability -- no prompt, no banner,
no first-run hint, per B-5."
```

---

## Task 5: The evening time row and its quiet-hours collision sub-line

**Files:**
- Modify: `lib/features/settings/evening_section.dart`
- Modify: `lib/features/settings/settings_screen.dart`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`
- Modify: `test/features/settings/evening_section_test.dart`

**Interfaces:**
- Consumes: Task 2's `SettingsTimeRow`, Task 3's `isWithinQuietHours`, `SettingsRepository.setEveningReminderTime(int)`, `DeviceSettings.eveningReminderMinutes` / `quietHoursEnabled` / `quietStartMinutes` / `quietEndMinutes`.
- Produces: `EveningTimeTile({required int minutesSinceMidnight, required ValueChanged<int> onChanged, bool insideQuietHours = false, Key? key})`, semantic id `settings.evening.time`.

**This is the task that stops quiet hours silently swallowing the evening re-reminder.** D7 drops (never defers) an evening slot inside the quiet window, so a user with quiet hours from 21:00 and an evening time of 21:30 would otherwise get nothing at all with no indication why. §6 requires a factual sub-line, computed as a pure projection of the two settings — no stored flag, always current, self-clearing the instant either time moves. The `insideQuietHours` bool is computed in `settings_screen.dart` from `isWithinQuietHours` and passed down, mirroring how `DigestToggleTile` takes `permissionDenied`.

**How the sub-line tests discriminate.** "Sub-line appears when the evening time is inside the window" is satisfied by a widget that always shows it, and by one that ignores the wrap. The suite below pins it from four directions at once: quiet hours OFF with a colliding time (proves it reads `enabled`), the *shipped* defaults 20:00 vs 22:00-07:00 (proves it is not always-on — and is the case §5.1 promises works out of the box), 21:30 inside a 21:00-07:00 window (the positive case), **06:00 inside a 22:00-07:00 window (the positive case on the far side of midnight, which a non-wrapping comparison gets wrong)**, and a self-clearing check that moves the quiet start from 21:00 to 22:00 with nothing else changing and requires the sub-line to vanish.

- [ ] **Step 1: Write the failing tests**

Append to `test/features/settings/evening_section_test.dart`, inside `main()` (the `toggleSubtitle` const is already in scope):

```dart
  // BINDING copy, spec docs/specs/notifications-n2.md §6 and §5.1, matched
  // literally for the same reason as the labels above.
  const collisionSubline = 'Inside your quiet hours — not delivering';

  /// Enables the evening re-reminder at [eveningMinutes], and quiet hours
  /// over [start]..[end] when [quietEnabled], then settles.
  Future<void> configure(
    WidgetTester tester,
    AppDatabase database, {
    required int eveningMinutes,
    required bool quietEnabled,
    int start = 1320,
    int end = 420,
  }) async {
    final settings = SettingsRepository(database);
    await settings.setEveningReminderEnabled(enabled: true);
    await settings.setEveningReminderTime(eveningMinutes);
    await settings.setQuietHoursEnabled(enabled: quietEnabled);
    await settings.setQuietHoursStart(start);
    await settings.setQuietHoursEnd(end);
    await tester.pumpAndSettle();
  }

  testChoreApp(
    'the evening time row is hidden while the toggle is off and revealed '
    'when it is turned on',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      expect(find.bySemanticsIdentifier('settings.evening.time'), findsNothing);

      await tester.tap(find.bySemanticsIdentifier('settings.evening.toggle'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('settings.evening.time'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'picking an evening time persists it and re-renders the row',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);
      await SettingsRepository(
        database,
      ).setEveningReminderEnabled(enabled: true);
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsIdentifier('settings.evening.time'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.first, '9');
      await tester.enterText(fields.last, '30');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final row = await database.select(database.settings).getSingle();
      expect(row.eveningReminderMinutes, 9 * 60 + 30);
      // See quiet_hours_section_test.dart: 9:30 is the one time whose 12h
      // and 24h renders share a substring.
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('settings.evening.time'),
          matching: find.textContaining('9:30'),
        ),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'no collision sub-line while quiet hours are off, even at a time that '
    'would be inside the window',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);
      // 23:00, squarely inside 22:00-07:00 -- but quiet hours are off.
      await configure(
        tester,
        database,
        eveningMinutes: 1380,
        quietEnabled: false,
      );

      expect(find.text(collisionSubline), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'no collision sub-line with the shipped defaults (20:00 evening, '
    '22:00-07:00 quiet hours)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);
      await configure(
        tester,
        database,
        eveningMinutes: 1200,
        quietEnabled: true,
      );

      // Spec §5.1: "the shipped defaults do not collide", so a user turning
      // the feature on with defaults gets a working feature and no sub-line.
      expect(find.text(collisionSubline), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'the collision sub-line appears when the evening time falls inside the '
    'window, and self-clears when the window moves off it',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);
      // Spec §5.1's own example: quiet hours from 21:00, evening at 21:30.
      await configure(
        tester,
        database,
        eveningMinutes: 1290,
        quietEnabled: true,
        start: 1260,
      );

      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('settings.evening.time'),
          matching: find.text(collisionSubline),
        ),
        findsOneWidget,
      );

      // Move ONLY the quiet-hours start, to 22:00. The sub-line is a pure
      // projection of the two settings -- no stored flag -- so it must
      // vanish with no other change and nothing to dismiss.
      await SettingsRepository(database).setQuietHoursStart(1320);
      await tester.pumpAndSettle();

      expect(find.text(collisionSubline), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'the collision sub-line appears for an evening time on the far side of '
    'midnight (06:00 inside a 22:00-07:00 window)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);
      // 06:00 is inside the shipped wrapping window even though 360 < 1320.
      // A non-wrapping `start <= m <= end` comparison reports it as
      // outside, and this assertion is what catches that.
      await configure(
        tester,
        database,
        eveningMinutes: 360,
        quietEnabled: true,
      );

      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('settings.evening.time'),
          matching: find.text(collisionSubline),
        ),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'an EMPTY quiet-hours window never reports the evening time as inside '
    'it: the two sub-lines are mutually exclusive by construction',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);
      // start == end == the evening time itself -- the most adversarial
      // arrangement available. §6 makes a zero-length window OFF, so
      // isWithinQuietHours is false for EVERY minute including this one,
      // and the evening row must stay clean.
      await configure(
        tester,
        database,
        eveningMinutes: 1200,
        quietEnabled: true,
        start: 1200,
        end: 1200,
      );

      expect(find.text(collisionSubline), findsNothing);
      // The empty-window line (Task 2, OD2) is what speaks instead, and it
      // speaks on a DIFFERENT row -- so the two can never contend for one
      // `sublabel` slot.
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('settings.quietHours.toggle'),
          matching: find.text('Start and end are the same — no quiet time'),
        ),
        findsOneWidget,
      );

      handle.dispose();
    },
  );
```

- [ ] **Step 2: Run and confirm red AT THE TEST STEP**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/settings/evening_section_test.dart
```

Expected: the two "no collision sub-line" tests PASS trivially (nothing renders the string yet — which is why they are not the load-bearing ones); the reveal test FAILS at `findsOneWidget`; the picker test FAILS at the `tester.tap`; the two positive sub-line tests FAIL at `findsOneWidget` with "Found 0 widgets". The mutual-exclusivity test also PASSES already — both halves of it are true before this task (nothing renders the collision line, and Task 2 shipped the empty-window line); it is a **regression guard on the interaction**, and Step 8's second inversion is what proves it can fail. Task 4's four tests still PASS.

- [ ] **Step 3: Add the ARB keys**

`lib/l10n/app_en.arb`, immediately after the `"@settingsEveningToggleSubtitle"` block:

```json
  "settingsEveningTime": "Evening time",
  "@settingsEveningTime": {
    "description": "Title of the settings row holding the evening re-reminder's fire time, revealed under settingsEveningToggle. Shows the chosen time as trailing text via TimeOfDay.format and opens a time picker on tap. Default 20:00, which sits an hour clear of the 22:00 quiet-hours default so the shipped combination does not collide."
  },
  "settingsEveningInQuietHoursHint": "Inside your quiet hours — not delivering",
  "@settingsEveningInQuietHoursHint": {
    "description": "BINDING COPY -- spec docs/specs/notifications-n2.md §6 and §5.1 fix this string verbatim. Factual sub-line on the evening time row, shown only while the chosen evening time falls inside the quiet-hours window. Unlike the digest and per-chore reminders, an evening re-reminder inside the window is DROPPED rather than deferred (decision D7) -- an 'evening' notification delivered at 07:00 has a false premise and would collide with the 08:00 digest -- so without this line the feature would silently do nothing. A pure projection of the two times: no stored flag, always current, self-clearing the moment either one moves. Same pattern as settingsDigestToggleDeniedHint."
  },
```

`lib/l10n/app_de.arb`, immediately after `"settingsEveningToggleSubtitle": "Nur wenn heute noch etwas offen ist",`:

```json
  "settingsEveningTime": "Abends um",
  "settingsEveningInQuietHoursHint": "Liegt in deinen Ruhezeiten — wird nicht zugestellt",
```

- [ ] **Step 4: Regenerate localizations**

```bash
flutter gen-l10n
```

- [ ] **Step 5: Write the widget**

Append to `lib/features/settings/evening_section.dart` (add `import 'package:chore_app/features/settings/settings_time_row.dart';`):

```dart
/// The evening re-reminder's fire-time row, revealed while
/// [EveningToggleTile] is on.
class EveningTimeTile extends StatelessWidget {
  /// Creates the time row.
  const EveningTimeTile({
    required this.minutesSinceMidnight,
    required this.onChanged,
    this.insideQuietHours = false,
    super.key,
  });

  /// The currently-chosen evening time, as minutes since local midnight.
  final int minutesSinceMidnight;

  /// Called with the newly-picked time, also as minutes since midnight.
  final ValueChanged<int> onChanged;

  /// Whether [minutesSinceMidnight] falls inside the user's quiet-hours
  /// window (spec `docs/specs/notifications-n2.md` §6).
  ///
  /// When true this grows a factual sub-line, because an evening
  /// re-reminder inside the window is DROPPED rather than deferred
  /// (decision D7): deferring it to 07:00 would deliver a notification
  /// whose entire premise -- "these are still open and there is still time
  /// today" -- is false by then, minutes before the digest says the same
  /// thing correctly. Without the sub-line the feature would silently do
  /// nothing.
  ///
  /// Computed by the caller as a pure projection of the two settings (see
  /// `isWithinQuietHours`), never stored: it is always current, it
  /// self-clears the instant either time moves, and there is nothing to
  /// dismiss. Same pattern as `DigestToggleTile.permissionDenied`.
  final bool insideQuietHours;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SettingsTimeRow(
      semanticId: 'settings.evening.time',
      icon: Icons.schedule_outlined,
      label: l10n.settingsEveningTime,
      sublabel: insideQuietHours
          ? l10n.settingsEveningInQuietHoursHint
          : null,
      minutesSinceMidnight: minutesSinceMidnight,
      onChanged: onChanged,
    );
  }
}
```

- [ ] **Step 6: Compose it in and wire the predicate**

In `settings_screen.dart` add the import:

```dart
import 'package:chore_app/domain/reminder_planner.dart';
```

and insert the row directly after the `EveningToggleTile(...)` entry from Task 4:

```dart
                  if (settings.eveningReminderEnabled)
                    EveningTimeTile(
                      minutesSinceMidnight: settings.eveningReminderMinutes,
                      insideQuietHours: isWithinQuietHours(
                        minuteOfDay: settings.eveningReminderMinutes,
                        enabled: settings.quietHoursEnabled,
                        startMinutes: settings.quietStartMinutes,
                        endMinutes: settings.quietEndMinutes,
                      ),
                      onChanged: settingsRepository.setEveningReminderTime,
                    ),
```

- [ ] **Step 7: Run and confirm green**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/settings/evening_section_test.dart test/features/settings/quiet_hours_section_test.dart test/features/settings/digest_section_test.dart test/domain/reminder_planner_test.dart
```

Expected: all PASS.

- [ ] **Step 8: Invert the implementation and confirm the tests catch it**

Two inversions, run the command after each:

1. In `settings_screen.dart`, replace the whole `insideQuietHours:` argument with `insideQuietHours: false`.
   Expected: **both positive sub-line tests FAIL at `findsOneWidget` with "Found 0 widgets"**, while the three negative ones still pass. Restore.
2. Replace it with `insideQuietHours: true`.
   Expected: **"no collision sub-line while quiet hours are off…", "no collision sub-line with the shipped defaults…", the self-clearing half of the positive test, AND the mutual-exclusivity test all FAIL at `findsNothing` with "Found 1 widget"**. This is the assertion that an always-on sub-line cannot survive, and the exclusivity test failing here is what shows it is a live guard rather than a comment. Restore and re-run to green.

A third inversion, specific to the exclusivity property — run it only if you want the interaction pinned rather than assumed. In `reminder_planner.dart`, temporarily drop `|| startMinutes == endMinutes` from `isWithinQuietHours`'s first guard, so a zero-length wrapping window falls through to `m >= start || m < end` and reports **every** minute as inside.
   Expected: **the mutual-exclusivity test FAILS at `expect(find.text(collisionSubline), findsNothing)`** — both sub-lines now claim the window at once, which is precisely the state OD2's collision map says cannot occur. Restore, and confirm Task 3's `start == end` group goes red too while the guard is missing.

- [ ] **Step 9: Format, analyze, commit**

```bash
dart format lib/features/settings lib/l10n/ test/features/settings/evening_section_test.dart
flutter analyze --fatal-infos --fatal-warnings
git add lib/features/settings lib/l10n test/features/settings/evening_section_test.dart
git commit -m "feat(settings): evening time row and its quiet-hours collision sub-line

N2 slice 6, spec docs/specs/notifications-n2.md §5.1/§6, decision D7. Quiet
hours DROP an evening re-reminder rather than defer it, so a colliding pair
of times would silently deliver nothing; the row states it factually as a
pure projection of the two settings. Tested from both sides, including
06:00 inside a 22:00-07:00 window, so a non-wrapping comparison cannot pass."
```

---

## Task 6: The §12 row-order guard, and the permission hint the evening toggle needs (OD1-A)

**Files:**
- Create: `test/features/settings/settings_row_order_test.dart`
- Modify: `lib/features/settings/settings_screen.dart`

**Interfaces:**
- Consumes: every row from Tasks 1, 2, 4, 5, plus the shipped `DigestToggleTile` / `DigestTimeTile` / `DigestPermissionHint`.
- Produces: nothing new. This task pins an arrangement.

**Why the order is a test and not a comment.** §12 makes the row order binding "because it is the whole of the evening re-reminder's discoverability and a later tidy-up must not undo it". A comment does not survive a tidy-up; a geometric assertion over the eight semantic ids does. This test is created here rather than in slice 5 because only now do all eight ids exist at once — creating a six-id version in Task 1 and editing it twice would be churn with a window in which the guard is wrong.

- [ ] **Step 1: Write the failing tests**

Create `test/features/settings/settings_row_order_test.dart`:

```dart
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'settings_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'the notification rows render in the order spec §12 binds, in ONE '
    'group, with the permission hint last (decision D12: this order is the '
    'whole of the evening re-reminder discoverability and a later tidy-up '
    'must not undo it)',
    today: today,
    overrides: [
      notificationPermissionGrantedProvider.overrideWith((ref) => false),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      // Turn both features on so all eight rows exist simultaneously.
      final settings = SettingsRepository(database);
      await settings.setEveningReminderEnabled(enabled: true);
      await settings.setQuietHoursEnabled(enabled: true);
      // A surface tall enough that the whole Preferences group is laid out
      // at once: `getTopLeft` needs a render box, and a ListView does not
      // lay out children that are far off-screen. `testChoreApp` already
      // registered `tester.view.resetPhysicalSize` as a tear-down.
      tester.view.physicalSize = const Size(800, 4000);
      await tester.pumpAndSettle();

      const ids = [
        'settings.digest.toggle',
        'settings.digest.time',
        'settings.evening.toggle',
        'settings.evening.time',
        'settings.quietHours.toggle',
        'settings.quietHours.start',
        'settings.quietHours.end',
        'settings.digest.permission',
      ];

      final tops = <String, double>{};
      for (final id in ids) {
        final finder = find.bySemanticsIdentifier(id);
        expect(finder, findsOneWidget, reason: '$id must be on screen');
        tops[id] = tester.getTopLeft(finder.first).dy;
      }

      for (var i = 1; i < ids.length; i++) {
        expect(
          tops[ids[i]],
          greaterThan(tops[ids[i - 1]]!),
          reason: '${ids[i]} must render below ${ids[i - 1]}',
        );
      }

      // One group, not two: §12 forbids a second section header, and the
      // orphan "Daily summary" string must not come back as one.
      expect(find.text('Daily summary'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'the permission hint is shown when the digest is OFF but the evening '
    're-reminder is ON and the OS permission is denied',
    today: today,
    overrides: [
      notificationPermissionGrantedProvider.overrideWith((ref) => false),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      final settings = SettingsRepository(database);
      await settings.setDigestEnabled(enabled: false);
      await settings.setEveningReminderEnabled(enabled: true);
      await tester.pumpAndSettle();

      // Without this, a user whose only notification is the evening
      // re-reminder sees a switch in its ON position while nothing is
      // delivered -- the exact lie B-5 built this row to remove.
      expect(
        find.bySemanticsIdentifier('settings.digest.permission'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'the permission hint stays hidden when both notifications are off, even '
    'with the permission denied',
    today: today,
    overrides: [
      notificationPermissionGrantedProvider.overrideWith((ref) => false),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      // Guard against the assertion below passing for the wrong reason: the
      // hint has to be there BEFORE the digest is turned off.
      expect(
        find.bySemanticsIdentifier('settings.digest.permission'),
        findsOneWidget,
      );

      await SettingsRepository(database).setDigestEnabled(enabled: false);
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('settings.digest.permission'),
        findsNothing,
      );

      handle.dispose();
    },
  );
}
```

- [ ] **Step 2: Run and confirm red AT THE TEST STEP**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/settings/settings_row_order_test.dart
```

Expected: the order test PASSES already (Tasks 1-5 composed the rows in this order — it is a guard, and it must be seen passing before it is trusted; Step 4's inversion is what proves it can fail). "the permission hint is shown when the digest is OFF but the evening re-reminder is ON…" FAILS at `findsOneWidget` with "Found 0 widgets", because `settings_screen.dart:125` still gates the hint on `digestEnabled` alone. The third test PASSES.

- [ ] **Step 3: Widen the permission hint's condition (OD1-A)**

In `settings_screen.dart`, replace:

```dart
                  if (settings.digestEnabled && !permissionGranted)
                    const DigestPermissionHint(onOpenSettings: openAppSettings),
```

with:

```dart
                  // Widened from `digestEnabled` alone: slice 6 creates a
                  // state that never existed before -- a notification that
                  // can be ON while the digest is OFF -- and without this
                  // the group carries no permission signal at all for a
                  // user whose only notification is the evening
                  // re-reminder. The hint's copy is already
                  // feature-neutral. It stays LAST, per spec §12.
                  if ((settings.digestEnabled ||
                          settings.eveningReminderEnabled) &&
                      !permissionGranted)
                    const DigestPermissionHint(onOpenSettings: openAppSettings),
```

- [ ] **Step 4: Run and confirm green, then invert both halves**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/features/settings/settings_row_order_test.dart test/features/settings/digest_section_test.dart
```

Expected: all PASS (`digest_section_test.dart` is the guard that widening the condition did not disturb the digest-only cases).

Then two inversions, running the command after each:

1. In `settings_screen.dart`, move the `EveningToggleTile` / `EveningTimeTile` pair to *below* the quiet-hours rows.
   Expected: **the order test FAILS at `expect(tops['settings.evening.toggle'], greaterThan(tops['settings.digest.time']))` — reason "settings.evening.toggle must render below settings.digest.time"**. Restore.
2. Revert the hint condition to `settings.digestEnabled && !permissionGranted`.
   Expected: **"the permission hint is shown when the digest is OFF but the evening re-reminder is ON…" FAILS at `findsOneWidget` with "Found 0 widgets"**. Restore and re-run to green.

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format lib/features/settings/settings_screen.dart test/features/settings/settings_row_order_test.dart
flutter analyze --fatal-infos --fatal-warnings
git add lib/features/settings/settings_screen.dart test/features/settings/settings_row_order_test.dart
git commit -m "test(settings): pin the spec §12 row order; widen the permission hint

N2 slices 5/6. The row order is the whole of the evening re-reminder's
discoverability (decision D12), so it is a geometric assertion over the
eight semantic ids rather than a comment a tidy-up can ignore. The hint's
condition widens to cover an evening re-reminder that is on while the digest
is off -- a state that could not exist before this wave (open decision OD1,
option A)."
```

---

## Task 7: Prove the evening half is live end to end

**Files:**
- Modify: `test/app/digest_reschedule_test.dart` (append one group at the end of `main()`)

**Interfaces:**
- Consumes: `eveningNotificationIdBase` and `eveningHorizonSlots` from `lib/domain/reminder_planner.dart` (slice 2, §3.1); `FakeDigestNotificationPlugin.scheduledCalls`; that file's own `_awaitBootstrap` and `_disposeAndClose` helpers; `DigestRescheduleController` via `digestRescheduleControllerProvider`.
- Produces: nothing. This is the proof that Task 4's toggle actually reaches the scheduler.

**What this catches that Task 4's widget tests cannot.** Task 4 proves the switch writes the column. It says nothing about whether anything downstream reads it. This group drives the real `DigestRescheduleController` against a real database and a faked plugin, and asserts on the **evening id range** (`3001..3007`) — so it fails if `buildNotificationPlans` ignores `evening_reminder_enabled` in either direction. The OFF case is the discriminating one: an implementation that schedules the evening horizon unconditionally passes the ON case and fails here.

Append at the end of `main()` in `test/app/digest_reschedule_test.dart` (add `import 'package:chore_app/domain/reminder_planner.dart';` to that file's imports if slice 3 has not already added it):

- [ ] **Step 1: Write the failing tests**

```dart
  group('the evening re-reminder (spec notifications-n2.md §5, decision D12)', () {
    /// The ids reserved for the evening horizon (spec §3.1).
    bool isEveningId(int id) =>
        id >= eveningNotificationIdBase &&
        id < eveningNotificationIdBase + eveningHorizonSlots;

    testWidgets(
      'ships OFF: a chore due today schedules nothing in the evening id '
      'range',
      (tester) async {
        final database = AppDatabase(NativeDatabase.memory());
        final plugin = FakeDigestNotificationPlugin();
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            // 07:00, so the default 20:00 evening slot is still ahead of
            // "now" today and would be armed if the feature were on.
            clockProvider.overrideWithValue(
              Clock.fixed(DateTime(2026, 7, 24, 7)),
            ),
            digestNotificationPluginProvider.overrideWithValue(plugin),
          ],
        );
        await container
            .read(householdRepositoryProvider)
            .createLocalHousehold('Me');

        container.read(digestRescheduleControllerProvider);
        final householdId = await _awaitBootstrap(tester, container);
        await tester.pump(digestRescheduleDebounce);

        await container
            .read(choreServiceProvider)
            .createChore(
              householdId: householdId,
              title: 'Water the plants',
              startDate: PlainDate.fromDateTime(
                container.read(clockProvider).now(),
              ),
              assignmentMode: AssignmentMode.anyone,
            );
        await tester.pump(digestRescheduleDebounce);

        // The digest fired (there IS something to say), so this is not a
        // vacuously-empty recompute -- which is what makes the evening
        // assertion below mean something.
        expect(plugin.scheduledCalls, isNotEmpty);
        expect(
          plugin.scheduledCalls.where((call) => isEveningId(call.id)),
          isEmpty,
        );

        await _disposeAndClose(tester, container, database);
      },
    );

    testWidgets(
      'turned on, a chore due today arms at least one evening slot',
      (tester) async {
        final database = AppDatabase(NativeDatabase.memory());
        final plugin = FakeDigestNotificationPlugin();
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            clockProvider.overrideWithValue(
              Clock.fixed(DateTime(2026, 7, 24, 7)),
            ),
            digestNotificationPluginProvider.overrideWithValue(plugin),
          ],
        );
        await container
            .read(householdRepositoryProvider)
            .createLocalHousehold('Me');

        container.read(digestRescheduleControllerProvider);
        final householdId = await _awaitBootstrap(tester, container);
        await tester.pump(digestRescheduleDebounce);

        await container
            .read(choreServiceProvider)
            .createChore(
              householdId: householdId,
              title: 'Water the plants',
              startDate: PlainDate.fromDateTime(
                container.read(clockProvider).now(),
              ),
              assignmentMode: AssignmentMode.anyone,
            );
        await tester.pump(digestRescheduleDebounce);
        plugin.scheduledCalls.clear();

        await container
            .read(settingsRepositoryProvider)
            .setEveningReminderEnabled(enabled: true);
        await tester.pump(digestRescheduleDebounce);

        expect(
          plugin.scheduledCalls.where((call) => isEveningId(call.id)),
          isNotEmpty,
        );

        await _disposeAndClose(tester, container, database);
      },
    );
  });
```

- [ ] **Step 2: Run and confirm the state of play**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/app/digest_reschedule_test.dart
```

Expected: **both PASS** if slices 2 and 3 landed the `evening_reminder_enabled` gate as F3 assumes. This is a verification task, so green on the first run is the intended outcome — Step 3's inversion is what turns it from an assumption into a proof.

**If "turned on, a chore due today arms at least one evening slot" fails**, the gate or the evening plans are missing from `buildNotificationPlans` / `applyPlans`. **Do not patch the UI. Report it as a slice-2 or slice-3 defect** and stop: nothing in slices 5-6 can compensate for a plan set that has no evening entries.

- [ ] **Step 3: Invert the implementation and confirm the test catches it**

The subject here is slice 2's gate, so the inversion is there. In `lib/application/digest_plan_builder.dart`, find where `buildNotificationPlans` consults `settings.eveningReminderEnabled` and temporarily force it true (e.g. pass a literal `true` in place of the field).

Expected: **"ships OFF: a chore due today schedules nothing in the evening id range" FAILS at `expect(..., isEmpty)` with an actual list containing a `ScheduledCall(id: 3001, ...)`.** Restore the field and re-run to green.

- [ ] **Step 4: Run the whole suite**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY=
```

Expected: PASS. This is also the pre-commit hook's own job (`lefthook.yml`), so a green run here means the commit will be accepted.

- [ ] **Step 5: Confirm gen-l10n is a zero diff**

```bash
flutter gen-l10n && git status --porcelain lib/l10n
```

Expected: empty output — the committed generated files match the ARBs exactly, per the wave-5 and wave-6 handover convention.

- [ ] **Step 6: Format, analyze, commit**

```bash
dart format test/app/digest_reschedule_test.dart
flutter analyze --fatal-infos --fatal-warnings
git add test/app/digest_reschedule_test.dart
git commit -m "test(app): prove the evening re-reminder reaches the scheduler

N2 slice 6. Task 4's toggle writes the column; this drives the real
DigestRescheduleController and asserts on the 3001-3007 id range, so it
fails if buildNotificationPlans ignores evening_reminder_enabled in either
direction. The OFF case is the discriminating one."
```

---

## Task 8: Correct §12 and §11 of the spec

**Files:**
- Modify: `docs/specs/notifications-n2.md` §11 (two passages) and §12 (two passages)

**Interfaces:** none. This task changes prose only. No code, no test, no l10n.

**Why this is a task and not a footnote.** `notifications-n2.md` is a binding contract written today, and two of its statements about shipped code are false (F1, F1b). A binding contract asserting a section that is not there will mislead its next reader exactly as it nearly misled this plan — and the specific failure it invites is the expensive one: someone creating a "Daily summary" section *to satisfy the spec*, moving the shipped digest rows, and destroying the discoverability landmark D12 is paying for. The correction has to say that out loud, not just fix the name.

**There is no TDD cycle here** — prose has no red. The verification steps are greps that must return nothing, which is the closest honest equivalent: they fail while the wrong text is present and pass once it is gone.

**Scope discipline:** correct only what was verified false, plus the §16.1 note in Step 5b. Do not restate decisions, do not renumber, do not touch §5.1 (whose "same Settings group as the digest toggle and digest time" is correct as written and needs no change), and do not touch the row list itself — the ordering survives contact and Task 6 pins it.

- [ ] **Step 1: Confirm the wrong text is still there**

```bash
cd /Users/igorzamyslov/Projects/chore-app
grep -n 'Daily summary" section\|digestDoneActionLabel\|existing digest section' docs/specs/notifications-n2.md
```

Expected: three hits — line ~801 (`group — the existing "Daily summary" section —`), ~763 (`digestDoneActionLabel`), ~786 (`existing digest section`). If any is absent, someone has already corrected it; re-read before editing.

- [ ] **Step 2: Fix §12's group name**

Replace:

```
**The Settings row order is binding** (D12, §5.1), because it is the whole of the
evening re-reminder's discoverability and a later tidy-up must not undo it. One
group — the existing "Daily summary" section — in exactly this order:
```

with:

```
**The Settings row order is binding** (D12, §5.1), because it is the whole of the
evening re-reminder's discoverability and a later tidy-up must not undo it. One
group — the existing **Preferences** group (`settingsPreferencesSectionTitle`),
which is where `settings_screen.dart` actually renders the digest rows — in
exactly this order:
```

- [ ] **Step 3: Fix §12's header sentence, and forbid the repair it invites**

Replace:

```
No new section header, no "Advanced" area, no second screen. Someone whose
notification "arrives, then is gone" opens the one group that holds the
notification they already know about and finds the answer two rows down. The
section header's own copy (`settingsDigestSectionTitle`) may be widened from
"Daily summary" to cover all three features, but the rows must not be split.
```

with:

```
No new section header, no "Advanced" area, no second screen. Someone whose
notification "arrives, then is gone" opens the one group that holds the
notification they already know about and finds the answer two rows down.

**Correction, 2026-08-30 (planning of slices 5-6).** This section previously
said the digest rows lived in a "Daily summary" section whose header copy
(`settingsDigestSectionTitle`) could be widened. **Neither is true, and the
error is load-bearing enough to record rather than silently fix.** theme-v2
merged the digest rows into the **Preferences** group, and
`settingsDigestSectionTitle` ("Daily summary") is an **orphan key**: it exists
in both ARBs and in all three generated `app_localizations*.dart`, and is
referenced by no widget (`grep -rn settingsDigestSectionTitle lib test e2e`
returns only `lib/l10n/`). There is therefore no header naming the digest rows
and nothing to widen.

**Do not create a section to satisfy this spec.** Promoting a notifications
section and moving the shipped digest rows into it would make the text above
literally true at the cost of the thing it exists to protect: §5.1's
discoverability argument is anchored to "the one group that already holds the
notification they know about", and since theme-v2 that group has been
Preferences. Moving the landmark in the same release that asks users to find a
new row beside it inverts D12. The rows must not be split, and they must not be
relocated either. `settingsDigestSectionTitle` may be deleted as dead code at
some future tidy-up; it must not be revived to found a section.
```

- [ ] **Step 4: Fix §11's group name**

Replace:

```
There is deliberately **no `settingsRemindersSectionTitle`**: the evening and
quiet-hours rows join the existing digest section rather than founding a second
one (§5.1, §12).
```

with:

```
There is deliberately **no `settingsRemindersSectionTitle`**: the evening and
quiet-hours rows join the existing **Preferences** group, where the digest rows
already live, rather than founding a second one (§5.1, §12 — and see §12's
2026-08-30 correction: there is no "Daily summary" section, and none must be
created).
```

- [ ] **Step 5: Fix §11's Done-action key name**

Replace:

```
- `reminderSnoozeActionLabel` — "Tomorrow" / "Morgen". It names the outcome
  rather than the mechanism, which is what a two-word notification button should
  do. The existing `digestDoneActionLabel` is **reused** for all three Done
  actions rather than duplicated per surface; amend its `@`-description to say
  so.
```

with:

```
- `reminderSnoozeActionLabel` — "Tomorrow" / "Morgen". It names the outcome
  rather than the mechanism, which is what a two-word notification button should
  do. The existing **`notificationActionDone`** ("Done", `app_en.arb`) is
  **reused** for all three Done actions rather than duplicated per surface;
  amend its `@`-description to say so. (Corrected 2026-08-30: this section
  previously named the key `digestDoneActionLabel`, which does not exist. The
  shipped key is `notificationActionDone`, threaded to the platform as
  `NotificationScheduler.initialize({required String doneActionTitle})`. The
  intent — one key, three surfaces — is unchanged.)
```

- [ ] **Step 5b: Record the pattern, for the next spec author**

Both corrections share a shape worth naming, and naming it is the part that pays forward. Append to §16, after the OQ2 block that closes it:

```
### 16.1 A note on this spec's own error class (added 2026-08-30)

Planning slices 5 and 6 verified every claim this document makes about
shipped code, and found two false: §12's "existing 'Daily summary' section"
(there is none; the digest rows are in **Preferences**, and
`settingsDigestSectionTitle` is an orphan key) and §11's
`digestDoneActionLabel` (the shipped key is `notificationActionDone`). Both
are corrected in place above.

**What is worth recording is the pattern, because it has now recurred in
every planning round of this project: the claims about INTENT held, and the
claims about SHIPPED CODE did not.** Every decision in §1, every rule in
§2-§7, the partition in §0.1, the id budget in §3 and all the binding copy
survived contact with the tree unchanged. What did not survive was the
incidental scaffolding — a section name, a key name — written from memory
of the codebase rather than from a grep, in passages whose actual subject
was something else entirely.

That asymmetry is not an accident, and it is not a reason to trust specs
less. It is a reason to treat a spec's *design* as authoritative and its
*citations* as hypotheses: cheap to check, and the check is a grep. The next
author of a spec in this repo should assume the same about their own draft,
and the next planner should verify before building on one -- which is how
both of these were caught before they reached code, rather than after.
```

- [ ] **Step 6: Verify the corrections took**

```bash
cd /Users/igorzamyslov/Projects/chore-app
grep -n 'digestDoneActionLabel\|existing digest section' docs/specs/notifications-n2.md
grep -c '16.1 A note on this spec' docs/specs/notifications-n2.md
```

Expected: no output from the first grep; `1` from the second.

```bash
grep -n 'Daily summary' docs/specs/notifications-n2.md
```

Expected: exactly two hits, both inside the Step 3 correction block describing the orphan key — and **none** in the form `the existing "Daily summary" section`.

```bash
grep -n 'Preferences' docs/specs/notifications-n2.md
```

Expected: three hits — §12's row-order sentence, §12's correction block, §11's sentence.

- [ ] **Step 7: Confirm nothing else moved**

```bash
git diff --stat docs/specs/notifications-n2.md
```

Expected: `docs/specs/notifications-n2.md` only, and no other file. The diff must not touch §5.1, the numbered row list in §12, or any decision in the §1 table.

- [ ] **Step 8: Commit**

```bash
git add docs/specs/notifications-n2.md
git commit -m "docs(spec): correct two N2 claims about shipped code

§12 asserted an existing 'Daily summary' settings section. There is none --
theme-v2 merged the digest rows into the Preferences group, and
settingsDigestSectionTitle is an orphan key no widget references. §11 named
the Done action's l10n key digestDoneActionLabel; the shipped key is
notificationActionDone.

Both intents survive untouched; only the claims about the code were wrong.
The §12 correction also forbids the repair it invites -- creating the section
to satisfy the spec would move the digest rows, which is the landmark §5.1's
discoverability argument is anchored to, inverting D12."
```

---

## Self-review

**Spec coverage.** §5.1 placement and wording → Tasks 4, 6. §5.1 no prompt/banner/first-run hint → nothing in this plan adds one; stated in Task 4's library doc and commit. §6 three settings, wrapping window, `start == end` OFF → Tasks 1, 2, 3. §6 evening collision sub-line → Task 5. §11 keys `settingsQuietHoursToggle` / `From` / `To` / `settingsEveningTime` / `settingsEveningInQuietHoursHint` / `settingsEveningToggle` / `settingsEveningToggleSubtitle` → Tasks 1, 2, 4, 5, all with `@`-descriptions and DE — plus one key §11 does not list, `settingsQuietHoursEmptyWindowHint`, added by OD2 and flagged as plan-authored in the binding-vs-authored table. §11 "no `settingsRemindersSectionTitle`" → no section header is added anywhere. §12 semantic ids `settings.evening.toggle` / `.time`, `settings.quietHours.toggle` / `.start` / `.end` → Tasks 1, 2, 4, 5. §12 row order → Task 6. §13.1 wrapping / non-wrapping / `start == end` / boundaries → Task 3. §13.2 "settings section states (quiet hours off / on / evening-inside-quiet-hours sub-line …)" → Tasks 1, 2, 5. D12 default OFF → Task 4. D7's no-silent-swallow → Task 5, enforced by tests rather than a comment, as the ticket requires.

§6's `start == end` honesty gap → **Task 2, Steps 12–19** (OD2, resolved). §12's structural claims about shipped code → **verified, and two found false** (F1, F1b); corrected in Task 8, with the true ones recorded in F1c so nobody re-checks them, and the recurring error class written into a new §16.1 for the next spec author.

**Both product decisions are resolved**, so no task is conditional: OD1's widening is Task 6, OD2's sub-line is Task 2's second cycle. Nothing in this plan says "if the owner picks…".

**Deliberately not covered, with reasons given above:** the ceiling sub-line (§3.2 — slice 4's), the chore-form reminder rows (§2.1 — slice 4's), the notification bodies and channels (§11's `eveningReminderBody`, `notificationChannelEveningName` — rendered by the scheduler, slice 3's), a Maestro flow (F5), OD2's option B, the `chore_form.*` id-convention wrinkle (F1c — slice 4's).

**Type consistency.** `SettingsTimeRow` is constructed with `semanticId` / `icon` / `label` / `sublabel` / `minutesSinceMidnight` / `onChanged` in Tasks 2 (×3 call sites) and 5 (×1) — all match its declaration. `isWithinQuietHours`'s four named parameters match between its declaration (Task 3), its use inside `applyQuietHours` (Task 3) and its use in `settings_screen.dart` (Task 5). The five `SettingsRepository` setters and five `DeviceSettings` fields are used with identical spelling in Tasks 1, 2, 4, 5, 6 and 7 — and F2 flags them as the one place slice 1 could disagree.

`QuietHoursToggleTile` is declared without `emptyWindow` in Task 1 and **widened** to `({required bool value, required ValueChanged<bool> onChanged, bool emptyWindow = false, Key? key})` in Task 2 Step 16. The default makes that widening source-compatible, and `settings_screen.dart` is its only call site, updated in the same step.

**`SettingsRow`'s assertion** ("at most one trailing element") holds for every new row: the two toggles pass `switchValue` + `onSwitchChanged` + `sublabel` and no `value`; the three time rows pass `value` (+ `sublabel` for the evening one) and no switch or chevron. `sublabel` is not counted by the assertion — verified against the `assert` in `settings_group.dart`, which sums only `value`, `onSwitchChanged` and `showChevron`.

**Sub-line uniqueness per row** (OD2's collision map): `settings.digest.toggle` carries the denied hint (and slice 4's ceiling hint); `settings.evening.toggle` carries its unconditional subtitle; `settings.evening.time` carries the quiet-hours collision line; `settings.quietHours.toggle` carries the empty-window line. Four rows, four sub-lines, no row with two — so no severity ordering is needed anywhere in this plan, and Task 5's mutual-exclusivity test pins the one pairing that could otherwise look contentious.
