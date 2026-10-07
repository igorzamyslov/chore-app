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
/// still to go', or a done-for-the-day line when K is 0, followed by ' · N
/// to catch up' when overdue occurrences exist), an optional
/// filter-active line, and a decorative 58dp progress ring.
///
/// **Counting rule (exact)**: [pendingDueToday] is the count of
/// still-pending occurrences due TODAY; [overdueCount] the still-pending
/// ones due before today; [completedToday] the occurrences with status
/// `done` (never `skipped` -- a skip isn't "done") closed today. `M` =
/// `pendingDueToday + overdueCount + completedToday`; `N` =
/// `completedToday`; the ring is `N / M`; the sub-line's "still to go" is
/// `M - N`, with the overdue share repeated as "N to catch up".
/// **Changed 2026-10-07** (first-use feedback on 0.15.0): overdue is part of
/// `M` again -- skipping is always available, so an overdue chore is part of
/// today's load. This supersedes the 2026-10-06 (persona review E5) rule that
/// kept overdue out of `M`. **Changed 2026-08-07** (triage T1.1/D3): all
/// figures are computed by the caller from the SAME member/category-filtered
/// collections the chores list screen renders its sections from -- never
/// the whole household when a filter is active -- so this card and the list
/// beneath it can never disagree. [filterActive] tells the card whether
/// that filtering is currently narrowing the count, so a filtered "1 of 2"
/// is never mistaken for the household's whole day.
///
/// The whole card renders as [SizedBox.shrink] when `M == 0` -- an empty
/// ring is noise, not signal. (An overdue-only pile has `M > 0` by
/// construction, so the 2026-10-07 overdue-only headline is gone.)
///
/// Semantic id `chores.progress`. The card carries a single [Semantics]
/// label with the same sentence the visible text already shows (title +
/// sub-line + filter line, when shown), and every descendant text node --
/// including the ring's decorative percentage -- is excluded from the
/// accessibility tree, so a screen reader announces the sentence exactly
/// once.
class ChoreProgressCard extends StatelessWidget {
  /// Creates the progress card for [completedToday]/[pendingDueToday]
  /// (see the counting rule above), on [today], noting via [filterActive]
  /// whether a member/category filter is currently narrowing those counts.
  const ChoreProgressCard({
    required this.completedToday,
    required this.pendingDueToday,
    required this.overdueCount,
    required this.today,
    required this.filterActive,
    super.key,
  });

  /// Occurrences with status `done` closed today (never `skipped`). This is
  /// both `N` and the "completed today" term added into `M`.
  final int completedToday;

  /// Still-pending occurrences due today.
  final int pendingDueToday;

  /// Still-pending occurrences overdue (due before [today]) -- counted into
  /// `M` and repeated on the sub-line as "N to catch up".
  final int overdueCount;

  /// The current local calendar day, per the app's injected clock.
  final PlainDate today;

  /// Whether a member/category filter is active on the chores list right
  /// now -- when `true`, [completedToday]/[pendingDueToday] are the
  /// FILTERED subset, not the whole household's day, and the card says so.
  final bool filterActive;

  @override
  Widget build(BuildContext context) {
    final total = completedToday + pendingDueToday + overdueCount;
    if (total == 0) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final localeName = Localizations.localeOf(context).toString();
    final remaining = total - completedToday;
    final progress = completedToday / total;

    // Natural case for the accessibility label, uppercase only for display:
    // uppercase is typography, not content.
    final dateNatural = DateFormat.MMMMEEEEd(
      localeName,
    ).format(DateTime.utc(today.year, today.month, today.day));
    final dateLabel = dateNatural.toUpperCase();
    final title = l10n.choresProgressTitle(completedToday, total);
    // `remaining == 0` implies nothing is overdue either, so the catch-up
    // segment only ever follows "N still to go".
    final subline = [
      if (remaining == 0)
        l10n.choresProgressAllDoneToday
      else
        l10n.choresProgressRemainingToday(remaining),
      if (overdueCount > 0) l10n.choresProgressCatchUp(overdueCount),
    ].join(' · ');
    final sublineStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final filterNote = filterActive ? l10n.choresProgressFilterActive : null;

    return semantic(
      'chores.progress',
      child: Semantics(
        label: [dateNatural, title, subline, ?filterNote].join('. '),
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
                        Text(subline, style: sublineStyle),
                        if (filterNote != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            filterNote,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
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
