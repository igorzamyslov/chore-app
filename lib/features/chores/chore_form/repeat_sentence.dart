/// The chore form's repeat rule, rendered as one fill-in-the-blank sentence.
library;

import 'package:chore_app/app/famdo_colors.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:chore_app/features/chores/chore_form/recurrence_builder.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Sentinels marking where a widget-shaped hole goes in a rendered ARB
/// sentence, one per hole *position* so a split can tell which hole it
/// found rather than relying on order.
///
/// These are Unicode **noncharacters** (`U+FDD0`..`U+FDD3`), permanently
/// reserved and guaranteed never to appear in real text — which is exactly
/// the promise neither the private-use area nor the interlinear-annotation
/// block can make. Written as escapes rather than literal glyphs: a literal
/// noncharacter is invisible in every editor and diff, and would be the
/// easiest thing in this file to mangle undetectably.
const String _holeInterval = '﷐';
const String _holeUnit = '﷑';
const String _holeMonthlyDayOrOrdinal = '﷒';
const String _holeMonthlyWeekday = '﷓';

/// Matches any one of the four hole sentinels in a rendered sentence.
///
/// Walked with `allMatches` rather than handed to `String.split`. Dart's
/// `split` **discards** the delimiter, capture group or not — unlike
/// JavaScript's, which returns captured groups as elements — so splitting
/// would silently drop every hole and leave the user a sentence with no
/// controls in it.
final RegExp _sentinelPattern = RegExp('[﷐-﷓]');

/// The chore form's repeat rule as one sentence whose blanks are tap
/// targets, e.g. "Repeat every **2** **weeks** on".
///
/// The sentence is a **whole** localized ARB message, never a concatenation
/// of fragments (G-2, `docs/plans/2026-08-18-repeat-form-sentence.md`
/// Analysis §4). The widget calls the message passing a unique sentinel per
/// hole, splits the returned string on those sentinels, splits each literal
/// run on whitespace into one [Text] per word, and emits the hole's widget
/// wherever its sentinel appeared. That is what lets a translator own the
/// entire sentence — choosing their own gender and number wording, and
/// placing the holes anywhere in it — which fragments cannot do, because
/// German inflects the frame by both the unit's gender (*jeden* Tag, *jede*
/// Woche) and the interval's number (*jede Woche* vs *alle 2 Wochen*), and
/// because a fixed widget order bakes English syntax into the tree.
///
/// The result is a [Wrap] rather than a `Text.rich` of `WidgetSpan`s: a
/// 40px chip inside a `WidgetSpan` against 17px text makes line height jump,
/// and `WidgetSpan` with a large [TextScaler] is a known source of
/// unbounded-height and overflow exceptions — and text scale 2.0 is a
/// release gate here (`docs/specs/theme-v2.md` §5). A `Wrap` simply wraps.
///
/// Which shape is rendered follows the same "a control that does not apply
/// does not exist" rule as the rest of the block. Note the month + **
/// completion** case deliberately renders the plain interval-and-unit
/// shape: `nextAfterCompletion`'s month branch is
/// `completedOn.addMonths(interval)` and reads no monthly field at all, so
/// a day-of-month hole there would be a control that changes nothing.
class RepeatSentence extends StatelessWidget {
  /// Creates the repeat sentence.
  const RepeatSentence({
    required this.intervalController,
    required this.intervalError,
    required this.unit,
    required this.onUnitChanged,
    required this.anchor,
    required this.monthlyMode,
    required this.monthlyDayOfMonth,
    required this.onMonthlyDayOfMonthChanged,
    required this.monthlyOrdinal,
    required this.onMonthlyOrdinalChanged,
    required this.monthlyWeekday,
    required this.onMonthlyWeekdayChanged,
    super.key,
  });

  /// Backs the raw interval text the user typed.
  final TextEditingController intervalController;

  /// Inline validation error for the interval hole, or `null` when valid.
  final String? intervalError;

  /// The currently-selected unit.
  final RecurrenceUnit unit;

