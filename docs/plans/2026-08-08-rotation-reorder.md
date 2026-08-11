# Rotation reorder (B-4 / T2.5) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a rotation's assignee order be edited directly (drag-reorder plus an explicit remove button) instead of only rebuildable by deselect-then-reselect, which always re-appends at the end.

**Architecture:** Pure UI change, one widget. `AssignmentFields` (`lib/features/chores/chore_form/assignment_fields.dart`) already receives `selectedMemberIds` in rotation order and an `onMemberTap` callback from `ChoreFormScreen`; add a sibling `onReorder(oldIndex, newIndex)` callback and, for `AssignmentMode.rotation` only, replace the single `Wrap` of all members with two parts: a compact `ReorderableListView` of the *selected* members (drag handle, avatar, order-labelled name, remove button — copying `manage_categories_screen.dart`'s drag-handle pattern verbatim) followed by a `Wrap` of the *not-yet-selected* members plus the existing "Add member…" chip, unchanged. `fixed` and `anyone` modes are untouched. No data-layer, repository, or schema change: `chore_assignees.position` (`lib/data/db/tables.dart:363`) is already an explicit order column, and `ChoreRepository.updateChore`/`ChoreService.updateChore` already replace the whole assignee set (delete all rows, reinsert in the given order) on every save — a reorder is just another such edit, indistinguishable at that layer from an add or remove.

**Tech Stack:** Flutter/Dart, `flutter_riverpod`, `drift`, existing `ReorderableListView`/`ReorderableDragStartListener` (already used by `manage_categories_screen.dart`, no new dependency).

## Global Constraints

- Every user-visible string goes through gen_l10n: `lib/l10n/app_en.arb` (template) + `lib/l10n/app_de.arb` (German du-form). Never inline English.
- Every interactive widget gets a stable id via `semantic()` (`lib/app/semantics.dart`); E2E selects only by id or `(?s)`-substring text.
- Widget tests are integration-style: real in-memory `AppDatabase` + fixed clock, overriding ONLY `appDatabaseProvider` and `clockProvider` (via the existing `testChoreApp` helper in `test/test_utils/pump_app.dart`). Never mock repositories or services.
- All touch targets ≥ 48×48dp (M3 minimum) — `docs/specs/design-language.md` line 67.
- Strict lints (very_good_analysis, `--fatal-infos --fatal-warnings`); public members need doc comments.
- TDD: write-failing-test → run → implement → run → commit. (One exception is called out explicitly in Task 1 below — it is a characterization test that already passes against the current code, not a red-then-green step, and the task says so.)
- Drag gestures are not simulated anywhere in this codebase's widget or E2E tests (see Task 4's rationale) — this plan follows that precedent rather than introducing flaky gesture-simulated tests.
- Never run `flutter`/`dart` commands yourself while *planning* — this plan's steps tell the *executor* which commands to run; that constraint does not apply to them.

---

## Design notes (read before starting)

**Where the ticket's premise was checked against code, and what that changed:**

1. **Persistence already supports arbitrary order.** `ChoreAssignees` (`lib/data/db/tables.dart:356-368`) has an explicit `position` `IntColumn`, not insertion order. `ChoreRepository._insertAssignees` (`lib/data/repositories/chore_repository.dart:602-613`) writes `position: i` for the given list's index `i`. `ChoreRepository.updateChore` (same file, lines 220-225), when `assigneeMemberIds != null`, deletes every existing `chore_assignees` row for the chore and reinserts the whole given list fresh. **This means reordering needs no new repository or service method** — the existing chore-form save flow (`_save()` in `lib/features/chores/chore_form_screen.dart:462-490`, which always passes the current, full `_selectedMemberIds`) already persists whatever order the in-memory list holds. The only gap is that today nothing in the UI can *produce* a reordered in-memory list except deselect-then-reselect (`_onMemberTap`, `chore_form_screen.dart:409-424`, cited exactly in the ticket).

2. **"Does the next turn stay with the same person, or shift?" is already answered by existing, tested code — not a new decision.** `ChoreService.updateChore` (`lib/application/chore_service.dart:278-338`) only regenerates the pending occurrence (and re-resolves its assignee) when `recurrence` or `startDate` changed; its own doc comment (lines 272-275) states: *"An edit that changes NEITHER `recurrence` nor `startDate` leaves the pending occurrence — and its assignee — completely untouched, no matter what else changed (title, notes, category, assignment mode/assignees)."* This is exercised today by `test/application/chore_update_regeneration_test.dart`'s `'unchanged edit'` group, specifically the test `'changing assignmentMode/assignees alone (no recurrence/startDate change) still leaves the pending occurrence untouched'` (lines 216-247), which already proves a changed assignee **list** (there, a swap from `[m1]` to `[m2]` under `fixed` mode) does not touch the current occurrence's `assignedMemberId`. A pure reorder is, at this layer, just another `assigneeMemberIds` diff through the identical code path (`assigneeMemberIds != null` in `ChoreRepository.updateChore`) — there is no branch anywhere that distinguishes "same members, new order" from "different members" or "added/removed a member". So: **the CURRENT pending occurrence's assignee never changes because of a reorder-only edit; the assignee whose turn it already is keeps that turn.** Only the *next* rotation step (computed by `nextRotationAssignee`, `lib/domain/rotation.dart`, at the following completion) reads the member's new position in the reordered list. Task 1 adds one characterization test proving this holds for reorder specifically (not just add/remove, which was already covered), so the invariant is pinned down for this feature rather than merely inherited.

