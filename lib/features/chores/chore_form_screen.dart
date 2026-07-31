/// The create/edit chore form screen.
library;

import 'dart:async';

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:chore_app/features/categories/category_picker.dart';
import 'package:chore_app/features/chores/chore_form/assignment_fields.dart';
import 'package:chore_app/features/chores/chore_form/form_validation.dart';
import 'package:chore_app/features/chores/chore_form/recurrence_builder.dart';
import 'package:chore_app/features/chores/chore_form/repeat_controls.dart';
import 'package:chore_app/features/chores/chore_form/repeat_section.dart'
    show RepeatToggle;
import 'package:chore_app/features/chores/chore_form/start_date_field.dart';
import 'package:chore_app/features/chores/chore_form/title_notes_fields.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Creates a new chore, or edits an existing one when [choreId] is given.
///
/// Saving an edit routes through `ChoreService.updateChore` rather than
/// `ChoreRepository.updateChore` directly: per
/// `docs/specs/occurrence-lifecycle.md` §2, changing recurrence and/or
/// start date regenerates the chore's pending occurrence (same rule as
/// `unpauseChore`), so that rule needs to live at the service layer.
class ChoreFormScreen extends ConsumerStatefulWidget {
  /// Creates the form. Omit [choreId] to create a new chore; pass an
  /// existing chore's id to edit it.
  const ChoreFormScreen({this.choreId, super.key});

  /// The chore being edited, or `null` when creating a new one.
  final String? choreId;

  @override
  ConsumerState<ChoreFormScreen> createState() => _ChoreFormScreenState();
}

class _ChoreFormScreenState extends ConsumerState<ChoreFormScreen> {
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();
  final _intervalController = TextEditingController(text: '1');

  bool _loading = false;
  String? _categoryId;
  bool _repeatEnabled = false;
  RecurrenceUnit _unit = RecurrenceUnit.week;
  RecurrenceAnchor _anchor = RecurrenceAnchor.schedule;
  Set<int> _weekdays = {};
  MonthlyMode _monthlyMode = MonthlyMode.dayOfMonth;
  late PlainDate _startDate;
  AssignmentMode _assignmentMode = AssignmentMode.anyone;
  List<String> _selectedMemberIds = [];

  TitleError? _titleError;
  IntervalError? _intervalError;
  AssignmentError? _assignmentError;

  bool get _isEditing => widget.choreId != null;

