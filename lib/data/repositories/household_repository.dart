/// Bootstraps and manages the single local household and its members.
library;

import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/db/sync_dirty.dart';
import 'package:chore_app/data/repositories/category_repository.dart'
    show CategoryRepository;
import 'package:drift/drift.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

/// A full typed snapshot of one household's data (spec
/// `docs/specs/sync-backend.md` §7.2), read directly via the typed drift row
/// classes -- see `HouseholdRepository.loadSnapshot`, which builds one, and
/// `HouseholdGateway` (`lib/application/household_gateway.dart`), whose
/// `uploadHouseholdData`/`downloadHousehold` pass one across the Supabase
/// seam.
///
/// Deliberately NOT built from `buildExportDocument`
/// (`lib/application/data_export.dart`): that reads raw SQL rows (so
/// converter-mapped columns like `chores.recurrence` come back as their
/// stored JSON text, not a decoded `Recurrence`), which is right for a
/// verbatim JSON backup but wrong here -- the Supabase gateway needs typed
/// values to re-encode per-column for each request.
@immutable
class HouseholdSnapshot {
  /// Creates a snapshot. Every list defaults to empty, and [household] to
  /// `null`, so a caller can build a partial snapshot (e.g.
  /// `HouseholdGateway.uploadHouseholdData`'s payload never includes
  /// [household] -- the household row itself is created by the
  /// `create_household` RPC, not uploaded).
  const HouseholdSnapshot({
    this.household,
    this.members = const [],
    this.categories = const [],
    this.chores = const [],
    this.choreAssignees = const [],
    this.choreOccurrences = const [],
    this.shoppingItems = const [],
  });

  /// The household's own row, or `null` when this snapshot doesn't carry
  /// one (every upload payload; a failed/empty
  /// `HouseholdGateway.downloadHousehold`).
  final Household? household;

  /// Every member row, in FK-parent-first upload order (spec §7.2: right
  /// after the household itself).
  final List<Member> members;

  /// Every category row.
  final List<Category> categories;

  /// Every chore row.
  final List<Chore> chores;

  /// Every chore-assignee row.
  final List<ChoreAssignee> choreAssignees;

  /// Every chore-occurrence row.
  final List<ChoreOccurrence> choreOccurrences;

  /// Every shopping-item row.
  final List<ShoppingItem> shoppingItems;
}

/// Repository for the household bootstrap and its member roster.
///
/// Spec `docs/specs/onboarding-v2.md` §0/§2: a household is never created
/// silently -- it exists only once the user explicitly chooses "start
/// fresh" ([createLocalHousehold], called from the welcome screen's create
/// card) or "join" (`HouseholdJoinService.joinFresh`). There is exactly one
/// household per device until a sync layer lands.
class HouseholdRepository {
  /// Creates a repository backed by [db].
  ///
  /// [newId] and [nowUtc] are injectable so tests can supply deterministic
  /// ids and a controllable clock; they default to a random UUIDv4
  /// generator and the real UTC clock, respectively.
  HouseholdRepository(
    this.db, {
    this.newId = _defaultNewId,
    this.nowUtc = _defaultNowUtc,
  });

  /// The database this repository reads from and writes to.
  final AppDatabase db;

  /// Generates the id for a newly inserted row.
  final String Function() newId;

  /// Returns the current UTC time, used for `created_at` / `updated_at`.
  final DateTime Function() nowUtc;

  /// Returns the single existing household, or `null` if none exists yet
  /// (spec `docs/specs/onboarding-v2.md` §2: a plain read, alongside
  /// [createLocalHousehold], replacing the old lazy-creating
  /// `ensureLocalHousehold`). `bootstrapProvider` (`lib/app/providers.dart`)
  /// calls this ASSUMING a non-null result -- it's only reachable once
  /// [watchHouseholdOrNull] (the welcome gate) has already confirmed one
  /// exists.
  Future<Household?> getHousehold() {
    return db.select(db.households).getSingleOrNull();
  }

  /// Watches whether ANY household row exists locally (spec
  /// `docs/specs/onboarding-v2.md` §2): `householdGateProvider`
  /// (`lib/app/providers.dart`) shows `WelcomeScreen` while this emits
  /// `null` (nothing local yet) and the tab shell once it emits a
  /// household. An existing install's very first emission is already
  /// non-null, so the gate never appears for it.
  Stream<Household?> watchHouseholdOrNull() {
    return db.select(db.households).watchSingleOrNull();
  }

