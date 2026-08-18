/// Threshold matrix for [computeSyncHealth] and unit coverage for
/// [dirtySinceStream] (spec `docs/specs/sync-freshness.md` §2.5).
library;

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
        observingSince: linkedAt,
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
        observingSince: linkedAt,
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
        observingSince: linkedAt,
        dirtySince: null,
      );
      expect(status, SyncHealthStatus.unhealthy);
    });

    test(
      'unhealthy: never pulled yet AND linked longer than pullStaleAfter ago',
      () {
        final now = linkedAt.add(const Duration(minutes: 6));
        final status = computeSyncHealth(
          now: now,
          lastPulledAt: null,
          linkedAt: linkedAt,
          observingSince: linkedAt,
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
          observingSince: linkedAt,
          dirtySince: null,
        );
        expect(status, SyncHealthStatus.healthy);
      },
    );

    test(
      'unhealthy: dirty rows stuck longer than dirtyStaleAfter even though '
      'pulls are fresh (asymmetric push-only failure)',
      () {
        final now = linkedAt.add(const Duration(minutes: 30));
        final status = computeSyncHealth(
          now: now,
          lastPulledAt: now.subtract(const Duration(seconds: 5)),
          linkedAt: linkedAt,
          observingSince: linkedAt,
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
        observingSince: linkedAt,
        dirtySince: null,
        pullStaleAfter: const Duration(minutes: 1),
      );
      expect(status, SyncHealthStatus.unhealthy);
    });

    group('observingSince floor (spec §2.5)', () {
      test(
        'healthy right after a cold start over an hours-old cursor: the '
        'device has not had a chance to fail yet',
        () {
          final now = linkedAt.add(const Duration(hours: 3));
          final status = computeSyncHealth(
            now: now,
            lastPulledAt: linkedAt,
            linkedAt: linkedAt,
            // The engine session began this instant.
            observingSince: now,
            dirtySince: null,
          );
          expect(status, SyncHealthStatus.healthy);
        },
      );

      test(
        'unhealthy once that same session has itself been failing longer '
        'than pullStaleAfter',
        () {
          final sessionStart = linkedAt.add(const Duration(hours: 3));
          final status = computeSyncHealth(
            now: sessionStart.add(const Duration(minutes: 6)),
            lastPulledAt: linkedAt,
            linkedAt: linkedAt,
            observingSince: sessionStart,
            dirtySince: null,
          );
          expect(status, SyncHealthStatus.unhealthy);
        },
      );

      test(
        'the floor never HIDES a stale cursor within the same session: a '
        'pull that landed after the session began still wins',
        () {
          final sessionStart = linkedAt;
          final now = sessionStart.add(const Duration(minutes: 30));
          final status = computeSyncHealth(
            now: now,
            // Pulled 20 minutes into the session, then stopped.
            lastPulledAt: sessionStart.add(const Duration(minutes: 20)),
            linkedAt: linkedAt,
            observingSince: sessionStart,
            dirtySince: null,
          );
          expect(status, SyncHealthStatus.unhealthy);
        },
      );
    });
  });

  group('dirtySinceStream', () {
    test(
      'pins to the moment dirty first flips true, resets on false, never '
      're-reads the clock on a true-to-true repeat',
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
          return DateTime.utc(2026).add(Duration(minutes: calls));
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
          reason:
              'now() must only be called on a false-to-true transition, '
              'twice across this sequence',
        );
      },
    );
  });
}
