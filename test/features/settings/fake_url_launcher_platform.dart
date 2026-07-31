/// A recording fake of `url_launcher`'s [UrlLauncherPlatform] for the About
/// section's donate-sheet widget tests -- no real OS "open URL" action is
/// ever touched.
library;

import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// A fake [UrlLauncherPlatform] that records the last URL/[LaunchOptions] it
/// was asked to launch instead of invoking a real platform channel.
///
/// Install ONE instance via `UrlLauncherPlatform.instance =
/// FakeUrlLauncherPlatform()` at the top of a test file's `main()` (or in
/// `setUp`), and call [reset] between tests. Unlike `share_plus`'s
/// `SharePlus.instance`, `package:url_launcher`'s top-level `launchUrl`
/// re-reads `UrlLauncherPlatform.instance` on every call, so re-pointing it
/// mid-suite is safe.
class FakeUrlLauncherPlatform extends UrlLauncherPlatform {
  /// The most recent URL passed to [launchUrl], or `null` if it hasn't been
  /// called since the last [reset].
  String? lastLaunchedUrl;

  /// The most recent [LaunchOptions] passed to [launchUrl], or `null` if it
  /// hasn't been called since the last [reset].
  LaunchOptions? lastOptions;

  @override
  LinkDelegate? get linkDelegate => null;

  /// Clears recorded state between tests.
  void reset() {
    lastLaunchedUrl = null;
    lastOptions = null;
  }

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    lastLaunchedUrl = url;
    lastOptions = options;
    return true;
  }
}