  /// Called when a different unit is picked from the unit hole's menu.
  final ValueChanged<RecurrenceUnit> onUnitChanged;

  /// The currently-selected anchor, which decides whether the monthly holes
  /// apply at all (see the class doc).
  final RecurrenceAnchor anchor;

  /// The currently-selected monthly mode, which picks between the
  /// day-of-month hole and the ordinal + weekday pair.
  final MonthlyMode monthlyMode;

  /// The currently-selected day of the month, 1..31 or `-1` for "the last
  /// day" (the same sentinel [Recurrence.monthlyDayOfMonth] persists).
  final int monthlyDayOfMonth;

  /// Called with the newly-picked day of the month, `-1` for "the last day".
  final ValueChanged<int> onMonthlyDayOfMonthChanged;

  /// The currently-selected monthly ordinal, 1..4 or `-1` for "last".
  final int monthlyOrdinal;

  /// Called with the newly-picked monthly ordinal, `-1` for "last".
  final ValueChanged<int> onMonthlyOrdinalChanged;

  /// The currently-selected monthly ISO weekday, 1..7.
  final int monthlyWeekday;

  /// Called with the newly-picked monthly ISO weekday.
  final ValueChanged<int> onMonthlyWeekdayChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeName = Localizations.localeOf(context).toString();
    // Best-effort parse for display only: the unit noun has to pluralize as
    // the user types, and an empty or invalid field must still render
    // *something* here. `intervalError` is what actually blocks save.
    final interval = int.tryParse(intervalController.text.trim()) ?? 1;

    final holes = <String, Widget>{
      _holeInterval: _IntervalHole(
        key: const ValueKey('chore_form.repeat.interval'),
        controller: intervalController,
        errorText: intervalError,
        label: l10n.choreFormSentenceIntervalA11y,
      ),
      _holeUnit: _MenuHole<RecurrenceUnit>(
        key: const ValueKey('chore_form.repeat.unit'),
        id: 'chore_form.repeat.unit',
        label: l10n.choreFormSentenceUnitA11y,
        text: _unitLabel(l10n, unit, interval),
        value: unit,
        onChanged: onUnitChanged,
        entries: [
          for (final value in RecurrenceUnit.values)
            _MenuEntry(
              value: value,
              text: _unitLabel(l10n, value, interval),
              id: 'chore_form.repeat.unit.${value.name}',
            ),
        ],
      ),
    };

