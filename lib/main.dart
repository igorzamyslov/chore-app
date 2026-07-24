import 'dart:async';

import 'package:chore_app/app/app.dart';
import 'package:chore_app/app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  // Activates the digest reschedule-on-mutation wiring immediately, before
  // the widget tree even builds (spec `docs/specs/notifications.md`
  // architecture #2: reschedule triggers include "bootstrap"). Deliberately
  // NOT wired inside `ChoreApp`/`AppShell` — see
  // `DigestRescheduleController`'s doc comment in `lib/app/providers.dart`
  // for why.
  final digestController = container.read(digestRescheduleControllerProvider);
  WidgetsBinding.instance.addObserver(_DigestResumeObserver(digestController));
  runApp(
    UncontrolledProviderScope(container: container, child: const ChoreApp()),
  );
}

/// Re-triggers the digest reschedule (and re-checks the OS notification
/// permission) whenever the app resumes from the background — the other
/// trigger the spec calls out that isn't itself a Riverpod-watchable value.
class _DigestResumeObserver extends WidgetsBindingObserver {
  _DigestResumeObserver(this._controller);

  final DigestRescheduleController _controller;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller.refreshPermissionState());
      _controller.triggerRecompute();
    }
  }
}
