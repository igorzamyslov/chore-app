/// The P2c join flow ("Join an existing household" -- spec
/// `docs/specs/sync-backend.md` §7.4, amended 2026-08-01), run from the
/// Settings Account section's join row/sheet
/// (`lib/features/settings/join_household_sheet.dart`) once the user has
/// picked an existing profile to claim or asked to join as a new member.
/// Also backs the P2d reconnect flow (§7.6, `ReconnectChoice`) via the same
/// sheet, opened by the Account section's reconnect row instead.
library;

import 'package:chore_app/application/household_archive.dart';
import 'package:chore_app/application/household_gateway.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart'
    show HouseholdSnapshot;
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:meta/meta.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Which household identity the caller picked in the P2c chooser step
/// ("Are you Anna?" + "I'm new here" -- spec §7.4).
@immutable
sealed class JoinChoice {
  const JoinChoice();
}

/// The caller claimed an existing unclaimed profile returned by
/// `HouseholdGateway.listClaimableMembers`.
@immutable
class ClaimMemberChoice extends JoinChoice {
  /// Creates a claim choice for the unclaimed [memberId].
  const ClaimMemberChoice(this.memberId);

  /// The unclaimed member profile's id.
  final String memberId;
}

/// The caller asked to join as a brand-new member instead ("I'm new here").
@immutable
class NewMemberChoice extends JoinChoice {
  /// Creates a new-member choice with [memberId], [name], and an
  /// auto-assigned [color].
  const NewMemberChoice({
    required this.memberId,
    required this.name,
    required this.color,
  });

  /// The new member's id, generated ONCE when the choice is made (not per
  /// [HouseholdJoinService.join] call): a retry after an interrupted join
  /// re-sends the SAME id, which is what lets the server's idempotent
  /// `join_as_new_member` (migration 20260801130000) recognize the retry
  /// and return the household instead of failing on a duplicate.
  final String memberId;

  /// The new member's display name, as entered by the caller.
  final String name;

  /// The new member's auto-assigned ARGB color (spec §7.4: "auto color").
  final int color;
}

/// The caller's account is ALREADY a claimed member of [householdId] (the
/// P2d reconnect flow, spec §7.6: a returning device -- phone reset, new
/// phone -- whose signed-in account already has a profile server-side).
/// Both ids come straight from the `MyMembership` the Account section's
/// `findMyMembership` probe already resolved, so [HouseholdJoinService.join]
/// skips the claim/join-as-new RPC entirely for this choice -- no invite
/// code is needed either.
@immutable
class ReconnectChoice extends JoinChoice {
  /// Creates a reconnect choice for the already-claimed [memberId] in
  /// [householdId].
  const ReconnectChoice({required this.householdId, required this.memberId});

  /// The household this device is reconnecting to.
  final String householdId;

  /// The caller's already-claimed member profile id in [householdId].
  final String memberId;
}

/// The outcome of a successful [HouseholdJoinService.join] call.
@immutable
class HouseholdJoinResult {
  /// Creates a join result.
  const HouseholdJoinResult({
    required this.householdId,
    required this.archiveFileName,
  });

  /// The joined household's id -- the new value of
  /// `settings.syncHouseholdId`.
  final String householdId;

  /// The archive file's name (spec §4: "Your old data was saved to
  /// famdo-archive-2026-08-01.json"), for the caller's post-join snackbar.
  final String archiveFileName;
}

