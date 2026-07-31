/// The application's local drift/SQLite database.
library;

import 'package:chore_app/data/db/converters.dart';
import 'package:chore_app/data/db/tables.dart';
// The generated `app_database.g.dart` part file below references
// `PlainDateConverter`/`RecurrenceConverter` and the `PlainDate`/`Recurrence`
// types they convert directly, so this library needs them in scope even
// though this hand-written file doesn't name them itself.
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

export 'package:chore_app/data/db/tables.dart';

part 'app_database.g.dart';

/// The application's local SQLite database.
///
/// This class takes a plain [QueryExecutor] via its constructor so tests can
/// construct it directly with an in-memory executor:
///
/// ```dart
/// AppDatabase(NativeDatabase.memory());
/// ```
///
/// The real app should instead use [openConnection], which opens a
/// persistent, platform-appropriate database file via drift_flutter:
///
/// ```dart
/// AppDatabase(openConnection());
/// ```
@DriftDatabase(
  tables: [
    Households,
    Members,
    Categories,
    Chores,
    ChoreAssignees,
    ChoreOccurrences,
    ShoppingItems,
    Settings,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Creates a database that sends its queries to [executor].
  //
  // A super parameter isn't used here because the generated superclass
  // names its positional parameter `e`, which would trip
  // `matching_super_parameters`.
  // ignore: use_super_parameters
  AppDatabase(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      // v1 -> v2 (spec `docs/specs/notifications.md`): adds the `settings`
      // table. [migrator.createTable] always builds the table from its
      // *current* (here, v3) column set, so a fresh v1 -> v3 jump already
      // gets `actingMemberId` for free — the `else if` below only needs to
      // backfill that column for an install that already has the v2-shaped
      // `settings` table (a "create then immediately re-add the same
      // column" pair would otherwise throw a duplicate-column error).
      if (from < 2) {
        await migrator.createTable(settings);
      } else if (from < 3) {
        // v2 -> v3 (spec `docs/specs/members-management.md`): adds the
        // nullable `settings.actingMemberId` column, defaulting to `NULL`
        // (the automatic acting-member fallback).
        await migrator.addColumn(settings, settings.actingMemberId);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

/// Opens the on-device, platform-appropriate database file.
///
/// Kept separate from [AppDatabase]'s constructor (which only depends on
/// plain drift and takes a [QueryExecutor]) so tests can construct
/// `AppDatabase(NativeDatabase.memory())` without pulling in Flutter.
QueryExecutor openConnection() => driftDatabase(name: 'chore_app');