    final String sentence;
    if (unit == RecurrenceUnit.month && anchor == RecurrenceAnchor.schedule) {
      if (monthlyMode == MonthlyMode.dayOfMonth) {
        holes[_holeMonthlyDayOrOrdinal] = _MenuHole<int>(
          key: const ValueKey('chore_form.repeat.monthly_day'),
          id: 'chore_form.repeat.monthly_day',
          label: l10n.choreFormSentenceMonthlyDayA11y,
          text: _dayLabel(l10n, monthlyDayOfMonth, localeName),
          value: monthlyDayOfMonth,
          onChanged: onMonthlyDayOfMonthChanged,
          entries: [
            for (var day = 1; day <= 31; day++)
              _MenuEntry(
                value: day,
                text: _dayLabel(l10n, day, localeName),
              ),
            _MenuEntry(value: -1, text: l10n.choreFormDayOfMonthLast),
          ],
        );
        sentence = l10n.choreFormSentenceMonthDayOfMonth(
          _holeInterval,
          _holeUnit,
          _holeMonthlyDayOrOrdinal,
        );
      } else {
        holes[_holeMonthlyDayOrOrdinal] = _MenuHole<int>(
          key: const ValueKey('chore_form.repeat.monthly_ordinal'),
          id: 'chore_form.repeat.monthly_ordinal',
          label: l10n.choreFormSentenceMonthlyOrdinalA11y,
          text: _ordinalLabel(l10n, monthlyOrdinal, localeName),
          value: monthlyOrdinal,
          onChanged: onMonthlyOrdinalChanged,
          entries: [
            for (final ordinal in [1, 2, 3, 4, -1])
              _MenuEntry(
                value: ordinal,
                text: _ordinalLabel(l10n, ordinal, localeName),
              ),
          ],
        );
        holes[_holeMonthlyWeekday] = _MenuHole<int>(
          key: const ValueKey('chore_form.repeat.monthly_weekday'),
          id: 'chore_form.repeat.monthly_weekday',
          label: l10n.choreFormSentenceMonthlyWeekdayA11y,
          text: weekdayName(monthlyWeekday, localeName),
          value: monthlyWeekday,
          onChanged: onMonthlyWeekdayChanged,
          entries: [
            for (var weekday = 1; weekday <= 7; weekday++)
              _MenuEntry(
                value: weekday,
                text: weekdayName(weekday, localeName),
              ),
          ],
        );
        sentence = l10n.choreFormSentenceMonthWeekday(
          _holeInterval,
          _holeUnit,
          _holeMonthlyDayOrOrdinal,
          _holeMonthlyWeekday,
        );
      }
    } else if (unit == RecurrenceUnit.week) {
      sentence = l10n.choreFormSentenceWeek(_holeInterval, _holeUnit);
    } else {
      sentence = l10n.choreFormSentenceDay(_holeInterval, _holeUnit);
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: _compose(sentence, holes),
    );
  }

  /// Splits [sentence] on its sentinels and returns the [Wrap]'s children:
  /// one [Text] per literal word, and each hole's widget where its sentinel
  /// stood.
  ///
  /// Asserts every hole was placed exactly once. A translation that drops a
  /// placeholder would otherwise silently delete a control from the form —
  /// the user would simply have no way to change that part of the rule, with
  /// nothing anywhere reporting it. This is an `assert` rather than a throw
  /// because a missing control is bad but a crashed form is worse, and
  /// because every translation ships through a debug build first.
  List<Widget> _compose(String sentence, Map<String, Widget> holes) {
    final children = <Widget>[];
    final placed = <String>{};

    void addWords(String run) {
      // Whitespace only, so punctuation stays attached to its word.
      for (final word in run.split(RegExp(r'\s+'))) {
        if (word.isNotEmpty) {
          children.add(Text(word));
        }
      }
    }

    var cursor = 0;
    for (final match in _sentinelPattern.allMatches(sentence)) {
      addWords(sentence.substring(cursor, match.start));
      final sentinel = match.group(0)!;
      final hole = holes[sentinel];
      if (hole != null) {
        assert(
          placed.add(sentinel),
          'The repeat sentence placed the same hole twice; a translation '
          'must use each placeholder exactly once.',
        );
        children.add(hole);
      }
      cursor = match.end;
    }
    addWords(sentence.substring(cursor));
    assert(
      placed.length == holes.length,
      'The repeat sentence is missing ${holes.length - placed.length} of its '
      '${holes.length} placeholders, so that many controls are absent from '
      'the form. Check the ARB message for this shape in every locale.',
    );
    return children;
  }

  String _unitLabel(AppLocalizations l10n, RecurrenceUnit value, int interval) {
    switch (value) {
      case RecurrenceUnit.day:
        return l10n.choreFormUnitDayPlural(interval);
      case RecurrenceUnit.week:
        return l10n.choreFormUnitWeekPlural(interval);
      case RecurrenceUnit.month:
        return l10n.choreFormUnitMonthPlural(interval);
    }
  }

  String _dayLabel(AppLocalizations l10n, int day, String localeName) {
    return day == -1
        ? l10n.choreFormDayOfMonthLast
        : localizedOrdinal(day, localeName);
  }

  String _ordinalLabel(AppLocalizations l10n, int ordinal, String localeName) {
    return ordinal == -1
        ? l10n.choreFormOrdinalLast
        : localizedOrdinal(ordinal, localeName);
  }
}

/// One entry in a hole's menu.
class _MenuEntry<T> {
  const _MenuEntry({required this.value, required this.text, this.id});

  final T value;
  final String text;

  /// A semantic id, for the entries that are E2E API (the three units).
  final String? id;
}