3. **Removing a member from the rotation via the new UI has identical semantics to today's remove-by-re-tap — nothing new to design.** If the member currently holding the pending occurrence's `assignedMemberId` is removed from the assignee list entirely (not just moved), the same untouched-occurrence rule applies: the occurrence keeps pointing at that now-absent member until the next regeneration trigger (recurrence/startDate edit, skip, or completion) re-resolves it via `nextRotationAssignee`'s "not found → first member" fallback (`lib/domain/rotation.dart:27-31`). This is pre-existing behavior (already true for the old chip-tap-to-remove gesture); the new UI's explicit remove button calls the exact same `onMemberTap` callback the chip tap does today, so it inherits this without any new code path.

4. **Sync/tombstone risk (`docs/specs/sync-backend.md` §8.5) is unchanged by this feature.** §8.5 already documents, as an accepted P3 limitation, that `chore_assignees` has no tombstones and that "assignee edits regenerate the full set, and the next full edit from any device converges it." `ChoreRepository.updateChore`'s delete-all-then-reinsert (point 1 above) is exactly that "regenerate the full set" behavior, and it fires identically whether the edit is an add, a remove, or (with this feature) a reorder. A reorder is not a new kind of write against this limitation — it's the same write with different `position` values. No task in this plan touches sync code, and none is needed.

**UI design chosen (of the options considered):**

- **Option A (chosen): compact reorderable list for selected rotation members, chip picker for the rest.** When `mode == AssignmentMode.rotation`, selected members render as rows in a `ReorderableListView.builder` (drag handle far-left, `MemberAvatar`, "`{order}. {name}`" label, trailing remove `IconButton`) — visually and structurally the same pattern as `manage_categories_screen.dart`'s `_CategoryRow`/`_CategoryList`. Not-yet-selected members plus the "Add member…" chip stay exactly as today, in a `Wrap` below the list; tapping one still appends it to the end (unchanged `_onMemberTap` rotation branch). `fixed` and `anyone` modes keep today's single `Wrap` untouched.
  - *Why:* matches the ticket's own suggestion ("consider whether the assignee list becomes a compact reorderable list when rotation is selected"), directly copies an existing, already-reviewed in-app pattern (least design risk, least new code), and keeps the add-a-missing-member flow (chip row + inline "Add member…" sheet) completely unchanged.
- **Option B (rejected): drag handles bolted onto the existing `FilterChip`s inside the `Wrap`.** Rejected because `Wrap` has no reorder semantics of its own (no `ReorderableListView` equivalent for wrapped/flowed layouts) and chip drag-reordering inside a wrap is exactly what the ticket calls "awkward" — there's no established Flutter widget for it, so it would mean hand-rolling a `Draggable`/`DragTarget` layout used nowhere else in this codebase.
- **Option C (rejected): up/down icon buttons per chip instead of drag.** Simpler to implement and trivially Maestro-testable (no gesture at all), but rejected because it doesn't fit chip layout either (an up/down pair per chip roughly doubles each chip's width) and, per Design note 4 below, drag is not actually required to be E2E-covered — the existing categories precedent already accepts widget-test-only coverage for drag mechanics, so Option C's only real advantage (E2E-friendliness) is not needed to satisfy this codebase's own testing conventions.

**Drag gestures and test coverage — following, not inventing, precedent:** `manage_categories_screen.dart` is the only other `ReorderableListView` in this codebase. Its own widget test, `test/features/settings/manage_categories_reorder_test.dart`, does **not** simulate a real drag gesture — it asserts the drag handle exists and is ≥48dp, then calls `CategoryRepository.reorderCategories(...)` directly with the comment *"gesture-simulated drags are covered, and known flaky under concurrent test execution, in manual/E2E verification instead"*. But the actual E2E flow, `e2e/flows/settings/category_edit_persists.yaml`, says the opposite in its own header comment: *"Drag-reorder mechanics are widget-tested; Maestro can't drive ReorderableListView reliably, so E2E covers the edit+persistence path"* — and greping the whole `e2e/` tree turns up no drag/reorder step anywhere. **So in practice, nothing in this codebase gesture-simulates a `ReorderableListView` drag, anywhere, ever; only its callback-driven effect is tested.** This plan follows that precedent, but goes one step more faithful than the categories test: instead of skipping the widget's own reorder wiring and calling a repository method directly, Task 3 and Task 4's tests call `ReorderableListView.onReorderItem` directly (a public field on a public widget, reachable via `tester.widget<ReorderableListView>(...)`) — deterministic, not gesture-based, but it does exercise `AssignmentFields`'/`ChoreFormScreen`'s own reorder wiring rather than bypassing it. No E2E flow is added or changed for the drag itself, matching the categories precedent exactly; existing E2E flows that touch the chore form's assignment section are unaffected since none currently build or edit a rotation (verified by grep — E2E's chore-form flows only cover fixed/anyone).

