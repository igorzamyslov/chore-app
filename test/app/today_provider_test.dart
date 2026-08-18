/// [todayProvider] tests (backlog A-2 / audit P1): the single source of
/// truth for the UI's "today", seeded from [clockProvider] and republished
/// by [TodayNotifier.refresh].
///
/// No database and no widget tree needed — this provider depends on nothing
/// but the clock, so a bare [ProviderContainer] with a mutable clock is the
/// whole fixture.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('todayProvider', () {
    test('seeds from clockProvider', () {
      final container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(
            Clock.fixed(DateTime(2026, 1, 5, 9)),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(todayProvider), PlainDate(2026, 1, 5));
    });

    test("refresh() republishes the clock's new calendar day", () {
      var currentTime = DateTime(2026, 1, 5, 23, 59, 50);
      final container = ProviderContainer(
        overrides: [clockProvider.overrideWithValue(Clock(() => currentTime))],
      );
      addTearDown(container.dispose);
      expect(container.read(todayProvider), PlainDate(2026, 1, 5));

      currentTime = DateTime(2026, 1, 6, 0, 0, 1);
      container.read(todayProvider.notifier).refresh();

      expect(container.read(todayProvider), PlainDate(2026, 1, 6));
    });

    test(
      'refresh() notifies nobody when the calendar day has not changed — so '
      'calling it on every app resume never re-subscribes the streams that '
      'watch it',
      () {
        var currentTime = DateTime(2026, 1, 5, 9);
        final container = ProviderContainer(
          overrides: [
            clockProvider.overrideWithValue(Clock(() => currentTime)),
          ],
        );
        addTearDown(container.dispose);
        var notifications = 0;
        container.listen<PlainDate>(
          todayProvider,
          (previous, next) => notifications++,
        );

        // Same day, later hour: three resumes, no notification.
        currentTime = DateTime(2026, 1, 5, 14);
        container.read(todayProvider.notifier).refresh();
        currentTime = DateTime(2026, 1, 5, 22);
        container.read(todayProvider.notifier).refresh();
        container.read(todayProvider.notifier).refresh();
        expect(notifications, 0);

        // Crossing into the next day notifies exactly once.
        currentTime = DateTime(2026, 1, 6, 0, 0, 1);
        container.read(todayProvider.notifier).refresh();
        expect(notifications, 1);
      },
    );
  });
}
