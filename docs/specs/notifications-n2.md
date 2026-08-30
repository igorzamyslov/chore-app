# Spec: Notifications N2 — finer-grained reminders

*Binding contract. Extends `docs/specs/notifications.md` (N1 + the F-1 digest
action), which stays in force: everything it says about the digest's horizon,
its silence rule, its channel, its locale resolution and its serialized write
queue is unchanged by this document except where a numbered decision below
says otherwise, in which case that decision is the amendment.*

*Design source: `DESIGN.md` §3, which already specifies this feature's intent —
digest by default, never nag; per-user settings; a per-chore override; quiet
hours; an evening re-reminder; a chosen overdue behaviour; Done and Snooze
actions. N2 is mostly the act of making those words precise enough to build.*

## 0. What this spec is about

v0.8.0 ships a daily digest that arrives and says the right thing. Asked what
actually goes wrong with it after living with it, the product owner named
exactly two failures, and they are this spec's acceptance criteria:

- **AC1 — "Too coarse: one daily lump."** "3 chores today" is not actionable.
  Chores that matter must remind individually, at their own time — bins out on
  Tuesday evening, not buried in an 08:00 summary.
- **AC2 — "It arrives, then it's gone."** Seen, dismissed while busy, never
  comes back. There must be a snooze that means something, an evening
  re-reminder while chores are still open, and quiet hours so nothing fires at
  a useless time.

Both are settled requirements, not options. Two failures were explicitly **not**
named and are therefore out of scope as problems: *it doesn't arrive* and *it
says the wrong thing*. Delivery is reliable and the copy is correct. **Do not
respec the digest**, and do not reach for N3 server push — reliability is not
what is broken here.

### 0.1 The one invariant everything else rests on

Two notification channels now describe the same chores, so the way they can
fail is by disagreeing. This spec's whole structure exists to make one property
true and testable:

> **The partition.** For every calendar date `D` in the digest horizon and every
> in-scope pending occurrence `X`: **either** `X` is counted by the digest slot
> that fires on `D`, **or** an individual reminder for `X` is armed to fire on
> `D`. Never both. Never neither.

"Never both" is AC1's failure mode inverted — being told twice on one day is
precisely the annoyance a per-chore reminder is supposed to cure. "Never
neither" is what keeps the digest's existing coverage argument intact once
chores start being removed from its counts. §2.4 states the rule that produces
it, §3.2 shows why it survives the id ceiling, and §13 makes it a required test.

The one honest cost is recorded in §2.5: the digest's *silence* is no longer
monotone along the horizon, and `test/domain/digest_projection_test.dart`'s
monotonicity group must be re-scoped accordingly.

## 1. Decisions (taken 2026-08-30)

| # | Decision | Because |
|---|---|---|
| **D1** | A per-chore reminder is **one nullable column on `chores`**: `reminder_minutes` (minutes since local midnight). `NULL` = no individual reminder. | The opt-in and the time are one fact, so they cannot disagree the way a boolean beside a time can. `DESIGN.md` §1 already lists "reminder overrides" as a field of the chore definition, so it is household data and it syncs (§8.2). |
| **D2** | **Rule D**: a digest slot omits an occurrence from its counts **iff** an individual reminder for that occurrence is armed to fire on that slot's own calendar date. | AC1. Being announced twice in one day is the failure being fixed. Keyed on the *armed* date, not the due date, so a quiet-hours deferral (§6) cannot desynchronise the two channels. |
| **D3** | **One armed reminder per chore**, at its next projected due date, only if that moment is within `reminderArmWindowDays` (14) and still in the future. | The digest is the long-range instrument (83 days); individual reminders are the same-fortnight instrument. Arming several occurrences per chore multiplies the id cost for coverage the digest already provides. |
| **D4** | At the id ceiling, reminders are ordered by **fire moment ascending, tie-broken by chore id**, and the first `reminderCeiling` win. The losers are **not silent**: Rule D never omits an unarmed occurrence, so they stay in the digest exactly as they are today. | §3.2. The ceiling degrades one chore at a time from "individually reminded" back to "in the summary" — a loss of cadence, never of coverage. It is the same trade the digest's weekly tail already made. |
| **D5** | **Snooze does not move the chore.** It writes a device-local row and re-arms one notification. It never touches `chore_occurrences.due_date`, never calls `skipOccurrence`, never advances rotation, never changes overdue-ness, never touches stats. | §4. This dissolves the question F-1 deferred rather than answering it: there is no "does a 3-days-overdue chore become due tomorrow" case, because nothing about the occurrence moves. The user said "not now", not "it isn't due". |
| **D6** | The **evening re-reminder counts only occurrences due *today*** — never overdue ones. | §5. An overdue backlog would otherwise generate an unconditional nightly notification with no exit except doing chores, which is the nag `DESIGN.md` forbids. The rule self-limits: the same chore cannot produce it two evenings running. |
| **D7** | **Quiet hours defer, never drop** — for the digest and for individual reminders. **The evening re-reminder is the exception: it is dropped, not deferred.** | §6. Deferring turns a useless 23:30 ping into a useful 07:00 one. But an "evening" re-reminder delivered at 07:00 has a false premise ("there is still time today") and would collide with the 08:00 digest. |
| **D8** | **Overdue behaviour is "silent"**, of `DESIGN.md` §3's three options, and it is **not a setting**. Individual reminders never fire for an occurrence that is already overdue. | §7. The digest already reports overdue counts every day at a time the user chose; an individual repeat is pure duplication. This also fixes what a reminder *means*: "this is due today", never "you failed". A setting whose other two options are rejected on principle is not a setting. |
| **D9** | The digest, the reminders and the evening re-reminder are planned in **one pass** and applied in **one enqueued write** on the existing `_digestWriteTail` queue. | §9. D2 couples the digest's counts to the reminders' arming; applying them in two writes opens a window in which a chore is announced twice or not at all. |
| **D10** | The Snooze action's platform work is **one `zonedSchedule` call**, not a horizon rewrite, and the durable half (the snooze row) is written first. | §10. This is what keeps AC2 off F-1's unverified GATE 3. |
| **D11** | Snooze means **tomorrow, at the chore's own reminder time** — one action, no duration menu. | §4.3. **The domain is day-granular by design**: `DESIGN.md` §2 specifies all-day due dates, chores carry no due *time*, and the whole occurrence model is a date. An hours-based snooze would import a precision the domain does not have. |
| **D12** | The evening re-reminder **ships OFF**, and its discoverability is paid for by **placement and wording**, never by a prompt, banner or first-run hint. | §5.1. `DESIGN.md` §3's governing principle is digest by default, never nag; defaulting a second daily notification to on imposes a behaviour change on every existing user who never asked for it. B-5 already established that a returning nudge *is* the nagging. |

## 2. Per-chore reminders (AC1)