## Open product decisions

**None.** The one question flagged in the ticket as "likely" needing a decision — what happens to an in-flight rotation position when order changes — turned out to be fully determined by existing, already-tested code (Design note 2 above): the current turn never moves because of an assignee-list edit of any kind, reorder included. This plan does not introduce, rely on, or need a new product decision anywhere.

---

## File map

- Modify: `lib/features/chores/chore_form/assignment_fields.dart` — add `onReorder`, split rotation-mode rendering into a reorderable list + picker `Wrap`, add a private `_RotationRow` widget.
- Modify: `lib/features/chores/chore_form_screen.dart` — add `_onReorderMember`, pass it to `AssignmentFields`.
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb` — one new key for the remove button's tooltip.
- Modify: `docs/specs/ui-foundation-chores.md` — rotation-mode description + semantic id list.
- Modify: `docs/specs/theme-v2.md` — one line describing rotation's chip rendering.
- Modify: `test/application/chore_update_regeneration_test.dart` — one new characterization test.
- Create: `test/features/chores/chore_form/assignment_fields_test.dart` — isolated widget tests for the new reorder wiring.
- Create: `test/features/chores/chore_form_rotation_reorder_test.dart` — full-flow integration widget test (build a rotation, reorder, remove, save, verify persistence).

---

### Task 1: Pin down the "reorder doesn't move the current turn, but does change the next one" invariant

**Files:**
- Modify: `test/application/chore_update_regeneration_test.dart` (add one test inside the existing `group('unchanged edit', ...)` block, after the test at lines 216-247)

**Interfaces:**
- Consumes: `ChoreService.updateChore` (`lib/application/chore_service.dart:278`), `ChoreService.completeOccurrence` (`chore_service.dart:101`), `ChoreRepository.pendingOccurrenceOf`, `ChoreRepository.getChore` — all already used elsewhere in this test file, no new imports needed.
- Produces: nothing new consumed by later tasks — this is a standalone regression/characterization test.

This is **not** a red-then-green TDD step: the behavior it checks already exists and passes against the current code (Design note 2 explains why). It exists to pin the invariant down specifically for a reorder (as opposed to the add/remove case already covered by the neighboring test) before the UI work in later tasks starts relying on it.

- [ ] **Step 1: Add the test**

Insert immediately after the closing `);` of the test ending at line 247 (`'changing assignmentMode/assignees alone (no recurrence/startDate change) still leaves the pending occurrence untouched'`), still inside `group('unchanged edit', ...)`:

```dart
    test(
      'reordering a rotation (same members, new order) leaves the current '
      "occurrence's assignee untouched, but the NEXT turn follows the new "
      'order',
      () async {
        final m1 = await _insertMember(db, 'm1', householdId);
        final m2 = await _insertMember(db, 'm2', householdId);
        final m3 = await _insertMember(db, 'm3', householdId);
        final chore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
          householdId: householdId,
          title: 'Dishes',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.rotation,
          recurrence: Recurrence.everyNDays(1),
          assigneeMemberIds: [m1, m2, m3],
        );
        final before = await repo.pendingOccurrenceOf(chore.id);
        expect(before!.assignedMemberId, m1);

        // Swap m2 and m3 -- m1 stays first, so the CURRENT occurrence's
        // assignee (m1) is unaffected either way; only the order after m1
        // changes.
        await serviceOn(PlainDate(2026, 1, 2)).updateChore(
          chore.id,
          assignmentMode: AssignmentMode.rotation,
          assigneeMemberIds: [m1, m3, m2],
        );

        // The pending occurrence is the SAME row, with the SAME assignee:
        // a reorder is not a recurrence/startDate change, so nothing
        // regenerates (ChoreService.updateChore doc comment, chore_service
        // .dart:272-275).
        final pending = await repo.pendingOccurrenceOf(chore.id);
        expect(pending!.id, before.id);
        expect(pending.assignedMemberId, m1);

        // Completing it, though, advances by the NEW order: under the
        // original [m1, m2, m3] the member after m1 would be m2; under the
        // reordered [m1, m3, m2] it's m3. Seeing m3 here proves the
        // rotation reads the reordered list, not a cached original one.
        await serviceOn(
          PlainDate(2026, 1, 2),
        ).completeOccurrence(pending.id, completedBy: m1);
        final after = await repo.pendingOccurrenceOf(chore.id);
        expect(after!.assignedMemberId, m3);
      },
    );