  /// Creates the household (named `'My household'`) with ONE admin member
  /// named [name] (first seed color) -- the welcome screen's explicit
  /// "Set up a new household" action (spec `docs/specs/onboarding-v2.md`
  /// §1/§2). Replaces the old lazy-creating `ensureLocalHousehold`: a fresh
  /// install now has NO household until the user chooses this (or joins).
  ///
  /// Idempotent, keeping the same race guard `ensureLocalHousehold` had: if
  /// a household already exists (e.g. a second, redundant call racing the
  /// first) the existing row is returned untouched -- [name] is only used
  /// the FIRST time this actually creates something.
  Future<Household> createLocalHousehold(String name) async {
    final existing = await db.select(db.households).getSingleOrNull();
    if (existing != null) {
      return existing;
    }
    return db.transaction(() async {
      final raceWinner = await db.select(db.households).getSingleOrNull();
      if (raceWinner != null) {
        return raceWinner;
      }
      final now = _isoNow();
      final household = Household(
        id: newId(),
        name: 'My household',
        createdAt: now,
        updatedAt: now,
        syncDirty: true,
      );
      await db
          .into(db.households)
          .insert(
            HouseholdsCompanion.insert(
              id: household.id,
              name: household.name,
              createdAt: household.createdAt,
              updatedAt: household.updatedAt,
              syncDirty: syncDirtyOnWrite,
            ),
          );
      await db
          .into(db.members)
          .insert(
            MembersCompanion.insert(
              id: newId(),
              householdId: household.id,
              name: name,
              color: CategoryRepository.seedColors.first,
              role: MemberRole.admin,
              createdAt: now,
              updatedAt: now,
              syncDirty: syncDirtyOnWrite,
            ),
          );
      return household;
    });
  }

  /// Watches every ACTIVE (non-soft-deleted) member of [householdId],
  /// ordered by creation time (spec `docs/specs/members-management.md` §2:
  /// stable, and consistent with the chore-form assignee chips, the
  /// members screen, and the acting-member switcher — all of which read
  /// this same order).
  ///
  /// This is the roster query (spec `docs/feedback/2026-08-01-ux-audit.md`
  /// A1): every provider built on it (`membersProvider`,
  /// `lib/app/providers.dart`) is a "who can I pick/act as/manage" listing,
  /// so a soft-deleted member must disappear from it. History-display
  /// joins (done-today "by {name}", occurrence assignee avatars,
  /// `completedBy`) live in `ChoreRepository` instead and deliberately do
  /// NOT filter on `deletedAt` — see that class's `watchPendingOccurrences`
  /// / `watchClosedOnDate`.
  Stream<List<Member>> watchMembers(String householdId) {
    final query = db.select(db.members)
      ..where(
        (tbl) => tbl.householdId.equals(householdId) & tbl.deletedAt.isNull(),
      )
      ..orderBy([(tbl) => OrderingTerm(expression: tbl.createdAt)]);
    return query.watch();
  }

  /// Watches [householdId]'s own row -- currently only used for its `name`
  /// (see `currentHouseholdProvider`, `lib/app/providers.dart`, backing the
  /// Account section's 'linked' subtitle, spec
  /// `docs/specs/sync-backend.md` §7.3 last paragraph).
  Stream<Household> watchHousehold(String householdId) {
    final query = db.select(db.households)
      ..where((tbl) => tbl.id.equals(householdId));
    return query.watchSingle();
  }

  /// Loads a full typed [HouseholdSnapshot] of [householdId]'s data (spec
  /// `docs/specs/sync-backend.md` §7.2), for `HouseholdLinkService.adopt`
  /// (`lib/application/household_link_service.dart`) to hand to
  /// `HouseholdGateway.uploadHouseholdData`.
  ///
  /// Includes every row regardless of `deletedAt` -- soft-deleted rows
  /// (tombstones) upload too, per spec §7.2 "tombstones included".
  Future<HouseholdSnapshot> loadSnapshot(String householdId) async {
    final household = await (db.select(
      db.households,
    )..where((tbl) => tbl.id.equals(householdId))).getSingleOrNull();
    final members = await (db.select(
      db.members,
    )..where((tbl) => tbl.householdId.equals(householdId))).get();
    final categories = await (db.select(
      db.categories,
    )..where((tbl) => tbl.householdId.equals(householdId))).get();
    final chores = await (db.select(
      db.chores,
    )..where((tbl) => tbl.householdId.equals(householdId))).get();
    final choreIds = chores.map((chore) => chore.id).toSet();
    final choreAssignees = choreIds.isEmpty
        ? <ChoreAssignee>[]
        : await (db.select(
            db.choreAssignees,
          )..where((tbl) => tbl.choreId.isIn(choreIds))).get();
    final choreOccurrences = choreIds.isEmpty
        ? <ChoreOccurrence>[]
        : await (db.select(
            db.choreOccurrences,
          )..where((tbl) => tbl.choreId.isIn(choreIds))).get();
    final shoppingItems = await (db.select(
      db.shoppingItems,
    )..where((tbl) => tbl.householdId.equals(householdId))).get();
    return HouseholdSnapshot(
      household: household,
      members: members,
      categories: categories,
      chores: chores,
      choreAssignees: choreAssignees,
      choreOccurrences: choreOccurrences,
      shoppingItems: shoppingItems,
    );
  }

