/// The member add/edit bottom sheet: rename, recolor, save, delete (spec
/// `docs/feedback/2026-08-01-ux-audit.md` A1).
///
/// Delete is visible only when the member is actually removable, which as of
/// F10 (spec `docs/specs/household-lifecycle.md` §3.2) no longer excludes
/// claimed profiles: an unclaimed profile is removable locally, and a
/// claimed one is removable through the `remove_member` RPC by ANY member
/// (D-L2 -- there is no role gate and none is coming). See [_DeleteGate] for
/// the three cases that still hide it.
///
/// Removing a claimed profile is the one action in this sheet that can fail
/// for a reason the user has to see, since it needs the network. That
/// failure is rendered inline (semantic id `members.remove.error`) rather
/// than swallowed into a silent retry.
library;

import 'package:chore_app/app/color_swatch_picker.dart';
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/application/member_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:chore_app/features/members/member_avatar.dart';
import 'package:chore_app/features/settings/member_delete_dialog.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the modal bottom sheet for adding a new member (when [member] is
/// omitted) or editing an existing [member] (rename/recolor).
///
/// A new member defaults to the first of
/// [CategoryRepository.palette] — the same fixed palette the category
/// edit sheet uses — not already used by another current member (wrapping
/// back to the first color if every palette color is taken).
///
/// Member colors are unique per household (G-4): a color another active
/// member holds is drawn inert and badged with that member's initials. See
/// `_takenColors` for why that rule relaxes rather than blocks once the
/// roster outgrows the palette.
Future<void> showMemberEditSheet(BuildContext context, {Member? member}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _MemberEditSheet(member: member),
  );
}

/// Why the member edit sheet's Delete affordance is or is not offered (spec
/// `docs/specs/household-lifecycle.md` §3.2, F10).
///
/// One value computed once per build, rather than a `canDelete` bool plus a
/// separately-derived reason string: those two encoded the same precedence
/// in two places that could drift, and re-deriving the reason meant a second
/// [membersProvider] watch the reason helper's own doc comment said it was
/// avoiding.
enum _DeleteGate {
  /// Adding a new member: no delete affordance applies at all, so there is
  /// nothing to explain either.
  notApplicable,

  /// Delete is offered.
  allowed,

  /// The household's last active member -- removing it would leave zero.
  /// Outranks every other reason, including [ownClaimedRow], which matters
  /// for a one-member household whose sole member is you.
  lastMember,

  /// The caller's own claimed row. Self-removal is what the server rejects
  /// (§2.2) and what the Leave action is for; it is never Delete.
  ownClaimedRow,

  /// A claimed target while this device is signed out or unlinked, so the
  /// `remove_member` RPC cannot be made at all.
  unreachable,
}

class _MemberEditSheet extends ConsumerStatefulWidget {
  const _MemberEditSheet({this.member});

  final Member? member;

  @override
  ConsumerState<_MemberEditSheet> createState() => _MemberEditSheetState();
}

class _MemberEditSheetState extends ConsumerState<_MemberEditSheet> {
  late final TextEditingController _nameController;
  late int _color;

  /// The localized message for a failed CLAIMED-member removal (spec
  /// `docs/specs/household-lifecycle.md` §3.2), or `null` when nothing has
  /// failed. Cleared on every new attempt.
  String? _removalError;

  /// True while the `remove_member` round trip is in flight -- Delete is
  /// disabled meanwhile, so a double tap cannot fire two RPCs.
  bool _removing = false;

  bool get _isEditing => widget.member != null;

  @override
  void initState() {
    super.initState();
    final member = widget.member;
    _nameController = TextEditingController(text: member?.name ?? '')
      ..addListener(_onNameChanged);
    _color = member?.color ?? _firstFreeColor();
  }

  @override
  void dispose() {
    _nameController
      ..removeListener(_onNameChanged)
      ..dispose();
    super.dispose();
  }

  void _onNameChanged() => setState(() {});

  bool get _canSave => _nameController.text.trim().isNotEmpty;

  /// The household's active roster, WATCHED so both the taken-color map
  /// and the preview avatar rebuild when somebody else's color changes.
  ///
  /// `_firstFreeColor` cannot use this: it runs from `initState`, where
  /// `ref.watch` is illegal, so it reads the same provider directly.
  List<Member> get _currentMembers =>
      ref.watch(membersProvider).value ?? const <Member>[];

