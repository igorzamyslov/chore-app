/// The chores app bar's acting-member avatar button and switcher sheet
/// (spec `docs/specs/members-management.md` §4).
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/features/members/member_avatar.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The chores app bar's leading button: shows the current acting member's
/// avatar and opens [showActingMemberSheet] on tap.
///
/// Shown even with a single household member — it's also the affordance
/// that teaches "the app knows who I am" (spec §4). Falls back to a plain
/// disabled icon for the brief window before [actingMemberProvider] has
/// resolved (before bootstrap / the first `membersProvider` emission).
class ActingMemberButton extends ConsumerWidget {
  /// Creates the acting-member button.
  const ActingMemberButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final member = ref.watch(actingMemberProvider);
    return semantic(
      'chores.actingMember',
      child: IconButton(
        tooltip: AppLocalizations.of(context).actingMemberButtonTooltip,
        onPressed: member == null ? null : () => showActingMemberSheet(context),
        icon: member == null
            ? const Icon(Icons.account_circle_outlined)
            : MemberAvatar(member: member, radius: 14),
      ),
    );
  }
}

/// Opens the acting-member switcher: one row per household member (avatar +
/// name + a check on the current one). Selecting a row persists it via
/// `SettingsRepository.setActingMember` and closes the sheet.
Future<void> showActingMemberSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => const _ActingMemberSheet(),
  );
}

class _ActingMemberSheet extends ConsumerWidget {
  const _ActingMemberSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final members = ref.watch(membersProvider).value ?? const <Member>[];
    final currentId = ref.watch(actingMemberProvider)?.id;

    return semantic(
      'actingMember.sheet',
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                l10n.actingMemberSheetTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final member in members)
              semantic(
                'actingMember.sheet.row.${member.id}',
                child: ListTile(
                  leading: MemberAvatar(member: member, radius: 14),
                  title: Text(member.name),
                  trailing: member.id == currentId
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () async {
                    await ref
                        .read(settingsRepositoryProvider)
                        .setActingMember(member.id);
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
