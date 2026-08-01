import 'dart:async';

import 'package:chore_app/app/app.dart';
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/supabase_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Only ever called here, before `runApp` -- never from a widget, never in
  // tests (spec `docs/specs/sync-backend.md` §5). `supabaseConfigured`
  // false (the empty-dart-define escape hatch -- see
  // `lib/app/supabase_config.dart`) keeps the app fully offline, which is
  // exactly what every test and E2E run does.
  if (supabaseConfigured) {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseAnonKey,
    );
  }
  final container = ProviderContainer();
  // Activates the digest reschedule-on-mutation wiring and the chore
  // catch-up resume/day-change wiring immediately, before the widget tree
  // even builds (spec `docs/specs/notifications.md` architecture #2:
  // reschedule triggers include "bootstrap"; spec
  // `docs/specs/polish-round-1.md` C1). Deliberately NOT wired inside
  // `ChoreApp`/`AppShell` — see `DigestRescheduleController`'s and
  // `CatchUpController`'s doc comments in `lib/app/providers.dart` for why.
  final digestController = container.read(digestRescheduleControllerProvider);
  final catchUpController = container.read(catchUpControllerProvider);
  WidgetsBinding.instance.addObserver(
    _AppResumeObserver(digestController, catchUpController),
  );
  runApp(
    UncontrolledProviderScope(container: container, child: const ChoreApp()),
  );
}

/// Re-triggers the digest reschedule (and re-checks the OS notification
/// permission), and re-runs chore catch-up, whenever the app resumes from
/// the background — the lifecycle trigger neither wiring can observe via
/// Riverpod alone, since an OS lifecycle transition isn't itself a
/// watchable value.
class _AppResumeObserver extends WidgetsBindingObserver {
  _AppResumeObserver(this._digestController, this._catchUpController);

  final DigestRescheduleController _digestController;
  final CatchUpController _catchUpController;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_digestController.refreshPermissionState());
      _digestController.triggerRecompute();
      _catchUpController.triggerOnResume();
    }
  }
}