### 2.1 Shape

`chores.reminder_minutes INTEGER NULL` (D1). The chore form gains one row: a
switch that, when turned on, reveals a time picker pre-filled from the constant
`defaultReminderMinutes = 1080` (18:00 — the hour "bins out on Tuesday evening"
names, and far enough from the 08:00 digest default that the two never read as
one event). The pre-fill is a **constant, not a settings column**: a default is
not state, and a stored one would have to pick a device scope for a value that
is only ever a starting point in a picker.

Turning the switch off writes `NULL`. There is no separate enabled flag, so
there is no state in which the app holds a reminder time it is not using.

### 2.2 Who it fires for

The same recipient predicate the digest already uses (`projectDigestCounts`,
triage T2.3): an occurrence is in scope when it is unassigned ("anyone") or
assigned to the acting member; when the acting member cannot be resolved,
everything is in scope. So `reminder_minutes` replicating across a household
does **not** mean both partners are reminded about a chore assigned to one of
them. The column says "this chore is worth an individual reminder"; scoping
decides whose device rings.

### 2.3 When it is armed

For each pending occurrence `X` of an active, unpaused, non-deleted chore with
`reminder_minutes != null`, in scope for this device:

1. `armDate` = `X`'s next projected due date on or after today, via the **same**
   `latestScheduledOnOrBefore` roll-forward `digest_projection.dart` already
   uses. A schedule-anchored chore rolls to its next series slot; a one-off or
   completion-anchored chore keeps its own `due_date`.
2. `armAt` = `armDate` at `reminder_minutes`, built from calendar components
   (never `add(Duration(days:))`) for the DST reason `nextDigestSlot` documents.
3. If a `reminder_snoozes` row exists for `X` with `snoozed_until` in the
   future, `armAt = snoozed_until` (§4).
4. `armAt` is passed through the quiet-hours shift (§6). This is the **only**
   place the shift is applied to a reminder, including a snoozed one, so there
   is exactly one implementation of "when may this fire".
5. Drop if `armAt <= now` (D8: already overdue means silent) or if `armAt` is
   more than `reminderArmWindowDays` (14) out (D3).

Survivors are sorted by `armAt` ascending, tie-broken by chore id ascending —
stable across recomputes and across devices, unlike title or creation order —
and the first `reminderCeiling` are armed (§3).

**Ids are position-relative, exactly like the digest's.** Reminder `i` in that
sorted list uses `reminderNotificationIdBase + i`, so an id names neither a
chore nor a date and **the payload is the only channel** that can address
anything. That is the same corollary N1 already records for the digest, and it
is why the payload gains a `nid` field in §10.1.

### 2.4 Rule D — never announced twice (D2)

A digest slot firing on date `D` omits occurrence `X` from `dueCount`,
`overdueCount` **and** the `soleOccurrenceId` gate iff step 5 above armed a
reminder for `X` whose `armAt` falls on calendar date `D`.

Because a reminder is armed only at `X`'s projected due date (post-shift), and
`X` sits in the digest's *due* bucket on exactly that date, the omission always
removes `X` from the due bucket and never from the overdue bucket. The general
form is stated anyway because §6's deferral can move `armAt` onto the following
calendar date, and the rule must follow the reminder, not the due date.

Two consequences worth stating because they look like bugs and are not:

- **A reminder-enabled chore reappears in the digest the day after.** Bins due
  Tuesday, reminded Tuesday 18:00, ignored: Wednesday's 08:00 digest says "1
  overdue chore". That is escalation, not repetition — the individual reminder
  is spent, and the digest is the overdue channel (D8).
- **A daily reminder-enabled chore is only omitted from one slot.** Only its
  next occurrence is armed (D3), so every later slot counts it normally. The
  partition holds date by date, not chore by chore.

### 2.5 What this costs the digest's monotonicity, stated plainly

N1's tail-safety argument rests on the digest's silence decision being monotone
in the date: once a date is non-silent, every later one is too. **N2 breaks
that for the digest taken alone.** If the only pending work is a reminder-enabled
chore, that chore's own date is silent in the digest and the day after is not.

What replaces it is §0.1's partition. Coverage is preserved date by date over
the **union** of the two channels: an occurrence removed from a digest slot is
removed precisely because the user is being told about it individually, by name,
on that same date. A sparse tail slot can now be silent where N1's would have
spoken, and in every such case a reminder fires on that date instead.

Required test changes are in §13; the existing monotonicity group must be
re-scoped to occurrence sets with no armed reminders (where it is unchanged and
still load-bearing), and the partition becomes its own required test.

The one place the partition genuinely degrades is when the user turns the digest
**off**. Then "counted by the digest" is false for everything and coverage is
reminders-only. That is what turning the digest off means, and it is not a
defect.

### 2.6 These are one-shot notifications, not alarms

A per-chore reminder is a `zonedSchedule`d one-shot rewritten on every
recompute, and it inherits every property of the digest's horizon: **nothing
re-arms it while the app is closed.** A chore whose reminder fires while the app
is never opened gets no further individual reminder; the digest picks it up from
the next day (§2.4). The UI must never describe reminders in language that
promises an alarm.

Android scheduling stays **`inexactAllowWhileIdle`**, matching the digest. This
is a decision, not an oversight: exact alarms need `SCHEDULE_EXACT_ALARM` (a
revocable runtime grant on Android 14+) or `USE_EXACT_ALARM`, which Play
restricts to alarm-clock and calendar apps — a chore app is neither, and a
policy rejection is a worse outcome than a reminder that lands at 18:07. A chore
that must fire to the minute is a calendar event. The accepted consequence: in
Doze, delivery can drift by a long interval, and only a hand check on a real
device (§13.3) can say how much.

## 3. The notification id budget (hard constraint)

`docs/specs/notifications.md` reserves **40 of iOS's 64** pending-notification
ids for N2 and requires that whoever plans N2 spends against 40, not 64. This
section is that spend, and it is the renegotiation that spec asks for.

### 3.1 The split

| Range | Ids | Count | Owner |
|---|---|---|---|
| `digestNotificationIdBase` | 1001–1024 | 24 | The digest horizon. **Unchanged.** |
| `reminderNotificationIdBase` | 2001–2033 | 33 | Per-chore reminders. |
| `eveningNotificationIdBase` | 3001–3007 | 7 | The evening re-reminder horizon. |

```dart
const int n2NotificationIdBudget = 40;       // reserved by notifications.md
const int eveningHorizonSlots = 7;
const int reminderCeiling = n2NotificationIdBudget - eveningHorizonSlots; // 33
const int reminderNotificationIdBase = 2001;
const int eveningNotificationIdBase = 3001;
const int reminderArmWindowDays = 14;
const int defaultReminderMinutes = 1080;     // 18:00
```

