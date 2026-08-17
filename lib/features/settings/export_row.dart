/// The Settings tab's 'Export data' row, the first row in the Data group
/// (spec `docs/specs/theme-v2.md` §4.2; spec
/// `docs/specs/polish-round-1.md` B1; spec
/// `docs/feedback/2026-08-01-field-feedback.md` B4/F7): builds a full JSON
/// backup of every table and hands it to the OS share sheet.
library;

import 'dart:convert';

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/app/snackbars.dart';
import 'package:chore_app/application/data_export.dart';
import 'package:chore_app/features/settings/settings_group.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// The 'Export data' row, the first row in the Data group, above the
/// destructive reset row (`ResetDataTile`, `reset_flow.dart`).
///
/// Tapping it builds the backup document via [buildExportDocument] (the
/// pure, share_plus-free half of this feature) and shares the encoded bytes
/// as a `famdo-export-<yyyy-mm-dd>.json` file (an in-memory `XFile`, whose
/// name is set via `ShareParams.fileNameOverrides` -- `XFile.fromData`'s own
/// `name` argument is ignored on every platform except web). Any failure
/// (building the document, or the share sheet itself) shows a generic
/// error via [showAppSnackbar] rather than crashing or silently doing
/// nothing.
class ExportDataTile extends ConsumerWidget {
  /// Creates the export row.
  const ExportDataTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return semantic(
      'settings.export',
      child: SettingsRow(
        icon: Icons.ios_share_outlined,
        label: l10n.settingsExportEntry,
        onTap: () => _export(context, ref),
      ),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    try {
      final database = ref.read(appDatabaseProvider);
      final clock = ref.read(clockProvider);
      final document = await buildExportDocument(
        database: database,
        clock: clock,
      );
      final bytes = utf8.encode(jsonEncode(document));
      final fileName = exportFileName(clock);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'application/json')],
          fileNameOverrides: [fileName],
        ),
      );
    } on Exception catch (_) {
      // Building the document (a database read) or the share sheet itself
      // can fail for reasons outside our control (disk error, no share
      // target available, ...); the spec's contract is simply "show a
      // generic error", not "enumerate every possible failure". Errors
      // (as opposed to Exceptions) are left to propagate/crash -- those
      // indicate a programming bug, not an expected runtime failure.
      if (context.mounted) {
        showAppSnackbar(
          context,
          message: AppLocalizations.of(context).settingsExportError,
        );
      }
    }
  }
}
