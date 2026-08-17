/// Pure computation behind the D-5 can't-reach-the-household indicator
/// (spec `docs/specs/sync-freshness.md` §2.5): whether a linked, signed-in
/// device's connection to its household looks healthy or worth flagging.
///
/// Deliberately never touches `SyncEngine`'s own swallow-everything failure
/// posture (spec `docs/specs/sync-backend.md` §8.3) -- every input here is
/// something the app already persists or observes for other reasons
/// (`syncLastPulledAt`, `syncLinkedAt`, and a live "any synced row still
/// dirty" watch), inferred rather than reported. See §2.5 for the full
/// rationale, including why this needs TWO independent signals rather than
/// one.
library;

/// Whether [computeSyncHealth] found anything worth flagging.
enum SyncHealthStatus {
  /// Nothing suggests a problem: the pull cursor is recent enough, and any
  /// locally dirty rows are still within the normal debounce/poll grace
  /// period.
  healthy,

  /// Either the pull cursor hasn't advanced recently enough, or dirty rows
  /// have sat unpushed longer than the grace period -- see
  /// [computeSyncHealth].
  unhealthy,
}

/// [computeSyncHealth]'s default pull-staleness grace period (spec
/// `docs/specs/sync-freshness.md` §2.5, DECIDED by Igor). A healthy linked
/// device pulls at least every 60s (the foreground safety-net poll, spec
/// §2.2), so five minutes is five missed cycles -- comfortably past a
/// tunnel, a lift, or a flaky handover, without letting real divergence sit
/// unmentioned. Named and centralized here so retuning it later is a
/// one-line diff that reads as tuning, not as a regression to revert.
const Duration defaultPullStaleAfter = Duration(minutes: 5);

/// [computeSyncHealth]'s default dirty-row grace period (spec
/// `docs/specs/sync-freshness.md` §2.5, DECIDED by Igor). The push debounce
/// is ~2s, so three minutes of continuous dirtiness is dozens of missed
/// debounce cycles -- never trips during ordinary bursty editing, but still
/// catches a push-only failure well within a normal session rather than
/// only after hours.
const Duration defaultDirtyStaleAfter = Duration(minutes: 3);

/// How often `syncHealthStatusProvider` (`lib/app/providers.dart`)
/// re-evaluates itself while linked and signed in (spec
/// `docs/specs/sync-freshness.md` §2.5's recomputation bullet).
///
/// A tick is required, not a nicety: a device that cannot reach the server
/// writes nothing, and [dirtySinceStream] deliberately pins its timestamp,
/// so in the central failure case NOTHING in Riverpod's dependency graph
/// changes and a purely reactive indicator would never fire at all. 60s
/// matches the engine's own foreground poll (spec §2.2), so worst-case
/// detection latency is one tick past whichever threshold was crossed.
const Duration syncHealthRecheckInterval = Duration(seconds: 60);

/// Computes [SyncHealthStatus] from data the app already keeps.
///
/// [now] is the current time. [lastPulledAt] is the `syncLastPulledAt`
/// cursor (`null` if this device has never completed a pull since linking).
/// [linkedAt] is `syncLinkedAt`. [observingSince] is the moment this device
/// most recently had a genuine chance to reach its household at all -- when
/// the current linked engine session began, re-armed on every app resume
/// (`syncObservingSinceProvider`, `lib/app/providers.dart`).
/// [dirtySince] is the wall-clock moment ANY synced-table row most recently
/// became continuously dirty with nothing pushed since (`null` while
/// clean) -- see [dirtySinceStream].
///
/// Pull staleness is measured from the LATEST of those three reference
/// points, never from the persisted cursor alone. [linkedAt] covers the
/// window before a freshly-linked device's first pull has ever completed;
/// [observingSince] covers the much more common case of a cold start or a
/// resume after more than [pullStaleAfter] away, where the cursor is
/// genuinely hours old but the device has not yet failed at anything -- see
/// spec §2.5, which explains why a banner that flashed on nearly every
/// launch would be the exact cry-wolf failure the thresholds exist to
/// avoid.
///
/// [pullStaleAfter]/[dirtyStaleAfter] are the two independent thresholds
/// (spec §2.5, DECIDED by Igor -- see [defaultPullStaleAfter]/
/// [defaultDirtyStaleAfter] for the rationale): either condition alone is
/// enough to report [SyncHealthStatus.unhealthy]. Two independent checks,
/// not one: a device whose PULLS keep succeeding but whose PUSHES are
/// silently and specifically broken (e.g. a permissions bug that only
/// affects writes) would never trip a pull-staleness check alone, since
/// other members' changes keep arriving fine -- only the dirty-duration
/// check catches that asymmetric failure.
SyncHealthStatus computeSyncHealth({
  required DateTime now,
  required DateTime? lastPulledAt,
  required DateTime linkedAt,
  required DateTime observingSince,
  required DateTime? dirtySince,
  Duration pullStaleAfter = defaultPullStaleAfter,
  Duration dirtyStaleAfter = defaultDirtyStaleAfter,
}) {
  final cursor = lastPulledAt ?? linkedAt;
  final pullReference = cursor;
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
/// to the first `true` after a `false` until the next `false`.
///
/// [now] is called ONLY on a false-to-true transition (never on a
/// true-to-true repeat), so the timestamp stays pinned to when the streak
/// actually started, not to when it was last observed. That pinning is what
/// makes the [defaultDirtyStaleAfter] threshold mean "unsent for three
/// minutes" rather than "unsent since the last time anything was written",
/// and it is also why `syncHealthStatusProvider` cannot rely on stream
/// emissions alone to notice the threshold being crossed (spec
/// `docs/specs/sync-freshness.md` §2.5's recomputation bullet).
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
