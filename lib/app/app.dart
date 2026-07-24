/// Root widget and bootstrap-state handling.
library;

import 'package:chore_app/app/app_shell.dart';
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Root widget of the chore app.
///
/// Watches [bootstrapProvider]: while it loads, shows a blank scaffold with
/// a centered progress indicator; on error, a centered error message; once
/// it resolves, shows [AppShell].
class ChoreApp extends ConsumerWidget {
  /// Creates the root widget.
  const ChoreApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bootstrap = ref.watch(bootstrapProvider);
    return MaterialApp(
      title: 'Chores',
      theme: appLightTheme,
      darkTheme: appDarkTheme,
      home: bootstrap.when(
        data: (_) => const AppShell(),
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (error, stackTrace) => Scaffold(
          body: Center(
            child: semantic(
              'app.bootstrap_error',
              child: Text('Something went wrong starting up: $error'),
            ),
          ),
        ),
      ),
    );
  }
}
