/// The settings screen's 'About' section (spec `docs/next-session-plan.md`
/// #5): app name/version, the licenses page entry, and a donate row that
/// opens a sheet linking to the developer's Ko-fi/PayPal pages.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Section header above the About rows, matching the digest section
/// header's style (design-language: labelLarge, onSurfaceVariant, 24/8
/// padding, no divider line).
class AboutSectionHeader extends StatelessWidget {
  /// Creates the section header.
  const AboutSectionHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        AppLocalizations.of(context).settingsAboutSectionTitle,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Non-tappable row showing the app's (localized) name and 'Version
/// {version} ({buildNumber})', sourced from [packageInfoProvider]. Shows an
/// em dash in place of the version/build number while that provider is
/// still loading.
class AboutVersionTile extends ConsumerWidget {
  /// Creates the version row.
  const AboutVersionTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final packageInfo = ref.watch(packageInfoProvider).valueOrNull;
    final version = packageInfo?.version ?? '—';
    final buildNumber = packageInfo?.buildNumber ?? '—';

    return semantic(
      'settings.about.version',
      child: ListTile(
        leading: const Icon(Icons.info_outline),
        title: Text(l10n.appTitle),
        subtitle: Text(l10n.settingsAboutVersionLabel(version, buildNumber)),
      ),
    );
  }
}

/// Row opening Flutter's built-in [showLicensePage].
class AboutLicensesTile extends ConsumerWidget {
  /// Creates the licenses row.
  const AboutLicensesTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final version = ref.watch(packageInfoProvider).valueOrNull?.version;

    return semantic(
      'settings.about.licenses',
      child: ListTile(
        leading: const Icon(Icons.description_outlined),
        title: Text(l10n.settingsAboutLicensesEntry),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showLicensePage(
          context: context,
          applicationName: l10n.appTitle,
          applicationVersion: version,
        ),
      ),
    );
  }
}

/// The developer's own donation links (user-provided 2026-07-31). These are
/// intentionally NOT localized or user-configurable -- they're constants,
/// not content.
const _koFiUrl = 'https://ko-fi.com/igorzamyslov';
const _payPalUrl = 'https://paypal.me/igorzamyslov';

/// Row opening [showDonateSheet], which links to the developer's Ko-fi and
/// PayPal pages.
class AboutDonateTile extends StatelessWidget {
  /// Creates the donate row.
  const AboutDonateTile({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return semantic(
      'settings.about.donate',
      child: ListTile(
        leading: const Icon(Icons.volunteer_activism_outlined),
        title: Text(l10n.settingsAboutDonateTitle),
        subtitle: Text(l10n.settingsAboutDonateSubtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showDonateSheet(context),
      ),
    );
  }
}

/// Opens the donate sheet: a Ko-fi row and a PayPal row, each launching the
/// corresponding URL externally (spec `LaunchMode.externalApplication`)
/// and then closing the sheet.
Future<void> showDonateSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => const _DonateSheet(),
  );
}

class _DonateSheet extends StatelessWidget {
  const _DonateSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    Future<void> open(String url) async {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }

    return semantic(
      'settings.about.donate.sheet',
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                l10n.settingsAboutDonateSheetTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            semantic(
              'settings.about.donate.kofi',
              child: ListTile(
                leading: const Icon(Icons.favorite_outline),
                title: Text(l10n.settingsAboutDonateKofiLabel),
                onTap: () => open(_koFiUrl),
              ),
            ),
            semantic(
              'settings.about.donate.paypal',
              child: ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: Text(l10n.settingsAboutDonatePaypalLabel),
                onTap: () => open(_payPalUrl),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
