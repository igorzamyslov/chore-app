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
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// The archive file's name: `famdo-archive-<yyyy-MM-dd-HHmmss>.json`, stamped
/// from [clock] (never `DateTime.now()`) so it's deterministic under a fixed
/// test/E2E clock. The time component (persona review B3) keeps two joins on
/// the same day from silently overwriting each other's saved copy -- the
/// older file is the only record of that earlier household.
String archiveFileName(Clock clock) {
  final now = clock.now();
  final date = PlainDate.fromDateTime(now).toIso8601();
  String two(int value) => value.toString().padLeft(2, '0');
  return 'famdo-archive-$date-${two(now.hour)}${two(now.minute)}'
      '${two(now.second)}.json';
}

final RegExp _archiveName = RegExp(r'^famdo-archive-.+\.json$');
final RegExp _archiveStamp = RegExp(
  r'^famdo-archive-(\d{4})-(\d{2})-(\d{2})(?:-(\d{2})(\d{2})(\d{2}))?\.json$',
);

/// One saved copy of an earlier household, as listed under Settings -> Data
/// (persona review B3).
@immutable
class HouseholdArchive {
  /// Creates an entry for the file at [path].
  const HouseholdArchive({required this.path, required this.fileName});

  /// The file's absolute path.
  final String path;

  /// The file's name, `famdo-archive-<stamp>.json`.
  final String fileName;

  /// When the copy was made, read back from [fileName] (device-local time),
  /// or `null` for a name that does not follow the stamp format.
  DateTime? get savedAt {
    final match = _archiveStamp.firstMatch(fileName);
    if (match == null) {
      return null;
    }
    int part(int group) => int.parse(match.group(group) ?? '0');
    return DateTime(part(1), part(2), part(3), part(4), part(5), part(6));
  }
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

  /// The directory archives live in (the app documents directory).
  Future<String> directoryPath();

  /// The absolute paths of every archive file in [directoryPath], in no
  /// particular order. Empty when the directory does not exist.
  Future<List<String>> list();

  /// Deletes the file at [path]; a file that is already gone is not an
  /// error.
  Future<void> delete(String path);
}

/// The production [ArchiveFileWriter]: a real `dart:io` file write.
class RealArchiveFileWriter extends ArchiveFileWriter {
  /// Creates the real writer.
  const RealArchiveFileWriter();

  @override
  Future<void> write(String path, String contents) {
    return File(path).writeAsString(contents);
  }

  @override
  Future<String> directoryPath() async =>
      (await getApplicationDocumentsDirectory()).path;

  @override
  Future<List<String>> list() async {
    final directory = Directory(await directoryPath());
    if (!directory.existsSync()) {
      return const [];
    }
    return [
      await for (final entity in directory.list())
        if (entity is File && _archiveName.hasMatch(_baseName(entity.path)))
          entity.path,
    ];
  }

  @override
  Future<void> delete(String path) async {
    final file = File(path);
    if (file.existsSync()) {
      await file.delete();
    }
  }
}

String _baseName(String path) => path.substring(path.lastIndexOf('/') + 1);

/// Every saved copy, newest first (names carry their timestamp, so a
/// descending name sort is newest-first).
Future<List<HouseholdArchive>> listHouseholdArchives() async {
  final paths = await ArchiveFileWriter.instance.list();
  final entries = [
    for (final path in paths)
      HouseholdArchive(path: path, fileName: _baseName(path)),
  ]..sort((a, b) => b.fileName.compareTo(a.fileName));
  return entries;
}

/// Deletes one saved copy.
Future<void> deleteHouseholdArchive(HouseholdArchive archive) =>
    ArchiveFileWriter.instance.delete(archive.path);

/// Deletes every saved copy (`resetAppData`: a reset promises a clean
/// device).
Future<void> deleteAllHouseholdArchives() async {
  final writer = ArchiveFileWriter.instance;
  for (final path in await writer.list()) {
    await writer.delete(path);
  }
}

/// The absolute path of the saved copy named [fileName] -- what the
/// post-join snackbar's "Share..." action hands to the share sheet.
Future<String> householdArchivePath(String fileName) async =>
    '${await ArchiveFileWriter.instance.directoryPath()}/$fileName';

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
