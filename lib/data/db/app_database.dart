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
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
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
