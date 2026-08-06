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

A `Timer.periodic` on the engine, **60 seconds**, calling `pullSince()`.

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
- Live two-device check before release: with both phones on the same
  household, kill the network on phone B for 30s, make three changes on
  phone A, restore B's network, and confirm B converges without being
  backgrounded — this is the exact scenario that is broken today.
