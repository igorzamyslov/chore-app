/// The automatic archive step of the P2c join flow (spec
/// `docs/specs/sync-backend.md` §7.4 step 1, §4 option 2): a full JSON
/// export of the local household -- reusing the G8 exporter
/// (`lib/application/data_export.dart`) -- written to disk (not shared via
/// the OS share sheet) so the old household's data survives being replaced
/// by the joined one.
library;

import 'dart:convert';
import 'dart:io';

import 'package:chore_app/application/data_export.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';

/// The archive file's name: `famdo-archive-<yyyy-mm-dd>.json`, dated from
/// [clock] (never `DateTime.now()`) so it's deterministic under a fixed
/// test/E2E clock -- mirrors `exportFileName`'s naming (same date format,
/// `archive` in place of `export`: this file is machine-written to the app
/// documents directory, not shared).
String archiveFileName(Clock clock) {
  final today = PlainDate.fromDateTime(clock.now());
  return 'famdo-archive-${today.toIso8601()}.json';
}

/// Seam for actually writing the archive's bytes to disk -- a plain static
/// swap (`ArchiveFileWriter.instance`), exactly like how `path_provider`'s
/// `PathProviderPlatform.instance` works, NOT a Riverpod provider.
///
/// This exists because of a `flutter_test` limitation specific to this
/// operation: a real `dart:io` file write, when it's triggered from inside
/// a widget's own (necessarily fire-and-forget -- `onPressed`/`onTap` are
/// plain `void Function()`s) callback in response to a simulated
/// `WidgetTester.tap`, never reliably completes under `testWidgets`'s
/// automated fake-clock pumping, REGARDLESS of `tester.runAsync` bracketing
/// at the call site -- confirmed empirically; there is no supported pattern
/// that makes it resolve. Widget tests
/// (`test/features/settings/join_household_sheet_test.dart`) therefore
/// install `FakeArchiveFileWriter`
/// (`test/features/settings/fake_archive_file_writer.dart`), which performs
/// no real I/O at all -- while the two PLAIN (non-widget) tests,
/// `test/application/household_archive_test.dart` and
/// `test/application/household_join_service_test.dart`, exercise the real
/// [RealArchiveFileWriter] path directly (a plain `test()` body runs on the
/// real event loop from the start, so real I/O there is unproblematic) and
/// are what actually proves the production write works.
abstract class ArchiveFileWriter {
  /// Allows subclasses to be `const`.
  const ArchiveFileWriter();

  /// The active writer. Defaults to [RealArchiveFileWriter]; widget tests
  /// swap this for a fake (see the class doc comment).
  static ArchiveFileWriter instance = const RealArchiveFileWriter();

  /// Writes [contents] to [path], creating/overwriting the file.
  Future<void> write(String path, String contents);
}

/// The production [ArchiveFileWriter]: a real `dart:io` file write.
class RealArchiveFileWriter extends ArchiveFileWriter {
  /// Creates the real writer.
  const RealArchiveFileWriter();

  @override
  Future<void> write(String path, String contents) {
    return File(path).writeAsString(contents);
  }
}

/// Builds the full backup document via [buildExportDocument] and writes it,
/// UTF-8 JSON encoded, to [archiveFileName] inside [directory] -- via
/// [ArchiveFileWriter.instance] -- returning a [File] referencing that path.
///
/// Any failure (building the document, or the write itself) propagates to
/// the caller unchanged: `HouseholdJoinService.join`
/// (`lib/application/household_join_service.dart`) aborts the whole join if
/// this throws (spec §7.4 step 1: "abort the whole join if this write
/// fails"), leaving the old household completely untouched.
Future<File> writeHouseholdArchive({
  required AppDatabase database,
  required Clock clock,
  required Directory directory,
}) async {
  final document = await buildExportDocument(database: database, clock: clock);
  final path = '${directory.path}/${archiveFileName(clock)}';
  await ArchiveFileWriter.instance.write(path, jsonEncode(document));
  return File(path);
}