  @override
  void initState() {
    super.initState();
    _startDate = PlainDate.fromDateTime(ref.read(clockProvider).now());
    final choreId = widget.choreId;
    if (choreId != null) {
      _loading = true;
      unawaited(_loadExisting(choreId));
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  Future<void> _loadExisting(String choreId) async {
    final details = await ref.read(choreRepositoryProvider).getChore(choreId);
    if (!mounted) {
      return;
    }
    if (details == null) {
      setState(() => _loading = false);
      return;
    }
    final chore = details.chore;
    final recurrence = chore.recurrence;
    setState(() {
      _titleController.text = chore.title;
      _notesController.text = chore.notes ?? '';
      _categoryId = chore.categoryId;
      _startDate = chore.startDate;
      _assignmentMode = chore.assignmentMode;
      _selectedMemberIds = List.of(details.assigneeMemberIds);
      if (recurrence != null) {
        _repeatEnabled = true;
        _unit = recurrence.unit;
        _anchor = recurrence.anchor;
        _weekdays = Set.of(recurrence.weekdays);
        _monthlyMode = recurrence.monthlyMode;
        _intervalController.text = recurrence.interval.toString();
      }
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formTitle = _isEditing
        ? l10n.choreFormEditTitle
        : l10n.choreFormNewTitle;
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(formTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final categories = ref.watch(choreCategoriesProvider).value ?? const [];
    final members = ref.watch(membersProvider).value ?? const [];
    final today = PlainDate.fromDateTime(ref.watch(clockProvider).now());

    return Scaffold(
      appBar: AppBar(title: Text(formTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TitleField(
            controller: _titleController,
            errorText: _titleError == null
                ? null
                : l10n.choreFormTitleRequiredError,
          ),
          const SizedBox(height: 16),
          NotesField(controller: _notesController),
          const SizedBox(height: 16),
          semantic(
            'chore_form.category',
            child: CategoryPicker(
              categories: categories,
              selectedCategoryId: _categoryId,
              onChanged: (value) => setState(() => _categoryId = value),
              idPrefix: 'chore_form.category',
            ),
          ),
          const SizedBox(height: 16),
          RepeatToggle(
            value: _repeatEnabled,
            onChanged: (value) => setState(() => _repeatEnabled = value),
          ),
          if (_repeatEnabled)
            RepeatControls(
              intervalController: _intervalController,
              intervalError: _intervalError == null
                  ? null
                  : l10n.choreFormIntervalTooSmallError,
              unit: _unit,
              onUnitChanged: _onUnitChanged,
              anchor: _anchor,
              onAnchorChanged: _onAnchorChanged,
              weekdays: _weekdays,
              onWeekdayToggle: _toggleWeekday,
              monthlyMode: _monthlyMode,
              onMonthlyModeChanged: (value) {
                setState(() => _monthlyMode = value);
              },
              startDate: _startDate,
            ),
          const SizedBox(height: 16),
          StartDateField(
            value: _startDate,
            today: today,
            onChanged: (value) => setState(() => _startDate = value),
          ),
          const SizedBox(height: 16),
          AssignmentFields(
            mode: _assignmentMode,
            onModeChanged: _onAssignmentModeChanged,
            members: members,
            selectedMemberIds: _selectedMemberIds,
            onMemberTap: _onMemberTap,
            errorText: _assignmentErrorText(l10n, _assignmentError),
          ),
        ],
      ),
      // Pinned, not the last ListView row: the primary action must stay
      // reachable no matter how long the form grows (design-language rule
      // 1) — and on a real phone the bottom of this form is below the
      // fold, which E2E caught as an unreachable save button.
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: semantic(
          'chore_form.save',
          child: FilledButton(onPressed: _save, child: Text(l10n.commonSave)),
        ),
      ),
    );
  }

  /// Maps an [AssignmentError] to its localized message, or `null` if
  /// [error] is `null`.
  String? _assignmentErrorText(AppLocalizations l10n, AssignmentError? error) {
    switch (error) {
      case null:
        return null;
      case AssignmentError.needsOneMember:
        return l10n.choreFormAssignmentNeedsOneError;
      case AssignmentError.needsTwoMembers:
        return l10n.choreFormAssignmentNeedsTwoError;
    }
  }

  void _onUnitChanged(RecurrenceUnit unit) {
    setState(() {
      _unit = unit;
      if (unit != RecurrenceUnit.month) {
        _monthlyMode = MonthlyMode.dayOfMonth;
      }
    });
  }

  void _onAnchorChanged(RecurrenceAnchor anchor) {
    setState(() {
      _anchor = anchor;
      if (anchor == RecurrenceAnchor.completion) {
        _monthlyMode = MonthlyMode.dayOfMonth;
      }
    });
  }

  void _toggleWeekday(int weekday) {
    setState(() {
      final updated = Set.of(_weekdays);
      if (!updated.remove(weekday)) {
        updated.add(weekday);
      }
      _weekdays = updated;
    });
  }

  void _onAssignmentModeChanged(AssignmentMode mode) {
    setState(() {
      _assignmentMode = mode;
      _selectedMemberIds = [];
      _assignmentError = null;
    });
  }

  void _onMemberTap(String memberId) {
    setState(() {
      switch (_assignmentMode) {
        case AssignmentMode.fixed:
          _selectedMemberIds = [memberId];
        case AssignmentMode.rotation:
          final updated = List.of(_selectedMemberIds);
          if (!updated.remove(memberId)) {
            updated.add(memberId);
          }
          _selectedMemberIds = updated;
        case AssignmentMode.anyone:
          break;
      }
    });
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final titleError = validateTitle(title);
    final intervalError = _repeatEnabled
        ? validateInterval(_intervalController.text)
        : null;
    final assignmentError = validateAssignment(
      mode: _assignmentMode,
      selectedMemberIds: _selectedMemberIds,
    );

    setState(() {
      _titleError = titleError;
      _intervalError = intervalError;
      _assignmentError = assignmentError;
    });
    if (titleError != null ||
        intervalError != null ||
        assignmentError != null) {
      return;
    }

    final recurrence = _repeatEnabled
        ? buildRecurrence(
            // Already validated above as an integer >= 1 whenever
            // `_repeatEnabled` is true.
            interval: int.parse(_intervalController.text.trim()),
            unit: _unit,
            anchor: _anchor,
            weekdays: _weekdays,
            monthlyMode: _monthlyMode,
            startDate: _startDate,
          )
        : null;
    final notes = _notesController.text.trim();

    if (_isEditing) {
      await ref
          .read(choreServiceProvider)
          .updateChore(
            widget.choreId!,
            title: title,
            notes: Value(notes.isEmpty ? null : notes),
            categoryId: Value(_categoryId),
            recurrence: Value(recurrence),
            startDate: _startDate,
            assignmentMode: _assignmentMode,
            assigneeMemberIds: _selectedMemberIds,
          );
    } else {
      final householdId = ref.read(bootstrapProvider).requireValue;
      await ref
          .read(choreServiceProvider)
          .createChore(
            householdId: householdId,
            title: title,
            startDate: _startDate,
            assignmentMode: _assignmentMode,
            notes: notes.isEmpty ? null : notes,
            categoryId: _categoryId,
            recurrence: recurrence,
            assigneeMemberIds: _selectedMemberIds,
            createdBy: ref.read(actingMemberProvider)?.id,
          );
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }
}
