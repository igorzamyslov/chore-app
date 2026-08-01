/// A fake `path_provider` platform for the P2c join-flow widget tests
/// (spec `docs/specs/sync-backend.md` §7.4): points
/// `getApplicationDocumentsDirectory()` at a real temp directory instead of
/// invoking a real platform channel, so `HouseholdJoinService.join`'s
/// archive-write step (`lib/application/household_archive.dart`) can be
/// exercised end to end without touching the actual app documents
/// directory.
library;

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// A [PathProviderPlatform] that always answers [path] for
/// `getApplicationDocumentsPath()`.
///
/// Unlike `share_plus`'s `SharePlus.instance` (see `FakeSharePlatform`'s
/// doc comment), `package:path_provider`'s top-level functions re-read
/// `PathProviderPlatform.instance` on every call, so re-pointing it mid-suite
/// (a fresh instance per test, each with its own temp directory) is safe.
class FakePathProviderPlatform extends PathProviderPlatform {
  /// Creates a fake that always resolves the documents directory to [path].
  FakePathProviderPlatform(this.path);

  /// The directory path `getApplicationDocumentsDirectory()` resolves to.
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}
