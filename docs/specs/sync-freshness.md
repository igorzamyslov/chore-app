# Spec: Sync freshness — reconnect pull, safety poll, manual refresh

*Status: BINDING. Amends `docs/specs/sync-backend.md` §8.3 (engine
triggers). Written 2026-08-06 from a field report: "if one person adds
something to a shopping list or changes its state, it takes very long for
the other household member to get an update, and there's no manual way to
refresh."*

## 1. Root cause

The P3 engine (`lib/application/sync_engine.dart`) pulls on exactly four
occasions:

| Trigger | Where | Status |
| --- | --- | --- |
| Engine start | `start()` → `pushDirty()` → `pullSince()` | works |
| After every successful push | `pushDirty()` tail | works |
| App resume | `SyncEngineController.triggerOnResume()` | works |
| A **live** realtime event arrives | `householdChanges` stream listener | works *while the socket is healthy* |

Nothing pulls when the realtime socket **re-establishes itself**, and
nothing pulls on a timer. `subscribe()` is called once with no status
callback, so the engine cannot tell a healthy subscription from a dead one.

That leaves one wide-open hole, and it is exactly the reported symptom:

> The app is in the foreground, the websocket has quietly died (Wi-Fi → cell
> handover, a doze window, a proxy timeout, a Supabase Realtime redeploy),
> and the client silently resubscribes. Every change the other phone made
> during the outage was broadcast to nobody. The engine has no idea it
> missed anything, so it never pulls. The device stays stale **until the
> user backgrounds and reopens the app, or happens to make a local edit**
> (which pushes, and therefore pulls).

"Takes very long" is precisely this: the next refresh is whenever the user
next leaves and returns to the app. Standing in a shop with the list open —
the exact case that produced the report — none of the four triggers fire.

Realtime itself is correctly configured: migration `20260801160000` puts
all seven synced tables in the `supabase_realtime` publication, and the
client subscribes to `shopping_items` with a `household_id` filter. This is
not a "realtime was never wired up" bug; it is a **gap-recovery** bug.

## 2. Fixes

### 2.1 Pull on every (re)subscribe — the important one

`SupabaseSyncTransport.householdChanges` must pass a status callback to
`RealtimeChannel.subscribe()` and emit a tick on the stream whenever the
status becomes `subscribed`.

Because the engine's listener maps every tick to `pullSince()`, this makes
"the subscription just (re)connected" a pull trigger — closing the gap
window automatically, with no timer, on the exact event that created it.
It also removes the need for a separate "pull on start" path (subscribing
is the first thing the engine does).

Channel errors (`channelError`, `timedOut`, `closed`) are logged through
the engine's existing `_logFailure` path and otherwise ignored — the
Supabase client reconnects on its own, and the reconnect produces the
`subscribed` tick that recovers the gap.

### 2.2 Foreground safety-net poll

