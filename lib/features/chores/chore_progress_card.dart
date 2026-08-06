/// The day-progress card atop the chores list (spec
/// `docs/specs/theme-v2.md` §4.1 item 1).
library;

import 'dart:math' as math;

import 'package:chore_app/app/depth_card.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// A raised card summarizing today's chore-completion progress: an
/// uppercase locale-formatted date, 'N of M done today', a sub-line ('K
/// still to go', or a done-for-the-day line when K is 0), and a decorative
/// 58dp progress ring.
///
/// **Counting rule (exact)**: [pendingDueOrOverdue] is the count of
/// still-pending occurrences due today or overdue; [completedToday] is the
/// count of occurrences with status `done` (never `skipped` -- a skip isn't
/// "done") closed today. `M` = `pendingDueOrOverdue + completedToday`; `N` =
/// `completedToday`. Both figures are computed by the caller from data the
/// chores list screen already watches (`pendingOccurrencesProvider`,
/// `closedTodayOccurrencesProvider`) -- no new provider needed.
///
/// The whole card renders as [SizedBox.shrink] when `M == 0` (nothing was
/// ever on the plate today) -- an empty ring is noise, not signal.
///
/// Semantic id `chores.progress`. The card carries a single [Semantics]
/// label with the same sentence the visible text already shows (title +
/// sub-line), and every descendant text node -- including the ring's
/// decorative percentage -- is excluded from the accessibility tree, so a
/// screen reader announces the sentence exactly once.
class ChoreProgressCard extends StatelessWidget {
  /// Creates the progress card for [completedToday]/[pendingDueOrOverdue]
  /// (see the counting rule above), on [today].
  const ChoreProgressCard({
    required this.completedToday,
    required this.pendingDueOrOverdue,
    required this.today,
    super.key,
  });

  /// Occurrences with status `done` closed today (never `skipped`). This is
  /// both `N` and the "completed today" term added into `M`.
  final int completedToday;

  /// Still-pending occurrences due today or overdue.
  final int pendingDueOrOverdue;

  /// The current local calendar day, per the app's injected clock.
  final PlainDate today;

  @override
  Widget build(BuildContext context) {
    final total = completedToday + pendingDueOrOverdue;
    if (total == 0) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final localeName = Localizations.localeOf(context).toString();
    final remaining = total - completedToday;
    final progress = completedToday / total;

    final dateLabel = DateFormat.MMMMEEEEd(
      localeName,
    ).format(DateTime.utc(today.year, today.month, today.day)).toUpperCase();
    final title = l10n.choresProgressTitle(completedToday, total);
    final subline = remaining == 0
        ? l10n.choresProgressAllDoneToday
        : l10n.choresProgressRemainingToday(remaining);

    return semantic(
      'chores.progress',
      child: Semantics(
        label: '$title. $subline',
        child: DepthCard(
          shadow: true,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          dateLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(title, style: theme.textTheme.titleLarge),
                        const SizedBox(height: 2),
                        Text(
                          subline,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                ExcludeSemantics(child: _ProgressRing(progress: progress)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The 58dp decorative progress ring: an `outlineVariant` track, a `primary`
/// arc (rounded cap, starting at 12 o'clock, drawn at its final value --
/// never animated, per the app's E2E-determinism motion rule), and the
/// percentage centered inside in `titleMedium` with [TextScaler.noScaling]
/// (it is decorative and the same information is in the sentence beside
/// it).
class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.progress});

  /// The completed fraction, in `[0, 1]`.
  final double progress;

  static const double _diameter = 58;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = (progress * 100).round();
    return SizedBox(
      width: _diameter,
      height: _diameter,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(_diameter, _diameter),
            painter: _ProgressRingPainter(
              progress: progress,
              track: theme.colorScheme.outlineVariant,
              arc: theme.colorScheme.primary,
            ),
          ),
          Text(
            '$percent%',
            textScaler: TextScaler.noScaling,
            style: theme.textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

/// Paints [_ProgressRing]'s track + arc.
class _ProgressRingPainter extends CustomPainter {
  const _ProgressRingPainter({
    required this.progress,
    required this.track,
    required this.arc,
  });

  final double progress;
  final Color track;
  final Color arc;

  static const double _strokeWidth = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - _strokeWidth) / 2;

    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    final clamped = progress.clamp(0.0, 1.0);
    if (clamped <= 0) {
      return;
    }
    final arcPaint = Paint()
      ..color = arc
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * clamped,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.track != track ||
        oldDelegate.arc != arc;
  }
}
