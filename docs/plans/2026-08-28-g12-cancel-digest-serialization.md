# G-12 — serialize `cancelDigest()` onto the digest write queue

*Written 2026-08-28, against the tree as it stands at that date (wave 5,
branch `wave5/small-items`). Backlog row **G-12**, size S. There was no
pre-existing plan for this row; this file is the plan, so the wave-5
"refresh a stale plan" pass is satisfied by construction — every line
below was written after reading the current
`lib/application/notification_scheduler.dart`,
`lib/application/notification_action_processor.dart`,
`test/application/notification_scheduler_test.dart` and
`test/app/digest_reschedule_test.dart`.*

## The defect

`NotificationScheduler.applyDigestPlans` serializes itself. It is a
**synchronous** method returning a `Future`: at call time, before any
suspension point, it captures the current tail, chains its real work
(`_applyDigestPlansNow`) onto it, reassigns the tail, and hands the caller
the future for *its own* link. Two callers therefore queue behind each
other rather than interleaving their `digestHorizonSlots` platform calls.

`cancelDigest()` does none of that. It is a plain `async` method that
awaits `ensureInitialized()` and then loops `plugin.cancel(id)` over
`digestNotificationIds`. Every `await` in that loop yields the isolate, so
a cancel's loop can interleave with an in-flight apply's loop, and the
apply can re-arm slot `k` **after** the cancel has already cleared it.

The reachable consequence is a wiped app with armed slots: `reset_flow.dart`
calls `cancelDigest()` as step 1 of a double-confirmed wipe, while a
notification-action horizon rewrite (`rewriteDigestHorizon`, F-1) is a
second independent writer. The next digest then fires about a household
that no longer exists.

The fix was specified by the wave-4 agent that recorded the hazard, in
`lib/application/notification_action_processor.dart`: *"fixing it means
serializing `cancelDigest` onto `_applyTail`, which belongs with whoever
owns `NotificationScheduler` next."* This plan does exactly that and
nothing more.

## Closed decisions this plan does not reopen

- **No cross-isolate lock.** The *other* hazard recorded in that same
  comment — `_applyTail` is per-instance and does not cross isolates — is
  deliberately unfixed and argued to be self-correcting. This fix is
  within one isolate. `docs/specs/notifications.md` and the action
  processor both say so explicitly.
- **The fix is not to have the notification action call `cancelDigest()`.**
  That trades one wrong notification for up to 83 days of silence for
  exactly the disengaged user the horizon serves. Recorded in the spec,
  the backlog and `notification_action_handler.dart`.

## Ordering semantics: FIFO is correct for both interleavings

Serializing gives FIFO **by arrival** (the order the methods were called),
not by completion. That is the right tiebreak because each caller decided
what it wanted from state it read at call time, so the caller that arrived
later holds the later view of the world. Checking both directions:

1. **A cancel issued during an in-flight apply runs after it.** Final
   state: nothing armed. Correct — the wipe is the last word, and this is
   precisely the bug: today the apply's trailing slots land after the
   cancel cleared them.
