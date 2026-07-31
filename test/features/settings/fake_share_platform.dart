/// A recording fake of `share_plus`'s [SharePlatform] for the B1 export
/// widget tests (spec `docs/specs/polish-round-1.md` B1: "share sheet
/// itself may be stubbed at the share_plus boundary") -- no real OS share
/// sheet is ever touched.
library;

import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

/// A fake [SharePlatform] that records the last [ShareParams] it was asked
/// to share instead of invoking a real platform channel.
///
/// Install ONE instance via `SharePlatform.instance = FakeSharePlatform()`
/// at the top of a test file's `main()`, before any `testWidgets`/`test`
/// body runs, and call [reset] in `setUp` between tests rather than
/// creating a new [FakeSharePlatform] per test: `SharePlus.instance` is a
/// `static final` singleton that captures whatever `SharePlatform.instance`
/// is the FIRST time it's read (in `export_row.dart`'s `_export`) and never
/// re-reads it afterwards, so re-pointing `SharePlatform.instance` at a
/// fresh fake mid-suite has no effect once that first read has happened.
class FakeSharePlatform extends SharePlatform {
  /// The most recent [ShareParams] passed to [share], or `null` if [share]
  /// hasn't been called since the last [reset].
  ShareParams? lastParams;

  /// If set, [share] throws this instead of recording [lastParams] --
  /// simulates the share sheet itself failing.
  Exception? errorToThrow;

  /// Clears recorded state between tests.
  void reset() {
    lastParams = null;
    errorToThrow = null;
  }

  @override
  Future<ShareResult> share(ShareParams params) async {
    final error = errorToThrow;
    if (error != null) {
      throw error;
    }
    lastParams = params;
    return const ShareResult('fake', ShareResultStatus.success);
  }
}
