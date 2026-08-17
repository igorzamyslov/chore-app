/// The D-5 can't-reach-the-household indicator (spec
/// `docs/specs/sync-freshness.md` §2.5): a self-hiding banner shown above the
/// list content on both the chores and shopping tabs whenever
/// [syncHealthStatusProvider] reports [SyncHealthStatus.unhealthy] --
/// invisible for a never-linked household, for a linked-but-signed-out device
/// (already covered by `docs/feedback/2026-08-07-field-feedback.md` A1.1's
/// own honest state in Settings → Account), and for a linked, signed-in
/// device that looks healthy.
library;

import 'package:chore_app/app/depth_card.dart';
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/domain/sync_health.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Renders nothing while healthy; otherwise one generic sentence -- see
/// spec §2.5 for why the copy doesn't distinguish which of the two
/// underlying signals tripped (the user needs the fact and the recourse, not
/// the mechanism), and why it never says "offline".
///
/// Never dismissible and never tappable: it disappears on its own the moment
/// the condition clears, unlike a manually-dismissed banner which could go
/// on hiding a still-ongoing problem — and a control here would only
/// duplicate the pull-to-refresh gesture already on the very same screen,
/// which the copy names instead.
///
/// Built as a [Row] with a single [Expanded] child inside a [DepthCard],
/// matching `CatchUpBanner`/`OnboardingNameBanner`/`DigestPrepromptBanner`
/// exactly, so it reflows rather than overflows at large text scales.
class SyncHealthBanner extends ConsumerWidget {
  /// Creates the banner.
  const SyncHealthBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(syncHealthStatusProvider) == SyncHealthStatus.unhealthy) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final onSecondaryContainer = theme.colorScheme.onSecondaryContainer;

    return semantic(
      'sync.health.banner',
      child: DepthCard(
        // `secondaryContainer`, never `errorContainer` (DECIDED, spec §2.5):
        // for a local-first app being briefly unreachable is a normal
        // condition, not an error, and red here would be alarmist as well as
        // eroding what red means everywhere else in the app.
        color: theme.colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Icon(
                Icons.sync_problem_outlined,
                color: onSecondaryContainer,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.syncHealthBannerMessage,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
