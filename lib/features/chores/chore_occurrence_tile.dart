/// A single pending occurrence's list tile.
library;

import 'package:chore_app/app/depth_card.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/app/theme.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/features/chores/chore_section.dart';
import 'package:chore_app/features/chores/due_tone.dart';
import 'package:chore_app/features/members/member_avatar.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// The localized due text for a non-overdue [dueDate] (on or after
/// [today]): 'Today'/'Tomorrow' near the boundary, 'In N days' for 2-7 days
/// out, else the locale-formatted weekday + month + day (e.g. 'Fri, Jul
/// 31') via `package:intl` — never a hardcoded weekday/month name.
///
/// [dueDate] must not be before [today]; an overdue tile uses
/// [overdueDueText] instead.
String futureDueText(
  AppLocalizations l10n,
  String localeName, {
  required PlainDate today,
  required PlainDate dueDate,
}) {
  final diff = today.daysUntil(dueDate);
  if (diff == 0) {
    return l10n.choresDueToday;
  }
  if (diff == 1) {
    return l10n.choresDueTomorrow;
  }
  if (diff <= 7) {
    return l10n.choresDueInDays(diff);
  }
  return DateFormat.MMMEd(
    localeName,
  ).format(DateTime.utc(dueDate.year, dueDate.month, dueDate.day));
}

/// The localized due text for an overdue [dueDate] (strictly before
/// [today]): 'Overdue · N days', pluralized.
String overdueDueText(
  AppLocalizations l10n, {
  required PlainDate today,
  required PlainDate dueDate,
}) {
  return l10n.choresDueOverdue(dueDate.daysUntil(today));
}

/// A tile for one pending [OccurrenceWithChore].
///
/// Layout (spec `docs/specs/theme-v2.md` §4.1 item 3, amending
/// `docs/specs/ux-round-2.md` A1): a leading 26dp complete ring inside a
/// 48dp tap target, vertically centered against a text block of the chore's
/// title (titleMedium), a metadata row (bodySmall, onSurfaceVariant) showing
/// the assignee's avatar + first name (when assigned), the category dot +
/// name, and the due text as a trailing chip — shown on every tile
/// where it adds information, in the tile's [DueTone] colors when overdue —
/// and, only when the chore has a note, a one-line ellipsized note row.
/// Tiles due today or overdue additionally tint their container (design
/// option C, see [dueTone]): a container ground, an outline border, and a
/// 3dp accent left edge -- success when due today, warning when overdue by
/// fewer than 7 days, error from 7 days on. Tapping the tile body or the
/// trailing menu button, or long-pressing anywhere on the tile, opens the
/// action sheet via [onOpenMenu] (tap added 2026-10-06, persona review C3).
class ChoreOccurrenceTile extends StatelessWidget {
  /// Creates a tile for [occurrence].
  const ChoreOccurrenceTile({
    required this.occurrence,
    required this.today,
    required this.section,
    required this.onComplete,
    required this.onOpenMenu,
    this.waitingToSend = false,
    super.key,
  });

  /// The occurrence (and its joined chore/category/assignee) to display.
  final OccurrenceWithChore occurrence;

  /// The current local calendar day, per the app's injected clock — used to
  /// compute the tile's relative due text.
  final PlainDate today;

  /// The list section this tile is rendered under. Drives whether the due
  /// text is shown at all: under Today/Tomorrow the header already states
  /// the due day, so repeating it on the tile is noise (user feedback, see
  /// ux-round-2.md A1).
  final ChoreSection section;

  /// Called when the leading complete button is tapped.
  final VoidCallback onComplete;

  /// Called when the tile body or the trailing menu button is tapped, or
  /// the tile is long-pressed.
  final VoidCallback onOpenMenu;

  /// Whether to show the small "waiting to send" clock before the menu
  /// button (persona review 2026-10-06 E10): the caller passes `true` only
  /// while the household is linked AND this occurrence is `syncDirty`, so
  /// a change made on a weak connection does not look identical to one the
  /// rest of the household already has.
  final bool waitingToSend;