```

- [ ] **Step 2: Run it**

Run: `flutter test test/application/chore_update_regeneration_test.dart`
Expected: PASS (all tests in the file, including the new one) — this confirms the invariant already holds; no implementation change follows from this task.

- [ ] **Step 3: Commit**

```bash
git add test/application/chore_update_regeneration_test.dart
git commit -m "test: pin down that reordering a rotation doesn't move the current turn"
```

---

### Task 2: Add the remove-button tooltip string

**Files:**
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_de.arb`

**Interfaces:**
- Produces: `AppLocalizations.choreFormAssigneeRemoveTooltip(String name)` — a `String Function(String)` on the generated `AppLocalizations` class, consumed by Task 3's `_RotationRow`.

- [ ] **Step 1: Add the EN key**

In `lib/l10n/app_en.arb`, immediately after the `choreFormAddMember`/`@choreFormAddMember` pair (around line 711-714), insert:

```json
  "choreFormAssigneeRemoveTooltip": "Remove {name} from the rotation",
  "@choreFormAssigneeRemoveTooltip": {
    "description": "Tooltip on the rotation reorder list's per-row remove button (chore form, assignment section).",
    "placeholders": {
      "name": {
        "type": "String",
        "example": "Anna"
      }
    }
  },
```

- [ ] **Step 2: Add the DE key**

In `lib/l10n/app_de.arb`, immediately after the `choreFormAddMember` line (around line 144), insert:

```json
  "choreFormAssigneeRemoveTooltip": "{name} aus der Rotation entfernen",
```

- [ ] **Step 3: Regenerate localizations**

Run: `flutter gen-l10n`
Expected: no errors; `lib/l10n/app_localizations.dart` (and the `en`/`de` variants) now declare `choreFormAssigneeRemoveTooltip`.

- [ ] **Step 4: Commit**

```bash
git add lib/l10n/app_en.arb lib/l10n/app_de.arb
git commit -m "l10n: add the rotation reorder remove-button tooltip"
```

---

### Task 3: Rework `AssignmentFields` — reorderable list for rotation, isolated widget tests

**Files:**
- Modify: `lib/features/chores/chore_form/assignment_fields.dart`
- Create: `test/features/chores/chore_form/assignment_fields_test.dart`

**Interfaces:**
- Consumes: `Member` (`lib/data/db/app_database.dart`), `MemberAvatar` (`lib/features/members/member_avatar.dart`), `AppLocalizations.choreFormAssigneeRemoveTooltip` (Task 2), `AppLocalizations.choreFormAssigneeOrderLabel` (existing).
- Produces: `AssignmentFields` now requires an additional constructor parameter `required this.onReorder` of type `void Function(int oldIndex, int newIndex)`, called with the SAME already-adjusted-for-removal semantics as `ReorderableListView.builder`'s `onReorderItem` (i.e. the caller does NOT need to subtract 1 when moving an item down, matching `manage_categories_screen.dart`'s `_reorder` comment). This is the exact signature Task 4's `ChoreFormScreen._onReorderMember` must implement.

- [ ] **Step 1: Write the failing isolated widget test**

Create `test/features/chores/chore_form/assignment_fields_test.dart`:

```dart
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
      await pumpAssignmentFields(
        tester,
        selectedMemberIds: [anna.id, ben.id],
      );

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
    },
  );

  testWidgets('selected rows show the order label and a MemberAvatar', (
    tester,
  ) async {
    await pumpAssignmentFields(
      tester,
      selectedMemberIds: [anna.id, ben.id],
    );

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
    },
  );

  testWidgets('an unselected member still renders as a tap-to-add chip', (
    tester,
  ) async {
    String? tapped;
    await pumpAssignmentFields(
      tester,
      selectedMemberIds: [anna.id],
      onMemberTap: (id) => tapped = id,
    );

    final miaChip = find.bySemanticsIdentifier(
      'chore_form.assignee.${mia.id}',
    );
    expect(
      find.descendant(of: miaChip, matching: find.byType(FilterChip)),
      findsOneWidget,
    );
    await tester.tap(miaChip);
    await tester.pump();
    expect(tapped, mia.id);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/chores/chore_form/assignment_fields_test.dart`
Expected: FAIL to even compile — `AssignmentFields` has no `onReorder` parameter yet, and none of `.drag`/`.remove` ids or the reorderable list exist.

- [ ] **Step 3: Rewrite `assignment_fields.dart`**

Replace the full contents of `lib/features/chores/chore_form/assignment_fields.dart` with:

