import 'package:chore_app/app/theme.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/features/chores/chore_form/assignment_fields.dart';
import 'package:chore_app/features/members/member_avatar.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Isolated widget tests for `AssignmentFields`' rotation-mode reorder
/// wiring (backlog B-4 / triage T2.5): re-tapping a member used to be the
/// ONLY way to change rotation order (always re-appending at the end);
/// this widget now also exposes a compact reorderable list for already
/// -selected members.
void main() {
  Member member(String id, String name) => Member(
    syncDirty: false,
    id: id,
    householdId: 'h1',
    name: name,
    color: 0xFF8C7BC9,
    role: MemberRole.member,
    createdAt: 't0',
    updatedAt: 't0',
  );

  final anna = member('m-anna', 'Anna');
  final ben = member('m-ben', 'Ben');
  final mia = member('m-mia', 'Mia');

  Future<void> pumpAssignmentFields(
    WidgetTester tester, {
    required List<String> selectedMemberIds,
    ValueChanged<String>? onMemberTap,
    void Function(int oldIndex, int newIndex)? onReorder,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: appLightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AssignmentFields(
            mode: AssignmentMode.rotation,
            onModeChanged: (_) {},
            members: [anna, ben, mia],
            selectedMemberIds: selectedMemberIds,
            onMemberTap: onMemberTap ?? (_) {},
            onReorder: onReorder ?? (_, __) {},
          ),
        ),
      ),
    );
  }

  testWidgets(
    'each selected rotation member gets a >= 48dp drag handle; unselected '
    "members don't",
    (tester) async {
      final handle = tester.ensureSemantics();
      await pumpAssignmentFields(tester, selectedMemberIds: [anna.id, ben.id]);

      final annaHandle = find.bySemanticsIdentifier(
        'chore_form.assignee.${anna.id}.drag',
      );
      final benHandle = find.bySemanticsIdentifier(
        'chore_form.assignee.${ben.id}.drag',
      );
      expect(annaHandle, findsOneWidget);
      expect(benHandle, findsOneWidget);
      final handleSize = tester.getSize(annaHandle);
      expect(handleSize.width, greaterThanOrEqualTo(48));
      expect(handleSize.height, greaterThanOrEqualTo(48));

      expect(
        find.bySemanticsIdentifier('chore_form.assignee.${mia.id}.drag'),
        findsNothing,
      );

      handle.dispose();
    },
  );

  testWidgets('selected rows show the order label and a MemberAvatar', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpAssignmentFields(tester, selectedMemberIds: [anna.id, ben.id]);

    expect(find.text('1. Anna'), findsOneWidget);
    expect(find.text('2. Ben'), findsOneWidget);
    for (final id in [anna.id, ben.id]) {
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('chore_form.assignee.$id'),
          matching: find.byType(MemberAvatar),
        ),
        findsOneWidget,
      );
    }

    handle.dispose();
  });

  testWidgets(
    "the reorderable list's onReorderItem calls onReorder with the same "
    'indices (no manual off-by-one adjustment expected of the caller)',
    (tester) async {
      (int, int)? captured;
      await pumpAssignmentFields(
        tester,
        selectedMemberIds: [anna.id, ben.id, mia.id],
        onReorder: (oldIndex, newIndex) => captured = (oldIndex, newIndex),
      );

      final reorderable = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
      reorderable.onReorderItem!(0, 2);

      expect(captured, (0, 2));
    },
  );

  testWidgets(
    "tapping a selected row's remove button calls onMemberTap for that "
    'member (same removal semantics as re-tapping a chip today)',
    (tester) async {
      final handle = tester.ensureSemantics();
      String? tapped;
      await pumpAssignmentFields(
        tester,
        selectedMemberIds: [anna.id, ben.id],
        onMemberTap: (id) => tapped = id,
      );

      await tester.tap(
        find.bySemanticsIdentifier('chore_form.assignee.${ben.id}.remove'),
      );
      await tester.pump();

      expect(tapped, ben.id);

      handle.dispose();
    },
  );

  testWidgets('an unselected member still renders as a tap-to-add chip', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    String? tapped;
    await pumpAssignmentFields(
      tester,
      selectedMemberIds: [anna.id],
      onMemberTap: (id) => tapped = id,
    );

    final miaChip = find.bySemanticsIdentifier('chore_form.assignee.${mia.id}');
    expect(
      find.descendant(of: miaChip, matching: find.byType(FilterChip)),
      findsOneWidget,
    );
    await tester.tap(miaChip);
    await tester.pump();
    expect(tapped, mia.id);

    handle.dispose();
  });
}
