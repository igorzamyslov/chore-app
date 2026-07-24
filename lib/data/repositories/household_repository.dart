/// Bootstraps and manages the single local household and its members.
library;

import 'package:chore_app/data/db/app_database.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// Repository for the household bootstrap and its member roster.
///
/// v1 note: a household is created lazily on first access via
/// [ensureLocalHousehold] and there is exactly one per device until a sync
/// layer lands.
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

  /// The ARGB color assigned to the bootstrap 'Me' member.
  static const int bootstrapMemberColor = 0xFF26A69A;

  /// The database this repository reads from and writes to.
  final AppDatabase db;

  /// Generates the id for a newly inserted row.
  final String Function() newId;

  /// Returns the current UTC time, used for `created_at` / `updated_at`.
  final DateTime Function() nowUtc;

  /// Returns the single existing household, creating one (named `'My
  /// household'`, with one admin member named `'Me'`) if none exists yet.
  ///
  /// Idempotent: calling this repeatedly never creates more than one
  /// household. This is the v1 bootstrap entry point.
  Future<Household> ensureLocalHousehold() async {
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
      );
      await db
          .into(db.households)
          .insert(
            HouseholdsCompanion.insert(
              id: household.id,
              name: household.name,
              createdAt: household.createdAt,
              updatedAt: household.updatedAt,
            ),
          );
      await db
          .into(db.members)
          .insert(
            MembersCompanion.insert(
              id: newId(),
              householdId: household.id,
              name: 'Me',
              color: bootstrapMemberColor,
              role: MemberRole.admin,
              createdAt: now,
              updatedAt: now,
            ),
          );
      return household;
    });
  }

  /// Watches every member of [householdId], ordered by name.
  Stream<List<Member>> watchMembers(String householdId) {
    final query = db.select(db.members)
      ..where((tbl) => tbl.householdId.equals(householdId))
      ..orderBy([(tbl) => OrderingTerm(expression: tbl.name)]);
    return query.watch();
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
    );
  }

  /// Renames an existing member.
  Future<void> renameMember(String memberId, String name) async {
    await (db.update(
      db.members,
    )..where((tbl) => tbl.id.equals(memberId))).write(
      MembersCompanion(name: Value(name), updatedAt: Value(_isoNow())),
    );
  }

  String _isoNow() => nowUtc().toIso8601String();
}

String _defaultNewId() => const Uuid().v4();

DateTime _defaultNowUtc() => DateTime.now().toUtc();