/// Runs the P2c join flow (and, via [ReconnectChoice], the P2d reconnect
/// flow -- spec §7.6): archives the local household, links this device's
/// account to a member profile in the joined household (claiming an
/// existing one, creating a new one, or -- for reconnect -- reusing an
/// already-claimed one with no RPC at all), downloads the joined
/// household's data, and replaces the local household with it -- optionally
/// carrying over the old household's still-open chores and unchecked
/// shopping items as fresh, history-free copies. Every step past the
/// claim/join/reconnect branch (archive-first ordering, import offer,
/// download/replace, settings-repoint, best-effort upload) is IDENTICAL and
/// shared across all three [JoinChoice] variants.
///
/// **Deliberate ordering refinement vs. the spec's own step list.** Spec
/// §7.4 lists the archive export as its step 1, implicitly AFTER the
/// chooser UI has already called `claimMember`/`joinAsNewMember` (those
/// happen during "Are you Anna?" / "I'm new here", which precede the
/// numbered steps in the flow description). This service instead performs
/// that claim/join-as-new call itself, as its OWN step 2 -- strictly AFTER
/// the archive write has already succeeded. Archive-first is strictly
/// safer: if writing the archive fails, nothing has touched the server at
/// all yet (no member claimed, no household joined), so the whole join
/// aborts with zero side effects, local or remote. Under the spec's literal
/// ordering, a purely local file-write failure would instead be discovered
/// only AFTER the caller's account was already irreversibly linked
/// server-side -- a failure the user can't act on by retrying (the archive
/// write itself doesn't depend on the claim having happened).
///
/// **Retry after a post-claim failure** (download/replace interrupted):
/// re-running the flow re-invokes `claimMember`/`joinAsNewMember` with the
/// SAME member id ([ClaimMemberChoice.memberId] is inherently stable;
/// [NewMemberChoice.memberId] is generated once when the choice is made,
/// not per call). The server's idempotent RPCs (migration
/// 20260801130000) recognize "this member is already the caller's" and
/// return the household id as success -- even if the invite expired in
/// between -- so the retry proceeds straight to download/replace instead
/// of failing.
class HouseholdJoinService {
  /// Creates the service.
  HouseholdJoinService({
    required this.gateway,
    required this.database,
    required this.settings,
    required this.clock,
    this.newId = _defaultNewId,
  });

  /// The Supabase seam this service claims/downloads/uploads through.
  final HouseholdGateway gateway;

  /// The local database this service reads the old household's data from
  /// and replaces it in, all inside one transaction (step 4).
  final AppDatabase database;

  /// The local settings repository -- repoints the acting member and
  /// records the linked state once the replace transaction commits.
  final SettingsRepository settings;

  /// Used for the archive's `exported_at` and for
  /// [SettingsRepository.setSyncLinked]'s `linkedAt` timestamp.
  final Clock clock;

  /// Generates the id for a newly created member (join-as-new) or an
  /// imported chore/occurrence/shopping-item copy.
  final String Function() newId;

  /// Runs the full join flow for [oldHouseholdId] (this device's current,
  /// about-to-be-replaced local household), redeeming [code] via [choice],
  /// and -- if [importAccepted] -- carrying over [oldHouseholdId]'s open
  /// chores and unchecked shopping items as fresh copies into the joined
  /// household.
  ///
  /// [code] is `null` for [ReconnectChoice] (spec §7.6: reconnect "skips
  /// code entry entirely" -- no invite is involved), and required for
  /// [ClaimMemberChoice]/[NewMemberChoice].
  ///
  /// Strictly in this order (see the class doc comment for why steps 1/2
  /// are swapped vs. the spec's literal list):
  /// 1. Write the automatic archive (`writeHouseholdArchive`) -- abort the
  ///    whole join, untouched, if this throws.
  /// 2. `claimMember`/`joinAsNewMember`, per [choice] -- skipped entirely
  ///    for [ReconnectChoice], which already carries the household/member
  ///    ids of an existing, already-claimed membership.
  /// 3. `downloadHousehold` of the joined household.
  /// 4. One local transaction: capture the import copies (read BEFORE any
  ///    deletion, per spec §7.4 step 2), delete [oldHouseholdId]'s rows
  ///    (FK-safe order), insert the downloaded snapshot, insert the import
  ///    copies, repoint `settings` (acting member + linked state).
  /// 5. Upload the import copies via `uploadHouseholdData` -- tolerated on
  ///    failure (see the inline comment at the call site): they simply stay
  ///    local-only until P3's sync engine picks them up.
  Future<HouseholdJoinResult> join({
    required String oldHouseholdId,
    required JoinChoice choice,
    required bool importAccepted,
    String? code,
  }) async {
    // Step 1.
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final archiveFile = await writeHouseholdArchive(
      database: database,
      clock: clock,
      directory: documentsDirectory,
    );

    // Step 2 -- deliberately after the archive; see the class doc comment.
    final String joinedHouseholdId;
    final String actingMemberId;
    switch (choice) {
      case ClaimMemberChoice(:final memberId):
        actingMemberId = memberId;
        joinedHouseholdId = await gateway.claimMember(code!, memberId);
      case NewMemberChoice(:final memberId, :final name, :final color):
        actingMemberId = memberId;
        joinedHouseholdId = await gateway.joinAsNewMember(
          code: code!,
          memberId: memberId,
          memberName: name,
          memberColor: color,
        );
      case ReconnectChoice(:final householdId, :final memberId):
        // Spec §7.6: already claimed server-side -- no RPC call at all,
        // straight into the shared download/replace machinery below with
        // the membership's own ids.
        actingMemberId = memberId;
        joinedHouseholdId = householdId;
    }

    // Step 3.
    final downloaded = await gateway.downloadHousehold(joinedHouseholdId);

    // Step 4: one local transaction.
    var importedChores = const <Chore>[];
    var importedOccurrences = const <ChoreOccurrence>[];
    var importedShoppingItems = const <ShoppingItem>[];
    await database.transaction(() async {
      if (importAccepted) {
        final copies = await _captureImportCopies(
          oldHouseholdId: oldHouseholdId,
          joinedHouseholdId: joinedHouseholdId,
        );
        importedChores = copies.chores;
        importedOccurrences = copies.occurrences;
        importedShoppingItems = copies.shoppingItems;
      }

      await _deleteHousehold(oldHouseholdId);
      await _insertSnapshot(downloaded);
      for (final chore in importedChores) {
        await database.into(database.chores).insert(chore);
      }
      for (final occurrence in importedOccurrences) {
        await database.into(database.choreOccurrences).insert(occurrence);
      }
      for (final item in importedShoppingItems) {
        await database.into(database.shoppingItems).insert(item);
      }

      await settings.setActingMember(actingMemberId);
      await settings.setSyncLinked(
        householdId: joinedHouseholdId,
        linkedAt: clock.now(),
      );
    });

    // Step 5: best-effort push of just the import copies. Tolerated on
    // failure -- unlike every other step here, this one deliberately does
    // NOT abort or surface an error: the copies already exist locally
    // (committed by the transaction above), and P3's sync engine (dirty
    // flag + push) will pick them up once it lands. Surfacing a failure
    // here to the user would be reporting a problem they can't do anything
    // about yet.
    if (importedChores.isNotEmpty || importedShoppingItems.isNotEmpty) {
      try {
        await gateway.uploadHouseholdData(
          HouseholdSnapshot(
            chores: importedChores,
            choreOccurrences: importedOccurrences,
            shoppingItems: importedShoppingItems,
          ),
        );
      } on Exception {
        // Tolerated -- see the comment above.
      }
    }

    return HouseholdJoinResult(
      householdId: joinedHouseholdId,
      archiveFileName: archiveFile.uri.pathSegments.last,
    );
  }