```dart
/// The chore form's assignment-mode and assignee-picker controls.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/features/members/member_avatar.dart';
import 'package:chore_app/features/settings/member_edit_sheet.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The assignment mode segmented control (spec `docs/specs/theme-v2.md`
/// §4.4 item 2) plus its dependent assignee controls.
///
/// `fixed` shows a single-select chip row (exactly one member must be
/// picked) and `anyone` shows none. `rotation` (backlog B-4 / triage
/// T2.5, `docs/plans/2026-08-08-rotation-reorder.md`) shows two parts:
/// already-selected members as a compact reorderable list — drag handle,
/// avatar, tap-order label, remove button — so the order can be edited
/// directly instead of only rebuilt by deselect-then-reselect; and
/// not-yet-selected members as a plain tap-to-add chip row underneath,
/// same as before. A trailing 'Add member…' chip (spec
/// `docs/feedback/2026-08-01-ux-audit.md` B2) closes the not-yet-selected
/// row, opening the new-member sheet inline so a missing person can be
/// added without abandoning the form -- the chip row refreshes
/// automatically once they're saved, since the caller
/// (`ChoreFormScreen`) watches `membersProvider` and passes the live
/// [members] list down.
class AssignmentFields extends StatelessWidget {
  /// Creates the assignment fields.
  const AssignmentFields({
    required this.mode,
    required this.onModeChanged,
    required this.members,
    required this.selectedMemberIds,
    required this.onMemberTap,
    required this.onReorder,
    this.errorText,
    super.key,
  });

  /// The currently-selected assignment mode.
  final AssignmentMode mode;

  /// Called when a different assignment mode is picked.
  final ValueChanged<AssignmentMode> onModeChanged;

  /// Every household member, selectable as an assignee.
  final List<Member> members;

  /// The currently-selected member ids. For `fixed`, 0 or 1 entries; for
  /// `rotation`, in rotation order (used for the visible order badges and
  /// the reorderable list's row order).
  final List<String> selectedMemberIds;

  /// Called when a member chip (unselected, or the selected row's remove
  /// button) is tapped; the caller decides how the selection changes
  /// based on [mode]. Selecting an unselected member always appends it to
  /// the end of [selectedMemberIds]; tapping a selected row's remove
  /// button removes it -- identical net effect to today's re-tap-to
  /// -remove chip gesture.
  final ValueChanged<String> onMemberTap;

  /// Called when the rotation reorder list moves an item, with the SAME
  /// already-adjusted-for-removal indices `ReorderableListView.builder`'s
  /// `onReorderItem` provides (no manual off-by-one correction needed by
  /// the caller). Unused outside [AssignmentMode.rotation].
  final void Function(int oldIndex, int newIndex) onReorder;

  /// Inline validation error, or `null` if the current selection is valid.
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<AssignmentMode>(
          expandedInsets: EdgeInsets.zero,
          showSelectedIcon: false,
          segments: [
            for (final entry in AssignmentMode.values)
              ButtonSegment(
                value: entry,
                label: semantic(
                  'chore_form.assignment.${entry.name}',
                  child: Text(_modeLabel(context, entry)),
                ),
              ),
          ],
          selected: {mode},
          onSelectionChanged: (selection) => onModeChanged(selection.first),
        ),
        if (mode == AssignmentMode.rotation) ...[
          const SizedBox(height: 8),
          _RotationAssigneeControls(
            members: members,
            selectedMemberIds: selectedMemberIds,
            onMemberTap: onMemberTap,
            onReorder: onReorder,
          ),
        ] else if (mode == AssignmentMode.fixed) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final member in members)
                semantic(
                  'chore_form.assignee.${member.id}',
                  child: FilterChip(
                    // The selection checkmark would otherwise paint over
                    // the avatar (Flutter darkens+overlays it), hiding the
                    // exact thing this chip most needs to show once
                    // picked; the chip's own selected styling already
                    // conveys the state without it.
                    showCheckmark: false,
                    avatar: MemberAvatar(member: member, radius: 12),
                    label: Text(member.name),
                    selected: selectedMemberIds.contains(member.id),
                    onSelected: (_) => onMemberTap(member.id),
                  ),
                ),
              _addMemberChip(context),
            ],
          ),
        ],
        if (errorText != null) ...[
          const SizedBox(height: 4),
          Text(
            errorText!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }

  String _modeLabel(BuildContext context, AssignmentMode mode) {
    final l10n = AppLocalizations.of(context);
    switch (mode) {
      case AssignmentMode.fixed:
        return l10n.choreFormAssignmentFixed;
      case AssignmentMode.rotation:
        return l10n.choreFormAssignmentRotation;
      case AssignmentMode.anyone:
        return l10n.choreFormAssignmentAnyone;
    }
  }
}

/// Builds the "Add member…" chip shared by the fixed-mode chip row and the
/// rotation-mode not-yet-selected chip row.
Widget _addMemberChip(BuildContext context) {
  return semantic(
    'chore_form.assignee.add',
    child: ActionChip(
      avatar: const Icon(Icons.add, size: 18),
      label: Text(AppLocalizations.of(context).choreFormAddMember),
      onPressed: () => showMemberEditSheet(context),
    ),
  );
}

/// Rotation mode's assignee controls: a reorderable list of already
/// -selected members, then a chip row of not-yet-selected ones.
class _RotationAssigneeControls extends StatelessWidget {
  const _RotationAssigneeControls({
    required this.members,
    required this.selectedMemberIds,
    required this.onMemberTap,
    required this.onReorder,
  });

  final List<Member> members;
  final List<String> selectedMemberIds;
  final ValueChanged<String> onMemberTap;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) {
    final selected = [
      for (final id in selectedMemberIds)
        members.firstWhere((member) => member.id == id),
    ];
    final unselected = [
      for (final member in members)
        if (!selectedMemberIds.contains(member.id)) member,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selected.isNotEmpty)
          // Embedding a ReorderableListView inside the form's outer,
          // already-scrollable ListView (chore_form_screen.dart) needs
          // shrinkWrap + disabled physics, same as any nested list in a
          // scrollable -- this list is always short (household member
          // count), so there's no lost scroll performance from sizing it
          // to content.
          ReorderableListView.builder(
            buildDefaultDragHandles: false,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: selected.length,
            itemBuilder: (context, index) {
              final member = selected[index];
              return _RotationRow(
                key: ValueKey(member.id),
                member: member,
                index: index,
                order: index + 1,
                onRemove: () => onMemberTap(member.id),
              );
            },
            onReorderItem: onReorder,
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final member in unselected)
              semantic(
                'chore_form.assignee.${member.id}',
                child: FilterChip(
                  avatar: MemberAvatar(member: member, radius: 12),
                  label: Text(member.name),
                  selected: false,
                  onSelected: (_) => onMemberTap(member.id),
                ),
              ),
            _addMemberChip(context),
          ],
        ),
      ],
    );
  }
}

/// One row of the rotation reorder list: drag handle, avatar, tap-order
/// label, remove button.
///
/// The drag handle is a sibling of the row's other content, not an
/// ancestor/descendant of any tappable widget -- nesting it inside one
/// would put an `ImmediateMultiDragGestureRecognizer` and a tap recognizer
/// in the same gesture arena for the same pointer (same reasoning as
/// `manage_categories_screen.dart`'s `_CategoryRow`).
class _RotationRow extends StatelessWidget {
  const _RotationRow({
    required this.member,
    required this.index,
    required this.order,
    required this.onRemove,
    super.key,
  });

  final Member member;
  final int index;
  final int order;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return semantic(
      'chore_form.assignee.${member.id}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            semantic(
              'chore_form.assignee.${member.id}.drag',
              child: ReorderableDragStartListener(
                index: index,
                child: const SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(Icons.drag_indicator),
                ),
              ),
            ),
            MemberAvatar(member: member, radius: 12),
            const SizedBox(width: 8),
            Expanded(
              child: Text(l10n.choreFormAssigneeOrderLabel(order, member.name)),
            ),
            semantic(
              'chore_form.assignee.${member.id}.remove',
              child: IconButton(
                icon: const Icon(Icons.close),
                tooltip: l10n.choreFormAssigneeRemoveTooltip(member.name),
                onPressed: onRemove,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/chores/chore_form/assignment_fields_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Format and analyze**

Run: `dart format lib/features/chores/chore_form/assignment_fields.dart test/features/chores/chore_form/assignment_fields_test.dart`
Run: `flutter analyze --fatal-infos --fatal-warnings lib/features/chores/chore_form/assignment_fields.dart`
Expected: both clean.

- [ ] **Step 6: Commit**

```bash
git add lib/features/chores/chore_form/assignment_fields.dart test/features/chores/chore_form/assignment_fields_test.dart
git commit -m "feat: reorderable rotation assignee list in the chore form"
```

---

### Task 4: Wire `ChoreFormScreen` to the new callback; full-flow integration test

**Files:**
- Modify: `lib/features/chores/chore_form_screen.dart:317-324` (the `AssignmentFields(...)` call) and the area around `_onMemberTap` (`chore_form_screen.dart:409-424`)
- Create: `test/features/chores/chore_form_rotation_reorder_test.dart`

**Interfaces:**
- Consumes: `AssignmentFields.onReorder` (Task 3), `ChoreService.createChore`/`getChore` via `ChoreRepository` (existing).
- Produces: nothing new consumed elsewhere — this is the top-level wiring and its end-to-end test.

- [ ] **Step 1: Write the failing integration test**

Create `test/features/chores/chore_form_rotation_reorder_test.dart`:

```dart
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// Full-flow coverage for backlog B-4 / triage T2.5: build a rotation by
/// tapping members, reorder it, remove one, and confirm the saved chore
/// persists the final order (not the tap order).
void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'reordering and removing a rotation in the form persists the final '
    'order on save',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final householdRepo = HouseholdRepository(database);
      final anna = await householdRepo.addMember(
        householdId,
        name: 'Anna',
        color: 0xFF8C7BC9,
      );
      final ben = await householdRepo.addMember(
        householdId,
        name: 'Ben',
        color: 0xFF4E9A51,
      );
      final me = (await database.select(database.members).get()).firstWhere(
        (member) => member.id != anna.id && member.id != ben.id,
      );

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      final titleField = find.descendant(
        of: find.bySemanticsIdentifier('chore_form.title'),
        matching: find.byType(TextField),
      );
      await tester.enterText(titleField, 'Dishes');
      await tester.tap(find.bySemanticsIdentifier('chore_form.assignment.rotation'));
      await tester.pumpAndSettle();

      // Tap order: Anna, Ben, Me.
      for (final id in [anna.id, ben.id, me.id]) {
        await tester.tap(find.bySemanticsIdentifier('chore_form.assignee.$id'));
        await tester.pumpAndSettle();
      }
      expect(find.text('1. Anna'), findsOneWidget);
      expect(find.text('2. Ben'), findsOneWidget);
      expect(find.text('3. Me'), findsOneWidget);

      // Reorder to Ben, Anna, Me: move index 0 (Anna) to index 1, the same
      // already-adjusted semantics ReorderableListView.builder's
      // onReorderItem provides.
      final reorderable = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
      reorderable.onReorderItem!(0, 1);
      await tester.pumpAndSettle();
      expect(find.text('1. Ben'), findsOneWidget);
      expect(find.text('2. Anna'), findsOneWidget);
      expect(find.text('3. Me'), findsOneWidget);

      // Remove Anna via her row's remove button.
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.assignee.${anna.id}.remove'),
      );
      await tester.pumpAndSettle();
      expect(find.text('1. Ben'), findsOneWidget);
      expect(find.text('2. Me'), findsOneWidget);
      expect(find.textContaining('Anna'), findsNothing);

      await tester.tap(find.bySemanticsIdentifier('chore_form.save'));
      await tester.pumpAndSettle();

      final chore = (await database.select(database.chores).get()).firstWhere(
        (c) => c.title == 'Dishes',
      );
      final details = await ChoreRepository(database).getChore(chore.id);
      expect(details!.assigneeMemberIds, [ben.id, me.id]);

      handle.dispose();
    },
  );
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/chores/chore_form_rotation_reorder_test.dart`
Expected: FAIL — `AssignmentFields(...)` in `chore_form_screen.dart` doesn't pass `onReorder` yet, so the app won't compile.

- [ ] **Step 3: Wire the callback**

In `lib/features/chores/chore_form_screen.dart`, update the `AssignmentFields(...)` call (currently lines 317-324):

```dart
            AssignmentFields(
              mode: _assignmentMode,
              onModeChanged: _onAssignmentModeChanged,
              members: members,
              selectedMemberIds: _selectedMemberIds,
              onMemberTap: _onMemberTap,
              onReorder: _onReorderMember,
              errorText: _assignmentErrorText(l10n, _assignmentError),
            ),
