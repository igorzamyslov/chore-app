# Push retry — plan for B-6 (`docs/backlog.md`)

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `SupabaseSyncEngine`'s existing 60-second foreground
safety-net poll the ability to retry a push that failed earlier (e.g.
connectivity dropped mid-debounce), so a dirty row no longer sits unpushed
indefinitely while the device is idle and foregrounded — **without** ever
making the poll's pull conditional on the push succeeding. Bring
`docs/specs/sync-backend.md` §8.3 and `docs/specs/sync-freshness.md` §2.2
into agreement with the new behavior.

**Non-goal:** making the failure/retry VISIBLE to the user. That is D-5
(offline indicator, `docs/backlog.md`) — see "Seam with D-5" below for
exactly where the boundary sits.

**Architecture:** A new private tick method, `_pollTick()`, becomes the
poll timer's callback (replacing today's bare `pullSince()`). It pushes
(swallowing failure exactly like `pushDirty()` does) and then **always**
pulls — regardless of whether the push succeeded. `pushDirty()` itself is
left completely untouched: its own callers (the debounced write listener,
`start()`, app resume) keep their existing "pull only after a successful
push" contract.

**Tech Stack:** Flutter 3.44, Riverpod, drift/SQLite. No server/migration
changes — this is client-only.

**Spec:** `docs/specs/sync-backend.md` §8.3 (binding, being amended here),
`docs/specs/sync-freshness.md` §2.2 (binding, being amended here).

**Note for the executing agent:** the hard "never run flutter/dart
commands" constraint that applied to *planning* this ticket does not apply
to executing it — run `flutter test`/`flutter analyze` normally per the
Steps below. Do not run more than 2 concurrent `flutter test` processes if
other agents are active in this repo at the same time.

---

## Analysis

### The problem, precisely