A `Timer.periodic` on the engine, **60 seconds**. Amended by B-6
(`docs/backlog.md`): each tick now pushes every dirty row (swallowing
failure per §8.3's posture) AND THEN ALWAYS pulls, regardless of whether
the push succeeded -- retrying anything a debounced push failed to send
(e.g. connectivity dropping mid-write) without ever making the pull
conditional on that retry's outcome. A tick is not simply
`pushDirty()` followed by `pullSince()`: `pushDirty()` already pulls
internally on a successful push, which would double-pull, and `pushDirty()`
returns early WITHOUT pulling on a failed push, which would turn one
persistently-rejected row into a total pull blackout -- exactly what this
section exists to prevent. The engine implements this as its own
`_pollTick()` method with an independent try/catch around the push half.

- 60s, not tighter: realtime is the fast path (sub-second when healthy);
  this only bounds worst-case staleness when realtime is degraded in a way
  §2.1 cannot see. A cursor-filtered pull over seven tables with nothing to
  return is cheap, but not free.
- **Foreground only.** The engine gains `pauseBackgroundWork()` /
  `resumeBackgroundWork()`; `main.dart`'s existing single
  `_AppResumeObserver` calls them alongside the `triggerOnResume()` it
  already makes — no second `WidgetsBindingObserver`. A backgrounded app
  must not hold a network wakeup every minute.
- The timer is created in `start()` and cancelled in `stop()`, exactly like
  `_pushTimer`, so the existing linked-state teardown keeps working.

### 2.3 Pull-to-refresh

`RefreshIndicator` around the Chores list and the Shopping list, calling
`pushDirty()` (push-then-pull: a pull-to-refresh should also flush anything
this device still owes, same reasoning as resume) and completing only when
that future settles, so the spinner reflects real work.

- Shown **only when the household is linked and signed in** — the same gate
  `syncEngineProvider` already applies. A local-only household has no
  remote to fetch from, and offering a refresh that provably does nothing
  is the kind of dishonest affordance waves M and R were about removing.
- Failure surfaces as a snackbar with the existing sync-error copy.
  Success is silent — the list simply updates, which is the platform
  convention.
- Semantic ids `chores.refresh` and `shopping.refresh` *(new)* on the
  indicators, so E2E can drive them.

### 2.4 "Last synced" honesty

Settings → Account gains a relative "Last synced <time>" line under the
sync-state row, from the `syncLastPulledAt` cursor the engine already
persists. This is the place a suspicious user can check whether sync is
alive, and it costs one existing DB field.

### 2.5 Can't-reach-the-household indicator (D-5, `docs/backlog.md`)

§2.4's "Last synced" line is passive and lives only in Settings. Everywhere
else — the chores list, the shopping list — a device that has been failing
to sync for hours renders exactly like one that is perfectly current.
Fixed by `docs/plans/2026-08-08-offline-indicator.md`:

- **Source of truth: inferred, never reported.** This indicator does NOT
  change `sync-backend.md` §8.3's failure posture (`pushDirty`/`pullSince`
  keep swallowing every error exactly as before) and does NOT read
  `SyncEngine`'s internal error state. It infers health from two
  independent, already-persisted signals: (a) the `syncLastPulledAt` cursor
  older than **5 minutes**, and (b) any synced-table row continuously
  `syncDirty` for longer than **3 minutes**. Either alone is enough to flag
  unhealthy — (a) alone cannot see a push-only failure (e.g. a permissions
  bug that only rejects writes) while pulls keep succeeding, and (b) alone
  cannot see a household with zero local writes whose pulls are what's
  actually failing.
- **Thresholds DECIDED (Igor).** A healthy linked device pulls at least
  every 60s (the foreground safety-net poll, §2.2), so 5 minutes is five
  missed cycles — comfortably past a tunnel, a lift, or a flaky handover,
  without letting real divergence sit unmentioned. A faster threshold would
  fire on ordinary mobile-network hiccups and train people to ignore the
  banner, which is worse than having no banner at all; a slower one is too
  slow for the case this exists for (someone mid-shop whose list is
  silently not reaching their partner). 3 minutes for the dirty check is
  well past the ~2s push debounce and ordinary bursty editing, short enough
  to catch a push-only failure within a normal session. Both values are
  named top-level constants (`defaultPullStaleAfter`/
  `defaultDirtyStaleAfter` in `lib/domain/sync_health.dart`) so retuning is
  a one-line diff that reads as tuning rather than as a regression.
- **Every threshold is measured from a moment this device actually had a
  chance to sync**, never from a persisted cursor alone. The pull-staleness
  reference point is the LATEST of: `syncLastPulledAt`, `syncLinkedAt` (for
  a device that has never completed a pull since linking), and
  `syncObservingSinceProvider` — the moment the current linked engine
  session began, re-armed on every app resume. Without that floor the
  banner would appear for the second or two between "the engine exists
  again" and "its first pull lands" on **every** cold start or resume after
  more than 5 minutes away, i.e. on most launches: the cursor is genuinely
  hours old at that instant, but the device has not yet failed at anything.
  A banner that flashes on almost every launch is precisely the
  cry-wolf failure the threshold rationale above exists to avoid. With the
  floor, each foreground session gets the same five-missed-cycles grace it
  would get mid-session.