`reminderCeiling` is **derived**, never written as `33`, for the same reason
`digestNotificationIds` is derived from `digestHorizonSlots`: the split must
move as one number when it moves at all.

The bases are deliberately far apart (1001 / 2001 / 3001) rather than adjacent,
so an off-by-one inside one range cannot silently land in another's.

**Why the evening horizon is 7 and not 14.** The evening re-reminder is the
"you are around today and busy" instrument. Someone who has not opened the app
in a week is not busy-today, they are away, and the digest's own 83-day horizon
is what serves them. Seven consecutive daily slots is one week away from the
app, after which the digest alone carries — the same postponement-not-miss trade
the digest's weekly tail made.

**The total is now exactly 64 and there is no slack left.** That is what the 40
was reserved for. Anything new must take ids from one of these three ranges, by
amending this table.

### 3.2 What happens at the ceiling (D4)

A household can easily have more than 33 chores with a reminder. When it does:

- **Which win:** the 33 whose fire moment is soonest (tie: lowest chore id).
  Nearest-first is the only ordering that never delays a reminder in favour of a
  later one, and the tiebreak is stable so the set does not churn between
  recomputes. Note that `reminderArmWindowDays` (14) already excludes far-future
  chores from competing at all, so the ceiling only binds when a household has
  33+ reminder-enabled chores due *inside a fortnight*.
- **What the losers get:** the digest, unchanged. Rule D omits only *armed*
  occurrences, so an occurrence that lost the ordering is counted by its date's
  digest slot exactly as it is today. **No chore is ever silent because of the
  ceiling** — it drops from "individually reminded" to "in the daily summary".
- **How the user finds out:** a factual sub-line under the Settings reminders
  section, shown only while the count exceeds the ceiling, naming how many
  chores stayed in the summary and what the limit is. It is a **pure projection**
  of state that already exists — no stored flag, nothing to dismiss, nothing that
  can go stale — which is the same pattern the digest's permission-denied
  sub-line follows (`notifications.md`, B-5 / T2.6). There is deliberately no
  warning at the moment a chore's reminder is switched on: that would be a
  one-shot claim about a set that changes every time any chore is edited.
- **Why silence beats a wrong notification:** what is forbidden at the ceiling is
  *inventing* a reminder. Never re-point a reminder at a different chore, never
  batch "and 7 others" into one individual reminder, never fire an approximate
  one at a rounded time. A notification that names the wrong chore or the wrong
  time destroys the trust the whole channel runs on, and it cannot be
  distinguished from a bug by the person receiving it. A chore quietly handled by
  the summary instead is a downgrade the user can neither notice nor be misled
  by.

### 3.3 The enforcement point

`test/application/notification_scheduler_test.dart` currently asserts
`digestHorizonSlots <= 32`. That guard's job was to make N2 renegotiate the
split explicitly rather than let the digest eat it; N2 is that renegotiation, so
the assertion is **replaced**, not deleted, by:

- `digestHorizonSlots + eveningHorizonSlots + reminderCeiling <= 64`, and
- the three id ranges are pairwise disjoint (computed from the bases and counts,
  not from literals).

Deleting the guard instead of replacing it would leave the 64 undefended for the
first time since N1.

## 4. Snooze (AC2, D5)

### 4.1 Semantics

**Snooze is a notification-level deferral and nothing else.** It re-arms one
notification later and leaves every piece of chore state untouched: the due
date, the status, the assignee, rotation position, stats and the in-app list are
all exactly as they were one second earlier.

**This does not answer the question F-1 deferred; it dissolves it, and that
distinction is the reason a ticket parked since wave 4 is now buildable.** F-1
closed with "Snooze to tomorrow" unbuilt because its semantics for the overdue
case were genuinely undefined: does snoozing a 3-days-overdue chore make it due
tomorrow (erasing how overdue it was) or shift it one day (still overdue, just
less so)? Both readings are defensible — and **both exist only if snooze moves
the due date.** Once snooze is a deferral of the *notification*, neither reading
has anything to attach to: the chore stays three days overdue, and it stays
three days overdue tomorrow. **You snooze an alarm, not a task.** The user
asserted "not now", which is a statement about the notification in front of
them, and nothing in it licenses rewriting a due date, a status, a rotation
position or a statistic.

Everything else in §4 follows from that one line, including why the durable
state is a device-scoped side table rather than a column on the occurrence
(§4.2), and why the isolate work is one `zonedSchedule` rather than a horizon
rewrite (§10.1).

`skipOccurrence` is explicitly the **wrong primitive** and must not appear
anywhere in this feature: it closes the occurrence as `skipped`, advances the
whole recurrence to the next slot and advances rotation. Snoozing must burn no
slot and must not pass anyone's turn.

### 4.2 Where it lives

A **new device-scoped, unsynced table**, `reminder_snoozes`:

| Column | Type | Notes |
|---|---|---|
| `occurrence_id` | TEXT PK | `references(ChoreOccurrences, #id, onDelete: KeyAction.cascade)` |
| `snoozed_until` | TEXT | ISO-8601 UTC instant, the convention every other timestamp column uses |
| `created_at` / `updated_at` | TEXT | as usual |

Device-scoped and not synced, because snoozing is a personal act about a
personal notification — the same scope `DESIGN.md` §3 gives every other
notification setting ("per-user settings, not per-household"). Igor pressing
Snooze must not silence his partner's reminder. It also keeps the entire N2
surface off the sync path except the one genuinely shared field (§8.2), which
means no Supabase migration, no mappers and no LWW semantics to argue about for
this table.

**The cascade delete is load-bearing, not decoration.** `ChoreService.pauseChore`
*deletes* the pending occurrence, and foreign keys are ON (`beforeOpen` sets
`PRAGMA foreign_keys = ON`). Without `onDelete: cascade` a snoozed chore could
not be paused.

Rows are garbage-collected on every plan pass: delete rows whose occurrence is
no longer pending or whose `snoozed_until` is in the past. Cheap, and it means
the table never grows.

### 4.3 What Snooze does

Tapping **Tomorrow** on a per-chore reminder writes
`snoozed_until = armDate + 1 day at reminder_minutes` — tomorrow, at the chore's
own reminder time, which is the "Snooze to tomorrow" `DESIGN.md` §3 names — and
re-arms that one notification (§10.1 has the ordering and the isolate
constraints). The quiet-hours shift is applied at plan time like any other
candidate (§2.3 step 4), not at write time, so `snoozed_until` stores intent and
one code path decides deliverability.