  /// Deletes every row of [householdId] from the local database, in the
  /// same FK-safe order as `resetAppData`
  /// (`lib/application/data_reset.dart`) -- scoped to one household rather
  /// than every table, and never touching `settings` (device-scoped, not
  /// household-scoped; step 4's caller repoints it instead of wiping it).
  ///
  /// `chore_assignees`/`chore_occurrences` carry no `household_id` column
  /// locally (only the server denormalizes it, per spec §2) so they're
  /// scoped via their chore's id instead.
  Future<void> _deleteHousehold(String householdId) async {
    final choreRows = await (database.select(
      database.chores,
    )..where((tbl) => tbl.householdId.equals(householdId))).get();
    final choreIds = choreRows.map((chore) => chore.id).toSet();

    if (choreIds.isNotEmpty) {
      await (database.delete(
        database.choreOccurrences,
      )..where((tbl) => tbl.choreId.isIn(choreIds))).go();
      await (database.delete(
        database.choreAssignees,
      )..where((tbl) => tbl.choreId.isIn(choreIds))).go();
    }
    await (database.delete(
      database.chores,
    )..where((tbl) => tbl.householdId.equals(householdId))).go();
    await (database.delete(
      database.shoppingItems,
    )..where((tbl) => tbl.householdId.equals(householdId))).go();
    await (database.delete(
      database.categories,
    )..where((tbl) => tbl.householdId.equals(householdId))).go();
    await (database.delete(
      database.members,
    )..where((tbl) => tbl.householdId.equals(householdId))).go();
    await (database.delete(
      database.households,
    )..where((tbl) => tbl.id.equals(householdId))).go();
  }

  /// Inserts every row of [snapshot] verbatim, in FK-parent-first order.
  /// Every row is brand new to this device (the old household was just
  /// deleted, and a device only ever downloads a household it has never
  /// held locally before), so a plain insert -- never an upsert -- is
  /// correct here.
  Future<void> _insertSnapshot(HouseholdSnapshot snapshot) async {
    final household = snapshot.household;
    if (household != null) {
      await database.into(database.households).insert(household);
    }
    for (final member in snapshot.members) {
      await database.into(database.members).insert(member);
    }
    for (final category in snapshot.categories) {
      await database.into(database.categories).insert(category);
    }
    for (final chore in snapshot.chores) {
      await database.into(database.chores).insert(chore);
    }
    for (final assignee in snapshot.choreAssignees) {
      await database.into(database.choreAssignees).insert(assignee);
    }
    for (final occurrence in snapshot.choreOccurrences) {
      await database.into(database.choreOccurrences).insert(occurrence);
    }
    for (final item in snapshot.shoppingItems) {
      await database.into(database.shoppingItems).insert(item);
    }
  }