/// A hole that opens a menu of choices.
class _MenuHole<T> extends StatelessWidget {
  const _MenuHole({
    required this.id,
    required this.label,
    required this.text,
    required this.value,
    required this.onChanged,
    required this.entries,
    super.key,
  });

  final String id;
  final String label;
  final String text;
  final T value;
  final ValueChanged<T> onChanged;
  final List<_MenuEntry<T>> entries;

  @override
  Widget build(BuildContext context) {
    return semantic(
      id,
      // The visible chip text ("2", "Weeks", "20th") is meaningless out of
      // context to a screen reader, so the hole carries a label naming what
      // it changes. Same Semantics + ExcludeSemantics shape `WeekdayChips`
      // already uses; the Text widgets themselves are untouched, so
      // `find.text` still sees them.
      child: Semantics(
        button: true,
        label: label,
        value: text,
        child: ExcludeSemantics(
          child: _SentenceChip(
            onTap: () => _open(context),
            trailing: const Icon(Icons.unfold_more, size: 16),
            child: Text(text),
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    // `showMenu`, not `MenuAnchor`: the day-of-month hole offers 32 choices,
    // and a popup menu route scrolls its items where a `MenuAnchor` panel
    // does not — at text scale 2.0 that is the difference between a usable
    // picker and an overflow.
    final picked = await showMenu<T>(
      context: context,
      position: position,
      initialValue: value,
      items: [
        for (final entry in entries)
          PopupMenuItem<T>(
            value: entry.value,
            child: entry.id == null
                ? Text(entry.text)
                : semantic(entry.id!, child: Text(entry.text)),
          ),
      ],
    );
    if (picked != null) {
      onChanged(picked);
    }
  }
}

/// The interval hole: a text field that reads as a blank in the sentence
/// rather than as a form input parked inside a paragraph.
///
/// It stays typeable (G-2 OPD-4) because a bounded picker would forbid
/// legitimate rules like "every 90 days", and because keeping it a
/// [TextField] preserves `validateInterval`, its inline error, and the
/// existing tests that reach it by descendant [TextField]. Everything else
/// about it is made to match the other holes: the same chip container, no
/// floating label, no helper text, no underline — the chip's own border
/// does all the work.
class _IntervalHole extends StatelessWidget {
  const _IntervalHole({
    required this.controller,
    required this.errorText,
    required this.label,
    super.key,
  });

  final TextEditingController controller;
  final String? errorText;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = errorText;
    // No ExcludeSemantics here, unlike the menu holes: the field must stay
    // an editable node for a screen reader to type into.
    final field = semantic(
      'chore_form.repeat.interval',
      child: Semantics(
        label: label,
        child: _SentenceChip(
          // Sizes to its content so "2" and "90" both sit tight and the
          // surrounding words do not jump apart, with maxLength keeping it
          // from growing without bound mid-sentence.
          child: IntrinsicWidth(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 3,
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                counterText: '',
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
      ),
    );
    if (error == null) {
      return field;
    }
    // An empty or invalid field mid-sentence reads as broken in a way a chip
    // never does, so the inline error stays live and sits directly under its
    // own hole rather than at the bottom of the block.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        field,
        Text(
          error,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ],
    );
  }
}

/// The one container every hole in the sentence shares: a filled, outlined
/// box that is a real tap target.
///
/// [BoxConstraints.minHeight] is a **floor, not a fixed height** — the chip
/// grows with the text at large text scales and the enclosing [Wrap]
/// reflows the sentence around it. If the sentence ever overflows, the fix
/// is the constraint; never a tap target below 40px.
class _SentenceChip extends StatelessWidget {
  const _SentenceChip({required this.child, this.onTap, this.trailing});

  final Widget child;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: famdoColors(context).primaryOutline),
          ),
          child: DefaultTextStyle.merge(
            style: theme.textTheme.titleSmall?.copyWith(
              color: colorScheme.onPrimaryContainer,
            ),
            child: IconTheme.merge(
              data: IconThemeData(color: colorScheme.primary),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(child: child),
                  ?trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