**Why one day and not a duration menu (D11).** The reason is the domain, not the
label. `DESIGN.md` §2 specifies **all-day due dates** — chores have no due
*time*, and a `ChoreOccurrence` is anchored to a `PlainDate` throughout the
model. An hours-based snooze ("+3 hours") would import a precision the domain
does not have, and would need a quiet-hours interaction of its own, because "+3
hours" from an 20:00 reminder lands at 23:00 while "tomorrow, same time" cannot
land anywhere the reminder's own time was not already validated. Same-time-
tomorrow inherits that validated slot for free: it reuses `reminder_minutes`,
which §2.3 already puts through `applyQuietHours`, so snooze adds no new
deliverability case to reason about. A duration menu would also cost a third
button on a surface where button space is the scarcest thing there is.

Snoozing is **stateless and unlimited**: a re-armed reminder can be snoozed
again, and there is no counter. Repeated snoozing is the user actively choosing,
which is the opposite of a nag, and a limit would need durable per-occurrence
state whose only purpose is to eventually ignore them.

Snooze is offered **only on per-chore reminders**. A summary (the digest or the
evening re-reminder) cannot be coherently snoozed — it names no single thing to
defer — so those carry Done (when unambiguous) and nothing else.

## 5. The evening re-reminder (AC2, D6)

**Trigger.** `eveningHorizonSlots` (7) consecutive daily slots, the first chosen
by the same "today if still ahead of now, else tomorrow" rule `nextDigestSlot`
uses, at `settings.evening_reminder_minutes` (default 20:00). A slot fires iff
at least one in-scope occurrence is **due on that slot's own date** and is not
about to be individually reminded — precisely: occurrence `X` counts toward the
evening slot firing at moment `M` iff `X`'s projected due date is that slot's
date **and not** (`X` has an armed reminder at `armAt` on that same date with
`armAt >= M`). A reminder that has already fired earlier that evening does not
suppress the summary; one that is still to come does, because it would arrive
minutes later and say the same thing better.

**Overdue occurrences never count** (D6). This is the whole anti-nag design and
it is worth stating as a property rather than a rule: *it is impossible to
receive the evening re-reminder two evenings running about the same chore*,
because by the second evening that chore is overdue, not due-today. There is no
state in which the feature can settle into a nightly drumbeat, and therefore no
need for a "stop nagging me" escape hatch.

**What it says.** An ICU-plural body, "N chores still open today" (§11). It
carries a Done action under the same gate the digest uses — attached iff exactly
one occurrence counts — and never a Snooze (§4.3).

### 5.1 Default OFF, and the obligation that comes with it (D12)

**Default: OFF** (§8.1). `DESIGN.md` §3's governing principle is *digest by
default, never nag*, and defaulting a second daily notification to ON would
impose a behaviour change on every existing v0.8.0 user who never asked for one —
the opposite of that principle, and a poor v0.9.0 upgrade experience.

A setting that ships off is only honest if the person it exists for can find it,
and that person is defined by their own words: *"it arrives, then it's gone."*
Someone who goes looking because their notification disappeared must land on this
row. That discoverability is paid for by **placement and wording**, and by
nothing else:

- **Placement is binding.** The evening rows live in the **same Settings group as
  the digest toggle and digest time**, directly beneath the digest time row —
  not in a separate "Reminders", "Advanced" or "More" area, and not on another
  screen. Someone hunting for "my chore notification" opens the one group that
  already holds the notification they know about; a second group is a second
  place to fail to look. (§12 fixes the order of rows so this cannot drift.)
- **Wording is binding.** The label names the problem, not the mechanism:
  `settingsEveningToggle` reads **"Remind me again in the evening"** /
  **"Abends noch mal erinnern"** — not "Evening re-reminder", not "Second
  notification". A user scanning the group is matching against their own
  complaint, not against our vocabulary. Its sub-line states the condition in the
  same register: "Only if something is still open today."
- **No prompt, no banner, no first-run hint, ever.** B-5 settled that a returning
  nudge *is* the nagging, and the digest pre-prompt is explicitly never re-armed.
  N2 must not reintroduce one under a new name. If the row cannot be found where
  it is with the label it has, the fix is the label — not a thing that appears
  uninvited.

**The default interacts correctly with quiet hours, by construction.** D7 drops
an evening re-reminder that falls inside the quiet window rather than deferring
it, so a user with quiet hours from 21:00 and an evening time of 21:30 would get
nothing. That is exactly the silent swallowing this section forbids, so it is
**not** left silent: §6's sub-line on the evening time row states it factually
whenever it is true ("Inside your quiet hours — not delivering"), computed as a
pure projection of the two times, always current, self-clearing the instant
either moves. Two further points make the default safe:

- Shipping OFF means the collision cannot be inherited — it can only be created
  by a user who has opened this group and set both times, i.e. someone who is
  looking at the sub-line as they do it.
- The shipped defaults do not collide: evening 20:00 sits an hour clear of the
  22:00 quiet-hours start, so a user turning the feature on with defaults gets a
  working feature and no sub-line.

## 6. Quiet hours (AC2, D7)

Three device-scoped settings (§8.1): enabled, `quiet_start_minutes` (default
22:00), `quiet_end_minutes` (default 07:00). The window wraps midnight in the
normal case and must be handled as a wrapping interval, not a numeric range.
`start == end` is treated as OFF, not as a 24-hour window — the latter would
mean "never notify", which is what the toggle is for.

One pure function owns the whole behaviour:

```dart
DateTime applyQuietHours({
  required DateTime candidate,
  required bool enabled, required int startMinutes, required int endMinutes,
});
```

It returns `candidate` unchanged when quiet hours are off or `candidate` falls
outside the window, and otherwise **the first instant at or after `candidate`
whose minute-of-day equals `endMinutes`**, built from calendar components. That
single formulation handles the midnight wrap and DST without a special case.

**Deferred, never dropped**, for the digest and for individual reminders (D7).
Dropping discards something the user asked for; deferring converts a 23:30 ping
nobody can act on into an 07:00 one they can. A deferral can land two
notifications on the same minute (a deferred digest and a deferred reminder both
at 07:00); that is accepted — they carry different content and both are true.

