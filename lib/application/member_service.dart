/// The member-deletion service (spec `docs/feedback/2026-08-01-ux-audit.md`
/// A1): the referential cleanup that has to run alongside a member's soft
/// delete, so no chore/occurrence is left pointing at a member no longer
/// selectable anywhere.
library;

import 'package:chore_app/application/household_gateway.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/db/sync_dirty.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart';

/// Thrown by [MemberService.deleteMember] when the server-side removal of a
/// CLAIMED member failed (spec `docs/specs/household-lifecycle.md` §3.2).
///
/// This is the one action in this app whose failure must be shown to the user
/// inline rather than swallowed into a silent retry
/// (`docs/specs/sync-backend.md` §8.3): it needs the network, it changed
/// nothing, and the person the user was trying to remove is still in the
/// household. Nothing local has been written when this is thrown.
class ClaimedMemberRemovalFailure implements Exception {
  /// Wraps the underlying transport/RPC [cause].
  const ClaimedMemberRemovalFailure(this.cause);

  /// The error the gateway threw.
  final Object cause;

  @override
  String toString() => 'ClaimedMemberRemovalFailure($cause)';
}

/// Orchestrates member deletion on top of [ChoreRepository] primitives and
/// a direct write to the `members` table (no dedicated member repository
/// method exists for the soft delete itself -- this is its only writer).
class MemberService {
  /// Creates a service backed by [database] (used to open the single
  /// transaction [deleteMember] runs in) and [chores] (the chore/assignee/
  /// occurrence primitives the referential cleanup orchestrates). [clock]
  /// defaults to the real system clock; tests should inject
  /// `Clock.fixed(...)`.
  MemberService({
    required this.database,
    required this.chores,
    required this.gateway,
    this.clock = const Clock(),
  });

  /// The database this service opens its transaction on, and reads/writes
  /// the `members` row directly on (soft delete has no repository method
  /// of its own).
  final AppDatabase database;

  /// The repository primitives this service orchestrates for the
  /// referential cleanup (rotation/fixed assignee lists, pending
  /// occurrences).
  final ChoreRepository chores;

  /// The Supabase seam used to remove a CLAIMED member server-side (spec
  /// `docs/specs/household-lifecycle.md` §3.2). Never touched for an
  /// unclaimed profile, which stays a purely local operation -- so a
  /// local-only household never reaches the network even though this
  /// dependency is always present.
  final HouseholdGateway gateway;

  /// The clock used for the soft-delete timestamp. Injectable for
  /// deterministic tests.
  final Clock clock;

