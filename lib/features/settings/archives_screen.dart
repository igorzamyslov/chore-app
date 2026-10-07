/// The saved copies of earlier households (persona review B3): the row under
/// Settings -> Data, the list it opens (Share and Delete per file), the
/// post-join snackbar that points at the newest copy, and the share call both
/// of them use.
///
/// A copy is written (`lib/application/household_archive.dart`) every time
/// this device joins or reconnects to a household and its old local data is
/// replaced. It is a full JSON export sitting in app-private storage, so
/// without this surface a person had no way to ever reach it, share it or
/// remove it -- the file name the old snackbar printed was no help.
library;

import 'dart:async';

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/app/snackbars.dart';
import 'package:chore_app/application/app_log.dart';
import 'package:chore_app/application/household_archive.dart';
import 'package:chore_app/features/settings/settings_group.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

/// Every saved copy on this device, newest first. A listing failure (no
/// documents directory, a plugin hiccup) reads as "none": the row simply
/// stays hidden rather than showing an error for a feature that is only
/// ever a convenience.
final AutoDisposeFutureProvider<List<HouseholdArchive>>
householdArchivesProvider = FutureProvider.autoDispose<List<HouseholdArchive>>((
  ref,
) async {
  try {
    return await listHouseholdArchives();
  } on Object catch (e, s) {
    AppLog.error('ui.archivesList', e, s);
    return const [];
  }
});

/// Opens the OS share sheet for the saved copy at [path] -- the same
/// `SharePlus` call shape as the Export row (`export_row.dart`), but for a
/// file that already exists on disk.
Future<void> shareHouseholdArchiveFile(String path) {
  final name = path.substring(path.lastIndexOf('/') + 1);
  return SharePlus.instance.share(
    ShareParams(
      files: [XFile(path, mimeType: 'application/json')],
      fileNameOverrides: [name],
    ),
  );
}

/// The snackbar shown after a join or reconnect that saved the old
/// household: says so, and offers "Share..." for that very file.
///
/// Lasts 10 s rather than the default 4: the person has just finished a
/// multi-step sheet and needs time to notice the action.
void showArchiveSavedSnackbar(BuildContext context, String fileName) {
  final l10n = AppLocalizations.of(context);
  showAppSnackbar(
    context,
    message: l10n.settingsAccountJoinSuccessSnackbar,
    duration: const Duration(seconds: 10),
    action: SnackBarAction(
      label: l10n.commonShare,
      onPressed: () => unawaited(_shareByName(context, fileName)),
    ),
  );
}

Future<void> _shareByName(BuildContext context, String fileName) async {
  try {
    await shareHouseholdArchiveFile(await householdArchivePath(fileName));
  } on Exception catch (e, s) {
    AppLog.error('ui.archiveShare', e, s);
    if (context.mounted) {
      showAppErrorSnackbar(
        context,
        message: AppLocalizations.of(context).settingsArchivesShareError,
      );
    }
  }
}

/// The Data-group row: "Saved copies of earlier households (N)", opening
/// [ArchivesScreen]. The caller only builds it when [count] > 0.
class ArchivesTile extends StatelessWidget {
  /// Creates the row for [count] saved copies.
  const ArchivesTile({required this.count, super.key});

  /// How many saved copies exist; shown in the label.
  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return semantic(
      'settings.archives',
      child: SettingsRow(
        icon: Icons.inventory_2_outlined,
        label: l10n.settingsArchivesRow(count),
        showChevron: true,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ArchivesScreen()),
        ),
      ),
    );
  }
}

/// The list of saved copies, each with Share and Delete (the latter behind
/// its own confirm). Pops itself when the last copy is deleted.
class ArchivesScreen extends ConsumerWidget {
  /// Creates the saved-copies screen.
  const ArchivesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final archives = ref.watch(householdArchivesProvider).valueOrNull ?? [];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsArchivesTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              l10n.settingsArchivesIntro,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          for (final archive in archives)
            _ArchiveRow(
              key: ValueKey(archive.path),
              archive: archive,
              isLast: archives.length == 1,
            ),
        ],
      ),
    );
  }
}

class _ArchiveRow extends ConsumerWidget {
  const _ArchiveRow({
    required this.archive,
    required this.isLast,
    super.key,
  });

  final HouseholdArchive archive;

  /// Deleting the last copy leaves nothing to list, so the screen closes.
  final bool isLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final savedAt = archive.savedAt;
    final title = savedAt == null
        ? archive.fileName
        : l10n.settingsArchivesItemTitle(
            DateFormat.yMMMd(l10n.localeName).add_Hm().format(savedAt),
          );
    return ListTile(
      title: Text(title),
      subtitle: savedAt == null ? null : Text(archive.fileName),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          semantic(
            'settings.archives.share',
            child: IconButton(
              tooltip: l10n.commonShare,
              icon: const Icon(Icons.ios_share_outlined),
              onPressed: () => unawaited(_share(context)),
            ),
          ),
          semantic(
            'settings.archives.delete',
            child: IconButton(
              tooltip: l10n.commonDelete,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => unawaited(_confirmDelete(context, ref)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _share(BuildContext context) async {
    try {
      await shareHouseholdArchiveFile(archive.path);
    } on Exception catch (e, s) {
      AppLog.error('ui.archiveShare', e, s);
      if (context.mounted) {
        showAppErrorSnackbar(
          context,
          message: AppLocalizations.of(context).settingsArchivesShareError,
          onRetry: () => unawaited(_share(context)),
        );
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.settingsArchivesDeleteConfirmTitle),
        content: Text(l10n.settingsArchivesDeleteConfirmBody),
        actions: [
          semantic(
            'settings.archives.delete.cancel',
            child: TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.commonCancel),
            ),
          ),
          semantic(
            'settings.archives.delete.confirm',
            child: TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.commonDelete),
            ),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !context.mounted) {
      return;
    }
    try {
      await deleteHouseholdArchive(archive);
    } on Exception catch (e, s) {
      AppLog.error('ui.archiveDelete', e, s);
      if (context.mounted) {
        showAppErrorSnackbar(
          context,
          message: AppLocalizations.of(context).settingsArchivesDeleteError,
        );
      }
      return;
    }
    ref.invalidate(householdArchivesProvider);
    if (isLast && context.mounted) {
      Navigator.of(context).pop();
    }
  }
}