**The evening re-reminder is dropped, not deferred** (D7). Deferring it to 07:00
would deliver a notification whose entire premise — "these are still open and
there is still time today" — is false by then, minutes before the 08:00 digest
says the same thing correctly. Instead of silently doing nothing, the settings
UI states it: while the chosen evening time falls inside quiet hours, the
evening time row carries a factual sub-line ("Inside your quiet hours — not
delivering"). This is the same projection-only pattern as the digest's
permission-denied sub-line: no stored flag, always current, self-clearing the
moment either time moves.

Quiet hours apply to the **digest** as well, which is a behaviour change to a
shipped feature and so is stated deliberately: it is additive (a new
user-controlled setting), it defaults OFF, and the shipped 08:00 digest default
is outside the default window anyway — so no existing install changes behaviour
until its owner turns the setting on.

## 7. Overdue behaviour (D8)

`DESIGN.md` §3 offers badge-only, one repeat, or silent. **Silent**, and not as
a setting:

- **Badge-only** needs a badge count, which `notifications.md` puts explicitly
  out of scope, and Android badge behaviour is OEM-dependent enough that the
  feature would work differently on every phone in the household.
- **One repeat** is an extra individual notification about a chore the digest
  already reports as overdue every single morning at a time the user chose. That
  is duplication with a different sound, and it is the nag `DESIGN.md` forbids.
- **Silent** makes the individual reminder's meaning exact: it says "this is due
  today", never "you failed to do this". Overdue is the digest's job, and the
  digest already does it.

Concretely: §2.3 step 5 drops any candidate whose `armAt` is in the past. Note
this does **not** silence a schedule-anchored chore that has rolled forward —
its next series slot is a genuine new due date and gets a genuine reminder, and
that is not a repeat.

No `overdue_behavior` column is added. A three-way setting two of whose options
are rejected on principle is a menu, not a choice.

## 8. Schema

### 8.1 Client schema v13 — `settings` (device-scoped, NOT synced)

Five columns, all with defaults, no data rewrite:

| Column | Type | Default | Meaning |
|---|---|---|---|
| `quiet_hours_enabled` | INTEGER (bool) | `false` | §6 |
| `quiet_start_minutes` | INTEGER | `1320` (22:00) | §6 |
| `quiet_end_minutes` | INTEGER | `420` (07:00) | §6 |
| `evening_reminder_enabled` | INTEGER (bool) | `false` | §5 |
| `evening_reminder_minutes` | INTEGER | `1200` (20:00) | §5 |

Both features default OFF so that upgrading to v13 changes the behaviour of
exactly zero installs until someone opens Settings.

**Placement in the migration is not a free choice.** These go inside the
existing `else` branch of `onUpgrade` (`if (from < 13) { addColumn... }`),
alongside every other `settings` column, because `settings` did not exist before
schemaVersion 2: a `from == 1` upgrade builds the table at full current width via
`createTable`, and a second unconditional `addColumn` for the same column throws
a duplicate-column error. `app_database.dart` documents this trap three times
already; it applies unchanged.

### 8.2 Client schema v13 — `chores.reminder_minutes` (synced)

`IntColumn get reminderMinutes => integer().nullable()();` — added
**unconditionally** (`if (from < 13) { await migrator.addColumn(chores,
chores.reminderMinutes); }`, outside the `settings` `else`), because `chores`
has existed since schemaVersion 1. Same shape as the `syncDirty` (v8) and
`members.deletedAt` (v9) backfills.

**What syncing it costs, itemised, because this is the only part of N2 that
leaves the device:**

1. `lib/data/sync/row_mappers.dart`: `'reminder_minutes': chore.reminderMinutes`
   in `choreRow`, and
   `reminderMinutes: (row['reminder_minutes'] as num?)?.toInt()` in
   `choreFromRow`. Reading with `as num?` rather than `as int?` matches how
   `color`/`sort_order` already tolerate PostgREST's JSON numbers.
2. A Supabase migration adding `reminder_minutes integer` to `public.chores`.
   No RLS change: the column is inside a row whose access is already decided by
   `household_id`.
3. **Mixed-version cost, accepted and stated:** the pull mapper must tolerate the
   key being absent (an un-migrated server) and yield `null`. In the other
   direction, a device still on v12 pushes a chore row without the key, so a
   reminder set on an upgraded device can be lost when the older device next
   edits that chore. Bounded and self-healing — the value is one picker away, it
   never corrupts anything else, and it converges the moment both devices are on
   v13. Not worth a schema-negotiation mechanism this app does not otherwise
   have.
4. It replicates the household's *intent*, not its notifications — §2.2 is what
   stops a shared column becoming a shared alarm.

The alternative — a device-scoped `chore_reminders` table so each member sets
their own time for the same chore — was rejected because `DESIGN.md` §1 lists
"reminder overrides" as a field of the chore definition, and because "the bins go
out Tuesday evening" is a fact about the bins, not about a phone.

### 8.3 Client schema v13 — `reminder_snoozes` (device-scoped, NOT synced)

`await migrator.createTable(reminderSnoozes);` — see §4.2 for the columns and
for why the cascade FK is required.

### 8.4 Migration tests must not be vacuous

`test/data/db/schema_migration_test.dart` asserts column existence via
`PRAGMA table_info`, and it must keep doing so for all three additions.
**`expect(row.reminderMinutes, isNull)` proves nothing**: drift maps an absent
nullable column to `null` on read, so that assertion passes whether or not the
migration ran — a vacuity this repo carried for eight schema versions. Every new
column here is nullable or defaulted, so `PRAGMA table_info` is the only
non-vacuous check. For `reminder_snoozes`, assert the table's presence and its
column set the same way, and additionally assert the FK's delete action, since a
missing cascade is invisible until someone pauses a snoozed chore.

## 9. Scheduling architecture

### 9.1 One planning pass

A new pure module `lib/domain/reminder_planner.dart` (zero imports beyond
`dart:core` plus `lib/domain/recurrence/`, same purity standard as
`digest_planner.dart`) holds the constants of §3.1, `applyQuietHours`, and the
plan types `ReminderPlan` / `EveningPlan`.

`lib/application/digest_plan_builder.dart` gains
`buildNotificationPlans({now, settings, pending, recipientMemberId})` returning a
`NotificationPlanSet` with three lists of exactly `digestHorizonSlots`,
`reminderCeiling` and `eveningHorizonSlots` entries. It computes in the order
**reminders → evening → digest**, because Rule D and §5's suppression both read
the armed set. `buildDigestPlans` remains as a thin wrapper returning the digest
half, so its three existing callers (the reschedule controller, the pre-prompt
banner, and the background isolate) keep compiling; the controller moves to the
new function.

### 9.2 One serialized write

`NotificationScheduler` gains `applyPlans(NotificationPlanSet)`, which rewrites
all three id ranges — schedule where non-null, cancel where null — inside a
**single** `_enqueueDigestWrite` body. Not three enqueued writes: D2 couples the
ranges, and two writes with a gap between them is a window in which a chore is
announced twice or not at all.

The field's name already anticipates this (`_digestWriteTail` was renamed for
*writes*, not applies, by G-12); rename it `_notificationWriteTail` and keep every
property G-12 pinned — synchronous enqueue, the tail never left completing with
an error, the error still reaching the caller that made that call.

`cancelDigest()` becomes `cancelAll()`, covering all three ranges, and
`reset_flow.dart`'s wipe must clear reminders and evening slots too. A wipe that
leaves per-chore reminders armed is strictly worse than the digest case G-12
fixed, because a reminder names a chore that no longer exists.

`applyDigestPlans` and `cancelDigest` may keep existing as narrow wrappers only
if nothing outside the scheduler calls them.

### 9.3 Triggers and channels

