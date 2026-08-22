# Digest notification actions (F-1) — Implementation Plan

> **REVISED 2026-08-17.** Written 2026-08-08 against a digest
> implementation that has since been replaced TWICE (A-1, then A-1b). Every
> target in the original has been re-read against the tree and retargeted;
> see "Revision log" below for what the original assumed and why it no
> longer holds. **Nothing in this file has been executed yet.**

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps
> use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user mark a chore done directly from the daily digest
notification, without opening the app — but only when doing so is
unambiguous. Ship "Done ✓" only; "Snooze to tomorrow" is a separate ticket
(decision CLOSED in `docs/backlog.md` F-1 — do not re-open it).

**Ticket:** `docs/backlog.md` F-1. **Spec:** `docs/specs/notifications.md`
(BINDING; N2 phase). Also touches `docs/feedback/2026-08-06-conventions-audit.md`
C11.

**Architecture, one paragraph:** the digest stays a summary, and it is now a
**segmented horizon of 24 one-shot notifications** (ids 1001..1024), all 24
rewritten on every recompute. A "Done" action is attached **per slot**, only
to those slots whose own projected counts sum to exactly one occurrence
(`dueTodayCount + overdueCount == 1`) — the one case where "the chore" is
unambiguous. Because a notification's id is **slot-relative** and carries no
information about which chore or which date it is about, the action's
`payload` is the *only* channel that can address anything: it carries a
small JSON object with the occurrence id **and** the acting-member id the
slot was computed for. Tapping fires
`flutter_local_notifications`' `onDidReceiveBackgroundNotificationResponse`
in a **separate background isolate** (no Riverpod, no open `AppDatabase`, no
`BuildContext`, and no Supabase session): a thin top-level entrypoint opens
its own drift connection, calls the existing
`ChoreService.completeOccurrence` attributed to the payload's member id,
pings the main app process over `dart:isolate`'s `IsolateNameServer` so an
open app refreshes immediately, then rewrites the remaining horizon from the
now-updated database so a closed app does not get re-nagged about work it was
just told is done, and closes the connection.

## Revision log — 2026-08-17: what the original assumed, and what is true now

Two plans landed under this one. **A-1**
(`docs/plans/2026-08-08-daily-digest-scheduling.md`, shipped 2026-08-08)
replaced the single digest notification with a rolling horizon of distinct
ids, rewritten on every trigger, counts projected per date and scoped to the
acting member. **A-1b**
(`docs/plans/2026-08-14-digest-horizon-ceiling.md`, shipped 2026-08-14) then
segmented that horizon into **14 daily slots followed by 10 at weekly
spacing** — the same 24 ids now reach roughly day 83 instead of day 23.

Every item below was verified against the tree on this branch before being
written here.

| The original assumed | Actually true now |
| --- | --- |
| A single notification id, `digestNotificationId` | `digestNotificationIdBase = 1001` plus `digestNotificationIds` (a list of `digestHorizonSlots = 24` ids) in `lib/application/notification_scheduler.dart`. **`digestNotificationId` does not exist** — any code referencing it will not compile. |
| `NotificationScheduler.scheduleDigest(DigestPlan)` | `NotificationScheduler.applyDigestPlans(List<DigestPlan?>)`, which must be given **exactly** `digestHorizonSlots` entries (it throws `ArgumentError` otherwise) and rewrites every id: non-null → schedule on `base + k`, null → cancel. Plus `cancelDigest()`. **`scheduleDigest` does not exist.** |
| `planDigest({now, digestMinutes, enabled, dueTodayCount, overdueCount})` | `planDigestSlot({fireAt, enabled, dueTodayCount, overdueCount})` in `lib/domain/digest_planner.dart`. The slot's `fireAt` is now computed by `digestSlots(...)` *before* planning, not derived inside the planner. **`planDigest` does not exist**, so the original Task 2's verbatim test and implementation blocks are both uncompilable. |
| The counts are produced by a loop inside `DigestRescheduleController._recompute` (`lib/app/providers.dart`), and that is where the sole-occurrence id gets captured | **That loop is gone.** Counting moved into the pure `projectDigestCounts` in `lib/domain/digest_projection.dart`, joined to real data by the free function `buildDigestPlans` in `lib/application/digest_plan_builder.dart`. `_recompute` is now four lines that call `buildDigestPlans` and hand the result to `applyDigestPlans`. This is *better* for us: one change point, not one per caller. |
| One counting call site | **Two** callers of `buildDigestPlans`: `DigestRescheduleController._recompute` (`lib/app/providers.dart:1101`) and `DigestPrepromptBanner._recomputeDigest` (`lib/features/chores/digest_preprompt_banner.dart:123`). They are byte-identical calls — which is exactly why `buildDigestPlans` was extracted. Neither needs editing if the id is threaded inside `buildDigestPlans`. |
| The occurrence id is available where the counting happens | **It is not.** `ProjectedOccurrence` (`lib/domain/digest_projection.dart`) carries `dueDate`/`startDate`/`recurrence`/`assignedMemberId` and **no id at all**, and `DigestCounts` returns only two integers. Capturing a sole occurrence id therefore requires adding an `id` to `ProjectedOccurrence` and a `soleOccurrenceId` to `DigestCounts` — see Task 3. |
| Actionability is a single household-wide condition | It is **per slot**. Each of the 24 slots gets its own projected counts and its own silence decision, so slot 0 can be actionable while slot 6 is not, and vice versa. |
| The handler can fall back to `NotificationResponse.id` to know which notification to cancel | `response.id` is **unreliable in the background path**: the plugin's own `callback_dispatcher.dart` builds the response with `id` falling back to `-1` when the native value is neither `int` nor `String`, and always hardcodes `notificationResponseType: selectedNotificationAction`. And even a correct id would say nothing useful, because ids are slot-relative (below). The refreshed design does not read `response.id` at all. |
| A plain-string payload is enough ("no JSON needed for one field") | Two fields are needed, and the second one cannot be re-derived in the isolate at all. See "Analysis: what the action payload must carry". |
| `_resolveActingMemberId` = stored `actingMemberId`, else first admin, else first member | That is only `actingMemberProvider`'s **unpinned** branch. The real chain (`lib/app/providers.dart:881`) checks `memberIdentityModeProvider` first and, in **pinned** mode with no resolvable claim, deliberately returns `null` rather than guessing — that guess is precisely the misattribution gate A-5 closed. Re-implementing the old three-step chain in the isolate would **re-introduce A-5**. Resolved by putting the member id in the payload instead. |
| `app_de.arb` repeats the `@`-metadata block for each key | It does **not**. `app_de.arb` is bare key/value only; all `@`-descriptions live in `app_en.arb` (the template). |
| `AndroidNotificationDetails` can keep its hardcoded `'Daily summary'` channel name | The **small-fixes-wave plan's E-1 merges before this plan executes** and changes that: `zonedSchedule` gains `required String channelName` / `required String channelDescription`, `digestChannelId` becomes `'digest_v2'`, `legacyDigestChannelId = 'digest'` appears, and the interface gains `deleteLegacyDigestChannel()`. See "Collision: small-fixes-wave E-1". |
| `DartPluginRegistrant.ensureInitialized()` is needed in the entrypoint | Not needed. `flutter_local_notifications`' own `callback_dispatcher.dart` already calls `WidgetsFlutterBinding.ensureInitialized()` before invoking our callback, and that itself initialises the plugin registrant. Harmless but redundant; leave it out. |

**Unchanged and still correct:** the ambiguity analysis (Option C), the
choice of a background isolate over a foreground handler, the
`IsolateNameServer` ping for cross-connection UI refresh, the WAL/second-
connection reasoning, and the Android-manifest and iOS-AppDelegate
requirements. Those sections are edited only where a specific API detail was
wrong.

## Collision: small-fixes-wave E-1 merges FIRST

`docs/plans/2026-08-08-small-fixes-wave.md` Task 4 (E-1) also edits
`lib/application/notification_scheduler.dart`,
`test/application/fake_digest_notification_plugin.dart`,
`test/application/notification_scheduler_test.dart` and both ARB files, and
it lands **before** this plan executes. By the time you start:

- `DigestNotificationPlugin.zonedSchedule` already takes
  `required String channelName` and `required String channelDescription`.
  Any `zonedSchedule` override or call you write must pass them.
- `digestChannelId` is `'digest_v2'`; `legacyDigestChannelId` is `'digest'`.
  **Do NOT mint a third channel id.** Notification *actions* are attached
  per-notification on Android, not per-channel, so nothing about this plan
  requires a new channel. Minting one would throw away the localized name
  E-1 just shipped and lose any importance/sound the user had customised.
- `DigestNotificationPlugin` has a `deleteLegacyDigestChannel()` member and
  `ensureInitialized` calls it. Your `ensureInitialized` change composes with
  that; it does not replace it.
- `ScheduledCall` in the fake already has `channelName`/`channelDescription`,
  and `FakeDigestNotificationPlugin` has
  `deleteLegacyDigestChannelCallCount`.

**Therefore: re-read `lib/application/notification_scheduler.dart` and
`test/application/fake_digest_notification_plugin.dart` at the start of every
task that touches them. Treat any interface snippet in this plan as a
statement of the delta you must add, never as the file's full shape.**

## Global Constraints

- Every user-visible string goes through gen_l10n: add to `lib/l10n/app_en.arb`
  (template, with the `@`-description) AND `lib/l10n/app_de.arb` (informal
  du-form, **no `@` blocks** — that file has none). This includes notification
  action labels: they are resolved where the notification is *scheduled*, with
  no `BuildContext` available, so they go through `lookupAppLocalizations` +
  `NotificationScheduler`'s existing `localeResolver` seam, exactly like the
  digest title/body already do. Note that after this plan the scheduling can
  happen in either isolate — see "4. Locale in the isolate".
- Strict lints: `very_good_analysis` with `--fatal-infos`. Public members
  need doc comments.
- Widget/unit tests are integration-style: real in-memory `AppDatabase` +
  fixed clock, overriding only `appDatabaseProvider`/`clockProvider` plus
  the documented `digestNotificationPluginProvider` seam. Never mock
  repositories or services.
- **Never hand-roll a `ProviderScope` pump in a widget test.** Use
  `test/test_utils/pump_app.dart`'s `testChoreApp` / `openSettingsTab` /
  `find.bySemanticsIdentifier`. A hand-rolled pump HANGS (flutter_test's
  pending-Timer leak check runs before tear-downs, so drift's stream-cleanup
  timer never drains) and takes the whole suite with it. The
  `ProviderContainer`-based tests this plan extends
  (`test/app/digest_reschedule_test.dart`) are the documented exception and
  already carry the correct pattern — mirror that file, do not invent.
- **No test code in this plan is transcribed from memory.** Where a test is
  specified, this plan states the requirement and names a reference file to
  mirror. Read the reference before writing.
- **Every task states its expected RED failure mode.** If a test passes
  before its implementation exists, the assertion is vacuous — fix the test,
  not the implementation.
- Test runs need the Supabase dart-defines, exactly as `lefthook.yml` does:
  `flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY=`.
  Without them six unrelated tests fail and read as regressions.
- Regenerate l10n with `flutter gen-l10n`; never hand-write or hand-merge
  `app_localizations*.dart`.
- **Do not edit `docs/backlog.md`.** Closing the F-1 row is the merge
  owner's job.
- Never `await` a drift stream outside a widget pump in a **test** — that's
  what deadlocks under `flutter test`'s fake-async zone. This rule does NOT
  apply to real production code running under the real VM (the background
  isolate is real, not fake-async) — but this plan avoids the question
  entirely by adding one-shot `Future`-returning repository methods
  (Task 5a) instead of `.watch().first`, so there's no ambiguity either way.