- **Recomputation is driven by a 60s tick that only exists while linked.**
  Riverpod's dependency graph alone is NOT sufficient, and assuming it was
  would have shipped a dead feature: a device that cannot reach the server
  writes nothing (`pullSince` failing persists no cursor), and the
  dirty-streak timestamp is deliberately pinned to when the streak STARTED,
  so a second local write re-emits an equal value that Riverpod
  (correctly) treats as no change. In the central failure case there is
  therefore no graph event at all, and a purely reactive indicator would
  never fire. `syncHealthStatusProvider` instead arms a one-shot 60s
  `Timer` that invalidates itself, **only** on the linked-and-signed-in
  branch — so it is never armed in a widget test or E2E run (both are
  always unlinked), exactly like the engine's own poll timer, and carries
  none of this project's "a Timer is still pending" test hazard. Worst-case
  detection latency is therefore one tick past the threshold.
- **Gating.** Shown only while the device is linked AND signed in — the
  same gate §2.3's pull-to-refresh indicator already uses. A never-linked
  household shows nothing (there is no remote to be unhealthy about); a
  linked-but-signed-out device also shows nothing here — that state has its
  own honest treatment already
  (`docs/feedback/2026-08-07-field-feedback.md` A1.1's paused-sync notice
  in Settings → Account), and duplicating it on the list screens would be
  redundant noise rather than a second useful signal.
- **Surface.** A single self-hiding banner above the list content on both
  the chores and shopping tabs, styled like this app's existing
  informational banners (`secondaryContainer`, never `errorContainer` —
  briefly unreachable is normal for a local-first app, not an error, and
  red here would erode what red means everywhere else). Never dismissible:
  it disappears the moment the underlying condition clears, which cannot go
  stale the way a manually-dismissed banner could. Not tappable, but the
  copy itself names the user's existing recourse (pull-to-refresh, present
  on both list screens and, since commit `60c15ce`, actually reporting
  failure rather than spinning regardless of outcome) — a notice with no
  way to act on it is a dead end, the same failure class as ticket E-2's
  startup error screen. Settings → Account's "Last synced" line remains the
  place for more detail.
- **The copy never says "offline".** The device may have a perfectly good
  network connection while genuinely unable to reach the household (an RLS
  or permissions bug, a Supabase outage), so "offline" would be a
  connectivity verdict the app cannot honestly make. It says the device
  hasn't reached the household in a while, and that local changes are safe.
- **Relationship to B-6** (push retry): B-6 makes failure recover sooner;
  this indicator makes failure visible regardless of whether or how it
  recovers. Fully independent — the indicator never reads engine internals
  or retry state, only the persisted cursor/link timestamps and the
  `syncDirty` flag every synced write already sets.

## 3. Non-goals

- No change to the conflict rule (LWW, dirty-local-wins) or the cursor
  protocol.
- No shortening of the 2s push debounce — the push side was never the
  reported problem.
- No background sync while the app is closed. That needs platform
  background-task work and a battery story; if the freshness complaint
  survives these fixes, it gets its own spec.

## 4. Verification

- Unit: a fake transport whose `householdChanges` emits a subscribe tick
  proves the engine pulls; a fake clock proves the 60s poll fires and that
  `pauseBackgroundWork()` stops it.
- Widget: the refresh indicator is absent for a local-only household and
  present for a linked one.
- §2.5: unit coverage for the threshold matrix (`computeSyncHealth`,
  including the observing-since floor) and for the dirty-streak stream;
  a bare-`ProviderContainer` test proves `syncHealthStatusProvider` reads
  real settings/dirty data for both signals; widget tests prove the banner
  renders on both list screens while unhealthy and is absent while healthy.
  **E2E cannot cover §2.5 at all** — the Maestro suite builds with empty
  Supabase dart-defines, so every run is unlinked and resolves to
  `NoopSyncEngine`/`NoopAuthGateway`, i.e. permanently healthy by
  construction. This feature is carried by widget tests only.
- Live two-device check before release: with both phones on the same
  household, kill the network on phone B for 30s, make three changes on
  phone A, restore B's network, and confirm B converges without being
  backgrounded — this is the exact scenario that is broken today.