Recompute triggers are unchanged from N1 (bootstrap, resume, day change, any
occurrence/chore/settings mutation, acting-member change, 500 ms debounce) —
`reminder_snoozes` and the new `settings` columns join the mutation set.

Two new Android channels, so a user can mute one instrument without losing the
others: `reminders_v1` and `evening_v1`, both **default importance**, matching
the digest. Default rather than high is deliberate: AC1's complaint is that
reminders are *untimely and anonymous*, not that they are quiet, and shipping
high-importance heads-up popups for household chores is what gets an app muted
wholesale. A user who wants more can raise it per channel in system settings.

Both channels inherit E-1's constraints in full: localized name and description
passed per `zonedSchedule` call, and **any future change to that copy must mint a
new id and delete the one it replaces**, because Android caches channel copy at
creation and cannot rename. The same accepted staleness applies — a language
switch does not relabel an existing channel.

iOS needs two new `DarwinNotificationCategory` registrations at `initialize()`:
`reminderActions` (Done, Tomorrow) and `eveningActions` (Done), referenced per
notification via `categoryIdentifier`. Category action titles are fixed at
registration, so the same locale-staleness window N1 accepts for `digestActions`
applies here unchanged.

## 10. The GATE 3 dependency — stated before it is relied on

F-1 shipped the digest's Done action with three hand-verified gates
(`docs/specs/notifications.md`, `docs/handover-2026-08-28-wave-5.md` §3):

- **GATE 1 — the background isolate can open the database: CLOSED**, confirmed
  on a real Android device against v0.7.0 build 10 on 2026-08-18.
- **GATE 2 — a foreground action tap still routes to the background callback:**
  verified from the installed plugin's Android source.
- **GATE 3 — the isolate survives long enough to rewrite the digest horizon:
  NEVER VERIFIED.** Still open, still needs a human with a phone.

Snooze-from-the-notification is the one part of N2 that runs in that isolate, so
this spec states the premise before resting anything on it.

### 10.1 N2 is designed so that Snooze does not rest on GATE 3

GATE 3 is about surviving a **24-call horizon rewrite**. Snooze does not need
one. Its handler does three things, ordered by durability exactly as F-1's is:

1. **Write the `reminder_snoozes` row.** One local insert-or-update. This is the
   user's intent and it must never be lost. It sits inside GATE 1's already-closed
   ground: the isolate demonstrably opens the database and demonstrably completes
   a `completeOccurrence` write today.
2. **Ping the main isolate** on the existing `notificationActionPortName` port
   (best-effort; a null lookup means the app is not running, which is the common
   case). An alive app then replans authoritatively and everything downstream is
   correct.
3. **Re-arm one notification**: a single `zonedSchedule` on the id the payload
   carries. Not 24 calls, not 33 — one.

For step 3 the payload must carry the id, because reminder ids are
position-relative (§2.3) and `NotificationResponse.id` is unreliable on the
background path. So `digest_action_payload.dart` moves to
`{"v":2,"kind":"digest"|"reminder"|"evening","occ":...,"by":...,"nid":<int>}`.
**The decoder must keep accepting `v:1`** and read it as `kind:"digest"` with no
`nid`: pending notifications survive an app upgrade, so a v1 payload can be
sitting in the shade when v13 is installed.

Re-arming on `nid` can in principle clobber another chore's reminder, if a
recompute moved a different chore onto that position between the schedule and
the fire. That requires the app to be alive — and an alive app receives step 2's
ping and replans afterwards. This is exactly the self-correcting cross-isolate
hazard F-1 already records and declines to fix with a lock; do not add one here
either.

The handler deliberately **does not rewrite the digest horizon**. A snooze does
change Rule D's answer for one date, so the already-armed digest slots can be
stale by one occurrence until the next recompute. **That staleness always errs
toward reporting the chore, never toward hiding it**: the morning digest says
the chore is still open, which it is. One redundant summary line after a snooze
is a far smaller error than the Done action's would be (there, the chore no
longer exists at all), and it is the error that buys independence from GATE 3.

New action ids, namespaced because the background callback is process-global and
`notifications.md` requires each new surface to mint its own rather than reuse
`digest.done`: **`reminder.done`**, **`reminder.snooze`**, **`evening.done`**.

### 10.2 If GATE 3 comes back negative

**Unaffected — all of AC1 and most of AC2.** Per-chore reminders, the digest
exclusion, quiet hours, the evening re-reminder, every settings surface and the
whole planning core are armed by the **main** isolate on ordinary recomputes and
involve no isolate work whatsoever. Done from any of the three notification
kinds also keeps working: it is F-1's step 1, inside closed GATE 1.

**Degraded — the tail of the Snooze handler.** If the isolate is cut short after
step 1, the snooze is *recorded but late*: no notification is armed until the
next recompute (app open, resume or day change), and if the snooze moment has
passed by then, §2.3 step 5 drops it and it simply never fires.

**The fallback is structural and needs no new mechanism.** A snoozed occurrence
with no armed reminder is, by Rule D, **not omitted from the digest** — so the
next morning's digest reports it. Snooze therefore degrades from "it comes back
tomorrow evening" to "it comes back in tomorrow's summary". The chore is never
lost, which is the property AC2 is actually asking for.

**Last resort, only if step 1 itself proves unreachable** (which would be GATE 1
regressing, and is not expected): make Snooze a foreground action —
`showsUserInterface: true`, so the tap launches the app and the main isolate
does the work. Cost: tapping Snooze opens the app, which is poor but functional.
Do **not** respond to a negative GATE 3 by removing Snooze, and do **not**
respond by calling `cancelAll()`, for the same reason F-1 forbids it.

### 10.3 A new gate

**GATE 4 (new, hand-verified once per platform):** a reminder armed by the main
isolate and re-armed by the background isolate on the *same* id does not
double-fire, and the re-armed one actually arrives. Method: a chore with a
reminder, app swiped away, tap Tomorrow, confirm exactly one notification
arrives the next day at the reminder time and none at the original time. Record
the result next to F-1's gates.

## 11. Localization

Every user-visible string goes through gen_l10n — `app_en.arb` (template, with
an `@`-description each) and `app_de.arb` (informal *du*, "Gerät" never
"Handy"). ICU plurals in **both** locales. **No ICU `zero{}` branch anywhere:**
CLDR has no distinct zero category in en or de, so the branch never fires; where
a zero case needs different wording it gets its own key.

Notification copy:

- `reminderBodyDueToday` — "Due today" / "Heute fällig". The reminder's **title
  is the chore title verbatim** (user data, not localized) — that is what makes
  it actionable, and it is the whole of AC1.
- `reminderBodyStillOpen` — "Still open" / "Noch offen", used when the armed
  date is later than the due date (a snooze, or a quiet-hours deferral). Two
  plain keys instead of one key with date arithmetic in it.