  /// Whether the delete action should be shown at all, and if not, why
  /// (spec: HIDDEN, never disabled).
  ///
  /// Claim state no longer blocks outright (spec
  /// `docs/specs/household-lifecycle.md` §3.2, F10): a claimed profile IS
  /// removable, via the `remove_member` RPC, by ANY member -- D-L2, there is
  /// no role gate here or anywhere else. What still blocks is
  /// [_DeleteGate.lastMember], [_DeleteGate.ownClaimedRow] and
  /// [_DeleteGate.unreachable], in that precedence.
  ///
  /// [membersProvider] is already the roster query (soft-deleted members
  /// excluded, `HouseholdRepository.watchMembers`), so its current length
  /// already reflects "active members" -- if the member being edited is
  /// one of only one, deleting it would leave zero.
  _DeleteGate get _deleteGate {
    final member = widget.member;
    if (member == null) {
      return _DeleteGate.notApplicable;
    }
    final activeMembers = ref.watch(membersProvider).value ?? const <Member>[];
    if (activeMembers.length <= 1) {
      return _DeleteGate.lastMember;
    }
    if (member.userId == null) {
      return _DeleteGate.allowed;
    }
    // Compared against [currentAuthUserProvider] directly rather than
    // through `claimedMemberProvider`: that provider is gated on
    // MemberIdentityMode.pinned, so while signed in but unlinked it returns
    // null and one's own row would fall through to
    // [_DeleteGate.unreachable] -- whose copy ("used on someone else's
    // phone") is flatly wrong about your own profile. Signed OUT there is no
    // id to compare against and `unreachable` is the honest answer.
    if (member.userId == ref.watch(currentAuthUserProvider).valueOrNull?.id) {
      return _DeleteGate.ownClaimedRow;
    }
    // The RPC needs a signed-in session AND a linked household, which is
    // precisely MemberIdentityMode.pinned -- reused rather than re-derived
    // from `settingsProvider`, whose bare watch that provider's own doc
    // comment forbids (a started sync engine writes
    // `settings.syncLastPulledAt` on every pull, so an unscoped watch
    // rebuilds this sheet on each of them).
    return ref.watch(memberIdentityModeProvider) == MemberIdentityMode.pinned
        ? _DeleteGate.allowed
        : _DeleteGate.unreachable;
  }

  /// The explanation that replaces the vanished Delete button for [gate]
  /// (T1.7 -- `docs/research/persona-anna.md` finding 6,
  /// `docs/research/triage.md` T1.7), or `null` when Delete is shown or no
  /// delete affordance applies (adding a new member).
  ///
  /// Worded as an accident prevented or a precondition missing, never a
  /// permission (spec D1, `docs/specs/sync-backend.md` §2: the household is
  /// flat by design -- this is "removing this profile would break
  /// something" or "this can't reach the household right now", never "you
  /// aren't allowed to").
  String? _deleteBlockedReason(AppLocalizations l10n, _DeleteGate gate) {
    return switch (gate) {
      _DeleteGate.notApplicable || _DeleteGate.allowed => null,
      _DeleteGate.lastMember => l10n.memberEditDeleteBlockedLastMember,
      _DeleteGate.ownClaimedRow => l10n.memberEditDeleteBlockedSelf,
      _DeleteGate.unreachable => l10n.memberEditDeleteBlockedOffline,
    };
  }

  int _firstFreeColor() {
    // `ref.read`, not `_currentMembers`: this is called from `initState`,
    // where `ref.watch` is illegal.
    final members = ref.read(membersProvider).value ?? const <Member>[];
    final usedColors = members.map((m) => m.color).toSet();
    const palette = CategoryRepository.palette;
    return palette.firstWhere(
      (color) => !usedColors.contains(color),
      orElse: () => palette[members.length % palette.length],
    );
  }