`_armPoll` (`lib/application/sync_engine.dart:307-318`) arms
`Timer.periodic(pollInterval, (_) => unawaited(pullSince()))`. Push only
happens from: a local write (debounced ~2s), `start()`, app resume
(`SyncEngineController.triggerOnResume`), and — indirectly — a realtime
reconnect tick (which triggers a *pull*, not a push; only `pushDirty`'s own
tail pulls, the reverse isn't true). A write made exactly as connectivity
drops has its debounced push fail (swallowed per §8.3's posture) and the row
stays `syncDirty = true` until the user makes another local write or
backgrounds/foregrounds the app. Traced in full in
`docs/research/persona-mia.md` finding 3 and
`docs/research/triage.md` T2.7.

### A correctness trap in the obvious fix (found in review — must not regress)

The naive version of "attach push to the poll" is to just point the timer
at `pushDirty()` instead of `pullSince()`. **That is wrong.** Read
`pushDirty()`:

```dart
Future<void> pushDirty() async {
  try {
    await _pushAll();
  } on Object catch (error, stackTrace) {
    _logFailure('pushDirty', error, stackTrace);
    return;                 // <-- early return, no pull
  }
  await pullSince();        // <-- only reached if the push succeeded
}
```

On failure it returns *before* pulling. Pointing the poll timer straight at
`pushDirty()` would make the periodic pull **conditional on the push
succeeding** — exactly backwards for a device with one permanently-stuck
row (e.g. a `42501` from the column-restricted `members`/`households`
grants, or a row referencing something deleted elsewhere): every tick's
push fails, so every tick's would-be pull never runs either. A single bad
row would turn the 60s freshness bound `sync-freshness.md` §2.2 exists to
guarantee into a total, silent pull blackout for that device — while the
*other* household member's changes keep piling up unseen. This is worse
than today's behavior, not better, and it directly defeats the spec this
poll exists to satisfy.

### Approaches considered (for the tick itself)

1. **`await pushDirty(); await pullSince();`** — rejected: double-pulls
   on every tick where the push succeeds (which is the common case), since
   `pushDirty()` already pulls once internally on success. Wasteful and
   makes "how many pulls per tick" depend on push outcome, which is exactly
   the kind of coupling this fix needs to avoid.
2. **Point the timer straight at `pushDirty()`** — rejected: the
   correctness trap above. A push failure must never suppress the pull.
3. **Refactor `pushDirty()` to expose a push-only, swallowed-failure
   primitive that both `pushDirty()` and the new tick share** (e.g.
   `Future<bool> _pushDirtySwallowed()`, with `pushDirty()` becoming
   `if (await _pushDirtySwallowed()) await pullSince();`). Correct, and
   removes the small duplication option 4 accepts — but it changes
   `pushDirty()`'s own body, which is exercised directly by several
   existing tests (`test/application/sync_engine_test.dart`'s "push
   mechanics" and "LWW matrix" groups call `engine.pushDirty()` directly).
   Touching it adds review surface to a widely-depended-on method for a
   ticket whose actual behavioral need is "the poll's tick," not
   "`pushDirty()` internals."
4. **Chosen: a new private `_pollTick()` with its own try/catch, used only
   by the poll timer; `pushDirty()` left byte-for-byte unchanged.** Slight
   duplication (the same `try { await _pushAll(); } on Object catch (...)`
   shape appears twice), but: `pushDirty()`'s existing contract, tests, and
   every other call site are provably unaffected (nothing about them
   changes); the new method is small, single-purpose, and its own doc
   comment states in one place exactly why it isn't built from `pushDirty()`
   (see Task 2 below) — a future reader hitting the "why not just call
   `pushDirty()`" question gets the answer inline instead of needing to
   reconstruct this analysis. Given the ticket's own emphasis on not
   reintroducing a subtle feedback bug, minimizing the blast radius on an
   already-carefully-tuned method outweighs a few duplicated lines.

**Chosen: approach 4.** `_pollTick()` always pushes-then-pulls, with the
push half swallowing its own failure independently of whether the pull
half runs.

### `hasDirtyRows` gate — still not needed

Unchanged conclusion from the original analysis, now on firmer footing:
`_pollTick()` calls `pullSince()` **unconditionally, every tick, exactly
once** — the same unconditional network round trip (1 `server_now()` RPC +
7 `pullTable` calls) the old bare `pullSince()` poll already made every
tick. The only thing this plan adds to a clean, healthy device's tick is
seven local `SELECT ... WHERE sync_dirty = true` queries against
family-scale tables (`docs/specs/sync-backend.md:88`) from the push half —
negligible next to the network round trip the tick was already making. A
gate would optimize the cheapest part of the tick and leave the expensive,
unconditional part exactly as expensive as it already is.

### Why this cannot reintroduce the documented restart-loop hazard

`syncEngineProvider`'s doc comment (`lib/app/providers.dart:356-377`)
documents a specific, already-fixed hazard: a pull writes
`settings.syncLastPulledAt`, and if the provider watched the *whole*
settings row, that write would re-emit it, rebuilding (tearing down and
restarting) the engine — an infinite loop. The fix already in place is
`settingsProvider.select((s) => s.valueOrNull?.syncHouseholdId)` — the
provider only reacts to `syncHouseholdId` changing.

This plan does not touch `syncEngineProvider`, does not add a new watched
value, and does not change what any push or pull writes. `pullSince()` was
already being called once per tick from inside a running engine before
this change; `_pollTick()` still calls it exactly once per tick after this
change. The specific hazard above is about the *provider's* watch scope,
which is unrelated to how many times the already-constructed engine's own
methods run, and this plan doesn't change that count.

One adjacent subtlety worth stating explicitly (not a new risk — it already
exists today, verified by reading `_push*` and confirmed by the existing
"push mechanics" test group): clearing a row's `syncDirty` flag after a
successful push is itself a write to a table `db.tableUpdates()` watches
(`start()`, `lib/application/sync_engine.dart:250-262`), so every push
already re-arms the debounced-push timer once more. That settles after one
harmless extra cycle — the follow-up push finds nothing dirty (every
`_push*` method no-ops on an empty dirty list) — not an infinite loop, and
nothing about this plan changes that dynamic; it was already true for every
push the engine made before this change.

### Open product decisions

**None.** Retry cadence is a technical implementation choice — piggybacking
on the cadence `docs/specs/sync-freshness.md` §2.2 already decided for
pull — not a new user-visible behavior needing a product call. The
user-visible half of this problem (surfacing that a push failed, or that a
retry happened) is explicitly out of scope; see below.

### Seam with D-5 (offline indicator) — do not absorb it here

This plan makes push recover automatically within the existing 60s
foreground bound. It deliberately adds **no** user-facing signal that a
push failed or that a retry happened or succeeded — that is D-5's job.

The natural hook for D-5 is `SupabaseSyncEngine._logFailure`
(`lib/application/sync_engine.dart:594-598`), already the single funnel
point for every push/pull/`refreshNow` failure (currently a bare
`debugPrint`) — and, after Task 2 below, also the funnel point for
`_pollTick()`'s own swallowed push failure. D-5's own plan should turn that
method into something observable (a stream/`ValueNotifier` of
last-failure/last-success state, or similar) — this plan does not touch
`_logFailure`'s signature or add any such observable, so D-5 can land
independently, before or after this, by wrapping or replacing that one
method without conflicting with anything here.

---

## Global Constraints

- Strict lints (`very_good_analysis`, `--fatal-infos`); public members need
  doc comments. `_pollTick` is private but still gets a full doc comment
  per this codebase's own convention (every other private method in this
  file has one).
- TDD: write failing tests, run them (confirm RED), implement, run them
  (confirm GREEN), then the full suite, then commit.
- Never add a `Co-Authored-By:` trailer to any commit.
- No l10n changes in this plan — every change here is internal engine
  behavior and spec text; nothing user-visible is added.
- No schema/migration changes.
- This plan touches exactly one `lib/` file
  (`lib/application/sync_engine.dart`), one test file
  (`test/application/sync_engine_test.dart`), and two spec files. Nothing
  else. `pushDirty()`'s own body must end up byte-for-byte unchanged —
  Task 2's diff review should confirm this explicitly.

## File map

| File | Change |
| --- | --- |
| `lib/application/sync_engine.dart` | New private `_pollTick()` (push, swallow failure, then always pull); `_armPoll`'s timer callback points at it instead of `pullSince`; doc-comment updates on `pollInterval`, `_armPoll`, the `start()` inline comment, and the class doc comment. `pushDirty()` unchanged. |
| `test/application/sync_engine_test.dart` | Two new tests in the `'SupabaseSyncEngine foreground poll'` group: (1) poll retries a push that failed once, (2) poll keeps pulling even when the push keeps failing forever |
| `docs/specs/sync-backend.md` | §8.3 "Triggers" bullet: add the poll to the push-trigger list |
| `docs/specs/sync-freshness.md` | §2.2: poll now pushes (retrying dirty rows) in addition to pulling, and the pull is unconditional |

---

## Task 1 — RED: two tests for the poll's push-retry behavior

**File:** `test/application/sync_engine_test.dart`

Add both tests inside the existing
`group('SupabaseSyncEngine foreground poll', ...)` block (it already
declares `db`, `transport`, `household`, `engine` with
`pushDebounce: const Duration(milliseconds: 20)` and
`pollInterval: const Duration(milliseconds: 30)` in its `setUp` — reuse
those, don't add a new group). Insert both as the last tests in the group,
right before the group's closing `});` (currently right after the
`'resumeBackgroundWork before start() leaves no stray timer'` test).

**Test A — the retry itself:**

```dart
    test(
      'foreground poll retries a push that failed earlier, without '
      'waiting for another local write or app resume (B-6, '
      'docs/backlog.md)',
      () async {
        var upsertAttempts = 0;
        transport.beforeUpsert = () async {
          upsertAttempts++;
          if (upsertAttempts == 1) {
            // Simulates the exact B-6 scenario: connectivity drops during
            // the debounced push that follows a local write.
            throw Exception('simulated connectivity drop');
          }
        };

        engine.start();
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await ShoppingRepository(db).addItem(household.id, name: 'Milk');

        // Let the 20ms debounced push fire and fail against the simulated
        // drop -- the row must still be dirty afterward, and nothing must
        // have reached the fake server.
        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(
          transport.serverRows['shopping_items'],
          isEmpty,
          reason: 'the first push attempt was made to fail on purpose',
        );
        final stillDirty = await (db.select(
          db.shoppingItems,
        )..where((tbl) => tbl.name.equals('Milk'))).getSingle();
        expect(stillDirty.syncDirty, isTrue);

        // The 30ms foreground poll must retry it on its own -- no further
        // local write, no resume.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(
          transport.serverRows['shopping_items']!.any(
            (row) => row['name'] == 'Milk',
          ),
          isTrue,
          reason:
              'the foreground safety-net poll must retry a dirty row left '
              'over from an earlier failed push (B-6) -- before this fix '
              'only pull was retried on a timer',
        );
      },
    );
```

**Test B — the blackout guard (this is the one the earlier draft of this
plan was missing, and the one that would have caught the naive
`pushDirty()`-on-the-timer bug):**

```dart
    test(
      'foreground poll still pulls even when the push half keeps '
      'failing forever -- a permanently-stuck dirty row must not '
      'silence pull too (B-6, docs/backlog.md)',
      () async {
        transport.beforeUpsert = () async {
          throw Exception('simulated permanent rejection, e.g. a 42501');
        };

        engine.start();
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await ShoppingRepository(db).addItem(household.id, name: 'Milk');

        // Let the debounced push fail (and keep failing -- beforeUpsert
        // always throws), then measure whether pulls keep happening on
        // the poll's own cadence regardless.
        await Future<void>.delayed(const Duration(milliseconds: 40));
        final before = transport.serverNowCalls;
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(
          transport.serverNowCalls,
          greaterThan(before),
          reason:
              'a poll tick must ALWAYS pull, whether or not the push '
              'half succeeded -- pointing the poll timer straight at '
              'pushDirty() would make the pull conditional on push '
              'success and turn one stuck row into a total pull '
              'blackout, exactly what sync-freshness.md §2.2 exists to '
              'prevent',
        );
      },
    );
```

`ShoppingRepository` is already imported at the top of this file (used by
other groups) — no new import needed.

- [ ] **Step 1: Run and confirm RED**

  ```bash
  env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/application/sync_engine_test.dart
  ```

  Expected against today's code (`_armPoll` calling bare `pullSince()`):
  Test A fails (nothing ever retries the failed push). If Task 2 is later
  implemented the *naive* way (pointing the timer straight at `pushDirty()`
  instead of adding `_pollTick()`), Test A would newly pass but Test B
  would fail — that is the whole point of Test B; make sure it's present
  before touching `lib/`. Every other test in the file should still pass.

- [ ] **Step 2: Commit the failing tests**

  ```bash
  git add test/application/sync_engine_test.dart
  git commit -m "Add failing tests: foreground poll must retry push and never block pull on it (B-6)"
  ```

## Task 2 — GREEN: `_pollTick()`, always push-then-pull

**File:** `lib/application/sync_engine.dart`

**2a. Add the new private method,** directly above `_armPoll` (or directly
below it — either is fine, keep it next to `_armPoll` since the two are
conceptually paired):

```dart
  /// The poll timer's own tick (B-6, `docs/backlog.md`): pushes every
  /// dirty row, swallowing any failure exactly like [pushDirty]'s own
  /// try/catch (spec §8.3's failure posture), and then ALWAYS pulls --
  /// regardless of whether the push succeeded.
  ///
  /// Deliberately NOT `await pushDirty(); await pullSince();`: [pushDirty]
  /// already pulls once internally on a successful push (spec §8.3c), so
  /// that would double-pull on every tick where nothing was wrong.
  ///
  /// Deliberately NOT a bare `await pushDirty()` either: [pushDirty]
  /// returns early on failure and never reaches its own pull (see its
  /// body) -- pointing the poll timer straight at it would make the
  /// periodic pull conditional on the push succeeding. A single
  /// persistently-rejected row (a `42501` from the column-restricted
  /// `members`/`households` grants, or a row referencing something
  /// deleted elsewhere) would then turn the 60s freshness bound
  /// `docs/specs/sync-freshness.md` §2.2 exists to guarantee into a
  /// total, silent pull blackout for this device -- while the other
  /// household member's changes keep arriving unseen. This method's own
  /// try/catch exists specifically so a push failure can never prevent
  /// the pull that follows it.
  Future<void> _pollTick() async {
    try {
      await _pushAll();
    } on Object catch (error, stackTrace) {
      _logFailure('pushDirty', error, stackTrace);
    }
    await pullSince();
  }
```

**2b. `_armPoll`'s body and doc comment.** Replace:

```dart
  /// (Re)arms the foreground safety-net poll, but only while the engine is
  /// started AND the app is foregrounded -- so a resume that arrives before
  /// the engine exists, or after it was stopped, never leaves a stray timer
  /// behind.
  void _armPoll() {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (!_started || !_foreground) {
      return;
    }
    _pollTimer = Timer.periodic(pollInterval, (_) => unawaited(pullSince()));
  }
```

with:

```dart
  /// (Re)arms the foreground safety-net poll, but only while the engine is
  /// started AND the app is foregrounded -- so a resume that arrives before
  /// the engine exists, or after it was stopped, never leaves a stray timer
  /// behind. Ticks call [_pollTick] (B-6, `docs/backlog.md`), not a bare
  /// [pullSince]: see [_pollTick]'s own doc comment for why it must push
  /// too, and why that push must never be allowed to block the pull.
  void _armPoll() {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (!_started || !_foreground) {
      return;
    }
    _pollTimer = Timer.periodic(pollInterval, (_) => unawaited(_pollTick()));
  }
```

**2c. `pollInterval`'s doc comment.** Replace:

```dart
  /// How often the foreground safety-net poll calls [pullSince] (spec
  /// `docs/specs/sync-freshness.md` §2.2: 60s). Realtime is the fast path;
  /// this only bounds worst-case staleness when realtime is degraded in a
  /// way the re-subscribe trigger cannot see. Tests pass a shorter value.
  final Duration pollInterval;
```

with:

```dart
  /// How often the foreground safety-net poll ticks (spec
  /// `docs/specs/sync-freshness.md` §2.2: 60s). Each tick runs [_pollTick]
  /// (extended by B-6, `docs/backlog.md`, from a bare [pullSince] to also
  /// retry any row a prior debounced push failed to send) -- see
  /// [_pollTick]'s doc comment for why the pull half is unconditional even
  /// when the push half fails. Realtime is still the fast path for pull;
  /// this only bounds worst-case staleness, for both directions, when
  /// realtime is degraded in a way the re-subscribe trigger cannot see.
  /// Tests pass a shorter value.
  final Duration pollInterval;
```

**2d. The inline comment above `_armPoll();` in `start()`.** Replace:

```dart
    // Push on start (recovers rows left dirty from a prior session that
    // never got pushed -- e.g. a cold start while linked), which itself
    // pulls afterward on success (spec §8.3a/c): this covers "pull on
    // start" too, so a bare pullSince() call here is not enough on its
    // own.
    unawaited(pushDirty());
    _armPoll();
```

with:

```dart
    // Push on start (recovers rows left dirty from a prior session that
    // never got pushed -- e.g. a cold start while linked), which itself
    // pulls afterward on success (spec §8.3a/c): this covers "pull on
    // start" too, so a bare pullSince() call here is not enough on its
    // own. _armPoll() below repeats a push-then-always-pull periodically
    // while foregrounded (B-6, see _pollTick), so a row that fails to
    // push here, or via the debounced write-listener, keeps getting
    // retried instead of waiting for the next local write or resume --
    // and the pull half of the poll keeps running even if that retry
    // itself fails again.
    unawaited(pushDirty());
    _armPoll();
```

**2e. The class-level doc comment.** Replace:

```dart
/// The production [SyncEngine]: LWW push/pull over a [SyncTransport], with
/// a debounced push-on-write trigger and a realtime pull trigger (spec
/// §8.3).
class SupabaseSyncEngine implements SyncEngine {
```

with:

```dart
/// The production [SyncEngine]: LWW push/pull over a [SyncTransport], with
/// a debounced push-on-write trigger, a realtime pull trigger, and a
/// periodic foreground poll that unconditionally pulls AND retries any
/// still-dirty push (spec §8.3, extended by B-6 -- see [_pollTick]).
class SupabaseSyncEngine implements SyncEngine {
```

**Explicitly confirm `pushDirty()`'s own body is untouched** by this task —
no edit above touches it; it is listed here only so the diff review checks
for it.

- [ ] **Step 1: Run the target test file and confirm GREEN**

  ```bash
  env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/application/sync_engine_test.dart
  ```

  Expected: every test in the file passes, including both new tests from
  Task 1. In particular, re-check the two pre-existing tests in the same
  group by inspection (no code change needed, just confirm they still pass
  as-is):
  - `'polls pullSince repeatedly while started and foregrounded'` — still
    passes because it counts `transport.serverNowCalls`, and `_pollTick()`
    still calls `pullSince()` (hence `serverNow()`) exactly once per tick,
    unconditionally.
  - `'pauseBackgroundWork stops the poll; resume re-arms it'` — still
    passes for the same reason; `pauseBackgroundWork`/`resumeBackgroundWork`
    cancel/re-arm the same `_pollTimer` regardless of what its callback is.

- [ ] **Step 2: Run the sync-adjacent regression suite**

  ```bash
  env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/application/sync_engine_test.dart test/app/sync_engine_provider_test.dart
  ```

  Expected: all green. In particular
  `sync_engine_provider_test.dart`'s first test (the restart-loop
  regression) is unaffected: it uses the engine's DEFAULT `pollInterval`
  (60s) and only pumps 5 seconds of virtual time, so the poll timer never
  fires during that test either before or after this change — the
  regression it guards against is about `syncEngineProvider`'s watch scope,
  which this plan does not touch. It also never calls `pushDirty()`
  directly in a way this task's untouched `pushDirty()` body would affect.

- [ ] **Step 3: Full suite + analyze**

  ```bash
  env -u GIT_DIR -u GIT_INDEX_FILE flutter analyze --fatal-infos && env -u GIT_DIR -u GIT_INDEX_FILE flutter test
  ```

  Expected: `No issues found!` and all tests passing.

- [ ] **Step 4: Commit**

  ```bash
  git add lib/application/sync_engine.dart
  git commit -m "Retry a failed push on the foreground poll without blocking its pull (B-6)"
  ```

## Task 3 — bring the binding specs into agreement

**File:** `docs/specs/sync-backend.md`

In §8.3, the "Triggers" bullet currently ends:

```
Push on: any local write while linked (debounced
  ~2s), app resume, reconnect.
```

Replace with:

```
Push on: any local write while linked (debounced
  ~2s), app resume, reconnect, and (B-6, `docs/backlog.md`) the 60s
  foreground safety-net poll defined below in `sync-freshness.md` §2.2 --
  the same timer already used for the pull safety net now retries anything
  still dirty on every tick too, not only on resume. The poll's pull half
  is unconditional: a push failure on one tick must never suppress that
  tick's pull (see `sync-freshness.md` §2.2 and
  `SupabaseSyncEngine._pollTick`'s doc comment for why).
```

**File:** `docs/specs/sync-freshness.md`

§2.2 currently opens:

```
### 2.2 Foreground safety-net poll

A `Timer.periodic` on the engine, **60 seconds**, calling `pullSince()`.
```

Replace with:

```
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
```

Leave the rest of §2.2's bullets (60s rationale, foreground-only rule, the
`pauseBackgroundWork`/`resumeBackgroundWork` pairing, timer lifecycle) as
they are — none of that text is specific to what the timer calls, and all
of it stays true.

- [ ] **Step 1: Apply both edits, proofread against the actual file text**

  (The exact surrounding text must match — re-read each file immediately
  before editing to confirm the quoted blocks above are still verbatim.)

- [ ] **Step 2: Commit**

  ```bash
  git add docs/specs/sync-backend.md docs/specs/sync-freshness.md
  git commit -m "Amend sync-backend.md §8.3 and sync-freshness.md §2.2 for the push-retry poll (B-6)"
  ```

---

## Done criteria

- `flutter analyze --fatal-infos` clean; `flutter test` green, including
  both new Task 1 tests.
- `pushDirty()`'s own body is byte-for-byte identical to before this plan.
- `docs/specs/sync-backend.md` §8.3 and `docs/specs/sync-freshness.md` §2.2
  describe the poll pushing-then-unconditionally-pulling, matching the
  code.
- No change to any provider, any widget, any l10n file, or the failure
  posture (`_logFailure` untouched in shape, only called from one more
  place) — this is a pure engine-internals fix.
- `docs/backlog.md` row B-6 can be marked closed once this lands (not done
  by this plan — leave that to whoever merges it, per this repo's practice
  of updating the backlog at merge time, not plan time).