- `eveningReminderBody` — ICU plural, `one{1 chore still open today}` /
  `other{{count} chores still open today}`; German
  `one{1 Aufgabe ist heute noch offen}` / `other{{count} Aufgaben sind heute
  noch offen}`. `count >= 1` by construction (§5), hence no zero key.
- `notificationChannelRemindersName` / `...Description`,
  `notificationChannelEveningName` / `...Description` — they appear in system
  Settings; see §9.3 for the id-versioning constraint they inherit.
- `reminderSnoozeActionLabel` — "Tomorrow" / "Morgen". It names the outcome
  rather than the mechanism, which is what a two-word notification button should
  do. The existing `digestDoneActionLabel` is **reused** for all three Done
  actions rather than duplicated per surface; amend its `@`-description to say
  so.

Settings and chore-form copy: `settingsQuietHoursToggle`,
`settingsQuietHoursFrom`, `settingsQuietHoursTo`, `settingsEveningTime`,
`settingsEveningInQuietHoursHint` (§6), `settingsRemindersCeilingHint` (ICU
plural over the number of chores that did not fit, with the limit as a second
placeholder — §3.2), `choreFormReminderToggle`, `choreFormReminderTime`,
`choreFormReminderHint` ("This chore won't be counted in the daily summary" /
"Diese Aufgabe taucht dann nicht in der Tageszusammenfassung auf" — the one
place Rule D is explained to the person it affects).

**`settingsEveningToggle` is binding copy, not a suggestion** (D12, §5.1):
**"Remind me again in the evening"** / **"Abends noch mal erinnern"**, with the
sub-line `settingsEveningToggleSubtitle` "Only if something is still open today"
/ "Nur wenn heute noch etwas offen ist". It is worded as the user's problem
rather than as our mechanism, because it ships off and the label is the only
thing that will lead the person who wants it to it. "Evening re-reminder" is the
name of the feature in this document and must not become the name of the row.

There is deliberately **no `settingsRemindersSectionTitle`**: the evening and
quiet-hours rows join the existing digest section rather than founding a second
one (§5.1, §12).

## 12. UI surfaces and semantic ids

Every interactive widget gets a stable id via
`semantic(String id, {required Widget child})` (`lib/app/semantics.dart`, named
`child`):

- Chore form: `chore_form.reminder.toggle`, `chore_form.reminder.time`.
- Settings: `settings.evening.toggle`, `settings.evening.time`,
  `settings.quietHours.toggle`, `settings.quietHours.start`,
  `settings.quietHours.end`.

**The Settings row order is binding** (D12, §5.1), because it is the whole of the
evening re-reminder's discoverability and a later tidy-up must not undo it. One
group — the existing "Daily summary" section — in exactly this order:

1. `settings.digest.toggle` (existing)
2. `settings.digest.time` (existing)
3. `settings.evening.toggle` — **directly beneath the digest time**
4. `settings.evening.time` (revealed when 3 is on)
5. `settings.quietHours.toggle`
6. `settings.quietHours.start`, `settings.quietHours.end` (revealed when 5 is on)
7. `settings.digest.permission` (existing inline hint row, stays last)

No new section header, no "Advanced" area, no second screen. Someone whose
notification "arrives, then is gone" opens the one group that holds the
notification they already know about and finds the answer two rows down. The
section header's own copy (`settingsDigestSectionTitle`) may be widened from
"Daily summary" to cover all three features, but the rows must not be split.

The ceiling sub-line (§3.2) and the quiet-hours sub-line (§6) are not
interactive and take no ids; they are sub-lines on rows that already have them,
matching `settingsDigestToggleDeniedHint`.

## 13. Testing

### 13.1 Pure unit tests (the bulk of the value)

- `applyQuietHours`: outside the window, inside a wrapping window, inside a
  non-wrapping window, `start == end` (OFF), a candidate exactly at `start`
  (inside) and exactly at `end` (outside), and across both DST transitions in
  Europe/Berlin — the deferral target is a wall-clock time, so it must be built
  from calendar components and must not shift an hour.
- Reminder arming (§2.3): the roll-forward for a schedule-anchored chore, no
  roll-forward for one-off and completion-anchored chores, the past-moment drop
  (D8), the 14-day window drop, the snooze override, and the ordering plus
  tiebreak at the ceiling with 34 candidates.
- Evening slots (§5): fires on a due-today count, does **not** fire on an
  overdue-only day, is suppressed by a still-to-come reminder at `armAt >= M`,
  is **not** suppressed by one that already fired, and — the property worth its
  own named test — **cannot fire two consecutive evenings about the same
  occurrence**.
- **The partition test (required).** §0.1 made executable: over a mixed set
  (one-off, completion-anchored, schedule-anchored daily and weekly, some
  reminder-enabled, some past the ceiling, with and without quiet hours), walk
  every date the horizon reaches and assert that each in-scope occurrence is
  counted by that date's digest slot **exclusive-or** has a reminder armed on
  that date. This is the single test that catches "told twice" and "told by
  nobody" in one assertion, and every rule in §2–§6 exists to keep it true.
- **Re-scope the existing monotonicity group** (`digest_projection_test.dart`):
  keep it verbatim for occurrence sets with **no** armed reminders — where the
  sparse tail's original safety argument is untouched and still load-bearing —
  and do not weaken it into an `isNotEmpty`-shaped assertion. §2.5 explains why
  it can no longer hold over the digest alone.

### 13.2 Scheduler, application and data tests

- Fake-plugin tests over the three id ranges: reminder `i` → `2001 + i`, evening
  `k` → `3001 + k`, a null entry cancels its id, and `cancelAll` clears all 64.
- **The budget guard (required)**, replacing `digestHorizonSlots <= 32`: the
  three counts sum to at most 64, and the three ranges are pairwise disjoint,
  both computed from the constants (§3.3).
- **One write per recompute (required):** an exact count, in the spirit of the
  existing cost bounds — a recompute that changes reminders and the digest
  enqueues exactly one write (D9), and a burst of five mutations in one debounce
  window still costs one apply with at most one trailing re-run.
- `notification_action_processor.dart`: the snooze path against an in-memory
  database — row written for a pending occurrence, `snoozed_until` correct,
  **no** change to the occurrence's `due_date`, `status`, `assigned_member_id`
  or to rotation (the assertion that makes D5 real), a no-op for an occurrence
  that is no longer pending, and idempotence on a double tap.
- Payload: `v:2` round-trip for all three kinds, and a `v:1` payload still
  decoding as a digest Done (§10.1).
- Cascade: pausing a chore with a snoozed occurrence deletes the snooze row
  rather than throwing (§4.2).
- Migration: `PRAGMA table_info` for the five `settings` columns, for
  `chores.reminder_minutes`, and for the `reminder_snoozes` table plus its FK
  delete action. `expect(col, isNull)` is not a migration assertion (§8.4).
