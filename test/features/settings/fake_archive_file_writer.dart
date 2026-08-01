/// A recording fake of `ArchiveFileWriter` for the P2c join-flow widget
/// tests (spec `docs/specs/sync-backend.md` §7.4) -- no real `dart:io` file
/// write ever happens; see that class's doc comment
/// (`lib/application/household_archive.dart`) for why widget tests can't
/// exercise the real one.
library;

import 'package:chore_app/application/household_archive.dart';

/// A fake [ArchiveFileWriter] that records every write in [writtenFiles]
/// (path -> contents) instead of touching the real filesystem.
///
/// Install via `ArchiveFileWriter.instance = FakeArchiveFileWriter()` in a
/// test's `setUp` (mirroring `FakePathProviderPlatform`'s installation),
/// and assert against [writtenFiles] instead of `File.existsSync()`.
class FakeArchiveFileWriter extends ArchiveFileWriter {
  /// Creates a fake writer.
  FakeArchiveFileWriter();

  /// Every write, keyed by the full path it was written to.
  final Map<String, String> writtenFiles = {};

  /// Set to make the next [write] call throw this instead of succeeding --
  /// simulates the archive write failing (spec §7.4 step 1's "abort the
  /// whole join if this write fails").
  Exception? errorToThrow;

  @override
  Future<void> write(String path, String contents) async {
    final error = errorToThrow;
    if (error != null) {
      throw error;
    }
    writtenFiles[path] = contents;
  }
}
