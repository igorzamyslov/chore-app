/// Widget coverage for the catch-up visibility banner (backlog B-1 / triage
/// T2.1): hidden/shown per `catchUpBannerCountProvider`, the singular and
/// plural copy, dismissal, the fact that a LATER lapse can explain itself
/// again after an earlier banner was dismissed, and — the one that proves
/// the whole feature is live — a real cold start over a real overdue backlog.
library;

import 'package:chore_app/app/app.dart';
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// The English copy the ARB produces for one and for several chores. Spelled
/// out here rather than read back from `AppLocalizations`, so a copy edit has
/// to be made deliberately in both places instead of a test happily asserting
/// whatever the app now says.
const _singularCopy =
    'We moved 1 overdue chore forward to its most recent due date, so '
    'nothing piled up.';
const _pluralCopyForTwo =
    'We moved 2 overdue chores forward to their most recent due dates, so '
    'nothing piled up.';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'hidden when nothing was caught up — the overwhelmingly common launch',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      expect(find.bySemanticsIdentifier('catchup.banner'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'one chore caught up: singular copy, no bare count',
    today: today,
    overrides: [catchUpBannerCountProvider.overrideWith((ref) => 1)],
    (tester, database) async {
      final handle = tester.ensureSemantics();

      expect(find.bySemanticsIdentifier('catchup.banner'), findsOneWidget);
      expect(find.text(_singularCopy), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'several chores caught up: plural copy naming the number',
    today: today,
    overrides: [catchUpBannerCountProvider.overrideWith((ref) => 2)],
    (tester, database) async {
      expect(find.text(_pluralCopyForTwo), findsOneWidget);
    },
  );

  testChoreApp(
    'dismissing hides it, and a LATER lapse can still explain itself: the '
    'dismissal is not the once-ever flag the first-run banners use',
    today: today,
    overrides: [catchUpBannerCountProvider.overrideWith((ref) => 2)],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsIdentifier('catchup.banner'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('catchup.banner.dismiss'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('catchup.banner'), findsNothing);

      // A fresh catch-up run reporting a fresh count — the shape a second
      // lapse weeks later produces. Nothing was persisted, so this shows
      // again; a `settings`-table flag would have silenced it forever.
      ProviderScope.containerOf(
        tester.element(find.byType(ChoreApp)),
        listen: false,
      ).read(catchUpBannerCountProvider.notifier).state = 1;
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('catchup.banner'), findsOneWidget);
      expect(find.text(_singularCopy), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'THE FIX, end to end: a cold start over a real two-week backlog rolls two '
    'chores forward and says so on the first frame, above the first-run '
    'banners',
    today: today,
    // Seeded BEFORE the app is pumped: bootstrapProvider runs catch-up to
    // completion before any widget builds, which is precisely the silence
    // this ticket is about (see testChoreApp's `seed` doc comment).
    seed: (database) async {
      final householdId = await currentHouseholdId(database);
      final service = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(DateTime(2026, 7, 10, 9)),
      );
      await service.createChore(
        householdId: householdId,
        title: 'Bins',
        startDate: PlainDate(2026, 7, 10),
        assignmentMode: AssignmentMode.anyone,
        recurrence: Recurrence.everyNDays(1),
      );
      // Differently spaced, so this is two distinct chores rather than two
      // copies of one fixture. Slots run 7/10, 7/12 ... 7/24.
      await service.createChore(
        householdId: householdId,
        title: 'Bathroom',
        startDate: PlainDate(2026, 7, 10),
        assignmentMode: AssignmentMode.anyone,
        recurrence: Recurrence.everyNDays(2),
      );
    },
    (tester, database) async {
      final handle = tester.ensureSemantics();

      expect(find.bySemanticsIdentifier('catchup.banner'), findsOneWidget);
      expect(find.text(_pluralCopyForTwo), findsOneWidget);

      // Ordering (a recorded decision): somebody coming back after a lapse
      // needs the what-just-happened explanation before the evergreen
      // first-run prompts. The name banner shows here too — this is a fresh
      // bootstrap household — which is what makes the comparison meaningful.
      final nameBannerCopy = find.text("Who's doing the chores here?");
      expect(nameBannerCopy, findsOneWidget);
      expect(
        tester.getTopLeft(find.text(_pluralCopyForTwo)).dy,
        lessThan(tester.getTopLeft(nameBannerCopy).dy),
      );

      handle.dispose();
    },
  );
}
