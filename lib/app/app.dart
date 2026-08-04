/// Root widget, welcome-gate switch, and bootstrap-state handling.
library;

import 'package:chore_app/app/app_shell.dart';
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/app/theme.dart';
import 'package:chore_app/features/onboarding/welcome_screen.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Root widget of the chore app.
///
/// Watches [householdGateProvider] (spec `docs/specs/onboarding-v2.md`
/// §1/§2): while it loads, shows a blank scaffold with a centered progress
/// indicator; on error, a centered error message; once it resolves to
/// `null` (no household exists locally yet -- a fresh install that hasn't
/// chosen "start fresh" or "join"), shows [WelcomeScreen]; once it resolves
/// to a household, hands off to [_Bootstrapped], which waits on
/// [bootstrapProvider]'s own id-resolving + side-effect role before
/// showing [AppShell].
class ChoreApp extends ConsumerWidget {
  /// Creates the root widget.
  const ChoreApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gate = ref.watch(householdGateProvider);
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: ref.watch(localeOverrideProvider),
      theme: appLightTheme,
      darkTheme: appDarkTheme,
      themeMode: ref.watch(themeModeProvider),
      home: gate.when(
        data: (household) =>
            household == null ? const WelcomeScreen() : const _Bootstrapped(),
        loading: () => const _LoadingScaffold(),
        error: (error, stackTrace) => _ErrorScaffold(error: error),
      ),
    );
  }
}

/// Shown once [householdGateProvider] has confirmed a household exists:
/// waits on [bootstrapProvider]'s id-resolving + side-effect role (seed
/// categories if missing, catch-up, stale-checked cleanup -- spec
/// `docs/specs/onboarding-v2.md` §2) before showing [AppShell].
class _Bootstrapped extends ConsumerWidget {
  const _Bootstrapped();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bootstrap = ref.watch(bootstrapProvider);
    return bootstrap.when(
      data: (_) => const AppShell(),
      loading: () => const _LoadingScaffold(),
      error: (error, stackTrace) => _ErrorScaffold(error: error),
    );
  }
}

/// A blank scaffold with a centered progress indicator, shown while either
/// [householdGateProvider] or [bootstrapProvider] is still loading.
class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

/// A centered error message, shown if either [householdGateProvider] or
/// [bootstrapProvider] fails (e.g. the local database couldn't be opened).
class _ErrorScaffold extends StatelessWidget {
  const _ErrorScaffold({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // A `Builder` is required here (rather than reusing the ambient
      // `context`): `home` is built as part of constructing `MaterialApp`
      // itself, so that `context` sits *above* the `Localizations` widget
      // `MaterialApp` establishes for its subtree — `AppLocalizations.of`
      // needs a `context` from inside that subtree instead.
      body: Builder(
        builder: (context) => Center(
          child: semantic(
            'app.bootstrap_error',
            child: Text(AppLocalizations.of(context).appBootstrapError(error)),
          ),
        ),
      ),
    );
  }
}
