/// Root widget and bootstrap-state handling.
library;

import 'package:chore_app/app/app_shell.dart';
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/app/theme.dart';
import 'package:chore_app/l10n/app_localizations.dart';
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
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: ref.watch(localeOverrideProvider),
      theme: appLightTheme,
      darkTheme: appDarkTheme,
      themeMode: ref.watch(themeModeProvider),
      home: bootstrap.when(
        data: (_) => const AppShell(),
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (error, stackTrace) => Scaffold(
          // A `Builder` is required here (rather than reusing `ChoreApp`'s
          // own `context`): `home` is built as part of constructing
          // `MaterialApp` itself, so `ChoreApp`'s `context` sits *above*
          // the `Localizations` widget `MaterialApp` establishes for its
          // subtree — `AppLocalizations.of` needs a `context` from inside
          // that subtree instead.
          body: Builder(
            builder: (context) => Center(
              child: semantic(
                'app.bootstrap_error',
                child: Text(
                  AppLocalizations.of(context).appBootstrapError(error),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