  @override
  Widget build(BuildContext context) {
    final chore = occurrence.chore;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final notes = chore.notes;
    final toneColors = dueToneColors(
      context,
      dueTone(today: today, dueDate: occurrence.occurrence.dueDate),
    );

    // Status treatment (spec §4.1 item 4, design option C): a 3dp accent
    // left edge, added as a plain leading sibling in the tile's own Row
    // (rather than wrapping the whole tile in another Row/Expanded layer)
    // so the InkWell/IconButton semantics subtree below keeps the exact
    // same shape as the neutral tile.
    final tile = semantic(
      'chores.occurrence.${chore.id}',
      child: InkWell(
        // Persona review 2026-10-06 C3: a tap on the body opens the same
        // sheet as the kebab -- tapping a chore to change it is the first
        // thing people try, and shopping rows already open on tap. The
        // complete ring and the kebab keep their own tap targets.
        onTap: onOpenMenu,
        onLongPress: onOpenMenu,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              if (toneColors != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4, top: 4, bottom: 4),
                  child: Container(
                    width: 3,
                    constraints: const BoxConstraints(minHeight: 48),
                    color: toneColors.accent,
                  ),
                ),
              semantic(
                'chores.occurrence.${chore.id}.complete',
                // G1 (persona review 2026-10-06): a screen reader walking a
                // list of identical "Complete" buttons cannot tell which
                // chore each one belongs to, so the label names it. The
                // inner IconButton's own tooltip semantics are excluded to
                // avoid announcing "Complete" twice.
                child: Semantics(
                  label:
                      '${l10n.choresOccurrenceCompleteTooltip}: '
                      '${chore.title}',
                  button: true,
                  excludeSemantics: true,
                  onTap: onComplete,
                  child: IconButton(
                    icon: const _CompleteRing(),
                    tooltip: l10n.choresOccurrenceCompleteTooltip,
                    onPressed: onComplete,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(chore.title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      _MetadataRow(
                        occurrence: occurrence,
                        today: today,
                        section: section,
                        toneColors: toneColors,
                      ),
                      if (notes != null && notes.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        _NoteLine(note: notes),
                      ],
                    ],
                  ),
                ),
              ),
              if (waitingToSend)
                Tooltip(
                  message: l10n.syncPendingItemTooltip,
                  child: Icon(
                    Icons.schedule,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              semantic(
                'chores.occurrence.${chore.id}.menu',
                child: Semantics(
                  label:
                      '${l10n.choresOccurrenceMoreActionsTooltip}: '
                      '${chore.title}',
                  button: true,
                  excludeSemantics: true,
                  onTap: onOpenMenu,
                  child: IconButton(
                    icon: const Icon(Icons.more_vert),
                    tooltip: l10n.choresOccurrenceMoreActionsTooltip,
                    onPressed: onOpenMenu,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (toneColors == null) {
      return DepthCard(child: tile);
    }

    // Tone container ground + outline border; color is never the only
    // signal -- the section header names the day, and an overdue tile's due
    // chip still spells out how late it is (see _DueChip).
    return DepthCard(
      color: toneColors.container,
      borderColor: toneColors.outline,
      child: tile,
    );
  }
}

/// The complete control's ring glyph: a 26dp circle with a 2px `outline`
/// border, drawn inside the [IconButton] that already provides the 48dp tap
/// target, tooltip, and semantics (spec `docs/specs/theme-v2.md` §4.1 item
/// 3). Every occurrence in this list is still open (a completed one moves
/// to the Done-today section instead), so only the "open" ring ever renders
/// here.
class _CompleteRing extends StatelessWidget {
  const _CompleteRing();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.outline,
          width: 2,
        ),
      ),
    );
  }
}

/// The metadata row: the assignee avatar + first name (if assigned), a
/// category dot + name (if categorized), and a trailing due chip — only under
/// sections where it adds information beyond the section header
/// (Overdue/This week/This month/Later; hidden under Today/Tomorrow).
class _MetadataRow extends StatelessWidget {
  const _MetadataRow({
    required this.occurrence,
    required this.today,
    required this.section,
    required this.toneColors,
  });

  final OccurrenceWithChore occurrence;
  final PlainDate today;
  final ChoreSection section;
  final DueToneColors? toneColors;

  bool get _showsDueText => switch (section) {
    ChoreSection.today || ChoreSection.tomorrow => false,
    ChoreSection.overdue ||
    ChoreSection.thisWeek ||
    ChoreSection.thisMonth ||
    ChoreSection.later => true,
  };

  @override
  Widget build(BuildContext context) {
    final category = occurrence.category;
    final assignee = occurrence.assignedMember;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final localeName = Localizations.localeOf(context).toString();
    final dueDate = occurrence.occurrence.dueDate;
    final isOverdue = section == ChoreSection.overdue;

    return DefaultTextStyle.merge(
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Assignee first: "whose is this" is what a scan of the list
          // looks for, so it sits at a fixed left position on every tile.
          if (assignee != null)
            _MemberAvatarName(member: assignee)
          else
            const _AnyoneChip(),
          if (category != null) _CategoryDotName(category: category),
          if (_showsDueText)
            _DueChip(
              text: isOverdue
                  ? overdueDueText(l10n, today: today, dueDate: dueDate)
                  : futureDueText(
                      l10n,
                      localeName,
                      today: today,
                      dueDate: dueDate,
                    ),
              toneColors: toneColors,
            ),
        ],
      ),
    );
  }
}