  /// Soft-deletes the member [memberId].
  ///
  /// Routing by claim state (spec `docs/specs/household-lifecycle.md` §3.2,
  /// F10), which replaced the old flat refusal of any claimed member:
  ///
  /// - **unclaimed** (`userId == null`) -- purely local, exactly as before;
  /// - **claimed** -- `remove_member` on the server FIRST (which unclaims
  ///   and soft-deletes the profile there), then the identical local
  ///   cleanup. A failed RPC throws [ClaimedMemberRemovalFailure] with
  ///   nothing written locally.
  ///
  /// Any member may remove any other: `members.role` is vestigial (D1/D-L2)
  /// and no role is consulted here or anywhere else. Removing one's OWN row
  /// is not this method's job and is rejected by the server (§2.2); the UI
  /// hides the action and points at Leave instead
  /// (`lib/features/settings/member_edit_sheet.dart`).
  ///
  /// The two guards -- the member exists and is active, and the household
  /// keeps at least one active member -- are evaluated TWICE on the claimed
  /// path: once before the RPC, so a removal the local rules refuse never
  /// reaches the server, and once inside the transaction, which is the
  /// atomic one. The RPC deliberately runs OUTSIDE the transaction: a
  /// network round trip inside one holds drift's write lock across it and
  /// cannot be rolled back anyway.
  ///
  /// Everything from here on runs in ONE transaction:
  ///
  /// 1. Both guards again (each throws [StateError], changing nothing).
  /// 2. Referential cleanup, over every active (non-soft-deleted) chore of
  ///    the member's household:
  ///    - rotation chores containing [memberId] in their assignee order:
  ///      remove them from that order; if 2 or more assignees remain, stay
  ///      rotation with the shorter order; if exactly 1 remains, convert
  ///      to `fixed` with that one assignee; if 0 remain, convert to
  ///      `anyone` (assignees cleared).
  ///    - fixed chores whose single assignee is [memberId]: convert to
  ///      `anyone` (assignees cleared).
  /// 3. Every PENDING occurrence currently assigned to [memberId] (across
  ///    every chore, regardless of the chore's own assignment mode) has
  ///    its `assignedMemberId` cleared to `null` -- this is what actually
  ///    unassigns the member's CURRENT turn, since step 2 alone only
  ///    changes a chore's future assignee list/mode, not an
  ///    already-inserted occurrence.
  /// 4. The member row itself is soft-deleted (`deletedAt` + `updatedAt`
  ///    set, `syncDirty` marked per the shared write-time helper).
  ///
  /// History is deliberately untouched throughout: closed occurrences'
  /// `assignedMemberId`/`completedBy` keep pointing at the now-deleted
  /// member row, so "who did what" stays readable (the soft delete alone
  /// makes that possible -- display joins never filter on `deletedAt`, see
  /// `lib/app/providers.dart`'s members-query classification).
  Future<void> deleteMember(String memberId) async {
    final claimed = (await _requireRemovable(memberId)).userId != null;
    if (claimed) {
      try {
        await gateway.removeMember(memberId);
      } on Object catch (error) {
        // `on Object`, not `on Exception`: this net exists to turn ANY
        // server-side failure into the one inline error surface the spec
        // mandates (§3.2), and an Error that escaped it would crash the
        // sheet instead. Nothing local has been written at this point.
        throw ClaimedMemberRemovalFailure(error);
      }
    }
    await database.transaction(() async {
      final member = await _requireRemovable(memberId);

      final activeChores = await chores.getActiveChores(member.householdId);
      for (final details in activeChores) {
        final assignees = details.assigneeMemberIds;
        if (!assignees.contains(memberId)) {
          continue;
        }
        switch (details.chore.assignmentMode) {
          case AssignmentMode.rotation:
            final remaining = [
              for (final id in assignees)
                if (id != memberId) id,
            ];
            if (remaining.length >= 2) {
              await chores.updateChore(
                details.chore.id,
                assigneeMemberIds: remaining,
              );
            } else if (remaining.length == 1) {
              await chores.updateChore(
                details.chore.id,
                assignmentMode: AssignmentMode.fixed,
                assigneeMemberIds: remaining,
              );
            } else {
              await chores.updateChore(
                details.chore.id,
                assignmentMode: AssignmentMode.anyone,
                assigneeMemberIds: const [],
              );
            }
          case AssignmentMode.fixed:
            await chores.updateChore(
              details.chore.id,
              assignmentMode: AssignmentMode.anyone,
              assigneeMemberIds: const [],
            );
          case AssignmentMode.anyone:
          // Unreachable: `anyone` chores have no assignees, so `assignees
          // .contains(memberId)` above is always false for this branch.
        }
      }

      await chores.unassignPendingOccurrencesForMember(memberId);

      final now = clock.now().toUtc().toIso8601String();
      await (database.update(
        database.members,
      )..where((tbl) => tbl.id.equals(memberId))).write(
        MembersCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          syncDirty: syncDirtyOnWrite,
        ),
      );
    });
  }

  /// Reads [memberId] and asserts both removal guards, throwing [StateError]
  /// (changing nothing) when either fails: the member must exist and be
  /// active, and its household must keep at least one active member
  /// afterwards.
  ///
  /// Called once BEFORE the `remove_member` RPC and once inside the
  /// transaction -- see [deleteMember] for why both.
  Future<Member> _requireRemovable(String memberId) async {
    final member = await (database.select(
      database.members,
    )..where((tbl) => tbl.id.equals(memberId))).getSingleOrNull();
    if (member == null || member.deletedAt != null) {
      throw StateError('No active member with id $memberId');
    }
    final activeMembers =
        await (database.select(database.members)..where(
              (tbl) =>
                  tbl.householdId.equals(member.householdId) &
                  tbl.deletedAt.isNull(),
            ))
            .get();
    if (activeMembers.length <= 1) {
      throw StateError(
        'Cannot delete member $memberId: it is the last remaining '
        'member of household ${member.householdId}',
      );
    }
    return member;
  }
}
