/// The settings screen's 'About' section (spec `docs/next-session-plan.md`
/// #5): app name/version, the error-reports switch, ONE 'Technical details'
/// row opening a sheet with the privacy notes, the source code, the licenses
/// page and the sync server's host (persona review D11; grouped behind one
/// row by Amendment 2026-10-07, `docs/specs/theme-v2.md`), and a donate row
/// that opens a sheet linking to the developer's Ko-fi/PayPal pages.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/app/supabase_config.dart';
import 'package:chore_app/features/settings/settings_group.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Non-tappable row showing the app's (localized) name and, as its
/// `bodySmall` sub-line, 'Version {version} ({buildNumber})', sourced from
/// [packageInfoProvider]. Shows an em dash in place of the version/build
/// number while that provider is still loading.
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
      child: SettingsRow(
        icon: Icons.info_outline,
        label: l10n.appTitle,
        sublabel: l10n.settingsAboutVersionLabel(version, buildNumber),
      ),
    );
  }
}

/// Switch row for `Settings.errorReportsEnabled` (spec
/// `docs/specs/client-error-reporting.md` §6): whether recorded errors are
/// uploaded to the sync server. Shown always, also while signed out -- the
/// value then governs future uploads. Defaults to on until the settings row
/// has loaded, matching the column's own default.
class AboutErrorReportsTile extends ConsumerWidget {
  /// Creates the error-reports switch row.
  const AboutErrorReportsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final enabled =
        ref.watch(settingsProvider).valueOrNull?.errorReportsEnabled ?? true;

    return semantic(
      'settings-error-reports-switch',
      child: SettingsRow(
        icon: Icons.bug_report_outlined,
        label: l10n.settingsErrorReportsTitle,
        sublabel: l10n.settingsErrorReportsSubtitle,
        switchValue: enabled,
        onSwitchChanged: (value) => ref
            .read(settingsRepositoryProvider)
            .setErrorReportsEnabled(enabled: value),
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
      child: SettingsRow(
        icon: Icons.description_outlined,
        label: l10n.settingsAboutLicensesEntry,
        showChevron: true,
        onTap: () => showLicensePage(
          context: context,
          applicationName: l10n.appTitle,
          applicationVersion: version,
        ),
      ),
    );
  }
}

/// The project's own public pages (persona review D11). Constants, not
/// content -- the same reasoning as the donation links below.
const _privacyUrl =
    'https://github.com/igorzamyslov/chore-app/blob/main/PRIVACY.md';
const _sourceUrl = 'https://github.com/igorzamyslov/chore-app';

/// Row opening the privacy notes (`PRIVACY.md`) in the browser.
class AboutPrivacyTile extends StatelessWidget {
  /// Creates the privacy-notes row.
  const AboutPrivacyTile({super.key});

  @override
  Widget build(BuildContext context) {
    return semantic(
      'settings.about.privacy',
      child: SettingsRow(
        icon: Icons.privacy_tip_outlined,
        label: AppLocalizations.of(context).settingsAboutPrivacy,
        showChevron: true,
        onTap: () => launchUrl(
          Uri.parse(_privacyUrl),
          mode: LaunchMode.externalApplication,
        ),
      ),
    );
  }
}

/// Row opening the source repository in the browser.
class AboutSourceTile extends StatelessWidget {
  /// Creates the source-code row.
  const AboutSourceTile({super.key});

  @override
  Widget build(BuildContext context) {
    return semantic(
      'settings.about.source',
      child: SettingsRow(
        icon: Icons.code,
        label: AppLocalizations.of(context).settingsAboutSource,
        showChevron: true,
        onTap: () => launchUrl(
          Uri.parse(_sourceUrl),
          mode: LaunchMode.externalApplication,
        ),
      ),
    );
  }
}

/// Non-tappable two-line tile naming the sync server's host (persona review
/// D11), so "the sync server" in the sign-in disclosure points somewhere
/// concrete. The label sits on the first line and the host on the second, as
/// selectable text: a trailing value squeezed the label into "Syn c ser ver"
/// (Amendment 2026-10-07). No chevron -- nothing opens. The technical-details
/// sheet only mounts it when `supabaseConfigured`; [serverUrl] defaults to the
/// configured URL and is a parameter only so a test can render it in a build
/// without one.
class AboutSyncServerTile extends StatelessWidget {
  /// Creates the sync-server tile.
  const AboutSyncServerTile({this.serverUrl = supabaseUrl, super.key});

  /// The configured Supabase URL; only its host is shown.
  final String serverUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return semantic(
      'settings.about.syncServer',
      child: ListTile(
        leading: Icon(
          Icons.dns_outlined,
          size: 21,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        title: Text(
          AppLocalizations.of(context).settingsAboutSyncServer,
          style: theme.textTheme.titleSmall,
        ),
        subtitle: SelectableText(
          Uri.tryParse(serverUrl)?.host ?? serverUrl,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// The About row (`settings.about.technical`) that opens
/// [showTechnicalDetailsSheet]: the project/legal/plumbing entries that used
/// to be four separate rows (Amendment 2026-10-07).
class AboutTechnicalTile extends StatelessWidget {
  /// Creates the technical-details row.
  const AboutTechnicalTile({super.key});

  @override
  Widget build(BuildContext context) {
    return semantic(
      'settings.about.technical',
      child: SettingsRow(
        icon: Icons.build_outlined,
        label: AppLocalizations.of(context).settingsAboutTechnicalTitle,
        showChevron: true,
        onTap: () => showTechnicalDetailsSheet(
          context,
          showSyncServer: supabaseConfigured,
        ),
      ),
    );
  }
}

/// Opens the technical-details sheet: Privacy notes, Source code, Open source
/// licenses and, when [showSyncServer] (the caller passes
/// `supabaseConfigured`), the Sync server's host. The tiles keep their
/// pre-grouping semantic ids.
Future<void> showTechnicalDetailsSheet(
  BuildContext context, {
  required bool showSyncServer,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _TechnicalDetailsSheet(
      showSyncServer: showSyncServer,
    ),
  );
}

class _TechnicalDetailsSheet extends StatelessWidget {
  const _TechnicalDetailsSheet({required this.showSyncServer});

  final bool showSyncServer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return semantic(
      'settings.about.technical.sheet',
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  l10n.settingsAboutTechnicalTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const AboutPrivacyTile(),
              const AboutSourceTile(),
              const AboutLicensesTile(),
              if (showSyncServer) const AboutSyncServerTile(),
            ],
          ),
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
      child: SettingsRow(
        icon: Icons.volunteer_activism_outlined,
        label: l10n.settingsAboutDonateTitle,
        sublabel: l10n.settingsAboutDonateSubtitle,
        showChevron: true,
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
