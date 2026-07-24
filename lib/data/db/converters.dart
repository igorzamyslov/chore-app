/// Drift [TypeConverter]s wrapping the domain's plain-old-Dart value types
/// so they can be stored in and read back from `TEXT` columns.
library;

import 'dart:convert';

import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:drift/drift.dart';

/// Converts a [PlainDate] to and from its `yyyy-mm-dd` ISO-8601 text form.
///
/// Used for every non-nullable `PlainDate` column (e.g. `Chores.startDate`,
/// `ChoreOccurrences.dueDate`). Nullable `PlainDate` columns (e.g.
/// `ChoreOccurrences.closedOn`) wrap this converter with
/// `NullAwareTypeConverter.wrap`.
class PlainDateConverter extends TypeConverter<PlainDate, String> {
  /// Creates the converter.
  const PlainDateConverter();

  @override
  PlainDate fromSql(String fromDb) => PlainDate.parse(fromDb);

  @override
  String toSql(PlainDate value) => value.toIso8601();
}

/// Converts a [Recurrence] to and from its JSON text representation.
///
/// The only column using this is `Chores.recurrence`, which is nullable
/// (`NULL` means a one-off chore); it is registered via
/// `NullAwareTypeConverter.wrap(const RecurrenceConverter())`.
///
/// Invalid persisted JSON (malformed text, or a well-formed JSON value that
/// doesn't decode to a valid [Recurrence]) surfaces as a thrown
/// [FormatException] when the column is read, since neither [jsonDecode] nor
/// [Recurrence.fromJson] swallow errors.
class RecurrenceConverter extends TypeConverter<Recurrence, String> {
  /// Creates the converter.
  const RecurrenceConverter();

  @override
  Recurrence fromSql(String fromDb) =>
      Recurrence.fromJson(jsonDecode(fromDb) as Map<String, Object?>);

  @override
  String toSql(Recurrence value) => jsonEncode(value.toJson());
}
