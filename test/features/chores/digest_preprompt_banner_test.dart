import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/application/notification_scheduler.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../application/fake_digest_notification_plugin.dart';
import '../../test_utils/pump_app.dart';

/// Widget coverage for the digest pre-prompt banner (spec
/// `docs/specs/polish-round-1.md` A3): the four-way visibility gate, and
/// the 'Turn on'/'Not now' action paths.
void main() {
  final today = DateTime(2026, 7, 24, 9);

  Future<void> seedChoreDueToday(AppDatabase database) async {
    final householdId = await currentHouseholdId(database);
    final service = ChoreService(
      database: database,
      chores: ChoreRepository(database),
      clock: Clock.fixed(today),
    );
    await service.createChore(
      householdId: householdId,
      title: 'Water plants',
      startDate: PlainDate(2026, 7, 24),
      assignmentMode: AssignmentMode.anyone,
    );
  }

  testChoreApp(
    'hidden on a fresh install (no chores yet) even with the OS '
    'permission denied — the name banner shows first instead',
    today: today,
    overrides: [
      notificationPermissionGrantedProvider.overrideWith((ref) => false),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();

      expect(find.bySemanticsIdentifier('digest.preprompt'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'shown once a chore exists, digest enabled, permission denied, flag '
    'unset',
    today: today,
    overrides: [
      notificationPermissionGrantedProvider.overrideWith((ref) => false),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await seedChoreDueToday(database);
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('digest.preprompt'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('digest.preprompt.enable'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('digest.preprompt.dismiss'),
        findsOneWidget,
      );
      expect(find.text("Want a daily summary of what's due?"), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'hidden when the OS permission is already granted (default state)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await seedChoreDueToday(database);
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('digest.preprompt'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'hidden when the digest itself is disabled',
    today: today,
    overrides: [
      notificationPermissionGrantedProvider.overrideWith((ref) => false),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await seedChoreDueToday(database);
      await SettingsRepository(database).setDigestEnabled(enabled: false);
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('digest.preprompt'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'flag already marked: stays hidden even though every other condition '
    'holds',
    today: today,
    overrides: [
      notificationPermissionGrantedProvider.overrideWith((ref) => false),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await seedChoreDueToday(database);
      await SettingsRepository(database).markDigestPrepromptShown();
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('digest.preprompt'), findsNothing);

      handle.dispose();
    },
  );

  final dismissPlugin = FakeDigestNotificationPlugin();
  testChoreApp(
    '"Not now" marks the flag and hides the banner WITHOUT requesting the '
    'OS permission',
    today: today,
    overrides: [
      notificationPermissionGrantedProvider.overrideWith((ref) => false),
      digestNotificationPluginProvider.overrideWithValue(dismissPlugin),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await seedChoreDueToday(database);
      await tester.pumpAndSettle();
      expect(find.bySemanticsIdentifier('digest.preprompt'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('digest.preprompt.dismiss'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('digest.preprompt'), findsNothing);
      expect(dismissPlugin.requestPermissionCallCount, 0);
      final settings = await database.select(database.settings).getSingle();
      expect(settings.digestPrepromptShownAt, isNotNull);
      // Digest stays enabled — 'Not now' only silences the pre-prompt, not
      // the digest itself.
      expect(settings.digestEnabled, isTrue);

      handle.dispose();
    },
  );

  final enablePlugin = FakeDigestNotificationPlugin();
  testChoreApp(
    '"Turn on" marks the flag, requests the OS permission exactly once, '
    'and triggers a digest recompute',
    today: today,
    overrides: [
      notificationPermissionGrantedProvider.overrideWith((ref) => false),
      digestNotificationPluginProvider.overrideWithValue(enablePlugin),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await seedChoreDueToday(database);
      await tester.pumpAndSettle();
      expect(find.bySemanticsIdentifier('digest.preprompt'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('digest.preprompt.enable'));
      await tester.pumpAndSettle();

      expect(enablePlugin.requestPermissionCallCount, 1);
      // One chore due today: the recompute must have scheduled a digest.
      expect(enablePlugin.scheduledCalls, isNotEmpty);
      expect(
        enablePlugin.pending.keys,
        everyElement(isIn(digestNotificationIds)),
        reason: 'the banner must arm the same horizon the controller does',
      );
      final settings = await database.select(database.settings).getSingle();
      expect(settings.digestPrepromptShownAt, isNotNull);
      expect(find.bySemanticsIdentifier('digest.preprompt'), findsNothing);

      handle.dispose();
    },
  );
}