2. **An apply issued during an in-flight cancel runs after it.** Final
   state: the horizon is armed from the apply's data. Correct — a
   legitimate post-wipe recompute (a fresh household after a reset, or the
   action isolate's rewrite) must still be able to arm. Today the apply
   runs immediately and the *later* cancel wipes its work, so the horizon
   ends up silent when it should be armed.

Both directions are wrong today and both are fixed by the same change,
which is why each gets its own test.

Alternative considered and **rejected**: giving cancel priority — letting
it jump the queue, or aborting an in-flight apply. It needs a cancellation
token threaded through `_applyDigestPlansNow`'s loop, and it makes case 2
nondeterministic (a legitimate later apply could be dropped by an earlier
cancel). More machinery, worse semantics.

## Shape fixes taken while in these files (wave-5 rules §0)

- **`_applyTail` is misnamed** once cancels ride it: it is the tail of all
  digest *writes*. Renamed `_digestWriteTail`, doc comment rewritten to
  say so. Field is private, so the rename is contained to this file.
- **The three-line enqueue is extracted** into
  `_enqueueDigestWrite(Future<void> Function() write)`. Duplicating it
  would mean two places that each have to get the error handling exactly
  right, and getting it wrong is silent and permanent (below). One
  implementation, two one-line call sites.

## The two error properties that must survive (currently at :450-455)

Both are load-bearing and both are preserved by construction because
`_enqueueDigestWrite` is the single implementation:

1. **The tail is never allowed to complete with an error.** It is assigned
   `thisWrite.catchError((_) {})`, so a failed write does not permanently
   jam every write that comes after it.
2. **The error still reaches the caller that made *that* call.** The
   method returns `thisWrite` itself — *not* the swallowed variant.

A third, less obvious property: **the tail reassignment must happen
synchronously, at call time.** If `cancelDigest` stayed `async` and did
`await waitForPrevious` before reassigning, two concurrent callers could
both capture the same tail and run in parallel — the serialization would
be silently vacuous. So `cancelDigest` becomes a synchronous method
returning `Future<void>`, mirroring `applyDigestPlans`, and the real body
moves to a private `_cancelDigestNow()`.

`applyDigestPlans`' `ArgumentError` length check stays **before** the
enqueue so it keeps throwing synchronously (its existing test asserts
`throwsArgumentError` on a bare closure, which only passes for a
synchronous throw).

## `ensureInitialized` stays inside the serialized body

`_cancelDigestNow()` awaits `ensureInitialized()` as its first statement,
exactly as `_applyDigestPlansNow` does. Hoisting it in front of the queue
wait would reintroduce a suspension point before the ordering is
established.

## Accepted consequence for the wipe path

`reset_flow.dart`'s `_cancelDigest` is documented as best-effort and must
never block a double-confirmed wipe. After this change it may **wait**
behind an in-flight apply. Accepted, because the exposure is not new in
kind: that path already awaits `ensureInitialized()`, i.e. a
`plugin.initialize()` platform call, so the wipe already depended on the
plugin's platform calls returning. The `on Object` guard there was always
about a *throw*, never about a hang. The alternative — a timeout on the
queue wait — reintroduces precisely the interleaving this row fixes. A
note goes on `_cancelDigest`'s doc comment so a future reader is not
surprised.

## Files

| File | Change |
| --- | --- |
| `lib/application/notification_scheduler.dart` | `_applyTail` → `_digestWriteTail` + new doc; extract `_enqueueDigestWrite`; `cancelDigest` becomes sync-returning-Future over new `_cancelDigestNow`; doc comments on both public methods state the shared queue. |
| `test/application/notification_scheduler_test.dart` | `_GatedPlugin` gains a gate target (`firstSchedule` default, `firstCancel`); three new tests (two reds, one error-isolation guard). |
| `lib/application/notification_action_processor.dart` | The "`cancelDigest()` is unserialized" hazard paragraph is now false — rewrite it to record that it is fixed. The cross-isolate paragraph beside it stays untouched. |
| `lib/features/settings/reset_flow.dart` | One sentence on `_cancelDigest`'s doc comment about queueing behind an in-flight apply. |
| `docs/specs/notifications.md` | Binding contract; its "Relatedly, `cancelDigest()` remains unserialized…" sentence contradicts the fix, so editing it is part of the task. |
| `docs/backlog.md` | Close G-12 in the file's own convention, and add it to the header's "Also closed" list. |

Historical handovers (`docs/handover-2026-08-14-planning.md` §4,
`docs/handover-2026-08-18-wave-4.md` §6) and the historical plan files under
`docs/plans/2026-08-*` are **dated records** and are deliberately left as
written.

## Tests

All three go in `test/application/notification_scheduler_test.dart`, reusing
the existing `_GatedPlugin` (mirrors `_PausingPlugin` in
`test/app/digest_reschedule_test.dart`) rather than inventing fake
infrastructure.

**RED 1 — a cancel during an in-flight apply.** Apply with every slot
non-null; it pauses at the gate before writing slot 0. Call `cancelDigest()`
while it is paused and pump the microtask queue. Assert
`plugin.cancelCallCount == 0` (serialized: the cancel has not started). Then
release, await both, and assert `plugin.pending` is empty.
*Red mode before the fix:* the mid-flight assertion fails with
`cancelCallCount` = `digestHorizonSlots` (the unblocked cancel loop ran to
completion), and the outcome assertion would fail with
`digestHorizonSlots` armed slots — the wiped-app-with-armed-slots bug.

**RED 2 — an apply during an in-flight cancel.** Gate the first
`plugin.cancel`. Start `cancelDigest()`; it pauses. Call `applyDigestPlans`
with every slot non-null and pump. Assert nothing has been scheduled yet.
Release, await both, assert all `digestHorizonSlots` ids are armed.
*Red mode before the fix:* the apply runs immediately, so the mid-flight
assertion fails; the final state ends up empty because the later cancel
wipes the apply's work.

**GUARD 3 — error isolation, both directions.** Not a red (before the fix
`cancelDigest` could not jam a queue it never touched); it exists because
getting this wrong is silent and permanent. A plugin whose first `cancel`
throws: `cancelDigest()`'s own future must reject, and a subsequent
`applyDigestPlans` must still complete and arm the horizon. Symmetrically,
a plugin whose first `zonedSchedule` throws must not stop a later
`cancelDigest()` from running.

## Task order

1. This plan, committed on its own.
2. Tests only → push → observe CI red at the **test** step with the modes
   above.
3. Implementation → push → green. **This is the commit that makes the fix
   live.**
4. Doc/comment updates (action processor, reset flow, spec, backlog) →
   push → green.
5. Inversion: restore the unserialized body *inside* `cancelDigest` (never
   delete the method — that fails at `analyze` on `unused_element` and the
   tests never run), push, confirm red at the test step, revert.