```

Then add `_onReorderMember` right after `_onMemberTap` (currently ending at line 424):

```dart
  void _onReorderMember(int oldIndex, int newIndex) {
    setState(() {
      final updated = List.of(_selectedMemberIds);
      final moved = updated.removeAt(oldIndex);
      updated.insert(newIndex, moved);
      _selectedMemberIds = updated;
    });
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/chores/chore_form_rotation_reorder_test.dart`
Expected: PASS.

- [ ] **Step 5: Format and analyze**

Run: `dart format lib/features/chores/chore_form_screen.dart test/features/chores/chore_form_rotation_reorder_test.dart`
Run: `flutter analyze --fatal-infos --fatal-warnings lib/features/chores/chore_form_screen.dart`
Expected: both clean.

- [ ] **Step 6: Commit**

```bash
git add lib/features/chores/chore_form_screen.dart test/features/chores/chore_form_rotation_reorder_test.dart
git commit -m "feat: wire the chore form's rotation reorder list to form state"
```

---

### Task 5: Regression-check the tests this change touches by proximity

**Files:**
- Read/run only: `test/features/chores/chore_form_avatars_test.dart`, `test/features/chores/chore_form_validation_test.dart`, `test/features/chores/chore_form_edit_test.dart`, `test/features/chores/chore_form_unsaved_changes_test.dart`

**Interfaces:** none — this task makes no code changes if all four already pass.

`chore_form_avatars_test.dart`'s rotation-mode test in particular asserts `find.text('1. Anna')`/`'2. Me'` and a `MemberAvatar` descendant of `find.bySemanticsIdentifier('chore_form.assignee.$memberId')` after tapping to select — Task 3's design keeps that exact id and exact order-label text on the now-a-row-instead-of-chip widget, so it should pass unchanged. This task exists to prove that rather than assume it.

- [ ] **Step 1: Run the four files**

Run: `flutter test test/features/chores/chore_form_avatars_test.dart test/features/chores/chore_form_validation_test.dart test/features/chores/chore_form_edit_test.dart test/features/chores/chore_form_unsaved_changes_test.dart`
Expected: PASS, no modifications needed.

- [ ] **Step 2: If any fail**

Read the failure, fix `assignment_fields.dart` (not the test) to preserve the documented existing contract, re-run, then commit the fix on its own:

```bash
git add lib/features/chores/chore_form/assignment_fields.dart
git commit -m "fix: preserve <specific behavior> after the rotation reorder change"
```

(No placeholder here because the expectation, backed by the design notes above, is that Step 1 passes outright — but this step exists in case that expectation is wrong.)

---

### Task 6: Update the two specs this change touches

**Files:**
- Modify: `docs/specs/ui-foundation-chores.md` (semantic id list around lines 54-55, rotation description around lines 130-135)
- Modify: `docs/specs/theme-v2.md` (line 277)

- [ ] **Step 1: Update the semantic id list**

In `docs/specs/ui-foundation-chores.md`, the line currently reading (around line 54-55):

```
  `chore_form.start_date`, `chore_form.assignment.<fixed|rotation|anyone>`,
  `chore_form.assignee.<memberId>`, `chore_form.save`
```

Replace with:

```
  `chore_form.start_date`, `chore_form.assignment.<fixed|rotation|anyone>`,
  `chore_form.assignee.<memberId>`, `chore_form.assignee.<memberId>.drag`
  (rotation reorder drag handle), `chore_form.assignee.<memberId>.remove`
  (rotation reorder remove button), `chore_form.save`
```

- [ ] **Step 2: Update the rotation-mode form description**

In `docs/specs/ui-foundation-chores.md`, the bullet currently reading (around lines 130-135):

```
- Assignment: segmented fixed/rotation/anyone; fixed → single-select member
  chips; rotation → multi-select member chips in tap order with visible
  order badges (1, 2, …), each chip showing the member's `MemberAvatar`
  before their name (field feedback F3). Validation errors inline: fixed
  needs exactly one ('Pick one member'), rotation at least two ('Pick at
  least two').
```

Replace with:

```
- Assignment: segmented fixed/rotation/anyone; fixed → single-select member
  chips, each showing the member's `MemberAvatar` before their name (field
  feedback F3). rotation (backlog B-4 / triage T2.5,
  `docs/plans/2026-08-08-rotation-reorder.md`) → already-selected members
  render as a compact reorderable list (drag handle, avatar, visible order
  label "1. Anna" etc., remove button), directly editable by dragging a
  row or tapping its remove button — not only rebuildable by deselecting
  and reselecting; not-yet-selected members stay a tap-to-add chip row
  below, appending to the end of the order, same as fixed mode's picker.
  Reordering is a widget-tested interaction only (not E2E: Maestro can't
  drive `ReorderableListView` reliably, same limitation already accepted
  for `manage_categories_screen.dart`). Validation errors inline: fixed
  needs exactly one ('Pick one member'), rotation at least two ('Pick at
  least two').
```

- [ ] **Step 3: Update theme-v2.md**

In `docs/specs/theme-v2.md`, the line currently reading (line 277):

```
- Rotation chips show turn order on the chip ("1. Anna", "2. Ben").
```

Replace with:

```
- Rotation mode shows selected members as a reorderable list with an
  order label per row ("1. Anna", "2. Ben") instead of chips, and
  not-yet-selected members as a chip row below it (spec
  `ui-foundation-chores.md`, `docs/plans/2026-08-08-rotation-reorder.md`).
```

- [ ] **Step 4: Commit**

```bash
git add docs/specs/ui-foundation-chores.md docs/specs/theme-v2.md
git commit -m "docs: update chore-form specs for the rotation reorder list"
```

---

### Task 7: Full verification pass

**Files:** none (verification only).

- [ ] **Step 1: Format the whole repo**

Run: `dart format .`
Expected: no files needing changes beyond what earlier tasks already formatted (a clean diff).

- [ ] **Step 2: Analyze**

Run: `flutter analyze --fatal-infos --fatal-warnings`
Expected: `No issues found!`

- [ ] **Step 3: Full test suite**

Run: `flutter test`
Expected: all tests PASS, including every file touched or added in Tasks 1, 3, 4, 5.

- [ ] **Step 4: Commit if Step 1 changed anything**

```bash
git add -A
git commit -m "chore: format after rotation reorder work"
```

(Skip this step entirely if `dart format .` in Step 1 made no changes.)