- Sync mappers: `choreRow`/`choreFromRow` round-trip including a null
  `reminder_minutes`, and `choreFromRow` tolerating the key being absent
  entirely (§8.2).
- Widget: chore-form reminder row states (off / on with time), settings section
  states (quiet hours off / on / evening-inside-quiet-hours sub-line / ceiling
  sub-line present and absent).

### 13.3 What only a human with a phone can verify

E2E runs fully offline against `NoopAuthGateway`, drives a Maestro flow on an
emulator, and **no CI job puts a real notification on a real device**. The
following are therefore ASSUMED, recorded here so nobody reads green CI as a
working feature, and hand-verified once per platform alongside F-1's gates:

1. That a per-chore reminder actually arrives, and **how far `inexactAllowWhileIdle`
   drifts in Doze** (§2.6). This is the one that could change a decision: if the
   drift is bad enough to make "bins out Tuesday evening" useless, exact alarms
   have to be re-argued against Play policy.
2. **GATE 4** (§10.3), and with it **GATE 3** (§10), which N2 no longer depends
   on but which remains open and worth closing while a device is in hand.
3. That the two new Android channels are created with localized names, that the
   digest channel is unaffected, and that muting one leaves the others working.
4. That the iOS `reminderActions` / `eveningActions` categories register and
   their buttons appear.
5. A real overnight quiet-hours deferral, including one across a DST boundary.

E2E (Maestro) can and should cover the *settings* surfaces — toggling quiet
hours, setting an evening time, enabling a chore reminder and seeing it persist
— which is the same carve-out N1 already accepts.

## 14. Slices (dependency order)

1. **Schema v13.** The five `settings` columns, `chores.reminder_minutes`, the
   `reminder_snoozes` table, repository methods, the non-vacuous migration
   tests, the sync mappers and the Supabase migration. No user-visible change.
2. **The planning core.** `reminder_planner.dart`, `applyQuietHours`,
   `buildNotificationPlans`, Rule D inside `digest_projection.dart`, the
   partition test and the re-scoped monotonicity group. Still nothing scheduled:
   this slice is pure functions and is where most of the risk actually lives.
3. **The scheduler.** `applyPlans` as one enqueued write over three id ranges,
   `cancelAll`, the reset-flow change, the budget guard replacing
   `digestHorizonSlots <= 32`.
4. **Per-chore reminders, end to end.** Chore-form row, l10n, the ceiling
   sub-line. **This slice alone satisfies AC1**, and it is deliverable without
   anything below it.
5. **Quiet hours settings UI.** Must precede slice 6, whose suppression rule and
   sub-line are defined in terms of it.
6. **The evening re-reminder.** Settings UI plus the evening plans. Satisfies
   the second half of AC2 that does not touch an isolate.
7. **Notification actions.** `reminder.done`, `reminder.snooze`, `evening.done`;
   payload `v:2`; the snooze write path in the background isolate; GATE 4.
   **Last on purpose:** it is the only slice standing on unverified
   platform ground, and by the time it starts, AC1 and two thirds of AC2 have
   already shipped.

**Main risk:** slice 7, and it is contained by §10 rather than by hope — if the
isolate work cannot be made to hold, slices 1–6 are still a complete answer to
AC1 and to the "evening re-reminder + quiet hours" half of AC2, and Snooze
degrades to the digest rather than disappearing.

## 15. Non-goals (explicitly)

- **No server push and no cross-user events.** That is N3. Reliability is not
  what AC1/AC2 are about.
- **No respec of the digest.** Its horizon, shape, silence rule, projection,
  channel, locale resolution and Done action are unchanged. Rule D changes what
  it *counts*, not how it works.
- **No exact alarms** and no `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM`
  permission dance (§2.6).
- **No badge counts** — still out of scope, as in N1 (§7).
- **No `overdue_behavior` setting** (§7).
- **No per-member notification settings.** `settings` stays device-scoped and
  one row; per-member is meaningless until accounts, exactly as N1 records.
- **No snooze picker.** One action, "Tomorrow" (§4.3). A duration menu on a
  notification is a settings screen in a bad place.
- **No reminders for shopping items.** Different lifecycle, no due dates, no
  demand.
- **No per-chore reminder for a paused chore.** Pause deletes the pending
  occurrence; there is nothing to arm.
- **No cross-isolate lock.** F-1 forbids it and §10.1 relies on the same
  self-correcting argument.

## 16. Open questions

**None. Both questions this spec opened were closed on 2026-08-30 by the product
owner, as decided, before any planning round began.** They are recorded here as
closed rather than deleted, so that the reasoning survives and nobody re-opens
them from the options alone.

**OQ1 — What "Snooze" should mean in time. CLOSED: tomorrow, at the chore's own
reminder time** (decision **D11**, specified in §4.3). Not because it matches
`DESIGN.md` §3's "Snooze to tomorrow" label, but because of the domain:
`DESIGN.md` §2 specifies all-day due dates, chores carry no due *time*, and a
`ChoreOccurrence` is a `PlainDate` throughout. An hours-based snooze imports a
precision the model does not have, and needs its own quiet-hours interaction
because "+3 hours" can land at 23:00 where "tomorrow, same time" cannot land
anywhere `reminder_minutes` was not already validated. The rejected options —
an hours-based snooze, or both as two actions — are argued in §4.3.

**OQ2 — Whether the evening re-reminder ships ON by default. CLOSED: OFF**
(decision **D12**, specified in §5.1). `DESIGN.md` §3's governing principle is
digest by default, never nag; shipping ON would impose a second daily
notification on every existing user who never asked for one, which is that
principle inverted and a poor v0.9.0 upgrade experience.

The obligation attached to that default is **binding, not advisory**, and lives
in §5.1 and §12: the person the setting exists for described their problem as
*"it arrives, then it's gone"*, so someone hunting for a vanished notification
must land on the row. That is paid for by **placement** (in the existing digest
settings group, directly beneath the digest time — §12 fixes the row order) and
by **wording** ("Remind me again in the evening" / "Abends noch mal erinnern",
the problem rather than the mechanism), and by **nothing else**. No prompt, no
banner, no first-run hint, now or later: B-5 already settled that a returning
nudge *is* the nagging, and the digest pre-prompt is never re-armed. A
discoverability problem here is a copy problem, and its fix is the label.

§5.1 also records why the OFF default is safe against §6's quiet-hours rule: an
evening re-reminder inside the quiet window is dropped rather than deferred
(D7), so the collision cannot be inherited by an upgrade — only created by a
user who is looking at the row's factual "Inside your quiet hours — not
delivering" sub-line as they create it — and the shipped defaults (20:00 evening,
22:00 quiet-hours start) do not collide.