  /// Reads [oldHouseholdId]'s still-open chores (active, with a current
  /// pending occurrence) and unchecked shopping items, and builds fresh
  /// copies of them for [joinedHouseholdId] -- new ids throughout, no
  /// history (spec §7.4 step 2: "new UUIDs, no history").
  ///
  /// A chore counts as "open" if it's active (`deletedAt == null`) AND has
  /// a current pending occurrence -- a paused chore never does (pausing
  /// deletes it, see `ChoreService.pauseChore`), and a one-off chore whose
  /// only occurrence is already closed doesn't either, so both are
  /// naturally excluded without a special case. The copy also carries over
  /// that pending occurrence's due date (as a fresh, unassigned pending
  /// occurrence of the new chore) so the imported chore is still
  /// immediately actionable, not a silent no-op row.
  ///
  /// Deliberate simplification: every copy's `assignmentMode` becomes
  /// [AssignmentMode.anyone] with no assignees, regardless of the
  /// original -- none of the old household's members exist in the joined
  /// household, so there is no valid assignee to carry over for `fixed`/
  /// `rotation` chores. `categoryId`/`addedBy`/`createdBy` are all cleared
  /// to `null` for the same reason (spec §7.4 step 3: "the old categories
  /// don't exist in the new household").
  Future<_ImportCopies> _captureImportCopies({
    required String oldHouseholdId,
    required String joinedHouseholdId,
  }) async {
    final now = clock.now().toUtc().toIso8601String();
    final chores = ChoreRepository(database);

    final activeChores = await chores.getActiveChores(oldHouseholdId);
    final choreCopies = <Chore>[];
    final occurrenceCopies = <ChoreOccurrence>[];
    for (final details in activeChores) {
      final chore = details.chore;
      final pending = await chores.pendingOccurrenceOf(chore.id);
      if (pending == null) {
        continue;
      }
      final newChoreId = newId();
      choreCopies.add(
        chore.copyWith(
          id: newChoreId,
          householdId: joinedHouseholdId,
          categoryId: const Value(null),
          assignmentMode: AssignmentMode.anyone,
          pausedAt: const Value(null),
          createdBy: const Value(null),
          createdAt: now,
          updatedAt: now,
          deletedAt: const Value(null),
          // Brand-new local rows the joined household doesn't have yet
          // (spec `docs/specs/sync-backend.md` §8.1: every insert/update of
          // a synced row marks it dirty) -- step 5 below best-effort
          // pushes them immediately, but this is what lets P3's ongoing
          // sync engine pick them up later if that push fails or is
          // interrupted.
          syncDirty: true,
        ),
      );
      occurrenceCopies.add(
        pending.copyWith(
          id: newId(),
          choreId: newChoreId,
          status: OccurrenceStatus.pending,
          assignedMemberId: const Value(null),
          completedBy: const Value(null),
          closedOn: const Value(null),
          createdAt: now,
          updatedAt: now,
          syncDirty: true,
        ),
      );
    }

    final uncheckedItems =
        await (database.select(database.shoppingItems)..where(
              (tbl) =>
                  tbl.householdId.equals(oldHouseholdId) &
                  tbl.deletedAt.isNull() &
                  tbl.checkedAt.isNull(),
            ))
            .get();
    final itemCopies = [
      for (final item in uncheckedItems)
        item.copyWith(
          id: newId(),
          householdId: joinedHouseholdId,
          categoryId: const Value(null),
          addedBy: const Value(null),
          checkedAt: const Value(null),
          createdAt: now,
          updatedAt: now,
          deletedAt: const Value(null),
          syncDirty: true,
        ),
    ];

    return _ImportCopies(
      chores: choreCopies,
      occurrences: occurrenceCopies,
      shoppingItems: itemCopies,
    );
  }
}

/// The captured, ready-to-insert import copies built by
/// [HouseholdJoinService._captureImportCopies].
class _ImportCopies {
  const _ImportCopies({
    required this.chores,
    required this.occurrences,
    required this.shoppingItems,
  });

  final List<Chore> chores;
  final List<ChoreOccurrence> occurrences;
  final List<ShoppingItem> shoppingItems;
}

String _defaultNewId() => const Uuid().v4();
