/// Root widget, welcome-gate switch, and bootstrap-state handling.
library;

import 'package:chore_app/app/app_shell.dart';
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/app/theme.dart';
import 'package:chore_app/features/onboarding/welcome_screen.dart';
import 'package:chore_app/features/settings/reset_flow.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Root widget of the chore app.
///
/// Watches [householdGateProvider] (spec `docs/specs/onboarding-v2.md`
/// §1/§2): while it loads, shows a blank scaffold with a centered progress
/// indicator; on error, [_ErrorScaffold]'s retry-or-reset screen; once it
/// resolves to
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
        error: (error, stackTrace) => _ErrorScaffold(
          error: error,
          onRetry: () => ref.invalidate(householdGateProvider),
        ),
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
      error: (error, stackTrace) => _ErrorScaffold(
        error: error,
        onRetry: () => ref.invalidate(bootstrapProvider),
      ),
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

/// Shown if either [householdGateProvider] or [bootstrapProvider] fails
/// (e.g. the local database couldn't be opened): a plain-language headline,
/// the raw exception as a de-emphasized detail line, a Retry action, and --
/// since retry alone cannot help with a genuinely broken database file -- a
/// Reset app data escape hatch running the exact same flow as the Settings
/// row.
///
/// Spec `docs/feedback/2026-08-08-prerelease-audit.md` S2: this screen used
/// to be a permanent dead end. Settings is unreachable from here (bootstrap
/// never got that far), so uninstalling the app was the only way out of a
/// database-open failure.
///
/// The raw exception is kept, not hidden: this app ships with no crash
/// reporting, so a screenshot of this line is the entire bug report. It is
/// merely demoted below a headline that a non-technical reader can act on.
class _ErrorScaffold extends ConsumerWidget {
  const _ErrorScaffold({required this.error, required this.onRetry});

  final Object error;

  /// Re-attempts whichever provider ([householdGateProvider] or
  /// [bootstrapProvider]) produced [error] — supplied by the call site,
  /// since only it knows which one that was. Tearing down
  /// [appDatabaseProvider] instead would not help: the failure is the data,
  /// not the provider, which is exactly why the reset hatch sits alongside.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Best-effort: with the database broken this is usually unavailable, so
    // it falls back to `false`, i.e. the "there is no cloud backup, this
    // can't be undone" copy. That is the conservative default of the two --
    // it never understates what a wipe costs, whereas defaulting to
    // `linked` would promise a server-side copy that may not exist.
    final linked =
        ref.watch(settingsProvider).valueOrNull?.syncHouseholdId != null;
    return Scaffold(
      // A `Builder` is required here (rather than reusing the ambient
      // `context`): `home` is built as part of constructing `MaterialApp`
      // itself, so that `context` sits *above* the `Localizations` widget
      // `MaterialApp` establishes for its subtree — `AppLocalizations.of`
      // needs a `context` from inside that subtree instead.
      body: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          final theme = Theme.of(context);
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.appBootstrapErrorTitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  semantic(
                    'app.bootstrap_error',
                    child: Text(
                      l10n.appBootstrapError(error),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  semantic(
                    'app.bootstrap_error.retry',
                    child: OutlinedButton(
                      onPressed: onRetry,
                      child: Text(l10n.commonRetry),
                    ),
                  ),
                  const SizedBox(height: 8),
                  semantic(
                    'app.bootstrap_error.reset',
                    child: TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                      onPressed: () =>
                          confirmAndResetAppData(context, ref, linked: linked),
                      child: Text(l10n.settingsResetEntry),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
