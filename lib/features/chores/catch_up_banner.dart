/// The catch-up visibility banner (backlog B-1 / triage T2.1): a dismissible
/// card at the top of the chores list explaining that
/// `ChoreService.catchUpOverdue` rolled some overdue chores forward, so their
/// sudden appearance as freshly-overdue tiles doesn't read as an unexplained
/// accusation (`docs/research/persona-ben.md` finding 1; the requirements are
/// recorded in `docs/specs/occurrence-lifecycle.md` §catchUpOverdue).
library;

import 'package:chore_app/app/depth_card.dart';
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shown only while [catchUpBannerCountProvider] is nonzero — i.e. only when
/// catch-up genuinely moved something the user hasn't acknowledged yet.
/// Dismissing resets that provider to `0`.
///
/// Unlike `OnboardingNameBanner` and `DigestPrepromptBanner`, which are
/// dismissed once and forever via a `settings`-table flag, this banner keeps
/// no persistent "seen" state at all: catch-up is a recurring background
/// event, so a genuinely new lapse months later has to be able to explain
/// itself again. See [catchUpBannerCountProvider].
///
/// Built as a [Row] inside a [DepthCard], matching the other two banners
/// exactly, so it reflows rather than overflows at large text scales.
class CatchUpBanner extends ConsumerWidget {
  /// Creates the banner.
  const CatchUpBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(catchUpBannerCountProvider);
    if (count == 0) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final onSecondaryContainer = theme.colorScheme.onSecondaryContainer;

    return semantic(
      'catchup.banner',
      child: DepthCard(
        color: theme.colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.catchUpBannerMessage(count),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: onSecondaryContainer,
                  ),
                ),
              ),
              semantic(
                'catchup.banner.dismiss',
                child: IconButton(
                  icon: Icon(Icons.close, color: onSecondaryContainer),
                  tooltip: l10n.catchUpBannerDismissTooltip,
                  onPressed: () =>
                      ref.read(catchUpBannerCountProvider.notifier).state = 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
