# Offline / can't-reach-server indicator — plan for D-5 (`docs/backlog.md`)

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a linked, signed-in device's failure to reach its household
visible on the chores and shopping lists — not just in the passive
"Last synced" line in Settings → Account — without touching
`SyncEngine`'s swallow-everything failure posture (spec
`docs/specs/sync-backend.md` §8.3).

**Non-goal:** making sync failure recover. That is B-6 (push retry,
`docs/plans/2026-08-08-push-retry.md`, already written) — see "Seam with
B-6" below for exactly where the boundary sits and why this plan touches
zero lines of `lib/application/sync_engine.dart`.

**Architecture:** A pure function, `computeSyncHealth`
(`lib/domain/sync_health.dart`), infers `SyncHealthStatus.healthy` /
`.unhealthy` from data the app already persists or can already observe —
the `syncLastPulledAt`/`syncLinkedAt` cursor timestamps and a live "is any
synced row still dirty" watch — never from the engine's own caught errors.
A new `syncHealthStatusProvider` (`lib/app/providers.dart`) wires this to
real data, gated on the exact same "linked AND signed in" condition
`syncEngineProvider` already uses for the pull-to-refresh indicator. A new
self-hiding banner widget, `SyncHealthBanner`
(`lib/features/sync/sync_health_banner.dart`), renders one sentence when
unhealthy and nothing otherwise, placed above the list content on both the
chores and shopping tabs.

**Tech Stack:** Flutter 3.44, Riverpod 2.6 (non-generator `Provider`/
`StreamProvider` API), drift/SQLite. No server/migration changes — this is
entirely client-side and needs no new database column (schema stays v8).

**Spec:** `docs/specs/sync-freshness.md` (binding, amended here — new
§2.5). `docs/specs/sync-backend.md` §8.3 is read but **not** amended: this
design does not require the failure posture to change (see Analysis).

**Note for the executing agent:** the hard "never run flutter/dart
commands" constraint that applied to *planning* this ticket does not apply
to executing it — run `flutter test`/`flutter analyze` normally per the
steps below. Do not run more than 2 concurrent `flutter test` processes if
other agents are active in this repo at the same time (this repo is
mid multi-agent run as of 2026-08-08; `docs/plans/2026-08-08-push-retry.md`
is a sibling plan that may be executing concurrently — see "Seam with B-6").

---

## Analysis

### The source-of-truth decision

`pushDirty`/`pullSince` swallow every error by contract (spec §8.3), so
nothing upstream of `SupabaseSyncEngine._logFailure` currently knows a
failure happened. Two honest designs were considered:

**Option A — the engine reports a health state.** Turn
`_logFailure` (`lib/application/sync_engine.dart:594-598`) into an
observable (a stream/`ValueNotifier` of last-failure/last-success time or
a consecutive-failure count), and derive the indicator from that. This is
explicitly the hook `docs/plans/2026-08-08-push-retry.md`'s "Seam with D-5"
section identifies as available ("D-5's own plan should turn that method
into something observable... by wrapping or replacing that one method").

**Option B — infer from staleness + dirty rows, never touch the failure
posture.** Compute health from data the app already persists for other
reasons: how old the `syncLastPulledAt` cursor is, and whether any
synced-table row has been `syncDirty` for longer than a grace period. The
engine's `_logFailure`/try-catch shape is never read or modified.

**Chosen: Option B.** Reasons, in order of weight:

1. **Zero overlap with the concurrently-planned/executed B-6.** B-6's own
   plan already exists (`docs/plans/2026-08-08-push-retry.md`) and edits
   `lib/application/sync_engine.dart` (a new `_pollTick()` method, changed
   `_armPoll` body, several doc comments). Option A would mean *this* plan
   also edits that same file, at the same time another independently
   written plan is editing it — exactly the collision class this
   multi-agent round's hard constraints exist to prevent. Option B touches
   `lib/application/sync_engine.dart` **not at all** (verify this in the
   File map below), so the two plans can land in either order, or truly
   concurrently, with no merge risk and no need to coordinate who edits
   `_logFailure` first.
2. **Option A's apparent precision advantage mostly evaporates once you
   add the debounce it also needs.** Reacting to a bare "a failure just
   happened" event would make the very first transient blip (a `pullSince`
   that fails once because a phone walked through an elevator) flip the
   banner on — exactly the noise the ticket says a local-first app must
   not produce ("being briefly offline is the NORMAL state ... explicitly
   not an error"). To avoid that, Option A needs its own
   consecutive-failure-count or elapsed-time-since-last-success threshold
   — the same *shape* of grace-period logic Option B needs, just fed by a
   different raw signal. The "reacts sooner" advantage is real but small
   once both designs need a comparable grace period.
3. **No spec amendment to §8.3's failure posture required.** The ticket
   brief is explicit: amend §8.3 ("if your design requires errors to stop
   being swallowed") only if the design needs it. Option B's inputs
   (`syncLastPulledAt`, `syncLinkedAt`, `syncDirty`) are already
   documented, persisted, and read elsewhere (§2.4, §8.1) — nothing about
   "an error stops being swallowed." §8.3 is read for context by this plan
   and left byte-for-byte alone.
4. **Covers the asymmetric-failure case Option A would also need to
   handle specially.** A device whose *pulls* keep succeeding (so a
   pull-recency check alone looks healthy) but whose *pushes* are
   specifically and silently broken (e.g. a permissions bug that only
   rejects writes) is exactly the "data is diverging and the app says
   nothing" case the ticket opens with. Option B catches it via the
   independent "dirty too long" signal (§2.5 below); Option A would need
   the same two-signal shape internally regardless of where the raw event
   comes from.
5. **No new schema.** Both `syncLastPulledAt` and `syncLinkedAt` already
   exist (client schema v7/v8); the "any row dirty" signal is a live watch
   query over the existing `syncDirty` columns, not a new persisted field.
   Option A's failure/success bookkeeping would need to live somewhere —
   in-memory on the engine instance is fine, but it's one more piece of
   engine-instance state for zero required capability gain given point 4.

**Trade-off accepted, stated plainly:** Option B is a few minutes coarser
than a live failure feed could theoretically be (see §2.5's own "known
limitation" on recompute timing, below). Given being briefly wrong for a
few minutes is explicitly *not* the failure mode this ticket cares about
("hours", per the ticket's own framing), this is the right side to be
coarse on.

### Two independent grace-period signals, not one

A single "pull cursor age" check cannot see a push-only failure (point 4
above), and a single "any row dirty" check cannot see a household with
zero local writes whose *pulls* are the thing failing. `computeSyncHealth`
therefore takes both and flags unhealthy if **either** exceeds its own
threshold — see `lib/domain/sync_health.dart` in Task 2.

### Gating: reuses an existing seam, doesn't invent a new one

The ticket asks for three distinct states: "not linked at all" (no
indicator), "linked, signed out" (already handled by wave A1's honest
signed-out state — do not duplicate), "linked, signed in, failing" (the
new banner). `syncEngineProvider` (`lib/app/providers.dart`) already
resolves to `NoopSyncEngine` in exactly the first two cases and a real
`SupabaseSyncEngine` in exactly the third (see its own doc comment: gated
on `syncTransportProvider != null && linkedHouseholdId != null &&
signedIn`). `syncHealthStatusProvider` reuses `ref.watch(syncEngineProvider)
is! NoopSyncEngine` as its own gate — the identical check
`chores_list_screen.dart`/`shopping_list_screen.dart` already use for the
pull-to-refresh indicator's `syncLinked` local. No new provider watches
`currentAuthUserProvider` or `settingsProvider.syncHouseholdId` directly;
this plan piggybacks on the already-correct, already-tested gate instead of
re-deriving it (avoiding the exact "unscoped watch" class of bug
`syncEngineProvider`'s own doc comment warns about).

### Surface: a self-hiding banner, matching this app's existing "quiet"
banners

Three candidates considered: (a) always-visible connectivity chrome (an
app-bar icon shown at all times, healthy or not) — rejected outright per
the ticket's own framing: brief disconnection is normal, so a
permanently-present icon would be noise, and would also force a second
"is this the good icon or the bad icon" read on every glance. (b) A
tap-to-dismiss banner — rejected: dismissing would hide a condition that
is, by construction, still ongoing (the banner only ever appears while
genuinely unhealthy), the same "a manual dismiss can hide a still-real
problem" reasoning `docs/research/triage.md` T2.6 already established for
the notification-permission nudge. (c) **Chosen: a self-hiding banner**,
present only while unhealthy, gone the instant conditions clear — the
exact pattern already proven twice in this codebase
(`OnboardingNameBanner`, `DigestPrepromptBanner`): a `DepthCard` over
`colorScheme.secondaryContainer`, `SizedBox.shrink()` otherwise, so every
existing test that doesn't care about it is unaffected (no semantics node
at all when hidden).

One generic sentence regardless of which of the two signals tripped
(dirty-too-long vs. pull-too-stale): the user does not need the mechanism,
only the fact, the reassurance that data is safe, and a recourse — mirroring
`syncRefreshError`'s existing tone ("Couldn't reach the household. Your
changes are saved here and will sync later.") rather than inventing a new
voice. Never uses the word "offline" (the ticket's own instruction): the
device may well have a perfectly good network connection while genuinely
unable to reach the household (RLS/permissions bug, Supabase outage), so
"offline" would be actively misleading.

**Decided (Igor): the copy names the recourse the user already has.** A
notice that reports a problem with no way to act on it is a dead end — the
same failure class as the startup error screen (ticket E-2). The banner
stays non-tappable and non-dismissible (a tap target here would duplicate
a gesture already on the same screen — pull-to-refresh — and routing to
Settings would be worse, since Settings cannot fix connectivity either),
but the sentence itself names that recourse in one short clause: "try
pulling down to refresh." Pull-to-refresh already exists on both list
screens and, since commit `60c15ce`, actually reports failure rather than
spinning and stopping regardless of outcome — so pointing at it is honest,
not decorative.

### Seam with B-6 (push retry) — this plan does not absorb it

`docs/plans/2026-08-08-push-retry.md` makes push failure **recover**
sooner, by retrying dirty rows on the existing 60s foreground poll. This
plan makes failure **visible**, regardless of whether or how it recovers.
The two are fully decoupled:

- This plan adds **zero** lines to `lib/application/sync_engine.dart`.
  Every input `computeSyncHealth` reads (`syncLastPulledAt`, `syncLinkedAt`,
  the live `syncDirty` watch) is data the engine already writes as a side
  effect of its normal push/pull methods, whether or not B-6's retry logic
  exists yet.
- Once B-6 lands, dirty rows simply clear sooner after a transient failure
  — `dirtySinceProvider` (Task 4) picks that up for free, with no change
  needed here, because it watches the same `syncDirty` column B-6 also
  writes to.
- Landing order between this plan and B-6 does not matter. Neither
  modifies a file the other modifies (confirmed against B-6's own File map:
  it touches `lib/application/sync_engine.dart`,
  `test/application/sync_engine_test.dart`, `docs/specs/sync-backend.md`
  §8.3's trigger list, and `docs/specs/sync-freshness.md` §2.2; this plan
  touches neither of those two source files, and amends
  `docs/specs/sync-freshness.md` at a **different** section, §2.5 —
  re-read the file immediately before editing it in Task 1 in case B-6 has
  already landed its own §2.2 edit first).

## Open product decisions

Both resolved (Igor). Recorded here for the record; the plan below
implements these decisions directly, not as open alternatives.

**1. The two grace-period thresholds — DECIDED: `pullStaleAfter = 5
minutes`, `dirtyStaleAfter = 3 minutes`.**

A healthy linked device pulls at least every 60s (the safety-net poll), so
5 minutes is five missed cycles — comfortably past a tunnel, a lift, or a
flaky handover, without letting real divergence sit unmentioned. A faster
threshold (2 min / 1 min) would fire on ordinary mobile-network hiccups
and train people to ignore the banner, which is worse than not having one
at all. A slower threshold (15 min / 10 min) is too slow for the case this
exists for: someone mid-shop whose list is silently not reaching their
partner.

Both values are **named top-level constants in one place**
(`defaultPullStaleAfter`/`defaultDirtyStaleAfter` in
`lib/domain/sync_health.dart`, Task 2) used as `computeSyncHealth`'s
default parameter values — changing them later is a one-line diff with no
migration, and reads as tuning rather than as a regression to revert. The
chosen values and this rationale are also recorded in
`docs/specs/sync-freshness.md` §2.5 (Task 1) for the same reason.

**2. Banner visual weight — DECIDED: `secondaryContainer`, non-dismissible
(as recommended). Tappability — PARTIALLY OVERRULED: still non-tappable,
but the copy must name the user's existing recourse.**

`secondaryContainer` is right and `errorContainer` would be wrong: for a
local-first app, being briefly unreachable is a normal condition, not an
error, and red styling here would be alarmist and erode what red means
everywhere else in the app.

But a notice that reports a problem and offers no way to act on it is a
dead end (the same failure class as ticket E-2's startup error screen). So:
keep it non-tappable and non-dismissible (a tap target duplicating
pull-to-refresh on the same screen would be redundant, and Settings cannot
fix connectivity either), but the copy itself must name the recourse — one
short clause pointing at pull-to-refresh, which already exists on both
list screens and (since commit `60c15ce`) actually reports failure rather
than spinning and stopping regardless of outcome. See the final copy in
Task 5.

This plan implements both decisions directly: the thresholds as named
constants (`lib/domain/sync_health.dart`, Task 2) and the banner as
`secondaryContainer`/non-tappable/non-dismissible with recourse-naming copy
(`lib/features/sync/sync_health_banner.dart`, Task 6; `app_en.arb`/
`app_de.arb`, Task 5).

---

## Global Constraints

- Every user-visible string goes through gen_l10n (`app_en.arb` template +
  `app_de.arb`, German du-form) — never inline English. One new key this
  plan adds: `syncHealthBannerMessage`.
- Every interactive widget gets a stable id via `semantic()`; this banner
  has no interactive children, but still gets its own container id
  (`sync.health.banner`) for E2E/widget-test discoverability, matching
  `settings.account.lastSynced`'s precedent (a plain `Text` still gets an
  id).
- Widget tests are integration-style: real in-memory `AppDatabase` + fixed
  clock, overriding ONLY `appDatabaseProvider`/`clockProvider` plus the
  documented `syncTransportProvider`/`authGatewayProvider` seams. Never
  mock repositories or services. Task 6/7's tests make one narrow,
  explicitly-justified exception (overriding `syncHealthStatusProvider`
  itself) — see those tasks for why, and see Task 4's tests for the
  real-data coverage that justifies the shortcut.
- Deadlock traps: never bare-await a drift stream outside a widget pump;
  never bare-await `bootstrapProvider.future` in a `ProviderContainer`
  test; `tester.pump(small duration)` between `container.dispose()` and
  `database.close()`. This plan adds **no new `Timer`** anywhere (see the
  "known limitation" in Task 1's spec text for why a periodic ticker was
  deliberately rejected) — every new stream in this plan (`watchAnyDirty`,
  `dirtySinceStream`) is driven by drift's own write-notification
  mechanism, not a `Timer`, so it carries none of this project's
  documented "Timer still pending" test hazard.
- Strict lints (`very_good_analysis`, `--fatal-infos`); public members need
  doc comments. Note: `StreamProvider.stream` is `@Deprecated` in this
  project's riverpod version (2.6.1) — this plan never uses it (see Task 4
  for how `dirtySinceProvider` avoids it).
- TDD: write failing test → run it (confirm RED) → implement → run it
  (confirm GREEN) → full suite → commit.
- Never add a `Co-Authored-By:` trailer to any commit.
- No schema/migration changes (schema stays v8) — every input this plan
  reads already exists.

## File map

| File | Change |
| --- | --- |
| `docs/specs/sync-freshness.md` | New §2.5 documenting the indicator (binding) |
| `lib/domain/sync_health.dart` | New. `SyncHealthStatus` enum, `computeSyncHealth`, `dirtySinceStream` — pure, no Flutter/drift imports |
| `test/domain/sync_health_test.dart` | New. Full threshold matrix for `computeSyncHealth`; unit coverage for `dirtySinceStream` |
| `lib/data/repositories/sync_repository.dart` | New method `watchAnyDirty()` |
| `test/data/repositories/sync_repository_test.dart` | New. Real in-memory `AppDatabase`, proves reactivity |
| `lib/app/providers.dart` | New `dirtySinceProvider`, `syncHealthStatusProvider`; file doc-comment gains a "seventh override point" note |
| `test/app/sync_health_status_provider_test.dart` | New. Bare `ProviderContainer`, real DB, `FakeSyncTransport`, mutable clock — proves the end-to-end wiring for both signals |
| `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb` | New key `syncHealthBannerMessage` |
| `lib/features/sync/sync_health_banner.dart` | New. `SyncHealthBanner` widget |
| `lib/features/chores/chores_list_screen.dart` | Insert `const SyncHealthBanner()` into the body `Column` |
| `test/features/chores/sync_health_banner_test.dart` | New. Chores-tab render/hide, via `syncHealthStatusProvider.overrideWithValue` |
| `lib/features/shopping/shopping_list_screen.dart` | Insert `const SyncHealthBanner()` into the body `Column` |
| `test/features/shopping/sync_health_banner_test.dart` | New. Shopping-tab render/hide, same technique |

**Not touched by this plan:** `lib/application/sync_engine.dart`,
`test/application/sync_engine_test.dart`, `docs/specs/sync-backend.md`
(read, not edited) — confirms the B-6 seam statement above.

---

## Task 1 — spec: document the indicator (§2.5)

**File:** `docs/specs/sync-freshness.md`

Re-read the file immediately before editing — if `docs/plans/
2026-08-08-push-retry.md` has already landed, its Task 3 rewrites §2.2's
opening paragraph; this edit only touches the NEW §2.5 inserted after the
existing §2.4, so it does not conflict either way.

Between the existing `## 3. Non-goals` heading and the `### 2.4 "Last
synced" honesty` section above it, insert a new `### 2.5` section. Find
this exact text (the end of §2.4 and the start of §3):

```
Settings → Account gains a relative "Last synced <time>" line under the
sync-state row, from the `syncLastPulledAt` cursor the engine already
persists. This is the place a suspicious user can check whether sync is
alive, and it costs one existing DB field.

## 3. Non-goals
```

Replace with:

```
Settings → Account gains a relative "Last synced <time>" line under the
sync-state row, from the `syncLastPulledAt` cursor the engine already
persists. This is the place a suspicious user can check whether sync is
alive, and it costs one existing DB field.

### 2.5 Offline / can't-reach-server indicator (D-5, `docs/backlog.md`)

§2.4's "Last synced" line is passive and lives only in Settings. Everywhere
else — the chores list, the shopping list — a device that has been failing
to sync for hours renders exactly like one that is perfectly current.
Fixed by `docs/plans/2026-08-08-offline-indicator.md`:

- **Source of truth: inferred, never reported.** This indicator does NOT
  change §8.3's failure posture (`pushDirty`/`pullSince` keep swallowing
  every error exactly as before) and does NOT read `SyncEngine`'s internal
  error state. It infers health from two independent, already-persisted
  signals: (a) the `syncLastPulledAt` cursor (falling back to
  `syncLinkedAt` before the device's first pull ever completes) older than
  **5 minutes**, and (b) any synced-table row continuously `syncDirty` for
  longer than **3 minutes**. Either alone is enough to flag unhealthy —
  (a) alone cannot see a push-only failure (e.g. a permissions bug that
  only rejects writes) while pulls keep succeeding, and (b) alone cannot
  see a household with zero local writes whose pulls are what's actually
  failing. **Thresholds DECIDED (Igor):** a healthy linked device pulls at
  least every 60s (the foreground safety-net poll, §2.2), so 5 minutes is
  five missed cycles — comfortably past a tunnel, a lift, or a flaky
  handover, without letting real divergence sit unmentioned; a faster
  threshold would fire on ordinary mobile-network hiccups and train people
  to ignore the banner, and a slower one is too slow for the case this
  exists for (someone mid-shop whose list is silently not reaching their
  partner). 3 minutes for the dirty check is well past the ~2s push
  debounce and ordinary bursty editing, short enough to catch a push-only
  failure within a normal session. Both values are named top-level
  constants (`defaultPullStaleAfter`/`defaultDirtyStaleAfter` in
  `lib/domain/sync_health.dart`) so retuning is a one-line diff.
- **Gating.** Shown only while the device is linked AND signed in — the
  same gate §2.3's pull-to-refresh indicator already uses. A never-linked
  household shows nothing (there is no remote to be unhealthy about); a
  linked-but-signed-out device also shows nothing here — that state has
  its own honest treatment already
  (`docs/feedback/2026-08-07-field-feedback.md` A1.1's paused-sync notice
  in Settings → Account), and duplicating it on the list screens would be
  redundant noise, not a second useful signal.
- **Surface.** A single self-hiding banner above the list content on both
  the chores and shopping tabs, styled like this app's existing
  informational banners (`secondaryContainer`, never `errorContainer` —
  briefly unreachable is normal for a local-first app, not an error).
  Never dismissible: it disappears the moment the underlying condition
  clears, which cannot go stale the way a manually-dismissed banner could.
  Not tappable, but the copy itself names the user's existing recourse
  (pull-to-refresh, present on both list screens and, since commit
  `60c15ce`, actually reports failure rather than spinning regardless of
  outcome) — a notice with no way to act on it is a dead end, the same
  failure class as ticket E-2's startup error screen. Settings → Account's
  "Last synced" line remains the place for more detail.
- **Known limitation.** Recomputation rides Riverpod's normal
  provider-dependency graph (a local write, a successful pull,
  linking/unlinking, sign-in/out) rather than a dedicated periodic timer —
  deliberately, to avoid this project's own documented "a Timer is still
  pending" widget-test hazard for zero real gain (see
  `docs/plans/2026-08-08-offline-indicator.md`'s Analysis). In the rare
  case of a session with genuinely zero local writes and zero pull
  attempts for the entire grace period, the indicator can lag a little
  behind the precise threshold rather than firing to the second — a small
  , explicitly accepted trade-off given the failure mode this exists to
  catch is measured in hours, not minutes.
- **Relationship to B-6** (`docs/plans/2026-08-08-push-retry.md`, push
  retry): B-6 makes failure recover sooner; this indicator makes failure
  visible regardless of whether or how it recovers. Fully independent —
  this indicator never reads engine internals or retry state, only the
  persisted cursor/link timestamps and the `syncDirty` flag every synced
  write already sets.

## 3. Non-goals
```

- [ ] **Step 1: Apply the edit, proofread against the live file**
- [ ] **Step 2: Commit**

  ```bash
  git add docs/specs/sync-freshness.md
  git commit -m "Document the D-5 offline indicator in sync-freshness.md §2.5"
  ```

## Task 2 — pure domain: `computeSyncHealth` and `dirtySinceStream`

**Files:**
- Create: `lib/domain/sync_health.dart`
- Test: `test/domain/sync_health_test.dart`

**Interfaces produced (later tasks depend on these exact names/types):**
- `enum SyncHealthStatus { healthy, unhealthy }`
- `const Duration defaultPullStaleAfter = Duration(minutes: 5)`
- `const Duration defaultDirtyStaleAfter = Duration(minutes: 3)`
- `SyncHealthStatus computeSyncHealth({required DateTime now, required DateTime? lastPulledAt, required DateTime linkedAt, required DateTime? dirtySince, Duration pullStaleAfter = defaultPullStaleAfter, Duration dirtyStaleAfter = defaultDirtyStaleAfter})`
- `Stream<DateTime?> dirtySinceStream(Stream<bool> anyDirty, DateTime Function() now)`

- [ ] **Step 1: Write the failing test**

  Create `test/domain/sync_health_test.dart`:

  ```dart
  import 'package:chore_app/domain/sync_health.dart';
  import 'package:flutter_test/flutter_test.dart';

  void main() {
    final linkedAt = DateTime.utc(2026, 8, 11, 8);

    group('computeSyncHealth', () {
      test('healthy: recent pull, nothing dirty', () {
        final status = computeSyncHealth(
          now: linkedAt.add(const Duration(minutes: 1)),
          lastPulledAt: linkedAt.add(const Duration(seconds: 30)),
          linkedAt: linkedAt,
          dirtySince: null,
        );
        expect(status, SyncHealthStatus.healthy);
      });

      test('healthy: dirty for less than dirtyStaleAfter', () {
        final now = linkedAt.add(const Duration(minutes: 10));
        final status = computeSyncHealth(
          now: now,
          lastPulledAt: now.subtract(const Duration(seconds: 10)),
          linkedAt: linkedAt,
          dirtySince: now.subtract(const Duration(minutes: 1)),
        );
        expect(status, SyncHealthStatus.healthy);
      });

      test('unhealthy: pull cursor older than pullStaleAfter', () {
        final now = linkedAt.add(const Duration(minutes: 20));
        final status = computeSyncHealth(
          now: now,
          lastPulledAt: now.subtract(const Duration(minutes: 6)),
          linkedAt: linkedAt,
          dirtySince: null,
        );
        expect(status, SyncHealthStatus.unhealthy);
      });

      test(
        'unhealthy: never pulled yet AND linked longer than pullStaleAfter '
        'ago',
        () {
          final now = linkedAt.add(const Duration(minutes: 6));
          final status = computeSyncHealth(
            now: now,
            lastPulledAt: null,
            linkedAt: linkedAt,
            dirtySince: null,
          );
          expect(status, SyncHealthStatus.unhealthy);
        },
      );

      test(
        'healthy: never pulled yet but linked less than pullStaleAfter ago '
        '(grace period for a fresh link)',
        () {
          final now = linkedAt.add(const Duration(minutes: 1));
          final status = computeSyncHealth(
            now: now,
            lastPulledAt: null,
            linkedAt: linkedAt,
            dirtySince: null,
          );
          expect(status, SyncHealthStatus.healthy);
        },
      );

      test(
        'unhealthy: dirty rows stuck longer than dirtyStaleAfter even '
        'though pulls are fresh (asymmetric push-only failure)',
        () {
          final now = linkedAt.add(const Duration(minutes: 30));
          final status = computeSyncHealth(
            now: now,
            lastPulledAt: now.subtract(const Duration(seconds: 5)),
            linkedAt: linkedAt,
            dirtySince: now.subtract(const Duration(minutes: 4)),
          );
          expect(status, SyncHealthStatus.unhealthy);
        },
      );

      test('custom thresholds are honored', () {
        final now = linkedAt.add(const Duration(minutes: 2));
        final status = computeSyncHealth(
          now: now,
          lastPulledAt: now.subtract(const Duration(minutes: 1, seconds: 30)),
          linkedAt: linkedAt,
          dirtySince: null,
          pullStaleAfter: const Duration(minutes: 1),
        );
        expect(status, SyncHealthStatus.unhealthy);
      });
    });

    group('dirtySinceStream', () {
      test(
        'pins to the moment dirty first flips true, resets on false, '
        'never re-reads the clock on a true-to-true repeat',
        () async {
          final flags = Stream<bool>.fromIterable([
            false,
            true,
            true,
            false,
            true,
          ]);
          var calls = 0;
          DateTime now() {
            calls++;
            return DateTime.utc(2026, 1, 1).add(Duration(minutes: calls));
          }

          final results = await dirtySinceStream(flags, now).toList();

          expect(results, [
            null,
            DateTime.utc(2026, 1, 1, 0, 1),
            DateTime.utc(2026, 1, 1, 0, 1), // unchanged: now() NOT re-called
            null,
            DateTime.utc(2026, 1, 1, 0, 2),
          ]);
          expect(
            calls,
            2,
            reason: 'now() must only be called on a false-to-true '
                'transition, twice across this sequence',
          );
        },
      );
    });
  }
  ```

- [ ] **Step 2: Run and confirm RED**

  ```bash
  env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/domain/sync_health_test.dart
  ```

  Expected: fails to compile (`lib/domain/sync_health.dart` doesn't exist
  yet).

- [ ] **Step 3: Write the implementation**

  Create `lib/domain/sync_health.dart`:

  ```dart
  /// Pure computation behind the D-5 offline/can't-reach-server indicator
  /// (spec `docs/specs/sync-freshness.md` §2.5): whether a linked,
  /// signed-in device's connection to its household looks healthy or worth
  /// flagging.
  ///
  /// Deliberately never touches `SyncEngine`'s own swallow-everything
  /// failure posture (spec `docs/specs/sync-backend.md` §8.3) -- every
  /// input here is something the app already persists or observes for
  /// other reasons (`syncLastPulledAt`, `syncLinkedAt`, and a live "any
  /// synced row still dirty" watch), inferred rather than reported. See
  /// §2.5 for the full rationale, including why this needs TWO
  /// independent signals rather than one.
  library;

  /// Whether [computeSyncHealth] found anything worth flagging.
  enum SyncHealthStatus {
    /// Nothing suggests a problem: the pull cursor is recent enough, and
    /// any locally dirty rows are still within the normal debounce/poll
    /// grace period.
    healthy,

    /// Either the pull cursor hasn't advanced recently enough, or dirty
    /// rows have sat unpushed longer than the grace period -- see
    /// [computeSyncHealth].
    unhealthy,
  }

  /// [computeSyncHealth]'s default pull-staleness grace period (spec
  /// `docs/specs/sync-freshness.md` §2.5, DECIDED by Igor). A healthy
  /// linked device pulls at least every 60s (the foreground safety-net
  /// poll, spec §2.2), so five minutes is five missed cycles --
  /// comfortably past a tunnel, a lift, or a flaky handover, without
  /// letting real divergence sit unmentioned. Named and centralized here
  /// so retuning it later is a one-line diff that reads as tuning, not as
  /// a regression to revert.
  const Duration defaultPullStaleAfter = Duration(minutes: 5);

  /// [computeSyncHealth]'s default dirty-row grace period (spec
  /// `docs/specs/sync-freshness.md` §2.5, DECIDED by Igor). The push
  /// debounce is ~2s, so three minutes of continuous dirtiness is dozens
  /// of missed debounce cycles -- never trips during ordinary bursty
  /// editing, but still catches a push-only failure well within a normal
  /// session rather than only after hours.
  const Duration defaultDirtyStaleAfter = Duration(minutes: 3);

  /// Computes [SyncHealthStatus] from data the app already keeps.
  ///
  /// [now] is the current time. [lastPulledAt] is the `syncLastPulledAt`
  /// cursor (`null` if this device has never completed a pull since
  /// linking). [linkedAt] is `syncLinkedAt`, used as the reference point
  /// INSTEAD of [lastPulledAt] until the first pull ever completes, so a
  /// device that just linked isn't flagged unhealthy during the few
  /// seconds before its first pull lands. [dirtySince] is the wall-clock
  /// moment ANY synced-table row most recently became continuously dirty
  /// with nothing pushed since (`null` while clean) -- see
  /// [dirtySinceStream].
  ///
  /// [pullStaleAfter]/[dirtyStaleAfter] are the two independent thresholds
  /// (spec `docs/specs/sync-freshness.md` §2.5, DECIDED by Igor -- see
  /// [defaultPullStaleAfter]/[defaultDirtyStaleAfter] for the rationale):
  /// either condition alone is enough to report
  /// [SyncHealthStatus.unhealthy]. Two independent checks, not one: a
  /// device whose PULLS keep succeeding but whose PUSHES are silently and
  /// specifically broken (e.g. a permissions bug that only affects writes)
  /// would never trip a pull-staleness check alone, since other members'
  /// changes keep arriving fine -- only the dirty-duration check catches
  /// that asymmetric failure.
  SyncHealthStatus computeSyncHealth({
    required DateTime now,
    required DateTime? lastPulledAt,
    required DateTime linkedAt,
    required DateTime? dirtySince,
    Duration pullStaleAfter = defaultPullStaleAfter,
    Duration dirtyStaleAfter = defaultDirtyStaleAfter,
  }) {
    final pullReference = lastPulledAt ?? linkedAt;
    if (now.difference(pullReference) > pullStaleAfter) {
      return SyncHealthStatus.unhealthy;
    }
    if (dirtySince != null && now.difference(dirtySince) > dirtyStaleAfter) {
      return SyncHealthStatus.unhealthy;
    }
    return SyncHealthStatus.healthy;
  }

  /// Turns a live "is anything dirty right now" stream into "the wall-clock
  /// moment the CURRENT dirty streak started" -- `null` while clean, pinned
  /// to the first `true` after a `null`/`false` until the next `false`.
  ///
  /// [now] is called ONLY on a false-to-true transition (never on a
  /// true-to-true repeat), so the timestamp stays pinned to when the
  /// streak actually started, not to when it was last observed.
  Stream<DateTime?> dirtySinceStream(
    Stream<bool> anyDirty,
    DateTime Function() now,
  ) async* {
    DateTime? since;
    await for (final dirty in anyDirty) {
      if (dirty) {
        since ??= now();
      } else {
        since = null;
      }
      yield since;
    }
  }
  ```

- [ ] **Step 4: Run and confirm GREEN**

  ```bash
  env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/domain/sync_health_test.dart
  ```

  Expected: all tests pass.

- [ ] **Step 5: Commit**

  ```bash
  git add lib/domain/sync_health.dart test/domain/sync_health_test.dart
  git commit -m "Add computeSyncHealth and dirtySinceStream (D-5)"
  ```

## Task 3 — `SyncRepository.watchAnyDirty()`

**Files:**
- Modify: `lib/data/repositories/sync_repository.dart`
- Test: `test/data/repositories/sync_repository_test.dart`

**Interfaces:**
- Consumes: `AppDatabase` (already a `SyncRepository` constructor param).
- Produces: `Stream<bool> SyncRepository.watchAnyDirty()`.

- [ ] **Step 1: Write the failing test**

  Create `test/data/repositories/sync_repository_test.dart`:

  ```dart
  /// Tests `SyncRepository.watchAnyDirty` (spec
  /// `docs/specs/sync-freshness.md` §2.5): the D-5 offline indicator's
  /// "does this household have unsent changes" signal. The rest of
  /// `SyncRepository`'s dirty-select/clear methods are already covered
  /// indirectly through `test/application/sync_engine_test.dart`; this
  /// method gets its own direct test because nothing else exercises it.
  library;

  import 'package:chore_app/data/db/app_database.dart';
  import 'package:chore_app/data/repositories/category_repository.dart';
  import 'package:chore_app/data/repositories/household_repository.dart';
  import 'package:chore_app/data/repositories/sync_repository.dart';
  import 'package:drift/native.dart';
  import 'package:flutter_test/flutter_test.dart';

  void main() {
    group('watchAnyDirty', () {
      test(
        'true while ANY synced table has a dirty row, false once none do, '
        'true again on a fresh write',
        () async {
          final db = AppDatabase(NativeDatabase.memory());
          final households = HouseholdRepository(db);
          final categories = CategoryRepository(db);
          final repo = SyncRepository(db);

          final household = await households.createLocalHousehold('Me');
          // createLocalHousehold's own household+member rows start dirty
          // (spec docs/specs/sync-backend.md §8.1: every write marks
          // dirty).
          expect(await repo.watchAnyDirty().first, isTrue);

          for (final table in [
            'households',
            'members',
            'categories',
            'chores',
            'chore_assignees',
            'chore_occurrences',
            'shopping_items',
          ]) {
            await db.customStatement('UPDATE $table SET sync_dirty = 0');
          }
          expect(await repo.watchAnyDirty().first, isFalse);

          final nextEmission = repo.watchAnyDirty().skip(1).first;
          await categories.createCategory(
            household.id,
            kind: CategoryKind.chore,
            name: 'Produce',
            icon: 'a',
            color: 1,
          );
          expect(await nextEmission, isTrue);

          await db.close();
        },
      );
    });
  }
  ```

- [ ] **Step 2: Run and confirm RED**

  ```bash
  env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/data/repositories/sync_repository_test.dart
  ```

  Expected: fails — `watchAnyDirty` is not a member of `SyncRepository`.

- [ ] **Step 3: Implement**

  In `lib/data/repositories/sync_repository.dart`, add this method to the
  `SyncRepository` class (anywhere inside the class body, e.g. right after
  the constructor/`db` field, before the "Dirty select" section comment):

  ```dart
    /// Watches whether ANY synced-table row is currently `syncDirty` --
    /// re-emits whenever a write touches any of the seven synced tables
    /// (drift's `readsFrom` wiring below), regardless of which table
    /// changed. Backs `dirtySinceProvider`
    /// (`lib/app/providers.dart`), the D-5 offline indicator's "this
    /// device has unsent changes" signal (spec
    /// `docs/specs/sync-freshness.md` §2.5).
    Stream<bool> watchAnyDirty() {
      return db
          .customSelect(
            'SELECT EXISTS('
            'SELECT 1 FROM households WHERE sync_dirty = 1 '
            'UNION ALL SELECT 1 FROM members WHERE sync_dirty = 1 '
            'UNION ALL SELECT 1 FROM categories WHERE sync_dirty = 1 '
            'UNION ALL SELECT 1 FROM chores WHERE sync_dirty = 1 '
            'UNION ALL SELECT 1 FROM chore_assignees WHERE sync_dirty = 1 '
            'UNION ALL SELECT 1 FROM chore_occurrences WHERE sync_dirty = 1 '
            'UNION ALL SELECT 1 FROM shopping_items WHERE sync_dirty = 1'
            ') AS any_dirty',
            readsFrom: {
              db.households,
              db.members,
              db.categories,
              db.chores,
              db.choreAssignees,
              db.choreOccurrences,
              db.shoppingItems,
            },
          )
          .watchSingle()
          .map((row) => row.read<int>('any_dirty') == 1);
    }
  ```

- [ ] **Step 4: Run and confirm GREEN**

  ```bash
  env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/data/repositories/sync_repository_test.dart
  ```

- [ ] **Step 5: Run the full repository test directory (regression check)**

  ```bash
  env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/data/repositories/
  ```

  Expected: all green — this task only adds a method, it doesn't change
  any existing one.

- [ ] **Step 6: Commit**

  ```bash
  git add lib/data/repositories/sync_repository.dart test/data/repositories/sync_repository_test.dart
  git commit -m "Add SyncRepository.watchAnyDirty (D-5)"
  ```

## Task 4 — wire `dirtySinceProvider` and `syncHealthStatusProvider`

**Files:**
- Modify: `lib/app/providers.dart`
- Test: `test/app/sync_health_status_provider_test.dart`

**Interfaces:**
- Consumes: `computeSyncHealth`/`dirtySinceStream`/`SyncHealthStatus`
  (Task 2), `SyncRepository.watchAnyDirty()` (Task 3), the existing
  `syncEngineProvider`, `settingsProvider`, `clockProvider`,
  `appDatabaseProvider`.
- Produces: `final dirtySinceProvider = StreamProvider<DateTime?>(...)`,
  `final syncHealthStatusProvider = Provider<SyncHealthStatus>(...)`.

**Important — avoid a deprecated API:** `StreamProvider.stream` is
`@Deprecated` in riverpod 2.6.1 (this project's pinned version) and would
trip `flutter analyze --fatal-infos`. Do NOT compose `dirtySinceProvider`
out of a separate `StreamProvider` plus `.stream` — call
`SyncRepository(db).watchAnyDirty()` directly inside `dirtySinceProvider`'s
own builder instead (shown below). There is exactly one new
`StreamProvider` in this task, not two.

- [ ] **Step 1: Write the failing tests**

  Create `test/app/sync_health_status_provider_test.dart`:

  ```dart
  /// `syncHealthStatusProvider` tests (spec
  /// `docs/specs/sync-freshness.md` §2.5): proves the full wiring from real
  /// settings/repository data to `SyncHealthStatus`, for BOTH independent
  /// signals `computeSyncHealth` combines (pull-cursor staleness, and
  /// dirty-row duration). The threshold matrix itself is already covered
  /// in isolation by `test/domain/sync_health_test.dart`; this file only
  /// proves the PROVIDER reads the right real inputs.
  ///
  /// Same bare-`ProviderContainer` + real-DB + `FakeSyncTransport`
  /// technique as `test/app/sync_engine_provider_test.dart`. Uses a
  /// MUTABLE clock (`Clock(() => currentTime)`, not `Clock.fixed`) so time
  /// can be advanced explicitly -- mirrors
  /// `test/app/day_change_catchup_test.dart`'s documented approach.
  /// `syncHealthStatusProvider` is a plain (non-stream) `Provider`, so
  /// after advancing `currentTime` this file calls
  /// `container.invalidate(syncHealthStatusProvider)` before re-reading it
  /// -- this is not a shortcut, it is exactly `docs/specs/
  /// sync-freshness.md` §2.5's documented "recomputes on read, not on a
  /// live ticking clock" behavior, made explicit.
  library;

  import 'package:chore_app/app/providers.dart';
  import 'package:chore_app/application/auth_gateway.dart';
  import 'package:chore_app/data/db/app_database.dart';
  import 'package:chore_app/domain/sync_health.dart';
  import 'package:clock/clock.dart';
  import 'package:drift/native.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import 'package:flutter_test/flutter_test.dart';

  import '../application/fake_sync_transport.dart';
  import '../features/settings/fake_auth_gateway.dart';

  /// A [FakeSyncTransport] whose [serverNow] always throws -- simulates a
  /// pull that can never complete, so `syncLastPulledAt` stays `null`
  /// forever and the reference point stays `syncLinkedAt`.
  class _AlwaysFailingPullTransport extends FakeSyncTransport {
    @override
    Future<DateTime> serverNow() async {
      throw Exception('simulated total pull outage');
    }
  }

  /// Mirrors `test/app/sync_engine_provider_test.dart`'s helper of the same
  /// name -- see its doc comment for why a bare `await
  /// container.read(bootstrapProvider.future)` deadlocks under `flutter
  /// test`.
  Future<String> _awaitBootstrap(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    for (var i = 0; i < 400; i++) {
      final value = container.read(bootstrapProvider);
      if (value.hasValue) {
        return value.requireValue;
      }
      if (value.hasError) {
        throw StateError('bootstrapProvider failed: ${value.error}');
      }
      await tester.pump(const Duration(milliseconds: 5));
    }
    throw StateError('bootstrapProvider never resolved');
  }

  /// Mirrors `test/app/sync_engine_provider_test.dart`'s helper of the same
  /// name.
  Future<void> _awaitLinkedEngine(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    for (var i = 0; i < 400; i++) {
      if (container.read(syncEngineProvider) is SupabaseSyncEngine) {
        return;
      }
      await tester.pump(const Duration(milliseconds: 5));
    }
    throw StateError('syncEngineProvider never switched to a real engine');
  }

  void main() {
    setUpAll(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    });

    testWidgets('healthy while unlinked, regardless of the clock', (
      tester,
    ) async {
      final database = AppDatabase(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
      );
      addTearDown(container.dispose);

      expect(
        container.read(syncHealthStatusProvider),
        SyncHealthStatus.healthy,
      );

      await database.close();
    });

    testWidgets(
      'unhealthy once the pull cursor is older than the grace period, '
      'using syncLinkedAt as the reference point before the first pull '
      'ever completes',
      (tester) async {
        final database = AppDatabase(NativeDatabase.memory());
        var currentTime = DateTime.utc(2026, 8, 11, 8);
        final transport = _AlwaysFailingPullTransport();
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            clockProvider.overrideWithValue(Clock(() => currentTime)),
            syncTransportProvider.overrideWithValue(transport),
            authGatewayProvider.overrideWithValue(
              FakeAuthGateway(
                currentUser: const AuthUser(id: 'u1', email: 'me@example.com'),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(householdRepositoryProvider)
            .createLocalHousehold('Me');
        container.read(syncEngineControllerProvider);
        final householdId = await _awaitBootstrap(tester, container);

        await container
            .read(settingsRepositoryProvider)
            .setSyncLinked(householdId: householdId, linkedAt: currentTime);
        await _awaitLinkedEngine(tester, container);

        expect(
          container.read(syncHealthStatusProvider),
          SyncHealthStatus.healthy,
          reason: 'just linked -- still inside the grace period',
        );

        currentTime = currentTime.add(const Duration(minutes: 6));
        container.invalidate(syncHealthStatusProvider);
        expect(
          container.read(syncHealthStatusProvider),
          SyncHealthStatus.unhealthy,
        );

        container.read(syncEngineProvider).stop();
        await database.close();
      },
    );

    testWidgets(
      'unhealthy once a synced row has been dirty for longer than the '
      'grace period, and heals once it is pushed',
      (tester) async {
        final database = AppDatabase(NativeDatabase.memory());
        var currentTime = DateTime.utc(2026, 8, 11, 8);
        final transport = FakeSyncTransport();
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            clockProvider.overrideWithValue(Clock(() => currentTime)),
            syncTransportProvider.overrideWithValue(transport),
            authGatewayProvider.overrideWithValue(
              FakeAuthGateway(
                currentUser: const AuthUser(id: 'u1', email: 'me@example.com'),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(householdRepositoryProvider)
            .createLocalHousehold('Me');
        container.read(syncEngineControllerProvider);
        final householdId = await _awaitBootstrap(tester, container);

        await container
            .read(settingsRepositoryProvider)
            .setSyncLinked(householdId: householdId, linkedAt: currentTime);
        await _awaitLinkedEngine(tester, container);

        transport.beforeUpsert = () async {
          throw Exception('simulated permanent push failure');
        };
        await container
            .read(shoppingRepositoryProvider)
            .addItem(householdId, name: 'Milk');
        // Let the debounced push attempt (and fail) -- 5s against the
        // engine's default 2s debounce, matching the proven-safe margin
        // `test/app/sync_engine_provider_test.dart` already uses for the
        // same default debounce.
        await tester.pump(const Duration(seconds: 5));
        expect(
          container.read(syncHealthStatusProvider),
          SyncHealthStatus.healthy,
          reason: 'freshly dirty -- still inside the grace period',
        );

        currentTime = currentTime.add(const Duration(minutes: 4));
        container.invalidate(syncHealthStatusProvider);
        expect(
          container.read(syncHealthStatusProvider),
          SyncHealthStatus.unhealthy,
        );

        // Recovery: let the push succeed. `transport.now` is the FAKE
        // SERVER's own clock (defaults to 2026-01-01, independent of this
        // test's `currentTime`) -- it stamps `updated_at` on every pushed
        // row and is what the following pull's `serverNow()` returns, so
        // it must be brought up to `currentTime` first. Otherwise the
        // pull below would set `syncLastPulledAt` to the fake's stale
        // default and the final assertion would see an ancient cursor and
        // wrongly stay unhealthy.
        transport.now = currentTime;
        transport.beforeUpsert = null;
        await container.read(syncEngineProvider).pushDirty();
        await tester.pump(const Duration(milliseconds: 50));
        container.invalidate(syncHealthStatusProvider);
        expect(
          container.read(syncHealthStatusProvider),
          SyncHealthStatus.healthy,
        );

        container.read(syncEngineProvider).stop();
        await database.close();
      },
    );
  }
  ```

- [ ] **Step 2: Run and confirm RED**

  ```bash
  env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/app/sync_health_status_provider_test.dart
  ```

  Expected: fails to compile — `syncHealthStatusProvider`/`dirtySinceProvider`
  don't exist yet.

- [ ] **Step 3: Implement**

  **3a.** Add two imports to `lib/app/providers.dart`. Find:

  ```dart
  import 'package:chore_app/data/repositories/shopping_repository.dart';
  import 'package:chore_app/domain/digest_planner.dart';
  import 'package:chore_app/domain/recurrence/plain_date.dart';
  ```

  Replace with:

  ```dart
  import 'package:chore_app/data/repositories/shopping_repository.dart';
  import 'package:chore_app/data/repositories/sync_repository.dart';
  import 'package:chore_app/domain/digest_planner.dart';
  import 'package:chore_app/domain/recurrence/plain_date.dart';
  import 'package:chore_app/domain/sync_health.dart';
  ```

  **3b.** Add a note to the file's top doc comment. Find:

  ```dart
  /// point, used only by `test/app/sync_engine_provider_test.dart` to exercise
  /// [syncEngineProvider]'s own linked-state branching against a fake
  /// transport, bypassing the compile-time [supabaseConfigured] gate that a
  /// test binary can't otherwise flip; see its own doc comment.
  library;
  ```

  Replace with:

  ```dart
  /// point, used only by `test/app/sync_engine_provider_test.dart` to exercise
  /// [syncEngineProvider]'s own linked-state branching against a fake
  /// transport, bypassing the compile-time [supabaseConfigured] gate that a
  /// test binary can't otherwise flip; see its own doc comment.
  /// [syncHealthStatusProvider] (spec `docs/specs/sync-freshness.md` §2.5)
  /// is a seventh, used only by `test/features/chores/
  /// sync_health_banner_test.dart` and `test/features/shopping/
  /// sync_health_banner_test.dart` to check the D-5 banner's own
  /// render/hide wiring without reconstructing a real unhealthy condition
  /// -- every other test (including `test/app/
  /// sync_health_status_provider_test.dart`) computes it for real.
  library;
  ```

  **3c.** Add the two new providers. Find the end of `syncEngineProvider`
  (the blank line and doc comment right before `currentHouseholdProvider`):

  ```dart
  final syncEngineProvider = Provider<SyncEngine>((ref) {
    final transport = ref.watch(syncTransportProvider);
    final linkedHouseholdId = ref.watch(
      settingsProvider.select(
        (settings) => settings.valueOrNull?.syncHouseholdId,
      ),
    );
    final signedIn = ref.watch(currentAuthUserProvider).valueOrNull != null;
    if (transport == null || linkedHouseholdId == null || !signedIn) {
      return const NoopSyncEngine();
    }
    final engine = SupabaseSyncEngine(
      db: ref.watch(appDatabaseProvider),
      transport: transport,
      settings: ref.watch(settingsRepositoryProvider),
      householdId: linkedHouseholdId,
    )..start();
    ref.onDispose(engine.stop);
    return engine;
  });

  /// The bootstrap household's own row (currently just its `name`), kept in
  ```

  Replace with:

  ```dart
  final syncEngineProvider = Provider<SyncEngine>((ref) {
    final transport = ref.watch(syncTransportProvider);
    final linkedHouseholdId = ref.watch(
      settingsProvider.select(
        (settings) => settings.valueOrNull?.syncHouseholdId,
      ),
    );
    final signedIn = ref.watch(currentAuthUserProvider).valueOrNull != null;
    if (transport == null || linkedHouseholdId == null || !signedIn) {
      return const NoopSyncEngine();
    }
    final engine = SupabaseSyncEngine(
      db: ref.watch(appDatabaseProvider),
      transport: transport,
      settings: ref.watch(settingsRepositoryProvider),
      householdId: linkedHouseholdId,
    )..start();
    ref.onDispose(engine.stop);
    return engine;
  });

  /// The wall-clock moment the household's synced tables most recently
  /// transitioned from "nothing dirty" to "something dirty" (spec
  /// `docs/specs/sync-freshness.md` §2.5), `null` while clean. In-memory
  /// only, derived live from [SyncRepository.watchAnyDirty] -- an app
  /// restart giving the benefit of the doubt is fine: if the underlying
  /// row really is still stuck dirty, the clock simply starts again from
  /// the restart rather than losing the signal entirely.
  ///
  /// Deliberately built by calling [SyncRepository.watchAnyDirty] directly
  /// inside this provider's own stream, NOT by composing a separate
  /// `StreamProvider` via its `.stream` modifier -- that modifier is
  /// `@Deprecated` in this project's pinned riverpod version (2.6.1) and
  /// would trip `flutter analyze --fatal-infos`.
  final dirtySinceProvider = StreamProvider<DateTime?>((ref) {
    final db = ref.watch(appDatabaseProvider);
    final clock = ref.watch(clockProvider);
    return dirtySinceStream(SyncRepository(db).watchAnyDirty(), clock.now);
  });

  /// The D-5 offline/can't-reach-server indicator's source of truth (spec
  /// `docs/specs/sync-freshness.md` §2.5): [SyncHealthStatus.healthy]
  /// whenever the device isn't linked+signed-in at all -- the same gate
  /// [syncEngineProvider] itself applies, so "not linked" and "linked,
  /// signed out" (spec `docs/feedback/2026-08-07-field-feedback.md` A1.1)
  /// never show anything here, exactly like the pull-to-refresh indicator
  /// -- otherwise inferred by [computeSyncHealth] from the persisted pull
  /// cursor/link time ([settingsProvider]) and the live
  /// [dirtySinceProvider] watch. Never reads `SyncEngine`'s own swallowed
  /// errors (spec `docs/specs/sync-backend.md` §8.3, deliberately
  /// untouched by this indicator -- see `sync-freshness.md` §2.5 for why).
  ///
  /// Recomputes whenever [syncEngineProvider], [settingsProvider], or
  /// [dirtySinceProvider] change -- NOT on a live ticking clock
  /// (deliberate; see §2.5's "known limitation"). Something in that list
  /// changes often enough in ordinary use (any local write, any successful
  /// pull, app resume, linking/unlinking) that a lingering failure
  /// surfaces within a normal session; it will not update purely from
  /// wall-clock time passing with zero app activity.
  final syncHealthStatusProvider = Provider<SyncHealthStatus>((ref) {
    final linked = ref.watch(syncEngineProvider) is! NoopSyncEngine;
    if (!linked) {
      return SyncHealthStatus.healthy;
    }
    final settings = ref.watch(settingsProvider).valueOrNull;
    final linkedAtRaw = settings?.syncLinkedAt;
    if (linkedAtRaw == null) {
      // Momentarily true right after linking, before this provider's
      // settings watch has seen the post-link write land -- treat as
      // healthy rather than guessing.
      return SyncHealthStatus.healthy;
    }
    final lastPulledAtRaw = settings?.syncLastPulledAt;
    final dirtySince = ref.watch(dirtySinceProvider).valueOrNull;
    return computeSyncHealth(
      now: ref.watch(clockProvider).now(),
      lastPulledAt: lastPulledAtRaw == null
          ? null
          : DateTime.parse(lastPulledAtRaw),
      linkedAt: DateTime.parse(linkedAtRaw),
      dirtySince: dirtySince,
    );
  });

  /// The bootstrap household's own row (currently just its `name`), kept in
  ```

- [ ] **Step 4: Run and confirm GREEN**

  ```bash
  env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/app/sync_health_status_provider_test.dart
  ```

- [ ] **Step 5: Run the sync-adjacent regression suite**

  ```bash
  env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/app/sync_engine_provider_test.dart test/app/providers_test.dart
  ```

  Expected: all green — this task only adds two new providers, it doesn't
  change `syncEngineProvider`'s own body.

- [ ] **Step 6: Analyze**

  ```bash
  env -u GIT_DIR -u GIT_INDEX_FILE flutter analyze --fatal-infos lib/app/providers.dart lib/domain/sync_health.dart lib/data/repositories/sync_repository.dart
  ```

  Expected: `No issues found!` (confirms no deprecated-member-use warning
  from `.stream`).

- [ ] **Step 7: Commit**

  ```bash
  git add lib/app/providers.dart test/app/sync_health_status_provider_test.dart
  git commit -m "Wire dirtySinceProvider and syncHealthStatusProvider (D-5)"
  ```

## Task 5 — l10n string

**Files:**
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_de.arb`

- [ ] **Step 1: Add the English entry**

  In `lib/l10n/app_en.arb`, find:

  ```json
  "syncRefreshError": "Couldn't reach the household. Your changes are saved here and will sync later.",
  "@syncRefreshError": {
    "description": "Snackbar shown when a USER-INITIATED pull-to-refresh fails (spec docs/specs/sync-freshness.md 2.3). Reassures rather than alarms: a local-first app has not lost anything, it just could not reach the server. The background triggers stay silent by design; only this explicit user action reports failure."
  },
  ```

  Replace with:

  ```json
  "syncRefreshError": "Couldn't reach the household. Your changes are saved here and will sync later.",
  "@syncRefreshError": {
    "description": "Snackbar shown when a USER-INITIATED pull-to-refresh fails (spec docs/specs/sync-freshness.md 2.3). Reassures rather than alarms: a local-first app has not lost anything, it just could not reach the server. The background triggers stay silent by design; only this explicit user action reports failure."
  },
  "syncHealthBannerMessage": "This device hasn't reached the rest of the household in a while. Your changes are saved — try pulling down to refresh.",
  "@syncHealthBannerMessage": {
    "description": "The D-5 offline/can't-reach-server banner shown above the chores/shopping lists (spec docs/specs/sync-freshness.md 2.5) whenever syncHealthStatusProvider is unhealthy. Reassuring, not alarming -- same tone as syncRefreshError. Never says 'offline': the device may have a perfectly good connection while still unable to reach the household (e.g. a server-side permissions issue). Names the user's existing recourse (pull-to-refresh) rather than just reporting a problem with no way to act on it (Igor's decision -- a notice with no recourse is the same dead-end class as ticket E-2's startup error screen); deliberately NOT a tappable banner and NOT a second control -- pull-to-refresh already exists on both list screens, so the copy points at it instead of duplicating it."
  },
  ```

- [ ] **Step 2: Add the German entry**

  **Do not copy the JSON block below verbatim as your search string.**
  Run `grep -n '"syncRefreshError"' lib/l10n/app_de.arb` first and use
  whatever it prints as the actual anchor: this specific line's umlauts
  are stored as six-character backslash-`u` JSON escape codes in the real
  file (confirmed with `xxd`), not as plain accented characters, even
  though the rendering below (and most other entries in the same file)
  shows/uses plain accented characters. Read the real line, match it
  byte-for-byte, then append the new key after it:

  ```json
  "syncRefreshError": "Haushalt nicht erreichbar. Deine Änderungen sind hier gespeichert und werden später synchronisiert.",
  ```

  Replace with:

  ```json
  "syncRefreshError": "Haushalt nicht erreichbar. Deine Änderungen sind hier gespeichert und werden später synchronisiert.",
  "syncHealthBannerMessage": "Dieses Gerät hat den Rest des Haushalts schon eine Weile nicht erreicht. Deine Änderungen sind gespeichert – zieh die Liste nach unten, um es erneut zu versuchen.",
  ```

  (The new line uses literal UTF-8 characters, matching this same file's
  own `settingsAccountPausedNotice` entry — this file already mixes both
  escaping styles across different keys, so either is consistent with
  something already there.)

  (App_de.arb entries are plain key/value pairs with no `@`-metadata blocks
  of their own — matching every other entry in this file.)

- [ ] **Step 3: Regenerate localizations and confirm the app compiles**

  ```bash
  env -u GIT_DIR -u GIT_INDEX_FILE flutter gen-l10n
  env -u GIT_DIR -u GIT_INDEX_FILE flutter analyze --fatal-infos lib/l10n/
  ```

  Expected: `No issues found!`, and each of
  `lib/l10n/app_localizations.dart`, `lib/l10n/app_localizations_en.dart`,
  `lib/l10n/app_localizations_de.dart` (confirmed present and git-tracked
  via `l10n.yaml` + `pubspec.yaml`'s `flutter.generate: true`) now declares
  `syncHealthBannerMessage`.

- [ ] **Step 4: Commit**

  ```bash
  git add lib/l10n/app_en.arb lib/l10n/app_de.arb lib/l10n/app_localizations.dart lib/l10n/app_localizations_en.dart lib/l10n/app_localizations_de.dart
  git commit -m "Add syncHealthBannerMessage l10n string (D-5)"
  ```

## Task 6 — `SyncHealthBanner` widget, wired into the chores list

**Files:**
- Create: `lib/features/sync/sync_health_banner.dart`
- Modify: `lib/features/chores/chores_list_screen.dart`
- Test: `test/features/chores/sync_health_banner_test.dart`

**Interfaces:**
- Consumes: `syncHealthStatusProvider` (Task 4), `SyncHealthStatus` (Task
  2), `syncHealthBannerMessage` (Task 5).
- Produces: `class SyncHealthBanner extends ConsumerWidget` — no
  parameters, semantic id `sync.health.banner`.

- [ ] **Step 1: Write the failing test**

  Create `test/features/chores/sync_health_banner_test.dart`:

  ```dart
  /// Widget coverage for [SyncHealthBanner] on the chores tab (spec
  /// `docs/specs/sync-freshness.md` §2.5): renders nothing while
  /// [syncHealthStatusProvider] is healthy, one row with the banner copy
  /// while unhealthy.
  ///
  /// Overrides [syncHealthStatusProvider] directly rather than
  /// reconstructing a real unhealthy condition -- a deliberate, narrow
  /// exception to this suite's usual "override only
  /// db/clock/transport/auth" rule (see `lib/app/providers.dart`'s file
  /// doc comment for why this override point exists). The underlying
  /// computation is already covered end to end, with real data, by
  /// `test/domain/sync_health_test.dart` and
  /// `test/app/sync_health_status_provider_test.dart`; this file's only
  /// job is the widget's own render/hide wiring.
  library;

  import 'package:chore_app/app/providers.dart';
  import 'package:chore_app/domain/sync_health.dart';
  import 'package:flutter_test/flutter_test.dart';

  import '../../test_utils/pump_app.dart';

  void main() {
    final today = DateTime(2026, 7, 24, 9);

    testChoreApp(
      'absent on the chores tab while healthy',
      today: today,
      overrides: [
        syncHealthStatusProvider.overrideWithValue(SyncHealthStatus.healthy),
      ],
      (tester, database) async {
        final handle = tester.ensureSemantics();
        expect(find.bySemanticsIdentifier('sync.health.banner'), findsNothing);
        handle.dispose();
      },
    );

    testChoreApp(
      'present on the chores tab while unhealthy, with the expected copy',
      today: today,
      overrides: [
        syncHealthStatusProvider.overrideWithValue(
          SyncHealthStatus.unhealthy,
        ),
      ],
      (tester, database) async {
        final handle = tester.ensureSemantics();
        expect(
          find.bySemanticsIdentifier('sync.health.banner'),
          findsOneWidget,
        );
        expect(
          find.text(
            "This device hasn't reached the rest of the household in a "
            'while. Your changes are saved — try pulling down to refresh.',
          ),
          findsOneWidget,
        );
        handle.dispose();
      },
    );
  }
  ```

- [ ] **Step 2: Run and confirm RED**

  ```bash
  env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/features/chores/sync_health_banner_test.dart
  ```

  Expected: fails to compile (`SyncHealthBanner`/the widget file don't
  exist yet; `syncHealthStatusProvider` does exist from Task 4).

- [ ] **Step 3: Create the widget**

  Create `lib/features/sync/sync_health_banner.dart`:

  ```dart
  /// The D-5 offline/can't-reach-server indicator (spec
  /// `docs/specs/sync-freshness.md` §2.5): a self-hiding banner shown above
  /// the list content on both the chores and shopping tabs whenever
  /// [syncHealthStatusProvider] reports [SyncHealthStatus.unhealthy] --
  /// invisible for a never-linked household, a linked-but-signed-out
  /// device (already covered by
  /// `docs/feedback/2026-08-07-field-feedback.md` A1.1's own honest state
  /// in Settings -> Account), and a linked+signed-in device that looks
  /// healthy.
  library;

  import 'package:chore_app/app/depth_card.dart';
  import 'package:chore_app/app/providers.dart';
  import 'package:chore_app/app/semantics.dart';
  import 'package:chore_app/domain/sync_health.dart';
  import 'package:chore_app/l10n/app_localizations.dart';
  import 'package:flutter/material.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';

  /// Renders nothing while healthy; otherwise one generic sentence -- see
  /// `docs/specs/sync-freshness.md` §2.5 for why the copy doesn't
  /// distinguish which of the two underlying signals tripped. Never
  /// dismissible: it disappears on its own the moment the condition
  /// clears, unlike a manually-dismissed banner which could go on hiding a
  /// still-ongoing problem.
  class SyncHealthBanner extends ConsumerWidget {
    /// Creates the banner.
    const SyncHealthBanner({super.key});

    @override
    Widget build(BuildContext context, WidgetRef ref) {
      final status = ref.watch(syncHealthStatusProvider);
      if (status == SyncHealthStatus.healthy) {
        return const SizedBox.shrink();
      }
      final l10n = AppLocalizations.of(context);
      final theme = Theme.of(context);
      final onSecondaryContainer = theme.colorScheme.onSecondaryContainer;
      return semantic(
        'sync.health.banner',
        child: DepthCard(
          color: theme.colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Icon(
                  Icons.sync_problem_outlined,
                  color: onSecondaryContainer,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.syncHealthBannerMessage,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }
  ```

- [ ] **Step 4: Wire it into the chores list**

  In `lib/features/chores/chores_list_screen.dart`, add the import. Find:

  ```dart
  import 'package:chore_app/features/chores/onboarding_name_banner.dart';
  import 'package:chore_app/l10n/app_localizations.dart';
  ```

  Replace with:

  ```dart
  import 'package:chore_app/features/chores/onboarding_name_banner.dart';
  import 'package:chore_app/features/sync/sync_health_banner.dart';
  import 'package:chore_app/l10n/app_localizations.dart';
  ```

  Then find the body `Column`'s children:

  ```dart
        children: [
          const OnboardingNameBanner(),
          const DigestPrepromptBanner(),
          // Only once occurrences have actually loaded -- avoids a
  ```

  Replace with:

  ```dart
        children: [
          const OnboardingNameBanner(),
          const DigestPrepromptBanner(),
          const SyncHealthBanner(),
          // Only once occurrences have actually loaded -- avoids a
  ```

- [ ] **Step 5: Run and confirm GREEN**

  ```bash
  env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/features/chores/sync_health_banner_test.dart
  ```

- [ ] **Step 6: Run the full chores feature test directory (regression
  check)**

  ```bash
  env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/features/chores/
  ```

  Expected: all green — every existing chores test runs with
  `syncHealthStatusProvider` NOT overridden, so it resolves to `healthy`
  (unlinked household in every one of those tests) and the banner renders
  `SizedBox.shrink()`, identical to how `OnboardingNameBanner`/
  `DigestPrepromptBanner` already behave in those same tests.

- [ ] **Step 7: Analyze**

  ```bash
  env -u GIT_DIR -u GIT_INDEX_FILE flutter analyze --fatal-infos lib/features/sync/ lib/features/chores/chores_list_screen.dart
  ```

  Expected: `No issues found!`

- [ ] **Step 8: Commit**

  ```bash
  git add lib/features/sync/sync_health_banner.dart lib/features/chores/chores_list_screen.dart test/features/chores/sync_health_banner_test.dart
  git commit -m "Add SyncHealthBanner and show it on the chores list (D-5)"
  ```

## Task 7 — wire `SyncHealthBanner` into the shopping list

**Files:**
- Modify: `lib/features/shopping/shopping_list_screen.dart`
- Test: `test/features/shopping/sync_health_banner_test.dart`

- [ ] **Step 1: Write the failing test**

  Create `test/features/shopping/sync_health_banner_test.dart`:

  ```dart
  /// Widget coverage for [SyncHealthBanner] on the shopping tab (spec
  /// `docs/specs/sync-freshness.md` §2.5) -- see
  /// `test/features/chores/sync_health_banner_test.dart` for why this
  /// overrides `syncHealthStatusProvider` directly.
  library;

  import 'package:chore_app/app/providers.dart';
  import 'package:chore_app/domain/sync_health.dart';
  import 'package:flutter_test/flutter_test.dart';

  import '../../test_utils/pump_app.dart';
  import 'shopping_test_utils.dart';

  void main() {
    final today = DateTime(2026, 7, 24, 9);

    testChoreApp(
      'absent on the shopping tab while healthy',
      today: today,
      overrides: [
        syncHealthStatusProvider.overrideWithValue(SyncHealthStatus.healthy),
      ],
      (tester, database) async {
        final handle = tester.ensureSemantics();
        await openShoppingTab(tester);
        expect(find.bySemanticsIdentifier('sync.health.banner'), findsNothing);
        handle.dispose();
      },
    );

    testChoreApp(
      'present on the shopping tab while unhealthy',
      today: today,
      overrides: [
        syncHealthStatusProvider.overrideWithValue(
          SyncHealthStatus.unhealthy,
        ),
      ],
      (tester, database) async {
        final handle = tester.ensureSemantics();
        await openShoppingTab(tester);
        expect(
          find.bySemanticsIdentifier('sync.health.banner'),
          findsOneWidget,
        );
        handle.dispose();
      },
    );
  }
  ```

- [ ] **Step 2: Run and confirm RED**

  ```bash
  env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/features/shopping/sync_health_banner_test.dart
  ```

  Expected: fails — `sync.health.banner` never found, since
  `ShoppingListScreen` doesn't render `SyncHealthBanner` yet.

- [ ] **Step 3: Wire it in**

  In `lib/features/shopping/shopping_list_screen.dart`, add the import.
  Find:

  ```dart
  import 'package:chore_app/features/shopping/shopping_quick_add_row.dart';
  import 'package:chore_app/l10n/app_localizations.dart';
  ```

  Replace with:

  ```dart
  import 'package:chore_app/features/shopping/shopping_quick_add_row.dart';
  import 'package:chore_app/features/sync/sync_health_banner.dart';
  import 'package:chore_app/l10n/app_localizations.dart';
  ```

  Then find the body `Column`'s children:

  ```dart
        body: Column(
          children: [
            const ShoppingQuickAddRow(),
            Expanded(
  ```

  Replace with:

  ```dart
        body: Column(
          children: [
            const SyncHealthBanner(),
            const ShoppingQuickAddRow(),
            Expanded(
  ```

- [ ] **Step 4: Run and confirm GREEN**

  ```bash
  env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/features/shopping/sync_health_banner_test.dart
  ```

- [ ] **Step 5: Run the full shopping feature test directory (regression
  check)**

  ```bash
  env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/features/shopping/
  ```

  Expected: all green, same reasoning as Task 6 Step 6.

- [ ] **Step 6: Full suite + analyze**

  ```bash
  env -u GIT_DIR -u GIT_INDEX_FILE flutter analyze --fatal-infos
  env -u GIT_DIR -u GIT_INDEX_FILE flutter test
  ```

  Expected: `No issues found!` and the entire suite green. If another
  agent's concurrent changes (e.g. B-6) cause unrelated failures, re-run
  scoped to this plan's own files to confirm this plan's slice is clean,
  and flag the unrelated failures separately rather than debugging them
  here.

- [ ] **Step 7: Commit**

  ```bash
  git add lib/features/shopping/shopping_list_screen.dart test/features/shopping/sync_health_banner_test.dart
  git commit -m "Show SyncHealthBanner on the shopping list too (D-5)"
  ```

---

## Done criteria

- `flutter analyze --fatal-infos` clean; `flutter test` green, including
  every new test file listed in the File map.
- `lib/application/sync_engine.dart` is untouched (byte-for-byte identical
  to before this plan) — confirms the B-6 seam.
- `docs/specs/sync-freshness.md` has a new §2.5 matching the shipped
  behavior; `docs/specs/sync-backend.md` is unmodified.
- The banner is invisible for a never-linked household and a
  linked-but-signed-out device on both the chores and shopping tabs, and
  appears with the correct copy once `syncHealthStatusProvider` is
  unhealthy.
- `docs/backlog.md` row D-5 can be marked closed once this lands (not done
  by this plan — left to whoever merges it, per this repo's practice of
  updating the backlog at merge time).
