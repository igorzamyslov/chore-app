/// The first-run name-prompt banner (spec `docs/specs/polish-round-1.md`
/// A2 / G2): a dismissible card at the top of the chores list inviting the
/// bootstrap member to set their real name, never a modal.
library;

import 'dart:async';

import 'package:chore_app/app/depth_card.dart';
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/features/settings/member_edit_sheet.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shown only while `settings.onboardingNamePromptShownAt` is `NULL` AND
/// the household still consists of exactly the bootstrap member named
/// 'Me'. Any other shape (an upgrading install that already renamed or
/// added members, or the moment right after 'Set my name' itself renamed
/// the bootstrap member) silently marks the flag instead of showing
/// anything — both cases collapse to the same "not the fresh bootstrap
/// shape anymore" check.
class OnboardingNameBanner extends ConsumerStatefulWidget {
  /// Creates the banner.
  const OnboardingNameBanner({super.key});

  @override
  ConsumerState<OnboardingNameBanner> createState() =>
      _OnboardingNameBannerState();
}

class _OnboardingNameBannerState extends ConsumerState<OnboardingNameBanner> {
  // Guards against dispatching the silent-mark write more than once while
  // its (fast, in-memory) round trip is in flight — harmless if it fired
  // twice anyway (each write just stamps a fresh timestamp), but there's no
  // reason to.
  bool _silentMarkDispatched = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value;
    final members = ref.watch(membersProvider).value;
    if (settings == null || members == null) {
      return const SizedBox.shrink();
    }
    if (settings.onboardingNamePromptShownAt != null) {
      return const SizedBox.shrink();
    }

    final isBootstrapShape = members.length == 1 && members.single.name == 'Me';
    if (!isBootstrapShape) {
      if (!_silentMarkDispatched) {
        _silentMarkDispatched = true;
        unawaited(
          ref.read(settingsRepositoryProvider).markOnboardingNamePromptShown(),
        );
      }
      return const SizedBox.shrink();
    }
    _silentMarkDispatched = false;

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final onSecondaryContainer = theme.colorScheme.onSecondaryContainer;
    final bootstrapMember = members.single;

    return semantic(
      'onboarding.name',
      child: DepthCard(
        color: theme.colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.onboardingNameBannerMessage,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: onSecondaryContainer,
                  ),
                ),
              ),
              semantic(
                'onboarding.name.set',
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: onSecondaryContainer,
                  ),
                  onPressed: () =>
                      showMemberEditSheet(context, member: bootstrapMember),
                  child: Text(l10n.onboardingNameBannerSetAction),
                ),
              ),
              semantic(
                'onboarding.name.dismiss',
                child: IconButton(
                  icon: Icon(Icons.close, color: onSecondaryContainer),
                  tooltip: l10n.onboardingNameBannerDismissTooltip,
                  onPressed: () => ref
                      .read(settingsRepositoryProvider)
                      .markOnboardingNamePromptShown(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