- Never bare-await `bootstrapProvider.future` in a `ProviderContainer` test;
  use the existing `_awaitBootstrap` polling helper style from
  `test/app/digest_reschedule_test.dart`.
- `tester.pump(small duration)` between `container.dispose()` and
  `database.close()`.
- Run Flutter/Dart commands as `env -u GIT_DIR -u GIT_INDEX_FILE flutter ...`
  when anywhere near git hooks or worktrees. The Flutter tool lock is global to
  the machine, so concurrent local runs serialize and read as a hang — if you
  are executing this alongside other agents, **treat CI as the test runner**
  (`gh pr checks --watch`, `gh run view --log-failed`) and commit/push with
  `LEFTHOOK=0`, since the pre-push hook runs the full suite and would fail the
  push on a deliberately-RED commit. `flutter gen-l10n` and `dart format .` are
  cheap and always fine.
- Never add `Co-Authored-By` or any co-author trailer to commits.
- TDD: write-failing-test → run (RED, and check it is the RED the task states)
  → implement → run (green) → commit, per task below.
- After green, **invert the implementation and confirm the test goes red at the
  TEST step.** A failure at `analyze` (e.g. `unused_element` after deleting the
  only caller) is not a valid inversion — the tests never ran. Invert inside the
  method body.

## Analysis: what can "Done" mean on a digest?

**The problem:** "Done ✓" on a notification that says "3 chores today" is
ambiguous — which of the three? DESIGN.md §3 named the action without
resolving this; the ticket explicitly asks not to invent a confusing
affordance.

**Option A — act on all of them.** "Done" marks every currently-pending
occurrence the digest counted as done. Rejected: silently completing chores
the user never looked at is worse than the ambiguity it resolves — a wrong
one-tap bulk action on physical chores (not todo-list items) is exactly the
kind of "trust" bug this project's `docs/feedback/` audits keep flagging.
Also can't attribute misses/skips sensibly (what if one was meant to be
skipped, not done?).