  /// The palette colors held by OTHER active members, mapped to their
  /// owner's badge (G-4: member colors are unique per household).
  ///
  /// The member being edited is excluded, so their own current color stays
  /// selectable. If every palette color is already held, this returns an
  /// EMPTY map: with twelve colors a thirteenth member has nothing free,
  /// and relaxing the rule is strictly better than refusing to add a person
  /// over a color. Uniqueness is UI guidance and never a database
  /// constraint -- under sync two devices can claim the same color
  /// concurrently, and the loser's save must not fail.
  Map<int, TakenSwatch> _takenColors(AppLocalizations l10n) {
    final editingId = widget.member?.id;
    final owners = <int, Member>{};
    for (final member in _currentMembers) {
      if (member.id != editingId) {
        owners.putIfAbsent(member.color, () => member);
      }
    }
    if (owners.length >= CategoryRepository.palette.length) {
      return const {};
    }
    return {
      for (final entry in owners.entries)
        entry.key: TakenSwatch(
          // The SHARED rule from member_avatar.dart, not a local copy: a
          // badged swatch must read as exactly that member's avatar.
          initials: memberInitials(entry.value.name),
          semanticsLabel: l10n.memberEditColorTakenBy(entry.value.name),
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final deleteGate = _deleteGate;
    final canDelete = deleteGate == _DeleteGate.allowed;
    final deleteBlockedReason = _deleteBlockedReason(l10n, deleteGate);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isEditing ? l10n.memberEditEditTitle : l10n.memberEditNewTitle,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          semantic(
            'members.edit.name',
            child: TextField(
              controller: _nameController,
              decoration: InputDecoration(labelText: l10n.memberEditNameLabel),
            ),
          ),
          const SizedBox(height: 24),
          // The live preview replaces the standalone color label: it shows
          // the picked ring and the typed initials together, which is the
          // thing the swatch grid below is actually choosing. The name
          // field's existing `_onNameChanged` listener already calls
          // `setState`, so the initials update as the user types.
          semantic(
            'members.edit.avatar',
            child: Row(
              children: [
                MemberAvatar(
                  member: previewMember(
                    name: _nameController.text,
                    color: _color,
                  ),
                  radius: 33,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    l10n.memberEditColorLabel,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ColorSwatchPicker(
            colors: CategoryRepository.palette,
            selected: _color,
            onSelected: (value) => setState(() => _color = value),
            semanticIdPrefix: 'members.edit.color',
            taken: _takenColors(l10n),
          ),
          const SizedBox(height: 12),
          semantic(
            'members.edit.colorHint',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.memberEditColorUniqueHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // T1.7: a member the sheet cannot remove gets no Delete button
          // (see [_DeleteGate]) -- previously nothing took its place, a
          // quiet dead end where the (already-shipped) A1 audit item told
          // the user deletion would now work. This explanation takes the
          // button's place instead, on its own line (never squeezed into
          // the Row below, which visual QA already flagged for overflow at
          // large text scales -- see settings_group.dart's stacking fix).
          if (deleteBlockedReason != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: semantic(
                'members.edit.deleteBlockedReason',
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        deleteBlockedReason,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // The ONE inline failure surface in this app (spec
          // `docs/specs/household-lifecycle.md` §3.2). Takes the same
          // visual slot as the blocked-reason explanation above -- and the
          // two are mutually exclusive in practice, since a removal can
          // only fail after Delete was shown.
          if (_removalError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: semantic(
                'members.remove.error',
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 20,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _removalError!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Row(
            children: [
              if (canDelete)
                semantic(
                  'members.edit.delete',
                  child: TextButton(
                    onPressed: _removing ? null : _delete,
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    child: Text(l10n.commonDelete),
                  ),
                ),
              const Spacer(),
              semantic(
                'members.edit.save',
                child: FilledButton(
                  onPressed: _canSave ? _save : null,
                  child: Text(l10n.commonSave),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final repo = ref.read(householdRepositoryProvider);
    final existing = widget.member;
    if (existing != null) {
      await repo.renameMember(existing.id, name);
      await repo.recolorMember(existing.id, _color);
    } else {
      final householdId = ref.read(bootstrapProvider).requireValue;
      await repo.addMember(householdId, name: name, color: _color);
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final existing = widget.member;
    if (existing == null) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final confirmed = await showMemberDeleteDialog(
      context,
      memberName: existing.name,
      claimed: existing.userId != null,
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() {
      _removing = true;
      _removalError = null;
    });
    try {
      await ref.read(memberServiceProvider).deleteMember(existing.id);
    } on ClaimedMemberRemovalFailure catch (_) {
      // The ONE inline error in this app (spec
      // `docs/specs/household-lifecycle.md` §3.2): the removal needs the
      // network, nothing was written, and the person the user tried to
      // remove is still in the household, so the user must be told --
      // unlike every local action in this sheet, and unlike
      // `docs/specs/sync-backend.md` §8.3's swallow-and-retry posture for
      // background sync.
      if (mounted) {
        setState(() {
          _removing = false;
          _removalError = l10n.memberRemoveError(existing.name);
        });
      }
      return;
    }
    // Any OTHER throw stays uncaught. [_DeleteGate] already excludes every
    // locally-refusable case, so a StateError from
    // `MemberService.deleteMember`'s guards here is a genuine bug (or an
    // exceedingly rare cross-device race), exactly as it was before this
    // slice -- and `MemberService` has already wrapped everything the
    // gateway can throw, `on Object`, into the failure above.
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }
}