  /// Renames [householdId] (spec `docs/feedback/2026-08-01-ux-audit.md`
  /// A2): the household name row at the top of the Members screen. Marks
  /// `syncDirty` per the shared write-time helper -- the server `UPDATE` on
  /// `households` is already granted (spec `docs/specs/sync-backend.md`
  /// §2), so a linked device's rename propagates on the next push.
  Future<void> renameHousehold(String householdId, String name) async {
    await (db.update(
      db.households,
    )..where((tbl) => tbl.id.equals(householdId))).write(
      HouseholdsCompanion(
        name: Value(name),
        updatedAt: Value(_isoNow()),
        syncDirty: syncDirtyOnWrite,
      ),
    );
  }

  /// Sets [memberId]'s role (spec `docs/specs/sync-backend.md` §7.3 step 3:
  /// the acting member becomes admin locally right after adopting,
  /// mirroring `create_household`'s server-side rule).
  Future<void> setMemberRole(String memberId, MemberRole role) async {
    await (db.update(
      db.members,
    )..where((tbl) => tbl.id.equals(memberId))).write(
      MembersCompanion(
        role: Value(role),
        updatedAt: Value(_isoNow()),
        syncDirty: syncDirtyOnWrite,
      ),
    );
  }

  /// Records locally that [memberId] is claimed by auth user [userId].
  ///
  /// Mirrors the claim the server made in `create_household` /
  /// `claim_member` (spec `docs/specs/household-lifecycle.md` §3.1 G-B).
  /// Deliberately does NOT mark the row `syncDirty`: `user_id` is
  /// server-owned and is not in the client's column-scoped UPDATE grant,
  /// so pushing it would be rejected.
  Future<void> setMemberUserId(String memberId, String userId) async {
    await (db.update(db.members)..where((tbl) => tbl.id.equals(memberId)))
        .write(MembersCompanion(userId: Value(userId)));
  }

  /// Adds a new member to [householdId].
  Future<Member> addMember(
    String householdId, {
    required String name,
    required int color,
    MemberRole role = MemberRole.member,
  }) async {
    final now = _isoNow();
    final id = newId();
    await db
        .into(db.members)
        .insert(
          MembersCompanion.insert(
            id: id,
            householdId: householdId,
            name: name,
            color: color,
            role: role,
            createdAt: now,
            updatedAt: now,
            syncDirty: syncDirtyOnWrite,
          ),
        );
    return Member(
      id: id,
      householdId: householdId,
      name: name,
      color: color,
      role: role,
      createdAt: now,
      updatedAt: now,
      syncDirty: true,
    );
  }

  /// Renames an existing member.
  Future<void> renameMember(String memberId, String name) async {
    await (db.update(
      db.members,
    )..where((tbl) => tbl.id.equals(memberId))).write(
      MembersCompanion(
        name: Value(name),
        updatedAt: Value(_isoNow()),
        syncDirty: syncDirtyOnWrite,
      ),
    );
  }

  /// Changes an existing member's color (spec
  /// `docs/specs/members-management.md` §3: the member edit sheet's color
  /// swatch picker).
  Future<void> recolorMember(String memberId, int color) async {
    await (db.update(
      db.members,
    )..where((tbl) => tbl.id.equals(memberId))).write(
      MembersCompanion(
        color: Value(color),
        updatedAt: Value(_isoNow()),
        syncDirty: syncDirtyOnWrite,
      ),
    );
  }

  String _isoNow() => nowUtc().toIso8601String();
}

String _defaultNewId() => const Uuid().v4();

DateTime _defaultNowUtc() => DateTime.now().toUtc();