**Option B — tap-through only, no action button at all.** Simplest, zero
ambiguity, matches the ticket's suggested "honest alternative." Rejected as
the *sole* answer because it leaves F-1 basically undone (it's exactly
today's N1 behavior) when a real, common case — a single remaining chore —
has an obviously correct action.

**Option C (chosen) — actions only when the digest is provably about one
occurrence.** Gate on `dueTodayCount + overdueCount == 1`. In that case the
digest body already reads as a single-chore sentence ("1 chore today" / "1
overdue chore") and there is exactly one occurrence id the action can mean.
Every other case (0 — no notification at all anyway; ≥2) gets no action,
falling back to tap-through (today's existing, already-correct behavior).
This is additive and never wrong: the label always matches what it acts on.

**Why not widen "sole occurrence" to "sole *chore*, multiple would-be
occurrences"?** Can't happen — a chore has at most one pending occurrence
at a time (see `ChoreService`'s invariants), so "one occurrence" and "one
chore's pending item" are the same condition.

### The gate is PER SLOT (new under A-1/A-1b)

There are 24 slots and each has its own projected counts, so the gate is
evaluated 24 times per recompute, against that slot's own date and the same
recipient scoping `projectDigestCounts` already applies. Slot 3 can be
actionable while slot 4 is not. Two consequences worth stating because a
reader will wonder:

- **Actionability is NOT monotone in the date**, even though the silence
  decision is (spec `docs/specs/notifications.md`, "Why a sparse tail loses
  no coverage" — the set of non-silent dates is an up-set). Counts only ever
  grow along the horizon, so a slot with exactly one occurrence is very
  often followed by slots with two. That asymmetry is correct and must not
  be "fixed": the up-set argument is about counts, not about whether one of
  them is unambiguous.
- **Do not restrict the gate to the daily segment.** It is tempting to
  argue a day-83 slot is "too speculative" to carry a button. It is not:
  the projection's accuracy is binary and slot-independent (A-1b's finding —
  the counts are exactly right if the local database has not changed, which
  is exactly the case in which a far slot ever fires, and stale if another
  device acted, which applies equally at day 2). A *pending* slot's payload
  is always as fresh as the last recompute, whether it is slot 0 or slot 23.
  Restricting by slot would buy nothing and would make the feature vanish
  for exactly the disengaged user A-1b exists to serve.

### What "Done" means when the slot's date is not today

With the segmented horizon a notification the user taps may be describing a
date well in the future *or* one already past (a slot fires on its own date,
but a notification can sit unread in the shade for days, and the last daily
slot is a week from the first tail slot). The definition must therefore be
date-free, and it is:

> **"Done" means: complete the specific occurrence ROW named in the payload,
> if it is still pending. If it is not still pending, do nothing at all.**

It does **not** mean "complete whatever is due on the date this notification
describes". That is what makes the segmented horizon harmless here — the
answer does not depend on which slot fired or when the user got round to
tapping. Three cases fall out of it:

- **Nothing changed since the slot was computed.** The row is still pending;
  it is completed and attributed. The projected date it was *reported* under
  is irrelevant to the write.
- **The row was already closed** (another device, or the user in-app, or a
  duplicate tap on a stale shade entry). Silent no-op. There is no UI to
  report to, and "someone already handled it" is a success, not a failure.
- **The row was replaced by catch-up.** If the app was opened between the
  digest being computed and the tap, `ChoreService.catchUpOverdue` may have
  marked the row `missed` and inserted a new pending occurrence with a new
  id. The payload's id is then stale → silent no-op. Note this window is
  narrower than it looks: opening the app also rewrites all 24 *pending*
  notifications with fresh payloads. Only an **already-delivered**
  notification sitting in the shade can carry a stale payload, because a
  delivered notification's payload is frozen at compute time and there is no
  API to refresh it.

**One accepted semantic divergence, called out because it is a product
decision and not an implementation detail.** For a *schedule-anchored
recurring* chore whose occurrence is already overdue, completing via this
action is not identical to completing in-app. In-app, `catchUpOverdue` runs
first and marks the stale occurrence `missed` before creating a fresh one;
from the notification, `completeOccurrence` closes that same row as `done`.
**We accept the `done`.** The user is asserting they did the chore; recording
that assertion is more truthful than recording the `missed` that catch-up
infers precisely from the *absence* of any such assertion. Running catch-up
inside the isolate first would be worse on every axis: much more machinery in
a time-boxed background context, and it would invalidate the payload's id
before we could use it, turning a legitimate "Done" into the silent no-op
above.

## Analysis: what the action payload must carry

**This is the single most important thing this revision changes.** The
original plan put one field in the payload and planned to recover everything
else from `NotificationResponse.id` or by re-deriving it in the isolate.
Neither works under A-1/A-1b.

**Notification ids are SLOT-RELATIVE, not date-derived.** `digestNotificationIds`
is `digestNotificationIdBase + k` where `k` is the offset from the *next*
slot, so **id 1001 means Monday 07:00 on one recompute and Tuesday 09:00 on
the next** — and past the daily segment, slot `k` is not even `k` days out.
`docs/handover-2026-08-14-planning.md` §4 records this and why it is
tolerable: correctness rests on every apply rewriting all slots, which holds
only if the loop finishes; the worst case is one duplicate morning
notification after a mid-apply process kill. A date-derived mapping would
have made a partial apply idempotent, but that is not the shape we have.

The consequence for us is absolute: **an action that must answer "which chore
and which date did the user tap Done on?" cannot infer any part of the answer
from the notification id.** The id is not a stable name for anything. On top
of that, `response.id` is not even reliably *delivered* on the background
path — the plugin's `callback_dispatcher.dart` substitutes `-1` when the
native notification id is neither an `int` nor a `String`, and hardcodes
`notificationResponseType: selectedNotificationAction` regardless. **The
payload is the only channel.**

So the payload carries two fields, and both are load-bearing:

1. **`occ` — the sole pending occurrence's id.** The thing to complete. The
   answer to "which chore", per the date-free definition above.
2. **`by` — the acting-member id the slot was computed for (nullable).** The
   attribution. This one is the non-obvious half: **the background isolate
   cannot re-derive it, and must not try.** `actingMemberProvider`'s real
   chain (`lib/app/providers.dart:881`) consults
   `memberIdentityModeProvider`, which needs `currentAuthUserProvider` — a
   live Supabase auth session. A notification-action isolate has no business
   initialising Supabase, and in **pinned** mode (linked + signed in) with no
   resolvable claim the provider deliberately returns `null` rather than
   guessing at a member, because that guess is exactly the misattribution
   gate A-5 closed. A simplified isolate-side "stored id, else first admin,
   else first member" chain — which is what the original plan specified —
   would silently re-introduce A-5 for every linked household. Passing the
   already-correctly-resolved value down instead is both simpler and the only
   correct option.

   `by` is also **exactly the right** member to attribute to, not merely the
   convenient one: the digest is scoped to the acting member (spec N1 /
   triage T2.3), so this slot's very existence and its counts were computed
   *for that member*. A `null` `by` (identity unknown — everything counts) is
   passed straight through to `completeOccurrence(completedBy: null)`, an
   unattributed completion, which is the honest answer and matches A-5's
   "never guess" posture.

   `by` is *also* what the isolate needs as `recipientMemberId` when it
   rewrites the horizon (see below), so one payload field serves both jobs.

**Format: a small JSON object, `{"v":1,"occ":"<id>","by":"<id>"|null}`**, with
`v` a schema version. Two reasons JSON rather than a delimited string: two
fields already, and the background callback is **process-global** — it
receives responses for *every* notification this app ever schedules,
including the 40 ids reserved for the unbuilt per-chore reminders (G-6 / F16,
see the spec's "Notification id budget"). A self-describing payload is what
lets G-6 add its own payload shape without either side having to guess.

**Action id: `digest.done`, namespaced.** `actionId` is the routing
discriminator, so it must not be a bare `done` that G-6 would plausibly reuse
for a per-chore reminder's own Done button. When G-6 lands it mints its own
action id; it does not reuse this one.

**What the payload deliberately does NOT carry.** Not the slot index, not the
notification id, and not the slot's date. The slot's date would only enable
"refuse a tap on a notification describing a stale date", and the "is it
still pending?" check is both stronger and simpler — a still-pending
occurrence is correct to complete no matter how old the notification is, and
a non-pending one is a no-op no matter how fresh.

## Analysis: the background isolate / cross-connection problem

The genuinely hard part, per the ticket. **Four** sub-problems now — the
original had two; A-1/A-1b added the third, and the fourth surfaced while
verifying the second.

**1. Opening a second DB connection safely.** `drift_flutter`'s
`openConnection()` (`lib/data/db/app_database.dart:186`) opens a WAL-mode
SQLite file at a fixed path per device. Two `AppDatabase(openConnection())`
instances — one in the main isolate, one freshly created inside the
background isolate for the single action-handling transaction — are two
independent native sqlite3 connections to the *same file*, in the *same OS
process* (Android/iOS both run the background notification-response
isolate as a second Dart isolate inside the same app process via the
plugin's own headless `FlutterEngineManager`, not a separate OS process).
SQLite's own file locking handles concurrent connections to one file
correctly (that's what WAL mode is for) — no corruption risk from opening a
second connection, as long as each side only holds it open for the single
transaction's lifetime and closes it immediately after (never left dangling
across isolate messages). This plan's `NotificationActionProcessor`
(Task 5) does exactly one `database.transaction(...)` worth of work (via
the existing `ChoreService`) plus one read-only query for the horizon
rewrite, and the entrypoint (Task 6) closes the connection immediately
after, in a `finally`.

**UNVERIFIED, and the highest-risk assumption in this plan.**
`openConnection()` is `driftDatabase(name: 'chore_app')` from
`package:drift_flutter`, which resolves its directory through `path_provider`
— i.e. a **platform channel**. That requires an initialised Flutter binding
in *this* isolate. The plugin does call `WidgetsFlutterBinding.ensureInitialized()`
in its own `callback_dispatcher.dart` before invoking our callback, and the
iOS plugin-registrant wiring in Task 9 exists precisely so the background
engine registers `path_provider` and `sqlite3_flutter_libs` — so this
*should* work. Nothing about it is provable from `flutter test`. **If the
on-device check in Task 10 shows the connection cannot be opened, the fix is
to give the isolate an explicit file path rather than a channel lookup;
`AppDatabase`'s own constructor takes a plain `QueryExecutor` and is already
clean, so this is a change of executor, not of the database class.** Do not
discover this at the end: Task 10's first Android check is the gate for
everything after Task 5.

**2. How does the in-app UI learn about a change made from outside it?**
This is the part with no free lunch. Drift's reactive `.watch()` streams
only re-emit on writes made **through the same `AppDatabase`/`QueryExecutor`
instance** — a write via a second, independently-opened connection to the
same file is invisible to the first connection's stream-invalidation bus.
Two isolates in the same process do not share that bus. Considered:

- **Rely solely on the existing app-resume observer.** Free, but wrong:
  `flutter_local_notifications` routes any action with
  `showsUserInterface: false` (which "Done" must be — it shouldn't launch
  the app) to the background isolate **even if the app is already in the
  foreground** — the routing decision is per-action, not per-app-state. A
  user who pulls down the notification shade while the app is open and taps
  "Done" would see no UI update at all until they happen to
  background/foreground the app.

  **VERIFY THIS BEFORE BUILDING ON IT** (the original plan asserted it as
  "confirmed in the plugin's own doc comment"; that citation could not be
  re-confirmed against 22.1.0 while revising, so treat it as unverified). Read
  the Android `ActionBroadcastReceiver` / `FlutterEngineManager` path in the
  installed package and settle whether a foreground tap is delivered to
  `onDidReceiveBackgroundNotificationResponse` or to
  `onDidReceiveNotificationResponse`. **This is a fork in the plan, not a
  detail:** if a foreground tap goes to the *foreground* callback instead,
  that callback runs in the main isolate with a live Riverpod container, and
  the correct handling there is a completely different (and much simpler) path
  — no second DB connection, no ping, just the existing `choreServiceProvider`
  — with the background path retained for the app-dead case. Record which one
  the package actually does, in the code, at the `initialize` call site.
  Whichever it is, the design below is correct for the app-dead case, which is
  the one that must work.
- **Chosen: cross-isolate ping via `dart:isolate`'s `IsolateNameServer`, then
  let the main isolate recompute.** The background isolate looks up a
  well-known port name and sends a no-payload ping, ignoring failure (`null`
  result — main isolate not alive right now). If the app is alive, the ping
  arrives essentially instantly and a new controller
  (`NotificationActionSignalController`, Task 7) invalidates the two
  drift-stream providers that read pending/closed occurrences and reruns
  the exact same calls `main.dart`'s app-resume observer already
  makes (`digestController.triggerRecompute()`,
  `syncEngineController.triggerOnResume()`).
  `IsolateNameServer` is in-process and OS-independent, so this also works
  identically in tests (Task 7's test looks the port up and sends to it
  directly, no real isolate spawn needed).

  **Ordering subtlety the test must pin.** `invalidate(pendingOccurrencesProvider)`
  does not synchronously deliver a fresh value, so the `triggerRecompute()`
  fired in the same handler may well read pre-invalidation data. That is fine
  and is not a race to fix: `DigestRescheduleController` already
  `ref.listen`s `pendingOccurrencesProvider`, so the invalidated stream's
  fresh emission triggers a *second*, correct recompute. The invalidate is
  what guarantees correctness; the explicit `triggerRecompute()` only makes
  the common case fast. Task 7's test must therefore assert on the state
  **after** the fresh emission has been pumped, not on the first apply.

This also solves sync propagation for free: `ChoreService.completeOccurrence`
already marks the row `syncDirty` regardless of which `AppDatabase`
connection called it (it's a column write, not a stream side effect), and
`syncEngineController.triggerOnResume()` (called by the same ping handler)
already knows how to push dirty rows — no new sync-engine code needed.

### 3. The rest of the horizon (NEW — did not exist before A-1)

With a single notification id, cancelling the acted-on notification cancelled
everything, and the original plan could stop there. With 24 ids it cannot.
The occurrence the user just completed was counted into **all** the still-
pending slots, so after the write those bodies are known-wrong. Concretely: a
one-off chore, marked done from the notification, app never re-opened — the
next slot fires saying "1 overdue chore" about a chore the user has *just told
the app they did*. That is a trust bug, and it is the exact class of bug this
project's feedback audits keep flagging.

Note first what is **not** a problem: the delivered notification itself needs
no cancelling. `AndroidNotificationAction.cancelNotification` defaults to
`true`, so tapping the action dismisses it, and it has already fired so
nothing is pending on its id. The refreshed design never calls `cancel` on a
specific id, which is what lets it ignore `response.id` entirely. *(iOS
dismiss-on-action-tap: see the manual checklist.)*

Three options for the pending slots:

- **Leave them.** Zero extra isolate work, but leaves up to 23 notifications
  armed with counts the isolate *knows* are wrong. Violates the spec's
  governing rule ("degrades into silence rather than into wrong counts").
- **`cancelDigest()` — cancel the whole horizon.** Satisfies the spec's
  preference, but costs the same 24 platform calls as a full rewrite while
  producing up to 83 days of silence for a user who does not re-open the app
  — destroying precisely what A-1 and A-1b were built to deliver. Strictly
  dominated.
- **Chosen: rewrite the whole horizon from the now-updated database.** Same
  cost as cancelling, strictly better result. The original plan rejected this
  as "duplicates `_recompute`'s counting/planning logic in a second place",
  and **that objection no longer holds**: `buildDigestPlans`
  (`lib/application/digest_plan_builder.dart`) is now a free function with no
  Riverpod dependency, extracted for exactly this reason and already shared by
  two callers "that cannot share a controller". A third caller in the
  background isolate is what it is for. The isolate needs three inputs, all
  of which it already has or can get cheaply: `DeviceSettings` (one-shot
  `SettingsRepository.ensureSettings()`), the pending occurrences (a new
  one-shot `ChoreRepository.getPendingOccurrences` — Task 5a), and
  `recipientMemberId` (the payload's `by`).

**Order the isolate's work by decreasing importance, so truncation degrades
gracefully.** The isolate runs inside a time-boxed context (Android's
`ActionBroadcastReceiver`; a background `FlutterEngine` on iOS) and the
callback typedef is `void Function(NotificationResponse)` — **synchronous
`void`, not `Future`** — so nothing awaits our async work. We must assume it
can be cut short:

1. **Complete the occurrence.** The user's intent. Must never be lost.
2. **Ping the main isolate.** One message. If the app is alive this alone
   fixes everything, because the main isolate then does the authoritative
   rewrite.
3. **Rewrite the horizon.** Long. Only matters when the app is *dead*, in
   which case nothing else is contending. Truncation here costs only the
   stale-count fix, and lands squarely inside the bound
   `docs/handover-2026-08-14-planning.md` §4 already accepts for a mid-apply
   process kill: at worst one duplicate morning notification.

**Two hazards to record, neither of which changes the choice.**

- **`applyDigestPlans`' serialization does not cross isolates.** Its
  `_applyTail` chain is a per-instance `Future` (`lib/application/notification_scheduler.dart`),
  so the isolate's own `NotificationScheduler` and the main isolate's are
  independent and *can* interleave writes to the same 24 ids. The interleave
  is self-correcting whenever it can happen at all: it requires the app to be
  alive, and an alive app receives the ping *after* the isolate's write, so
  the last apply in the main isolate always runs on post-completion data
  (`DigestRescheduleController`'s depth-1 queue makes a trigger arriving
  during an in-flight apply run afterwards, not get dropped). When the app is
  dead there is no second writer at all. Document this at the isolate's call
  site; do **not** attempt a cross-isolate lock.
- **`cancelDigest()` is unserialized against `applyDigestPlans`**
  (`docs/handover-2026-08-14-planning.md` §4) — previously academic because
  there was no concurrent caller. `reset_flow.dart` calls `cancelDigest()`,
  and this plan adds a second *process-level* writer of the same ids, so the
  hazard is now reachable in principle: a wipe racing a notification action.
  The consequence is bounded (a reset that leaves an armed slot behind, fixed
  by the next recompute) and the window is a user physically confirming a
  destructive wipe while also tapping a notification. **Flagged, not fixed
  here** — fixing it means serializing `cancelDigest` onto `_applyTail`,
  which belongs with whoever owns that class next, not bolted onto F-1.

### 4. Locale in the isolate

The isolate constructs its own `NotificationScheduler` for step 3, which
resolves notification copy through `localeResolver`, defaulting to
`ui.PlatformDispatcher.instance.locale`. **Use that default** — do not invent
an isolate-specific locale source. The point is that the isolate and the main
isolate must produce *identical* copy; introducing a second, better rule in
one of them would be a new inconsistency.

Note for the record (**pre-existing defect, explicitly out of scope**): that
default reads the **OS** locale, while the app's UI honours
`localeOverrideProvider` (`lib/app/providers.dart:210`) which is driven by the
persisted `settings.locale`. A user who picks German on an English phone
already gets English digest bodies. F-1 makes this more visible — a *button
label* in the wrong language reads worse than body text — but fixing it means
threading a locale into `NotificationScheduler`, which is E-1's file and E-1's
concern. It needs its own backlog row; raise it in the PR rather than
absorbing it here.

## Platform setup, concretely

*All API shapes below were re-verified against the resolved
`flutter_local_notifications 22.1.0` in the pub cache on 2026-08-17. Note
22.x is the **all-named-parameters** API (the v19 breaking change): every
`initialize`/`zonedSchedule`/`cancel` argument is named. Two exceptions that
bite: `AndroidNotificationDetails`' `channelId`/`channelName` are still
**positional**, and `AndroidNotificationAction`'s `id`/`title` are
**positional**.*

**Android:** no new *permission* (correct per the ticket). It DOES need one
new manifest **receiver** the app doesn't have yet:
`com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver` — required
by the package README ("so that the plugin can process the actions and
trigger the appropriate callback(s)") and present in its example manifest
alongside the two receivers this app already declares
(`ScheduledNotificationReceiver`, `ScheduledNotificationBootReceiver`). The
plugin's own manifest declares no receivers at all, so this must be declared
in the app's manifest.

`AndroidNotificationDetails.actions` is `List<AndroidNotificationAction>?`
(nullable, no default), and `AndroidNotificationAction(id, title, {...})`
takes `id`/`title` positionally with `showsUserInterface = false` and
`cancelNotification = true` as defaults — i.e. **both defaults are already
what we want**, so neither needs passing. Pass `showsUserInterface: false`
explicitly anyway: it is the load-bearing decision (it is what routes to the
background isolate rather than launching the app) and must not read as an
accident.

Action buttons render fine at the digest channel's existing default
importance — **no channel change needed, and none may be made** (see
"Collision: small-fixes-wave E-1": E-1 has just minted `digest_v2`).

**Release-artifact verification.** `docs/handover-2026-08-14-planning.md` §6:
capability boundaries must be checked on the RELEASE artifact, not a debug
run — `release.yml` already asserts `INTERNET` and `allowBackup=false`
fail-closed, from the v0.2.0 incident where a debug-only `INTERNET`
declaration shipped a release with sync dead. `ActionBroadcastReceiver` is a
**component declaration, not a permission**, and it is declared in the main
manifest (not a debug/profile variant), so it is not subject to that exact
failure mode. It is nonetheless a new manifest entry whose absence in a
release build would make "Done" silently do nothing — a failure mode
indistinguishable from a working app until a user taps the button. **State in
the PR that this warrants a release-artifact assertion and leave the
mechanism to the human. Do NOT edit `.github/workflows/release.yml`; that
file is off limits to this plan.**

**iOS:** needs (a) a `DarwinNotificationCategory` with the "Done" action
registered at `initialize()` time
(`DarwinInitializationSettings.notificationCategories`, a non-nullable
`List<DarwinNotificationCategory>` defaulting to const `[]`; the category
takes its `identifier` positionally and `actions` as a named
`List<DarwinNotificationAction>`; `DarwinNotificationAction.plain(identifier,
title, {options})` takes both strings positionally;
`DarwinNotificationDetails.categoryIdentifier` is a nullable named `String?`),
and (b) `ios/Runner/AppDelegate.swift` wiring that the app does not have
today — verified against the plugin's own example `AppDelegate.swift`:
`UNUserNotificationCenter.current().delegate` must be set, and
`FlutterLocalNotificationsPlugin.setPluginRegistrantCallback` must run
*inside* `didInitializeImplicitFlutterEngine`, *before*
`GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)` —
otherwise the background engine's own plugin channels (including drift's
sqlite3 plugin) never get registered and the isolate silently can't do
anything. This file is 100% untestable from `flutter test`; verify manually
on a real device/simulator once (see Testing).

iOS category action titles are fixed at `initialize()` time (`UNNotificationCategory`
has no per-notification title override, unlike Android). Since
`NotificationScheduler.ensureInitialized()` is idempotent for the process's
lifetime, the iOS "Done" label is fixed at whichever locale was active on
the very first `ensureInitialized()` call of that process — same
class of limitation the existing `localeResolver` doc comment already
lives with for the body text refreshing per-call; Android's per-notification
action title has no such staleness. Documented, not solved — a language
change taking a relaunch to fully propagate is normal on both platforms.

## Product decisions — all CLOSED. Do not re-open any of these.

**D1 — Ship "Done" only; "Snooze to tomorrow" is its own ticket.**
**RECORDED AND CLOSED** in `docs/backlog.md`'s F-1 decision row: *"Ship
'Done' only; 'Snooze to tomorrow' becomes its own ticket. Its semantics are
genuinely undefined for the overdue case and would block the unambiguous
half."* This was an open recommendation when the plan was written; it is now a
settled decision. Do not implement Snooze, do not re-litigate it, and do not
"improve" the reasoning below.

*Why:* "Snooze to tomorrow" needs domain semantics that don't exist yet.
`skipOccurrence` advances the chore's *entire* recurrence schedule (wrong —
snoozing shouldn't burn the slot or touch rotation); there is no existing
"shift this one occurrence's due date by a day, keep everything else" op.
Worse, its meaning is genuinely undefined for the overdue case this ticket
also has to handle: does "snooze to tomorrow" on a 3-days-overdue occurrence
make it due tomorrow (quietly erasing how overdue it was) or shift it one
day *from its current due date* (still overdue, just less so — confusing)?
That's a real product call with no derivable answer, and bundling it into
this ticket would block the unambiguous, clearly-scoped "Done" half on it.

**D2 — Attribution is the acting member, not "whoever tapped the phone."**
Identical to the app's existing single-device model for the in-app complete
button — not a new ambiguity this ticket introduces. **Revised:** the acting
member is resolved **in the main isolate and carried in the payload**, not
re-derived in the background isolate; the original plan's isolate-side
fallback chain would have re-introduced the A-5 misattribution in pinned mode.
See "Analysis: what the action payload must carry".

**D3 (new, decided here) — the isolate rewrites the horizon rather than
cancelling it or leaving it.** See "3. The rest of the horizon".

**D4 (new, decided here) — "Done" completes the payload's occurrence row if
still pending, and is otherwise a silent no-op; it does not run catch-up
first, and it accepts recording `done` where in-app catch-up would have
recorded `missed`.** See "What 'Done' means when the slot's date is not
today".

**D5 (new, decided here) — the gate is per slot and is NOT restricted to the
daily segment.** See "The gate is PER SLOT".

## Notification id budget

**This plan spends ZERO new notification ids and must keep it that way.** The
spec's "Notification id budget" section allocates 24 of iOS's 64 to the digest
horizon and reserves the remaining **40** for the unbuilt per-chore reminders
(G-6 / F16). `test/application/notification_scheduler_test.dart` asserts
`digestHorizonSlots <= 32` as the enforcement point.

Notification *actions* attach to existing notifications and consume no ids, so
nothing here touches the budget. Do not add a separate confirmation or
"undone" notification — that would spend G-6's budget, and changing that guard
means renegotiating the split, not editing a number.

## File map

**New:**
- `lib/application/notification_action_processor.dart` — testable
  completion + horizon-rewrite logic (payload → complete → rebuild plans).
- `lib/application/notification_action_handler.dart` — the `@pragma('vm:entry-point')`
  top-level background-isolate entrypoint; thin glue only.
- `test/application/notification_action_processor_test.dart`
- `test/app/notification_action_signal_test.dart`

**Edited:**
- `docs/specs/notifications.md` — new N2 section.
- `lib/domain/digest_projection.dart` + `test/domain/digest_projection_test.dart`
  — `ProjectedOccurrence.id`, `DigestCounts.soleOccurrenceId`.
- `lib/domain/digest_planner.dart` + `test/domain/digest_planner_test.dart`
  — `DigestPlan.soleOccurrenceId`, `planDigestSlot`'s new optional param.
- `lib/application/digest_plan_builder.dart` — thread the occurrence id and
  the resulting `soleOccurrenceId` through; **the single change point that
  serves both `buildDigestPlans` callers.**
- `lib/app/providers.dart` — new `NotificationActionSignalController` +
  provider. **`_recompute` itself needs NO change** (contrary to the original
  plan) — the id is threaded inside `buildDigestPlans`.
- `test/app/digest_reschedule_test.dart` — per-slot payload coverage.
- `lib/application/notification_scheduler.dart` +
  `test/application/notification_scheduler_test.dart` — actionable
  scheduling per slot, localized action title, iOS category.
  **Shared with small-fixes-wave E-1 — re-read before editing.**
- `test/application/fake_digest_notification_plugin.dart` — record the new
  `zonedSchedule`/`initialize` parameters. **Shared with E-1.**
- `lib/data/repositories/chore_repository.dart` +
  `test/data/repositories/chore_repository_test.dart` — one-shot
  `getPendingOccurrences`, `getOccurrence`.
- `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb` — `notificationActionDone`.
  **Shared with E-1 and two other wave-4 plans: append at a distinct
  location, keep it to the one key, and regenerate with `flutter gen-l10n`.**
- `lib/main.dart` — construct `NotificationActionSignalController` alongside
  the other three bootstrap controllers.
- `android/app/src/main/AndroidManifest.xml` — `ActionBroadcastReceiver`.
- `ios/Runner/AppDelegate.swift` — plugin registrant callback + delegate.

**No longer edited** (the original plan listed these; the need has gone away):
- `lib/data/repositories/household_repository.dart` — the one-shot
  `getMembers` existed only to feed the isolate's acting-member chain, which
  the payload replaces. **Do not add it**; an unused public repository method
  is dead code, and `--fatal-infos` will not save you from it.

**Which task makes the behaviour LIVE** — stated because the original plan
did not, and because the P0 plan built five tasks' worth of machinery with
zero callers before anything shipped:
- Tasks 2–3 are inert: they add data that nothing reads yet.
- **Task 4 is the first live task on Android** — the moment the adapter
  attaches `actions`, a real notification grows a visible button. It will not
  *work* yet.
- **Task 8 (manifest receiver) is what makes tapping it do anything on
  Android.** Between Task 4 and Task 8 the app ships a button that silently
  does nothing. If the tasks are split across commits, do not stop in that
  window.
- **Task 9 is the equivalent for iOS**, which is additionally unverified by
  CI: `e2e.yml`'s iOS job is gated on `refs/heads/main` and NEVER runs on a
  PR.

---

## Task 1: Spec first — extend `docs/specs/notifications.md`

**Files:** Edit `docs/specs/notifications.md`.

Add a new section after "## Testing" and before "## Out of scope for N1"
(and amend that out-of-scope line, which currently lists "actions on the
notification" as N2 scope — leave it, but add a forward pointer). Also amend
the **"Notification id budget"** section with one line recording that N2's
actions spend no ids, so the next reader of that budget does not have to
re-derive it.

```markdown
## N2: digest notification actions

Adds a single "Done" action to the digest notification (`docs/backlog.md`
F-1) — NOT the per-chore reminders/evening-re-reminder parts of N2, which
remain unbuilt (G-6). Spends **zero** notification ids: actions attach to the
existing horizon, so G-6's reserved 40 are untouched.

**Gate, evaluated PER SLOT.** The action is attached to a slot IF AND ONLY IF
that slot's own projected counts sum to exactly one occurrence
(`dueTodayCount + overdueCount == 1`) — the only case where "the chore" the
action names is unambiguous. Every other case (silent, or two-or-more) gets no
action; tapping the notification body still opens the app on the chores tab,
unchanged from N1. Slots are judged independently, so actionability is NOT
monotone along the horizon even though the silence decision is — counts only
grow, so a one-occurrence slot is often followed by two-occurrence ones. The
gate is deliberately NOT restricted to the daily segment: a pending slot's
payload is exactly as fresh as the last recompute whether it is slot 0 or
slot 23, and the projection's accuracy is binary and slot-independent.

**What "Done" means.** Complete the specific occurrence ROW named in the
payload, if it is still pending; otherwise do nothing. Deliberately NOT
"complete whatever is due on the date this notification describes" — that is
what makes the answer independent of which slot fired and of how long the
notification sat unread. A row that is no longer pending (completed
elsewhere, or replaced by `catchUpOverdue` after an app open) is a silent
no-op. For a schedule-anchored overdue occurrence this records `done` where
in-app catch-up would have recorded `missed`; that divergence is accepted —
the user is asserting they did it, and `missed` is what catch-up infers from
the absence of any such assertion.

**Not shipped in N2 as scoped here:** "Snooze to tomorrow" — its own ticket
(decision closed in `docs/backlog.md` F-1).

**Payload.** Notification ids are SLOT-RELATIVE (`digestNotificationIdBase +
k`, k = offset from the next slot), so an id names neither a chore nor a date
and cannot be used to address anything; `NotificationResponse.id` is
additionally unreliable on the background path. The payload is therefore the
only channel, and carries JSON `{"v":1,"occ":"<occurrenceId>","by":"<memberId>"|null}`:

- `occ` — the sole pending occurrence's id.
- `by` — the acting member the slot was computed and scoped for, resolved in
  the MAIN isolate. The background isolate must NOT re-derive this: the real
  chain needs `memberIdentityModeProvider`/`currentAuthUserProvider` (a live
  auth session), and in **pinned** mode with no resolvable claim it returns
  `null` rather than guessing — guessing is the misattribution A-5 closed. A
  `null` `by` becomes an unattributed completion.

Action id is namespaced **`digest.done`**; a future per-chore reminder (G-6)
mints its own rather than reusing it, because the background callback is
process-global.

**Handling:** `flutter_local_notifications`'
`onDidReceiveBackgroundNotificationResponse`, a SEPARATE background isolate
with no Riverpod container, no open `AppDatabase`, no `BuildContext`, and no
Supabase session. The top-level entrypoint
(`lib/application/notification_action_handler.dart`) opens its own
`AppDatabase(openConnection())` and, **in this order** (the callback is a
synchronous `void` typedef and the hosting context is time-boxed, so the work
must degrade gracefully if cut short):

1. calls the existing `ChoreService.completeOccurrence(occ, completedBy: by)`
   — the user's intent, must never be lost;
2. pings the main isolate via `IsolateNameServer` (best-effort; a `null`
   lookup means the app isn't running, which is fine);
3. rewrites the WHOLE horizon from the now-updated database via
   `buildDigestPlans` + `applyDigestPlans`, so a device whose app is never
   re-opened is not re-nagged about the chore it was just told is done. This
   is the only correct option: leaving the remaining slots armed means
   knowingly wrong counts, and cancelling them all means up to 83 days of
   silence, at identical cost.

then closes the connection in a `finally`. It never calls `cancel` on a
specific id: `AndroidNotificationAction.cancelNotification` defaults to
`true`, so the tapped notification is dismissed by the platform, and it has
already fired so nothing is pending on its id.

**Known, bounded hazard:** `applyDigestPlans`' `_applyTail` serialization is
per-instance and does NOT cross isolates, so the background isolate and the
main isolate can interleave writes to the same 24 ids. Self-correcting
whenever it can occur — it requires the app to be alive, and an alive app
receives the ping after the isolate's write, so the main isolate's last apply
always runs on post-completion data. Do not attempt a cross-isolate lock.
Relatedly, `cancelDigest()` remains unserialized against `applyDigestPlans`;
with a second process-level writer that is now reachable in principle
(a wipe racing an action) and is tracked rather than fixed here.

**Cross-isolate UI refresh:** the main isolate registers a well-known
`IsolateNameServer` port at bootstrap. On a ping, it invalidates
`pendingOccurrencesProvider`/`closedTodayOccurrencesProvider` (so any open
screen re-reads the file fresh — a write through a second connection is
invisible to the first connection's stream-invalidation bus) and re-runs the
same recompute/push calls the existing app-resume observer already makes. The
invalidate is what guarantees correctness: the recompute fired in the same
handler may read pre-invalidation data, and `DigestRescheduleController`'s
existing `ref.listen` on the invalidated stream is what delivers the correct
second recompute. See `NotificationActionSignalController` in
`lib/app/providers.dart`.

**Platform setup:**
- Android: `AndroidNotificationAction('digest.done', <localized 'Done'>,
  showsUserInterface: false)` in `AndroidNotificationDetails.actions`,
  attached per-notification (so it always uses the current locale) only for
  slots carrying a sole occurrence id. New manifest receiver
  `com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver` (no new
  permission, and **no new channel id** — actions are per-notification, and
  the channel id is E-1's `digest_v2`).
- iOS: `DarwinNotificationCategory('digestActions', actions:
  [DarwinNotificationAction.plain('digest.done', <localized 'Done'>)])`
  registered once at `initialize()` via
  `DarwinInitializationSettings.notificationCategories`, and referenced
  per-notification through `DarwinNotificationDetails.categoryIdentifier`.
  Category action titles are fixed at registration, not per-notification — a
  known, accepted staleness window across a locale change until the next full
  app relaunch. `ios/Runner/AppDelegate.swift` needs
  `UNUserNotificationCenter.current().delegate = self` plus
  `FlutterLocalNotificationsPlugin.setPluginRegistrantCallback` wired
  inside `didInitializeImplicitFlutterEngine`, before the existing
  `GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)`
  call — without it the background engine's other plugins (path_provider and
  sqlite3, which drift needs) never register and the isolate can't touch the
  database.

**Testing:** the completion/attribution/rewrite logic
(`NotificationActionProcessor`) is fully unit-testable against an in-memory
`AppDatabase`, and the ping receiver is testable because `IsolateNameServer`
is same-process. The plugin-level wiring (real background isolate spawn, the
manifest receiver, the AppDelegate change, and whether `openConnection()`'s
path_provider channel lookup succeeds in a background engine) is not
E2E-testable in reasonable time — same carve-out N1's spec already accepts
for fire-time verification — and needs one manual on-device check per
platform before release.
```

No code changes in this task. Commit message: "Spec the F-1 digest notification actions design".

---

## Task 2: `DigestPlan.soleOccurrenceId` (pure domain, INERT)

> **RETARGETED.** The original version of this task called
> `planDigest(now:, digestMinutes:, enabled:, dueTodayCount:, overdueCount:)`.
> That function no longer exists: A-1 split slot arithmetic out of the planner,
> and the planner is now `planDigestSlot({fireAt, enabled, dueTodayCount,
> overdueCount})` with the slot's `fireAt` computed beforehand by
> `digestSlots(...)`. The original's verbatim test and implementation blocks
> were both uncompilable and have been removed rather than patched, so nobody
> is tempted to copy them.

TDD: extend the existing pure-domain test first.

**Files:**
- Edit `test/domain/digest_planner_test.dart`
- Edit `lib/domain/digest_planner.dart`

**What to build.** Add an optional `String? soleOccurrenceId` to `DigestPlan`
(field, constructor param, and inclusion in `==` / `hashCode` / `toString`),
and an optional `String? soleOccurrenceId` parameter to `planDigestSlot` that
is threaded through untouched. `planDigestSlot` stays pure and does **not**
decide the sole occurrence — it carries whatever the caller determined. Task 3
is what determines it.

Document on the field that it is set only when `dueTodayCount + overdueCount
== 1` — the one case where the chore a notification action names is
unambiguous (spec `docs/specs/notifications.md` N2) — and that the class does
not enforce that invariant itself; `projectDigestCounts` does.

**Tests.** Mirror the existing style in `test/domain/digest_planner_test.dart`:
there is already a `group('DigestPlan equality')` (whose "plans differing in
any field are not equal" case must grow the new field) and a
`group('planDigestSlot')` whose "carries both counts and the exact fireAt
through" case is the natural neighbour. Cover:

1. `planDigestSlot` carries a provided `soleOccurrenceId` through unchanged.
2. It is `null` when the parameter is omitted.
3. `==` AND `hashCode` both distinguish two plans differing only in
   `soleOccurrenceId`.

**Expected RED:** a compile error — `planDigestSlot` has no named parameter
`soleOccurrenceId` and `DigestPlan` has no such getter. A *passing* run here
means you added the field before the test; discard and redo. On test 3, note
that forgetting the field in `Object.hash` while remembering it in `==` leaves
the `hashCode` half passing by luck; if you see that combination green, treat
it as a fluke to fix rather than a pass.

**This task ships nothing.** `DigestPlan.soleOccurrenceId` is null everywhere
until Task 3, and nothing reads it until Task 4.

Commit: "Add DigestPlan.soleOccurrenceId".

---

## Task 3: determine the sole occurrence id in the projection (INERT)

> **RETARGETED — this is the task the original got most wrong.** The original
> edited a counting loop inside `DigestRescheduleController._recompute`
> (`lib/app/providers.dart`) and left a note for "whoever re-applies this
> after A-1 lands". That loop no longer exists. Counting is now the pure
> `projectDigestCounts` (`lib/domain/digest_projection.dart`), joined to real
> data by the free function `buildDigestPlans`
> (`lib/application/digest_plan_builder.dart`). **`_recompute` needs no edit
> at all**, and neither does `DigestPrepromptBanner._recomputeDigest` — the
> second caller of the same free function. That is the whole point of the
> extraction, and it means one change point instead of two.
>
> The original also assumed the occurrence id was in scope where the counting
> happens. It is not: `ProjectedOccurrence` carries no id, by design (it is
> "one pending occurrence, reduced to just the fields the projection needs").
> Adding one is part of this task.

**Files:**
- Edit `test/domain/digest_projection_test.dart`
- Edit `lib/domain/digest_projection.dart`
- Edit `lib/application/digest_plan_builder.dart`
- Edit `test/app/digest_reschedule_test.dart`

**What to build, in three steps.**

**3a. `ProjectedOccurrence` gains a required `String id`.** Make it
**required**, not optional: an optional id would silently produce a
never-actionable digest if a future caller forgot it, and the churn is
negligible — there are only two construction sites in the whole tree
(`lib/application/digest_plan_builder.dart`, and a single private
`_occurrence({...})` factory at the top of
`test/domain/digest_projection_test.dart` through which all 25 of that file's
usages funnel; give the helper a defaulted named param and all 25 absorb the
change).

**3b. `DigestCounts` gains `String? soleOccurrenceId`, computed by
`projectDigestCounts`.** This is the right home, and the only correct one: the
sole-occurrence decision must apply **exactly** the same recipient scoping and
the same projected-due-date comparison the counts do, per slot. Determining it
anywhere else duplicates both rules. Include it in `==`/`hashCode`/`toString`.

Semantics: set it to the qualifying occurrence's id when
`dueCount + overdueCount == 1` after the loop, `null` otherwise. The simplest
correct shape is to remember the last qualifying id seen and null it out when
the total is not 1 — the final check enforces the invariant regardless of
iteration order, so no separate match counter is needed.

**3c. `buildDigestPlans` threads it.** Pass `row.occurrence.id` into each
`ProjectedOccurrence`, and pass `counts.soleOccurrenceId` into
`planDigestSlot`. Two one-line changes in
`lib/application/digest_plan_builder.dart`; **no change to either caller.**

**Tests — projection (`test/domain/digest_projection_test.dart`).** Mirror the
existing `group('projectDigestCounts')` cases. Cover:

1. Exactly one occurrence due on the queried date → `soleOccurrenceId` is that
   occurrence's id.
2. Exactly one occurrence *overdue* as of the queried date, none due →
   `soleOccurrenceId` is that occurrence's id (an overdue-only slot is still
   actionable).
3. Two occurrences → `null`.
4. Zero → `null`.
5. **Scoping is respected:** two occurrences of which one belongs to a
   partner, queried for a recipient → the recipient's own id, *not* `null`.
   This is the case that catches computing the sole id before scoping instead
   of after, which would silently make the action vanish in every two-person
   household. Mirror the existing "scoping is applied before projection, not
   after" test's setup.
6. **Projection is respected:** a schedule-anchored occurrence that rolls
   forward is still the sole id at a date where it is the only thing
   contributing.

Do **not** add `soleOccurrenceId` assertions to the 120-day monotonicity
group. Actionability is deliberately non-monotone (see "The gate is PER SLOT")
and asserting otherwise there would be wrong.

**Expected RED for 3a/3b:** compile errors — `_occurrence` has no `id`
parameter and `DigestCounts` has no `soleOccurrenceId` getter.

**Tests — end to end through the horizon (`test/app/digest_reschedule_test.dart`).**
Mirror the file's existing `testWidgets` + `ProviderContainer` +
`_awaitBootstrap` + `tester.pump(digestRescheduleDebounce)` pattern exactly;
read the file's header comment first — it documents why `_awaitBootstrap`
polls instead of awaiting, and it is the reference for this whole class of
test. Do NOT hand-roll a pump. Note these tests need `payload` on the fake's
`ScheduledCall`, which Task 4 adds, so either do Task 4's fake/interface edit
first or land the two together.

Cover, at minimum:

1. **One due-today chore, nothing else** → the slot-0 notification carries a
   payload naming that chore's pending occurrence id (fetch it via
   `ChoreRepository.pendingOccurrenceOf` rather than hardcoding).
2. **Two due-today chores** → slot 0 carries no payload.
3. **The case only a horizon has:** one due-today chore plus one due on a
   *later* slot's date. Assert slot 0 IS actionable and the later slot is NOT
   — the same recompute must produce different actionability per slot. **This
   is the assertion that would catch a global rather than per-slot gate, and
   the equivalent test could not exist on a single-notification digest.** Pick
   the second chore's start date so it lands inside the daily segment
   (`digestDailyHorizonDays = 14`), and derive the slot index from
   `digestSlots(...)` rather than hardcoding it.

**Watch for size-coupled fixtures.** Wave 3's digest change broke an unrelated
catch-up test whose fixture date had been chosen relative to the old horizon
length. Before pushing, grep the suite for tests asserting on
`scheduledCalls`/`pending` lengths or on absolute `fireAt` dates, and check
none of them is counting payload-bearing calls.

**Expected RED for the reschedule tests:** they compile (once the fake has
`payload`) and fail on the assertion — `payload` is `null` on every call
because nothing threads the id yet. A green run before 3c means the assertion
is not reading what you think it is; check the slot index.

**This task still ships nothing user-visible.** The payload is computed and
handed to `applyDigestPlans`, but the adapter drops it until Task 4.

Commit: "Determine the sole pending occurrence per digest slot".

---

## Task 4: actionable scheduling per slot — FIRST LIVE TASK (Android UI)

> **RETARGETED.** The original wrote `scheduleDigest(DigestPlan)`, which does
> not exist, and hardcoded the channel name `'Daily summary'`, which E-1 has
> since replaced with a localized `channelName`/`channelDescription` pair. The
> verbatim interface and adapter blocks have been replaced with a delta
> specification for that reason: **the file's real shape after E-1 merges is
> the source of truth, not any snippet here.** Re-read
> `lib/application/notification_scheduler.dart` and
> `test/application/fake_digest_notification_plugin.dart` before writing a
> line.

**This is the first task whose effect a user can see.** The moment the adapter
attaches `actions`, a real digest notification grows a visible "Done" button.
It will not *work* until Task 8 (Android) / Task 9 (iOS). Do not leave the
branch parked in that window.

TDD: scheduler tests first.

**Files:**
- Edit `test/application/fake_digest_notification_plugin.dart`
- Edit `test/application/notification_scheduler_test.dart`
- Edit `lib/application/notification_scheduler.dart`
- Edit `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`

**l10n.** One key, `notificationActionDone` — `"Done"` in `app_en.arb` with an
`@notificationActionDone` description block, `"Erledigt"` in `app_de.arb`.
**`app_de.arb` carries NO `@`-metadata blocks** (the original plan claimed it
did; it does not — every description lives in the template). Append near the
existing `notificationDigest*` entries, keep it to this one key (three wave-4
plans touch these files), and regenerate with `flutter gen-l10n` — never
hand-edit `app_localizations*.dart`.

**Two new top-level constants** in `notification_scheduler.dart`:
`digestActionsCategoryId = 'digestActions'` and
`digestDoneActionId = 'digest.done'`. The action id is namespaced — see
"Analysis: what the action payload must carry" for why a bare `'done'` is
wrong.

**Interface delta on `DigestNotificationPlugin`** (add to whatever the members
look like after E-1; do not retype the whole interface):

- `initialize()` gains `required String doneActionTitle`. Used only for the
  iOS category registration; Android's action title is set per notification.
- `zonedSchedule(...)` gains `String? payload` and `bool actionable = false`.
  It already has `id`/`title`/`body`/`fireAt` and, post-E-1,
  `channelName`/`channelDescription`.

Document on `zonedSchedule` that `payload` is the JSON action payload and is
non-null exactly when `actionable` is true, and that `actionable` attaches the
localized "Done" action — Android per-notification, iOS via the
`digestActionsCategoryId` category registered in `initialize`.

**`FakeDigestNotificationPlugin` / `ScheduledCall`:** record
`doneActionTitle` (as `String? lastDoneActionTitle`) and add `payload` and
`actionable` to `ScheduledCall`. The fake also maintains a `pending` map and a
`deliverDue` simulator that the original plan predates — preserve both; the
horizon regression tests depend on them.

**`NotificationScheduler` changes:**
- `ensureInitialized()` resolves the l10n once and passes
  `doneActionTitle: l10n.notificationActionDone` to `plugin.initialize(...)`.
  It must keep whatever E-1 added there (the `deleteLegacyDigestChannel()`
  call) and stay idempotent.
- `_applyDigestPlansNow`'s per-slot loop passes
  `payload: <encoded payload for this plan>` and
  `actionable: plan.soleOccurrenceId != null`.

**Where does the member id come from?** `DigestPlan` does not carry it, and it
should not: it is a property of the whole recompute, not of one slot. Add it as
a parameter of `applyDigestPlans` — `applyDigestPlans(List<DigestPlan?> plans,
{String? actingMemberId})` — and pass it from both `buildDigestPlans` callers,
which already read `actingMemberProvider` on the very next line
(`lib/app/providers.dart:1106`,
`lib/features/chores/digest_preprompt_banner.dart:129`). Keep it optional so
the existing arity check and every existing test keep working unchanged.

*(Alternative considered and rejected: putting `actingMemberId` on `DigestPlan`
next to `soleOccurrenceId`. It would be identical on all 24 entries, would have
to enter `==`/`hashCode` for no benefit, and would push an application-layer
identity into a pure-domain value.)*

**Encoding the payload.** A small private helper in
`notification_scheduler.dart` producing `jsonEncode({'v': 1, 'occ': ...,
'by': ...})`, with the matching decoder in Task 5's processor. Put the version
number and both key names in named constants shared by encoder and decoder so
the pair cannot drift.

**`FlutterLocalNotificationsAdapter` changes:**
- `initialize` registers a `DarwinNotificationCategory(digestActionsCategoryId,
  actions: [DarwinNotificationAction.plain(digestDoneActionId,
  doneActionTitle)])` through
  `DarwinInitializationSettings.notificationCategories`, and passes
  `onDidReceiveBackgroundNotificationResponse: <Task 6's entrypoint>`.
  `initialize`'s `settings:` argument is **named and required** in 22.x.
- `zonedSchedule` passes `payload: payload`; sets
  `AndroidNotificationDetails.actions` to a one-element list when `actionable`
  (`AndroidNotificationAction(digestDoneActionId, _doneActionTitle,
  showsUserInterface: false)` — `id`/`title` are **positional**; `false` is
  already the default but pass it, it is the load-bearing decision) and `null`
  otherwise; and sets `DarwinNotificationDetails.categoryIdentifier` to
  `digestActionsCategoryId` when `actionable`, `null` otherwise.
- The `const` on `NotificationDetails`/`AndroidNotificationDetails`/
  `DarwinNotificationDetails` has to come off now that fields are conditional.
  The compiler will say so.
- Leave `androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle`, the
  `tz.UTC` conversion, and both of their doc comments exactly as they are —
  they encode deliberate spec decisions ("do NOT 'upgrade' this to an exact
  schedule mode").

**Tests** (`test/application/notification_scheduler_test.dart`; the file
already has `group('applyDigestPlans')` with a `plansOf({})` helper that builds
a full-length horizon from a sparse map — use it):

1. A slot whose plan has a `soleOccurrenceId` is scheduled `actionable: true`
   with a payload that **decodes** to `{v: 1, occ: <id>, by: <member>}`. Assert
   on the decoded map, never on a hand-written JSON string — string equality
   would pin key order, which `jsonEncode` does not guarantee.
2. A slot whose plan has none is scheduled `actionable: false`,
   `payload: null`.
3. **Mixed horizon in one apply:** slot 0 actionable, slot 5 not. This is the
   assertion that catches "actionable" being decided once per apply instead of
   once per slot.
4. `ensureInitialized` passes the localized Done title (`'Done'` under the
   default `Locale('en')` the file's `setUp` already pins).
5. German locale localizes it to `'Erledigt'` — mirror the file's existing
   German-copy test, which builds a second scheduler with
   `localeResolver: () => const Locale('de')`.
6. `actingMemberId: null` still yields a valid payload with `by: null`. The
   unattributed case must neither crash nor silently drop the action.

**Expected RED, in three distinct stages** — they are all legitimate reds but
they are *different* reds, so do not mistake the first for the last and skip
ahead: (a) compile failure against the fake (no `payload`/`actionable`/
`lastDoneActionTitle`); then (b) compile failure against `lib/` (no such
parameters on `DigestNotificationPlugin`); then (c) real assertion failures. A
green run at any point before the scheduler change is vacuous.

**Do not touch** the `digestHorizonSlots <= 32` budget test or the
`digestNotificationIds` consecutiveness test. If either goes red you have
changed the horizon, which this plan must not do.

Commit: "Attach a localized Done action to single-occurrence digest slots".

---

## Task 5: `NotificationActionProcessor` — the testable core

> **RETARGETED.** The original resolved the acting member inside this file, via
> a `_resolveActingMemberId` reimplementing "stored id, else first admin, else
> first member" on top of a new `HouseholdRepository.getMembers`. **Do not
> build that.** That chain is only `actingMemberProvider`'s *unpinned* branch;
> the real provider (`lib/app/providers.dart:881`) consults
> `memberIdentityModeProvider` first and, in **pinned** mode with no resolvable
> claim, deliberately returns `null` rather than guessing — the guess being
> exactly the misattribution A-5 closed. Reimplementing it here would
> re-introduce A-5 for every linked household, and it cannot be implemented
> correctly anyway without a live Supabase session the isolate must not have.
> The member id arrives in the payload instead. `HouseholdRepository.getMembers`
> is therefore **not** to be added — an unused public repository method is dead
> code and `--fatal-infos` will not catch it.
>
> The original also had this file do only the completion. It now also owns the
> horizon rewrite, so that the isolate's entrypoint stays untestable glue and
> everything with a decision in it is unit-tested.

TDD: test first, against a real in-memory `AppDatabase` (per Global
Constraints — nothing mocked).

**Files:**
- Create `test/application/notification_action_processor_test.dart`
- Create `lib/application/notification_action_processor.dart`
- Edit `lib/data/repositories/chore_repository.dart`
- Edit `test/data/repositories/chore_repository_test.dart`

### 5a. Two one-shot reads on `ChoreRepository`

Both are needed because the background isolate has no Riverpod container to
hold a stream subscription open, and awaiting a drift stream is the deadlock
this project has been bitten by before.

**`Future<ChoreOccurrence?> getOccurrence(String occurrenceId)`** — an
occurrence looked up by id regardless of which chore owns it. Verified: this
does not exist today. `ChoreService` has a private `_findOccurrence` doing
exactly this query, and `ChoreRepository`'s own doc comments say it "only
exposes chore-scoped occurrence lookups". Add the public one and **make
`ChoreService._findOccurrence` delegate to it** rather than leaving a second
copy of the same query — the file is already open and a third copy is how the
next one appears.

**`Future<List<OccurrenceWithChore>> getPendingOccurrences(String householdId)`**
— the one-shot twin of `watchPendingOccurrences`, needed for the horizon
rewrite. `getActiveChores`/`watchActiveChores` are the house-style precedent
for exactly this pair, and they share their row mapping through the private
`_choreDetailsFromRows` ("Shared so the two query methods can't drift apart").
`watchPendingOccurrences` does **not** yet have that shape — its mapping is an
inline collection-for inside the `.map()` closure. So: **hoist the mapping into
a private synchronous `_occurrencesWithChoreFromRows(List<TypedResult>)`
first** (it needs no per-row follow-up query, unlike `_choreDetailsFromRows`,
so it stays sync), then have both the stream and the one-shot use it. Duplicating
the query *builder* between the two matches what `getActiveChores` already
does; duplicating the *mapping* does not and must not happen.

Keep the identical filters — `chores.householdId`, `chores.deletedAt.isNull()`,
`chores.pausedAt.isNull()`, `status == pending` — and the identical
`orderBy(dueDate, chores.title)`. A divergence here would make the isolate's
horizon disagree with the app's for reasons no test would explain.

**Tests** (`test/data/repositories/chore_repository_test.dart`, alongside the
existing `watchPendingOccurrences` cases — mirror their seeding, do not invent
a new pattern): `getPendingOccurrences` returns the same rows in the same order
as the stream's first emission for a seeded household; it excludes paused and
soft-deleted chores; `getOccurrence` returns a seeded occurrence and `null` for
an unknown id.

**Expected RED:** compile errors — no such methods. Then, for the
same-as-the-stream test specifically, beware a vacuous pass: if you seed only
one chore, "same order" holds trivially. Seed at least three with due dates
that make the ordering non-alphabetical, so a wrong `orderBy` actually fails.

### 5b. `NotificationActionProcessor`

A library with two top-level functions and a payload codec. No class needed; it
holds no state.

**`DigestActionPayload` (decode side of Task 4's encoder).** Parse the JSON,
tolerate garbage. It must return `null` — never throw — for: malformed JSON, an
unknown `v`, a missing or empty `occ`. The payload arrives from the OS across a
process boundary and may have been written by a previous app version. Share the
version and key-name constants with the encoder.

**`Future<void> applyDoneAction({required AppDatabase database, required
String occurrenceId, required String? actingMemberId, Clock clock = const
Clock()})`**

Behaviour, in order:
1. `getOccurrence(occurrenceId)`; return if `null` or not
   `OccurrenceStatus.pending`. Silent no-op — the definition in "What 'Done'
   means" — not an error. There is no UI to report to and "someone already
   handled it" is a success.
2. `ChoreService(database: ..., chores: ChoreRepository(database), clock:
   clock).completeOccurrence(occurrenceId, completedBy: actingMemberId)`.
   `actingMemberId` is passed straight through, `null` included: an
   unattributed completion is the honest answer when identity is unknown, and
   is what A-5's "never guess" posture requires.
3. `ChoreService._closeAndAdvance` **throws `StateError`** when the occurrence
   is not pending (verified in `lib/application/chore_service.dart` — it is a
   throw, not a silent return, so the original plan's `on StateError` catch was
   correct). Catch it and treat it as the same silent no-op: it means something
   closed the row between step 1's read and step 2's transaction. Catch
   `StateError` specifically, not `on Object` — this is a narrow known race,
   not a safety net around a destructive user action.

Note it deliberately does NOT run `catchUpOverdue` first (decision D4) and does
NOT touch notifications; scheduling is the next function's job.

**`Future<void> rewriteDigestHorizon({required AppDatabase database, required
NotificationScheduler scheduler, required String? actingMemberId, Clock clock =
const Clock()})`**

Reads `SettingsRepository(database).ensureSettings()` and
`ChoreRepository(database).getPendingOccurrences(household.id)`, calls the
existing free function `buildDigestPlans(now:, settings:, pending:,
recipientMemberId: actingMemberId)`, and hands the result to
`scheduler.applyDigestPlans(plans, actingMemberId: actingMemberId)`. No new
planning logic — reusing `buildDigestPlans` is the whole reason this is
affordable, and re-deriving counts here would be a defect.

Needs the household id: `HouseholdRepository(database).getHousehold()`; return
early if `null`. Note `ensureSettings()` **writes** a row if none exists (it is
not a pure read) — harmless here and consistent with every other caller, but
know that it does.

Document at this function's body the two hazards from
"3. The rest of the horizon": `applyDigestPlans`' serialization does not cross
isolates (self-correcting via the ping, do not add a lock), and `cancelDigest`
remains unserialized against it.

**Tests** (`test/application/notification_action_processor_test.dart`) — real
in-memory `AppDatabase`, real repositories and `ChoreService`, fixed clock, no
`ProviderContainer` and no widget pump needed since none of this touches
Riverpod. For the seeding of a second member and of a rotation chore, mirror
`test/application/chore_service_test.dart`; do not invent a new pattern.

1. Completes a pending occurrence and attributes it to the passed
   `actingMemberId`.
2. `actingMemberId: null` completes it with `completedBy` null — and **assert
   `completedBy` is null explicitly**, not merely that the status is `done`. A
   status-only assertion would pass even if the code invented a member.
3. Silent no-op when the occurrence is already closed (must not throw; assert
   the closed row's `completedBy` is *unchanged*, so a no-op that actually
   re-wrote the row still fails).
4. Silent no-op for an unknown occurrence id (must not throw).
5. A rotation chore still advances and rotates: complete via `applyDoneAction`
   and assert the newly-inserted pending occurrence's assignee advanced. This
   proves the real `ChoreService` path is used rather than a hand-rolled
   shortcut. Mirror the rotation assertions in `chore_service_test.dart`.
6. Payload codec: round-trips the encoder's output; returns `null` for
   malformed JSON, for an unknown `v`, and for a missing `occ`.
7. `rewriteDigestHorizon` against a `FakeDigestNotificationPlugin`: after
   completing the only due chore, the rewritten horizon has **nothing armed**
   for that chore — i.e. every slot is cancelled. **This is the test that
   proves the stale-body fix**, and the one whose absence would let the whole
   point of D3 ship broken.
8. `rewriteDigestHorizon` scopes to `actingMemberId`: with a partner's chore
   pending and `actingMemberId` set to the other member, the rewritten horizon
   ignores it. Guards against passing `null` through by accident, which would
   silently widen every digest to household-wide.

**Expected RED:** compile failure (no such library) → then, for test 7
specifically, the pre-fix failure mode is that slots remain armed with a count
of 1. If test 7 passes before `rewriteDigestHorizon` exists, you have asserted
on an empty fake; check the fake actually received calls (`initializeCallCount`
> 0) before trusting an "everything cancelled" assertion.

Commit: "Add NotificationActionProcessor for the digest Done action".

---

## Task 6: the background isolate entrypoint

Not unit-tested: real isolate/plugin glue, the same carve-out this codebase
already applies to `FlutterLocalNotificationsAdapter` itself (no direct test;
covered only through `NotificationScheduler` against the fake). Keep this file's
logic at the unavoidable minimum so nothing with a decision in it is untested.

**Files:** Create `lib/application/notification_action_handler.dart`.

**Two corrections to the original, both of which would not have compiled or
would have been dead code:**

1. **The callback typedef is `void Function(NotificationResponse)` — synchronous
   `void`, not `Future<void>`.** A declared `Future<void> Function(...)` will
   not type-check against
   `onDidReceiveBackgroundNotificationResponse`. Write a `void` top-level
   function that kicks off an `async` inner future; nothing awaits it, which is
   precisely why the work is ordered by decreasing importance (see below).
2. **Drop `DartPluginRegistrant.ensureInitialized()`.** The plugin's own
   `callback_dispatcher.dart` already calls
   `WidgetsFlutterBinding.ensureInitialized()` before invoking our callback,
   and that initialises the plugin registrant. The original called it "the
   standard pattern other background-isolate plugins use"; here it is dead
   code.

**What the file contains:**

- `const String notificationActionPortName = 'chore_app.notification_action'` —
  the well-known `IsolateNameServer` port name the main isolate registers
  (Task 7) and this handler pings.
- A top-level `@pragma('vm:entry-point')` **`void`** function. The pragma and
  top-level-or-static placement are hard requirements: the plugin looks the
  callback up by its compile-time handle from a fresh isolate that has never
  run any of this app's other code, and without the pragma the compiler strips
  it. Do not make it an instance method or a closure.

**What it does, in this exact order — the order is the design (see "Order the
isolate's work by decreasing importance"):**

1. Return immediately unless `response.actionId == digestDoneActionId`. **Do
   not read `response.id`** — it is meaningless (slot-relative) and unreliable
   (`callback_dispatcher.dart` substitutes `-1`). Do not read
   `notificationResponseType` either: the background path hardcodes it to
   `selectedNotificationAction` regardless.
2. Decode `response.payload` via Task 5's codec; return on `null`.
3. Open `AppDatabase(openConnection())`, wrapped so it is closed in a
   `finally`.
4. `applyDoneAction(...)` with the payload's `occ` and `by`. **The user's
   intent; must never be lost.**
5. `IsolateNameServer.lookupPortByName(notificationActionPortName)?.send(null)`
   — best-effort. A `null` lookup means the app is not running, which is fine.
   Sent *before* the horizon rewrite so an alive app starts its own
   authoritative recompute as early as possible.
6. `rewriteDigestHorizon(...)` with a `NotificationScheduler(plugin:
   FlutterLocalNotificationsAdapter())`. Long, and only matters when the app is
   dead. **Use the scheduler's default `localeResolver`** — see "4. Locale in
   the isolate": the isolate and the main isolate must produce identical copy.
7. Close the connection.

Wrap steps 4–6 so that a throw in the rewrite cannot swallow a successful
completion, and comment at the site *why* the order is what it is — an
"optimisation-minded" future reader will otherwise reorder it.

Commit: "Add the background notification-action entrypoint".

---

## Task 7: `NotificationActionSignalController` — the receiving side

TDD: this one CAN be tested — `IsolateNameServer` is a same-process, same-VM
registry, so a test can look up the port the controller registered and `.send()`
to it directly, no real isolate spawn needed.

> **RETARGETED, lightly.** The design is unchanged; the original's verbatim test
> has been replaced by a requirements list, because it was transcribed from
> memory and its final assertion (`expect(plugin.scheduledCalls, isNotEmpty)`)
> is **vacuous under the horizon**: with 24 slots, a bootstrap recompute already
> fills `scheduledCalls`, and even after `.clear()` an `isNotEmpty` would pass on
> any recompute for any reason — including one triggered by the chore creation
> in the test's own setup rather than by the ping. It also cannot distinguish the
> ping's own recompute from the one the invalidated stream triggers, which is the
> distinction that matters (see "Ordering subtlety" above).

**Files:**
- Create `test/app/notification_action_signal_test.dart`
- Edit `lib/app/providers.dart`
- Edit `lib/main.dart`

**What to build.** A `NotificationActionSignalController` with the same shape as
`DigestRescheduleController` / `CatchUpController` / `SyncEngineController`,
including their shared "never read from the widget tree; constructed once from
`main.dart` before `runApp`" discipline — copy the reasoning from their doc
comments rather than restating it.

- Constructor: `IsolateNameServer.removePortNameMapping(...)` then
  `registerPortWithName(...)` (remove-first so a hot restart, which leaves the
  old mapping behind, does not fail the registration), and subscribe to the
  `ReceivePort`.
- `dispose()`: cancel the subscription, close the port, remove the mapping.
  Wired via `ref.onDispose` in the provider.
- On a ping: `invalidate(pendingOccurrencesProvider)`,
  `invalidate(closedTodayOccurrencesProvider)`, then
  `digestRescheduleControllerProvider.triggerRecompute()` and
  `syncEngineControllerProvider.triggerOnResume()` — the same calls
  `main.dart`'s `_AppResumeObserver` already makes. `triggerOnResume()` returns
  `void` and wraps its own fire-and-forget push, so no `unawaited` is needed
  here, mirroring that observer's own call site.

Document at `_onPing` **why the invalidate is the part that guarantees
correctness**: the write came through a *separate* `AppDatabase` connection, so
drift's stream-invalidation bus never saw it; and the `triggerRecompute()` fired
in the same handler may still read pre-invalidation data, with the *correct*
recompute arriving via `DigestRescheduleController`'s existing `ref.listen` on
the freshly-emitting stream. The explicit trigger is a latency optimisation, not
the mechanism.

**`lib/main.dart`:** `container.read(notificationActionSignalControllerProvider)`
alongside the other three, before `runApp`. No lifecycle-observer wiring — it has
no on-resume behaviour, it only reacts to pings; it just has to be constructed
once so `ref.onDispose` does not fire until the container is torn down.

**Test requirements** — mirror `test/app/digest_reschedule_test.dart` exactly
(its `ProviderContainer` + `_awaitBootstrap` + `tester.pump(digestRescheduleDebounce)`
pattern, `driftRuntimeOptions.dontWarnAboutMultipleDatabases = true` in
`setUpAll`, `addTearDown(container.dispose)`, and `await database.close()` as the
last statement *inside* the test body). Read its header comment first.

1. **The port is registered at construction.**
   `IsolateNameServer.lookupPortByName(notificationActionPortName)` is non-null
   after reading the provider, and **null again after `container.dispose()`** —
   assert both. Without the second half, a leaked mapping across tests would go
   unnoticed and would break the *next* test's registration.
2. **A ping causes a recompute that reflects a change made outside the app.**
   Seed a household, activate the controllers, let bootstrap settle, then make a
   change and ping. Assert on the *content* of what ends up armed — e.g. a chore
   created after the last recompute appears in the rewritten horizon's bodies or
   payloads — **not** on `scheduledCalls` being non-empty. Pump long enough for
   the invalidated stream's fresh emission to land and drive its own recompute,
   not just for the ping's immediate one.
3. **A ping with no listener does not throw.** Look up and send to the port
   after disposing the container, or simply assert the lookup is null and that
   the handler's `?.send` shape tolerates it. This is the app-not-running path
   the isolate relies on.

**Expected RED:** test 1 fails at compile (no such provider or constant), then
on the assertion (nothing registered). Test 2's pre-fix failure mode is that
the horizon still describes the pre-change state — if it passes before the
controller exists, the change is being picked up by an unrelated trigger
(`DigestRescheduleController` listens to `pendingOccurrencesProvider` already,
so a change made through the *same* connection recomputes on its own). **That is
the trap in this test.** To avoid a vacuous pass, make the change in a way the
in-app stream cannot see, or assert on the recompute count rather than the
content; if neither is practical, state in the test's own comment that it covers
the ping *wiring* only and that the cross-connection invisibility is covered by
Task 5's tests plus the manual check in Task 10. Do not let it silently look
like more than it is.

Commit: "Wire the notification-action cross-isolate ping to a UI refresh".

---

## Task 8: Android manifest receiver — MAKES "DONE" WORK ON ANDROID

**Files:** Edit `android/app/src/main/AndroidManifest.xml`.

**This is the task that makes Task 4's button functional on Android.** Between
Task 4 and this one the app ships a visible "Done" that silently does nothing.

```xml
<!-- flutter_local_notifications (spec docs/specs/notifications.md N2):
     required for notification ACTION buttons (the digest's 'Done' action)
     to reach the background isolate handler. Required by the package's own
     README and present in its example manifest; the plugin's own manifest
     declares no receivers at all. No new permission needed -- this is a
     component declaration, not a permission. -->
<receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver" />
```

Place it next to the existing `ScheduledNotificationReceiver` /
`ScheduledNotificationBootReceiver` declarations, inside `<application>`, and
match the surrounding comment style — that block already explains why no
`SCHEDULE_EXACT_ALARM` receiver is registered, and this one should read as part
of the same explanation.

**Release-artifact verification.** Not unit-testable, and its absence in a
release build would look exactly like a working app until someone taps the
button. `docs/handover-2026-08-14-planning.md` §6 is emphatic that capability
boundaries are verified on the RELEASE artifact, not a debug run — that lesson
came from a debug-only `INTERNET` declaration shipping a release with sync
dead. This declaration lives in the main manifest, so it is not subject to that
exact variant-shadowing failure, but it is still an untested capability edge.
**Say so in the PR and leave the mechanism to the human. Do NOT edit
`.github/workflows/release.yml`** — that file is off limits to this plan.

Verify manually (Task 10).

Commit: "Register the notification-action broadcast receiver on Android".

---

## Task 9: iOS AppDelegate wiring — MAKES "DONE" WORK ON iOS

**Files:** Edit `ios/Runner/AppDelegate.swift`.

**This is Task 8's iOS equivalent, and it is the least verifiable task in the
plan.** `e2e.yml`'s iOS job is gated on `refs/heads/main` and NEVER runs on a
pull request, so nothing in CI will exercise this before it merges. Treat the
manual check as the only gate.

The file today is the Flutter template plus a bare
`GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)` inside
`didInitializeImplicitFlutterEngine`. Two additions:

```swift
import Flutter
import UIKit
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // Required so the BACKGROUND engine spawned for notification actions
    // (spec docs/specs/notifications.md N2) registers every other plugin
    // into itself -- specifically path_provider and sqlite3_flutter_libs,
    // which drift's openConnection() needs. Without this the background
    // isolate's AppDatabase(openConnection()) call fails, and it fails
    // silently: there is no UI to report to. Verified against
    // flutter_local_notifications' own example AppDelegate.swift. Must run
    // BEFORE the GeneratedPluginRegistrant call below.
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { (registry) in
        GeneratedPluginRegistrant.register(with: registry)
    }
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
```

Not unit-testable, and not compiled by `flutter test` or by the Android CI
jobs either — a syntax error here surfaces only in an iOS build. Verify
manually (Task 10).

Commit: "Wire iOS background-isolate plugin registration for notification actions".

---

## Task 10: manual on-device verification (not automatable)

Not a code task — a checklist to run once per platform before this ships,
mirroring the spec's existing "fire-time verification is NOT E2E-testable"
carve-out. **Three of these items are gates on design decisions this plan could
not verify from source; they are marked GATE and their fallbacks are stated so
whoever runs them does not have to re-derive the alternative.**

- [x] **GATE — the background isolate can open the database at all.** **CONFIRMED on a real Android device against v0.7.0 (build 10), 2026-08-18** (reported by Igor): tapping "Done" on the digest marks the chore done in the app. So `openConnection()`'s `path_provider` channel lookup DOES work in the background engine, the fallback below was not needed, and Tasks 7-9 no longer rest on an unverified premise. Original check, kept for the record: Android:
      one due-today chore, force the digest (temporarily set the digest time a
      minute out), tap "Done" **with the app fully swiped away**, confirm the
      chore shows as done on next app open. If it does not, the likely cause is
      `openConnection()`'s `path_provider` channel lookup failing in the
      background engine. *Fallback:* give the isolate an explicit database file
      path instead of a channel lookup — `AppDatabase` takes a plain
      `QueryExecutor`, so this is a change of executor, not of the class. See
      "1. Opening a second DB connection safely". **Run this immediately after
      Task 6; everything after it depends on it.**
- [ ] **GATE — a foreground tap routes to the background isolate.** Same setup,
      but with the app **open in the foreground** when the shade is pulled down
      and "Done" tapped. Confirm the chores list updates within about half a
      second with no further user action (this exercises the
      `IsolateNameServer` ping, not the app-resume path). If instead nothing
      happens until backgrounding, or if the app visibly restarts, the routing
      assumption is wrong. *Fallback:* handle the foreground case through
      `onDidReceiveNotificationResponse` in the main isolate, where a live
      Riverpod container makes it far simpler, and keep the background path for
      the app-dead case. See the "Rely solely on the existing app-resume
      observer" bullet.
- [ ] **GATE — the isolate survives long enough to rewrite the horizon.** With
      a single **one-off** (non-recurring) chore, tap "Done" with the app swiped
      away, then wait for the next digest slot without opening the app. Confirm
      **no** notification arrives claiming an overdue chore. If one does, the
      rewrite was truncated by the hosting broadcast receiver. *Fallback:*
      accept the truncation and document it — the bound is the one
      `docs/handover-2026-08-14-planning.md` §4 already accepts for a mid-apply
      process kill. Do not respond by switching to `cancelDigest()`; that
      trades one wrong notification for up to 83 days of silence.
- [ ] Two due-today chores: confirm NO action button appears on the digest, and
      that tapping the notification body still opens the app on the chores tab.
- [ ] A slot beyond the daily segment: seed work such that a slot ~3 weeks out
      is the sole-occurrence one, and confirm the button is attached there too
      (the gate is deliberately not restricted to the daily segment — decision
      D5).
- [ ] Tap "Done" a second time on an already-actioned or removed notification
      (a stale shade entry, if reproducible) — confirm no crash and no
      duplicate completion.
- [ ] iOS: repeat the first three GATE items, plus confirm the tapped
      notification is dismissed on action tap (assumed, not verified from
      source — on Android `AndroidNotificationAction.cancelNotification`
      defaults to `true`, and the design relies on the equivalent iOS
      behaviour).
- [ ] iOS: switch the device language and relaunch, confirm the "Done" label
      follows on the *next full relaunch* and not before (the known, accepted
      `UNNotificationCategory` staleness — verify it is a relaunch and not
      "never").
- [ ] Release-artifact check that `ActionBroadcastReceiver` is present in the
      built release APK (see Task 8 — mechanism left to the human; do not edit
      `release.yml`).

Not committed as code; record results in the PR description when this plan's
work is submitted for review, including which GATE fallbacks (if any) were
taken.

---

## Task list summary

1. Spec: extend `docs/specs/notifications.md` (N2 section) and its
   "Notification id budget".
2. `DigestPlan.soleOccurrenceId` + `planDigestSlot` param — pure domain, inert.
3. `ProjectedOccurrence.id` + `DigestCounts.soleOccurrenceId` +
   `buildDigestPlans` threading — inert. **Neither `_recompute` nor the
   pre-prompt banner is edited.**
4. `NotificationScheduler`/`DigestNotificationPlugin`/adapter: per-slot
   actionable scheduling, payload encoding, iOS category, l10n. **First task
   with a user-visible effect.**
5. `NotificationActionProcessor` + payload codec + `ChoreRepository.getOccurrence`
   / `getPendingOccurrences` — the unit-tested core, completion *and* horizon
   rewrite.
6. Background isolate entrypoint (untested glue, `void` callback).
7. `NotificationActionSignalController` — cross-isolate ping receiver.
8. Android manifest receiver. **Makes "Done" functional on Android.**
9. iOS AppDelegate wiring. **Makes "Done" functional on iOS; unverified by CI.**
10. Manual on-device verification checklist, with three design GATEs.

10 tasks, 2 of which (8, 9) are single-file platform config edits and one
(10) is a manual checklist — 7 tasks carry real TDD cycles.

**Dropped from the original plan:** `HouseholdRepository.getMembers` and the
isolate-side acting-member fallback chain (replaced by the payload's `by`; the
chain would have re-introduced A-5), and every verbatim code block that
referenced `planDigest`, `scheduleDigest`, `digestNotificationId`, or
`DigestRescheduleController._recompute`'s counting loop — none of which exist.
