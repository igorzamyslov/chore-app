# Pre-release audit — 2026-08-08 (v0.4.1+7)

*A lifecycle-and-conventions pass over the whole app, asking the question the
persona walkthrough couldn't: **what breaks when the app is NOT being used?**
Every finding below was traced in the source, not assumed. Findings marked
NEW appear in no existing spec, feedback doc or backlog entry.*

The persona round (`docs/research/triage.md`) audited the app as a user sees
it in a session. Waves N1/N2 and A1 closed all of Tier 1 except T1.3. What
neither pass covered is the app's behaviour *between* sessions — timers,
schedules, and the day boundary — which is where the two most serious
findings live.

---

## P0 — The daily digest is not daily (NEW)

**`lib/domain/digest_planner.dart` + `lib/application/notification_scheduler.dart:145`**

`planDigest` returns exactly one `fireAt` — the next slot — and
`zonedSchedule` is a **one-shot** schedule (no `matchDateTimeComponents`,
verified: zero hits for any repeat API in `lib/`). Nothing re-arms it after
it fires. The only reschedule triggers are, per
`DigestRescheduleController` (`lib/app/providers.dart:672-760`) and
`main.dart:83-99`:

- `bootstrapProvider` resolving (app start),
- a `pendingOccurrencesProvider` / `settingsProvider` emission (a local
  mutation),
- `_AppResumeObserver` (app resume),
- catch-up, and only when it reports `changed == true`.

**Every one of those requires the app to be running.** So the sequence is:

| Day | What happens |
| --- | --- |
| Mon 21:00 | User opens the app. Digest scheduled for Tue 08:00. |
| Tue 08:00 | Digest fires. Nothing is scheduled to replace it. |
| Wed 08:00 | Silence. |
| Thu 08:00 | Silence — until the user next opens the app. |

The digest therefore works only for users who already open the app every
day, and goes silent for exactly the users a reminder exists to serve. Spec
`notifications.md` states the intent as *"One notification per day at a
user-chosen time"*; the spec's own reschedule-trigger list (architecture #2)
has the same gap, so this is a spec bug as much as a code bug — it was never
"after the digest fires".

