/// The create/edit chore form screen.
library;

import 'dart:async';

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:chore_app/features/chores/chore_form/assignment_fields.dart';
import 'package:chore_app/features/chores/chore_form/category_chips.dart';
import 'package:chore_app/features/chores/chore_form/form_validation.dart';
import 'package:chore_app/features/chores/chore_form/recurrence_builder.dart';
import 'package:chore_app/features/chores/chore_form/repeat_controls.dart';
import 'package:chore_app/features/chores/chore_form/repeat_section.dart'
    show RepeatToggle;
import 'package:chore_app/features/chores/chore_form/start_date_field.dart';
import 'package:chore_app/features/chores/chore_form/title_notes_fields.dart';
import 'package:chore_app/features/chores/chore_form_discard_dialog.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show listEquals, setEquals;
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

  // C4 (conventions audit, docs/feedback/2026-08-06-conventions-audit.md):
  // the form's field values at the moment they were last known-saved --
  // immediately, for a new chore, or once `_loadExisting` resolves, for an
  // edit -- compared against the live values by `_isDirty` below to decide
  // whether a pop needs the discard-confirm guard (design-language.md
  // interaction rule 7: "never lose user input").
  late String _initialTitle;
  late String _initialNotes;
  String? _initialCategoryId;
  late bool _initialRepeatEnabled;
  late RecurrenceUnit _initialUnit;
  late RecurrenceAnchor _initialAnchor;
  late Set<int> _initialWeekdays;
  late MonthlyMode _initialMonthlyMode;
  late String _initialInterval;
  late PlainDate _initialStartDate;
  late AssignmentMode _initialAssignmentMode;
  late List<String> _initialSelectedMemberIds;

  bool get _isEditing => widget.choreId != null;

  /// Whether any field's live value has diverged from the snapshot
  /// [_captureInitialSnapshot] took -- gates the PopScope discard-confirm
  /// below. Recurrence sub-fields only count while repeat is (or was)
  /// actually enabled, so toggling it on and back off without touching
  /// anything else doesn't read as dirty.
  bool get _isDirty {
    if (_titleController.text != _initialTitle ||
        _notesController.text != _initialNotes ||
        _categoryId != _initialCategoryId ||
        _repeatEnabled != _initialRepeatEnabled ||
        _startDate != _initialStartDate ||
        _assignmentMode != _initialAssignmentMode ||
        !listEquals(_selectedMemberIds, _initialSelectedMemberIds)) {
      return true;
    }
    if (_repeatEnabled &&
        (_unit != _initialUnit ||
            _anchor != _initialAnchor ||
            _monthlyMode != _initialMonthlyMode ||
            _intervalController.text != _initialInterval ||
            !setEquals(_weekdays, _initialWeekdays))) {
      return true;
    }
    return false;
  }

  void _captureInitialSnapshot() {
    _initialTitle = _titleController.text;
    _initialNotes = _notesController.text;
    _initialCategoryId = _categoryId;
    _initialRepeatEnabled = _repeatEnabled;
    _initialUnit = _unit;
    _initialAnchor = _anchor;
    _initialWeekdays = Set.of(_weekdays);
    _initialMonthlyMode = _monthlyMode;
    _initialInterval = _intervalController.text;
    _initialStartDate = _startDate;
    _initialAssignmentMode = _assignmentMode;
    _initialSelectedMemberIds = List.of(_selectedMemberIds);
  }

  @override
  void initState() {
    super.initState();
    // read, not watch: the default start date is captured ONCE, when the
    // form opens. A day rollover moves the picker's range reference (see
    // `today` in build) but must never move a date the user is looking at.
    _startDate = ref.read(todayProvider);
    // RepeatControls reads the interval's live text (to pluralize the unit
    // label and the after-last-completion subtitle, field feedback
    // G3 stage 1); typing into the field doesn't otherwise trigger a
    // rebuild, so this keeps that reading in sync as the user types.
    _intervalController.addListener(_onIntervalTextChanged);
    // C4: title/notes are plain TextEditingControllers with no listener of
    // their own, so without this, typing a few characters and immediately
    // backing out (no OTHER field touched to force a rebuild) would leave
    // the PopScope below holding a stale `canPop` from before the edit --
    // `canPop` is only as fresh as the widget's last build.
    _titleController.addListener(_onDirtyTrackedFieldChanged);
    _notesController.addListener(_onDirtyTrackedFieldChanged);
    final choreId = widget.choreId;
    if (choreId != null) {
      _loading = true;
      unawaited(_loadExisting(choreId));
    } else {
      _captureInitialSnapshot();
    }
  }

  @override
  void dispose() {
    _titleController
      ..removeListener(_onDirtyTrackedFieldChanged)
      ..dispose();
    _notesController
      ..removeListener(_onDirtyTrackedFieldChanged)
      ..dispose();
    _intervalController
      ..removeListener(_onIntervalTextChanged)
      ..dispose();
    super.dispose();
  }

  void _onIntervalTextChanged() {
    setState(() {});
  }

  void _onDirtyTrackedFieldChanged() {
    setState(() {});
  }

  Future<void> _loadExisting(String choreId) async {
    final details = await ref.read(choreRepositoryProvider).getChore(choreId);
    if (!mounted) {
      return;
    }
    if (details == null) {
      setState(() => _loading = false);
      _captureInitialSnapshot();
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
    _captureInitialSnapshot();
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
    // One definition of "today" across the whole UI (backlog A-2 / audit
    // P1): this is the StartDateField picker's range reference, min =
    // today - 1 year.
    final today = ref.watch(todayProvider);

    // The category picker's "edit categories" entry point (feedback round
    // 3) can push the manage-categories screen and come back having
    // deleted the currently-selected category. `choreCategoriesProvider`
    // only ever lists active categories, so if the selected id drops out
    // of it, fall back to 'None' — the same end state a persisted chore
    // already lands in, since `CategoryRepository.softDeleteCategory`
    // clears `categoryId` on every chore referencing it in the same
    // transaction; this covers the in-memory, not-yet-saved case that
    // cascade can't reach.
    ref.listen<AsyncValue<List<Category>>>(choreCategoriesProvider, (
      _,
      next,
    ) {
      final active = next.value;
      if (active == null) {
        return;
      }
      if (_categoryId != null && !active.any((c) => c.id == _categoryId)) {
        setState(() => _categoryId = null);
      }
    });

    // C4 (conventions audit, docs/feedback/2026-08-06-conventions-audit.md):
    // a dirty form intercepts the pop and confirms via
    // showChoreFormDiscardDialog; a pristine one pops immediately, same as
    // before this wave. `Navigator.pop()` inside the confirmed branch always
    // pops regardless of `canPop` -- that flag only gates the SYSTEM back
    // gesture/button this PopScope intercepts.
    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        final discard = await showChoreFormDiscardDialog(context);
        if (discard && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(formTitle)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          // C8 (conventions audit): dismisses the keyboard on a scroll drag,
          // matching the chores/shopping/settings lists.
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
              child: ChoreFormCategoryChips(
                categories: categories,
                selectedCategoryId: _categoryId,
                onChanged: (value) => setState(() => _categoryId = value),
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
        //
        // C15 (docs/feedback/2026-08-06-conventions-audit.md): the outer
        // Padding lifts the bar above the on-screen keyboard. `Scaffold`
        // only applies `resizeToAvoidBottomInset` to its BODY — it lays
        // `bottomNavigationBar` out at the bottom of the SCREEN, so with the
        // keyboard up this button sat behind it and was absent from the
        // accessibility tree entirely (verified on a Pixel emulator
        // 2026-08-06: keyboard y1517-2274, form content ended y1480, no
        // `chore_form.save` node). A user who typed a title simply could not
        // see how to save.
        bottomNavigationBar: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: semantic(
              'chore_form.save',
              child: FilledButton(
                onPressed: _save,
                child: Text(l10n.commonSave),
              ),
            ),
          ),
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