/// A 7dp category dot followed by the category name, both in
/// [categoryTone] (spec `docs/specs/theme-v2.md` §4.1 item 3) -- the tile's
/// own replacement for `CategoryBadge`'s icon+name pairing; `CategoryBadge`
/// itself is untouched, other screens still use it.
class _CategoryDotName extends StatelessWidget {
  const _CategoryDotName({required this.category});

  final Category category;

  @override
  Widget build(BuildContext context) {
    final color = categoryTone(context, category.color);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(category.name, style: TextStyle(color: color)),
      ],
    );
  }
}

/// The due text's trailing chip (spec `docs/specs/theme-v2.md` §4.1 item 3):
/// `surfaceContainerHigh` ground, `onSurfaceVariant` ink, `labelMedium`,
/// radius 8. An overdue tile swaps in its tone's chip ground and accent ink
/// ([toneColors], item 4) -- the chip's own text still states how late it
/// is, so color is never the only signal.
class _DueChip extends StatelessWidget {
  const _DueChip({required this.text, required this.toneColors});

  final String text;
  final DueToneColors? toneColors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = toneColors?.accent ?? theme.colorScheme.onSurfaceVariant;
    final ground = toneColors?.chip ?? theme.colorScheme.surfaceContainerHigh;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: ground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(color: ink),
      ),
    );
  }
}

/// The chip standing in for the assignee on an unassigned tile (persona
/// review 2026-10-06 E1): anyone may do it, and the member filter keeps it.
class _AnyoneChip extends StatelessWidget {
  const _AnyoneChip();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.group_outlined,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Text(AppLocalizations.of(context).choresAssigneeAnyone),
      ],
    );
  }
}

/// A circular avatar in [member]'s color with their initial, followed by
/// their first name.
class _MemberAvatarName extends StatelessWidget {
  const _MemberAvatarName({required this.member});

  final Member member;

  @override
  Widget build(BuildContext context) {
    final trimmedName = member.name.trim();
    final firstName = trimmedName.isEmpty
        ? member.name
        : trimmedName.split(RegExp(r'\s+')).first;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MemberAvatar(member: member),
        const SizedBox(width: 4),
        Text(firstName),
      ],
    );
  }
}

/// The note row: a small icon followed by [note], truncated to one
/// ellipsized line.
class _NoteLine extends StatelessWidget {
  const _NoteLine({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(Icons.notes_outlined, size: 16, color: color),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            note,
            // G2 (persona review 2026-10-06): at large text sizes one
            // ellipsized line shows barely a word, so the note gets a
            // second line.
            maxLines: MediaQuery.textScalerOf(context).scale(1) > 1.3 ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
