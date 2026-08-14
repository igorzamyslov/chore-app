/// The digest pre-prompt banner (spec `docs/specs/polish-round-1.md` A3 /
/// G3): a dismissible card at the top of the chores list explaining the
/// daily-summary notification BEFORE the one-shot OS permission dialog
/// fires, so that dialog only ever appears from this explicit tap (or the
/// Settings digest permission hint's recovery path).
library;

import 'package:chore_app/app/depth_card.dart';
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/application/digest_plan_builder.dart';
import 'package:chore_app/features/chores/active_chores_presence.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shown only while ALL hold: `settings.digestPrepromptShownAt` is `NULL`,
/// the digest is enabled, the OS notification permission is not granted,
/// and at least one chore exists in the household (so a fresh install shows
/// the name-prompt banner first, `onboarding_name_banner.dart`).
class DigestPrepromptBanner extends ConsumerWidget {
  /// Creates the banner.
  const DigestPrepromptBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value;
    final permissionGranted = ref.watch(notificationPermissionGrantedProvider);
    final hasActiveChores = ref.watch(hasActiveChoresProvider).value ?? false;

    if (settings == null) {
      return const SizedBox.shrink();
    }
    final shouldShow =
        settings.digestPrepromptShownAt == null &&
        settings.digestEnabled &&
        !permissionGranted &&
        hasActiveChores;
    if (!shouldShow) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final onSecondaryContainer = theme.colorScheme.onSecondaryContainer;

    return semantic(
      'digest.preprompt',
      child: DepthCard(
        color: theme.colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.digestPrepromptMessage,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: onSecondaryContainer,
                  ),
                ),
              ),
              semantic(
                'digest.preprompt.dismiss',
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: onSecondaryContainer,
                  ),
                  onPressed: () => _dismiss(ref),
                  child: Text(l10n.digestPrepromptDismissAction),
                ),
              ),
              semantic(
                'digest.preprompt.enable',
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: onSecondaryContainer,
                  ),
                  onPressed: () => _enable(ref),
                  child: Text(l10n.digestPrepromptEnableAction),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _dismiss(WidgetRef ref) {
    return ref.read(settingsRepositoryProvider).markDigestPrepromptShown();
  }

  Future<void> _enable(WidgetRef ref) async {
    await ref.read(settingsRepositoryProvider).markDigestPrepromptShown();
    // The one-shot OS dialog. Safe to call unconditionally: the OS only
    // ever prompts the user once, silently returning the existing
    // grant/deny status on later calls (see `DigestNotificationPlugin.
    // requestPermission`'s doc comment).
    final plugin = ref.read(digestNotificationPluginProvider);
    await plugin.requestPermission();
    final granted = await plugin.isPermissionGranted();
    ref.read(notificationPermissionGrantedProvider.notifier).state = granted;
    await _recomputeDigest(ref);
  }

  /// Re-runs the same horizon build the `DigestRescheduleController`
  /// (`lib/app/providers.dart`) runs, via the shared
  /// [buildDigestPlans] — this used to be a hand-copied duplicate of that
  /// controller's private recompute, which it cannot call directly (the
  /// controller owns a persistent debounced `Timer` and is activated
  /// exactly once, from `main.dart`, never from the widget tree).
  Future<void> _recomputeDigest(WidgetRef ref) async {
    final scheduler = ref.read(notificationSchedulerProvider);
    await scheduler.ensureInitialized();

    final settings = ref.read(settingsProvider).value;
    final pending = ref.read(pendingOccurrencesProvider).value;
    if (settings == null || pending == null) {
      return;
    }

    await scheduler.applyDigestPlans(
      buildDigestPlans(
        now: ref.read(clockProvider).now(),
        settings: settings,
        pending: pending,
        recipientMemberId: ref.read(actingMemberProvider)?.id,
      ),
    );
  }
}