The scheduler's comment at `notification_scheduler.dart:141-144` is aware of
the one-shot choice and defends it ("every digest is cancelled and freshly
re-scheduled on its own"), but the freshness it relies on only exists while
the process lives.

`DESIGN.md` calls notifications the retention maker/breaker; `notifications.md`
opens with the same line. This is the single highest-value fix in the list.

**Options, in increasing cost:**

1. **Schedule N days ahead.** On every recompute, cancel and schedule the
   next ~7 slots as distinct notification ids (`1001..1007`), with counts
   projected from the recurrence engine per date — which the engine can
   already answer. Silence rule per day still applies. No new permission, no
   background isolate, no platform work. Stale after 7 unopened days, which
   is a far better failure mode than stale after one.
2. **`matchDateTimeComponents: DateTimeComponents.time`** for a genuinely
   repeating daily alarm — but the body text then freezes at whatever the
   counts were when it was scheduled, and it needs a named `Location` (the
   `flutter_timezone` dependency the current comment explains away). It also
   cannot honour the "silence when nothing is due" rule.
3. Background isolate / server push (N3) — out of scope for this release.

**Recommendation: option 1.** It keeps the silence rule, keeps the counts
honest, and needs nothing new from either platform.

Whatever ships, add a test that advances the fake clock past `fireAt` with
no app interaction and asserts a notification still exists for the next day.
No current test does this.

---

## P1 — Date-derived UI never rolls over at midnight (NEW)

**`lib/app/providers.dart:545-552`, `lib/features/chores/chores_list_screen.dart:53`**

`clockProvider` is a plain `Provider` that never re-emits. Everything that
means "today" reads it once and is only refreshed when *something else*
happens to trigger a rebuild:

- `closedTodayOccurrencesProvider` captures `today` at provider-build time
  and watches nothing that changes at midnight (`bootstrapProvider.future`
  and `clockProvider`, both stable). **It never rebuilds.** An app left open
  overnight shows yesterday's completions under "Done today" indefinitely —
  and the progress card's `completedToday` is computed from that same list,
  so the ring is wrong too.
- `ChoresListScreen`'s `today` (line 53) re-reads the clock only when the
  widget rebuilds. `CatchUpController`'s midnight timer fires
  (`providers.dart:855-862`) but only calls `triggerRecompute` on the digest
  when catch-up **changed** something. On the common night — nothing
  schedule-anchored fell overdue — nothing emits, nothing rebuilds, and the
  Overdue / Today / Tomorrow section headers stay on yesterday's boundaries.

The infrastructure is already there and correct: `nextLocalMidnight` is
DST-safe and unit-tested, and `CatchUpController` already arms a timer on it
and re-arms on resume. What is missing is that the timer's only consumer is
catch-up.

**Fix.** Introduce a `todayProvider` (a `StateProvider<PlainDate>` or a
notifier seeded from `clockProvider`) that `CatchUpController._armDayChangeTimer`'s
callback and `triggerOnResume` both update unconditionally — *not* gated on
`changed`. Have `closedTodayOccurrencesProvider`, `ChoresListScreen`, and
anything else that buckets by date watch that instead of reading
`clockProvider` directly. E2E/widget determinism is unaffected: it still
derives from the injectable clock.

`test/app/day_change_catchup_test.dart` covers the catch-up half well; the
UI half has no coverage at all (`closedTodayOccurrencesProvider` appears in
zero tests). Add: pump past midnight with nothing overdue, assert "Done
today" is empty and the section buckets moved.

---

## P2 — Android auto-backup is still unconfigured (NEW as a finding; open since G8)

**`android/app/src/main/AndroidManifest.xml`** — no `android:allowBackup`,
no `android:fullBackupContent`, no `android:dataExtractionRules` (verified:
zero hits anywhere under `android/`). `allowBackup` therefore defaults to
`true` and Android backs up the whole app data directory with no rules.

`docs/app-lifecycle.md` G8 flagged exactly this as "VERIFY … check the
manifest/flags". It was never resolved, and the app has since grown a
network layer and an auth session, which changes the stakes:

1. **A live SQLite database is copied without coordination.** drift's
   `chore_app.sqlite` plus its `-wal`/`-shm` sidecars can be captured
   mid-write. A restore can land a torn database — the worst possible
   failure for a local-first app, because it looks like data loss with no
   explanation.
2. **The Supabase session is backed up with it.** `supabase_flutter`
   persists its refresh token in shared preferences, which auto-backup
   includes by default. Restoring onto a new device carries a live
   authenticated session across, alongside a restored `syncLastPulledAt`
   cursor and a device-scoped `actingMemberId` — two devices that believe
   they are the same device. Given last-push-wins, that is a data-clobbering
   configuration, not just an untidy one.

This is a release gate: it is invisible in every emulator and E2E run (the
same blind spot class as the v0.2.0 `INTERNET` permission miss — the project
already has the rule "verify the RELEASE artifact when a feature crosses a
capability boundary").

**Decide and declare explicitly**, either way:

- **`allowBackup="false"`** — honest and simple, given that the app's own
  answer to "don't lose my data" is sync + the JSON export. Uninstall means
  gone, which is what the reset copy already tells users.
- **Keep backup, with rules** — `dataExtractionRules` (API 31+) and
  `fullBackupContent` (below) that *exclude* the auth shared-prefs file and
  the WAL sidecars, and ideally exclude the database in favour of an
  export-shaped backup agent. More work, and the DB-consistency problem
  doesn't fully go away.

Recommendation: **`allowBackup="false"` for this release**, with a note in
`future-improvements.md` that a real backup story is the export/import pair
(F12), not the OS's.

---

## P3 — "Reset app data" leaves the account signed in (NEW)

**`lib/application/data_reset.dart:20-31`, `lib/features/settings/reset_flow.dart`**

`resetAppData` wipes all eight tables and nothing else. The Supabase session
is untouched. After a double-confirmed "Delete everything", the user lands
on the welcome screen still authenticated, so tapping *Join* skips the email
step entirely and goes straight to the membership probe.

Two problems:

- **Honesty.** The linked confirm copy says *"You can reconnect by signing in
  again"* (`settingsResetConfirm1BodyLinked`), which describes a sign-out
  that does not happen. The screen the user reaches contradicts the dialog
  they just read twice.
- **Handover.** "Reset app data" is the action someone takes before handing
  the phone on or starting clean. A live session for the previous account
  surviving that is the wrong default, and it's the one operation where the
  user has most explicitly asked for a clean slate.

**Fix.** `resetAppData` (or `ResetDataTile`, alongside its existing
`settingsProvider` invalidation) should call `authGateway.signOut()` and
`notificationScheduler.cancelDigest()` before or after the wipe. Note that
the *Disconnect* action added in wave A1 is the deliberate
keep-my-session-unlink; reset is the other end of that spectrum and should
behave like it.

---

## P4 — Smaller, verified (NEW)

| # | Finding | Where |
| --- | --- | --- |
| S1 | **The Android notification channel name and description are hardcoded English** — `'Daily summary'` / `'The once-a-day chores digest notification.'`. These are user-visible in system Settings → Apps → Notifications, so a German user sees English there. Violates the project's "every user-visible string through l10n" rule. Note Android caches the channel's name at creation time, so changing it later needs a new channel id — worth getting right before the first wide install | `notification_scheduler.dart:155-158` |
| S2 | **The startup error screen is a dead end.** `_ErrorScaffold` renders `appBootstrapError(error)` — the raw exception's `toString()` — with no retry, no reset, no way out. A user who hits a database-open failure has a permanently bricked app and a stack-trace-flavoured message. Add a retry (`ref.invalidate(householdGateProvider)`) and a route to the reset flow; the list screen's own `_ErrorState` already has the retry pattern to copy | `lib/app/app.dart:79-102` |
| S3 | **Android back on a non-first tab exits the app.** `AppShell` holds tab state in a plain field with no `PopScope`; Material guidance is that back returns to the start destination first. Cheap, and it pairs naturally with F1 (tab swiping) and F4 (re-tap to scroll to top) — one shell wave | `lib/app/app_shell.dart:66-116` |
| S4 | `pubspec.yaml` still describes the app as *"A new Flutter project."* Cosmetic, but it is package metadata on an open-source release | `pubspec.yaml:2` |

---

## Already tracked, and still open — my read on what gates the release

Verified against source today, not taken from the docs:

- **T1.3 / B1 — acting-member misattribution. Still entirely unbuilt.**
  `ActingMemberButton` is the unconditional `leading` of the chores app bar
  (`chores_list_screen.dart:96`) with no linked-household gate, and
  `markDoneFor` does not exist anywhere in `lib/`. This is the last open
  Tier 1 item and the only one that makes *synced multi-device* data wrong
  rather than merely confusing. **Gate the release on it.**
- **T2.3 — the digest is household-wide, not per-recipient.**
  `_recompute` (`providers.dart:736-745`) counts every pending occurrence
  with no member scoping. This compounds P0: once the digest actually fires
  daily, both partners get the same undifferentiated number every morning.
  Fix them together.
- **T2.7 — push has no periodic retry.** Confirmed: `_armPoll`
  (`sync_engine.dart:307-317`) arms `pullSince` only. A write made as
  connectivity drops sits dirty until the next local write or app resume.
- T2.1, T2.2, T2.4, T2.5, T2.6 remain open as triaged.
- **F5 — no offline indicator** is worth reconsidering as a release item
  rather than backlog: with P0 and T2.7 both in play, a device that silently
  cannot reach Supabase currently has no tell at all.

Not release gates, correctly parked: F1–F4, F6–F8, F14–F20.

---

## Suggested order

1. **P0** (digest scheduling) — highest value, self-contained, and the fix
   is a day's work with the recurrence engine already in place.
2. **P2** (`allowBackup`) — a one-line manifest decision, but it must be
   made *before* the first wide install, not after.
3. **P1** (day rollover) — small, and the timer it needs already exists.
4. **T1.3** — the last Tier 1 item; already specced in field feedback B1.
5. **P3**, **S2**, **S1** — one small honesty-and-dead-ends wave.
6. **T2.3** with P0 if they land together; then Tier 2 in triage order.
7. **S3** with the F1/F4 shell wave, whenever that runs.
