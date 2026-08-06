/// The welcome gate's root screen (spec `docs/specs/onboarding-v2.md` §1):
/// shown full-screen, no tab shell, whenever `ChoreApp`
/// (`lib/app/app.dart`) finds no household locally yet. Two cards --
/// "Set up a new household" (inline name entry, right here) and "Join my
/// family's household" (a pushed subpage,
/// `lib/features/onboarding/welcome_join_page.dart`) -- plus small print.
/// The join card is hidden entirely when Supabase isn't configured
/// ([NoopAuthGateway]).
library;

import 'package:chore_app/app/depth_card.dart';
import 'package:chore_app/app/famdo_colors.dart';
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/features/chores/chore_form/labelled_field_card.dart';
import 'package:chore_app/features/onboarding/welcome_join_page.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The welcome screen -- see the library doc comment above.
class WelcomeScreen extends ConsumerStatefulWidget {
  /// Creates the welcome screen.
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  /// Whether the primary card's inline name form is showing (spec §1:
  /// "Tapping asks for the user's name inline") instead of the two-card
  /// chooser.
  bool _creatingHousehold = false;

  final _nameController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _nameController
      ..removeListener(_onNameChanged)
      ..dispose();
    super.dispose();
  }

  void _onNameChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _creatingHousehold
              ? _buildCreateNameForm(context)
              : _buildCards(context),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // The two-card chooser.

  Widget _buildCards(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // Spec §1: "If Supabase is unconfigured ... the join card is hidden
    // entirely" -- mirrors AccountSectionBody's identical Noop check
    // (`lib/features/settings/account_section.dart`).
    final joinEnabled = ref.watch(authGatewayProvider) is! NoopAuthGateway;

    return SingleChildScrollView(
      key: const ValueKey('cards'),
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The accent app tile (spec docs/specs/theme-v2.md §4.5) sits
          // above the wordmark; `Center` keeps it from being stretched to
          // the column's full width by the `stretch` cross-axis alignment
          // above (unlike `Icon`, a fixed-size `Container` has no built-in
          // self-centering under a tight incoming width constraint).
          Center(
            child: Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.checklist_rounded,
                size: 32,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.appTitle,
            style: theme.textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.welcomeTagline,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          _WelcomeCard(
            id: 'welcome.create',
            icon: Icons.home_outlined,
            title: l10n.welcomeCreateTitle,
            subtitle: l10n.welcomeCreateSubtitle,
            emphasized: true,
            onTap: () => setState(() => _creatingHousehold = true),
          ),
          if (joinEnabled) ...[
            const SizedBox(height: 16),
            _WelcomeCard(
              id: 'welcome.join',
              icon: Icons.group_add_outlined,
              title: l10n.welcomeJoinTitle,
              subtitle: l10n.welcomeJoinSubtitle,
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const WelcomeJoinPage()),
              ),
            ),
          ],
          const SizedBox(height: 32),
          semantic(
            'welcome.offline',
            child: Text(
              l10n.welcomeOffline,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // The primary card's inline name form.

  Widget _buildCreateNameForm(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final famdo = famdoColors(context);
    final canConfirm = !_saving && _nameController.text.trim().isNotEmpty;

    return SingleChildScrollView(
      key: const ValueKey('createName'),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: semantic(
              'welcome.create.back',
              child: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _saving
                    ? null
                    : () => setState(() => _creatingHousehold = false),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Raised primaryOutline card (spec docs/specs/theme-v2.md §4.5):
          // heading, sub-line, the always-visible (permanently-labelled,
          // never floating) name field, and a filled 48dp submit.
          DepthCard(
            margin: EdgeInsets.zero,
            shadow: true,
            borderColor: famdo.primaryOutline,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.welcomeCreateTitle,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.welcomeCreateSubtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  semantic(
                    'welcome.create.name',
                    child: LabelledFieldCard(
                      label: l10n.welcomeCreateNameLabel,
                      controller: _nameController,
                      autofocus: true,
                      textInputAction: TextInputAction.done,
                      // Enter is the SOLE submit path here (spec
                      // docs/specs/onboarding-v2.md; E2E
                      // e2e/common/onboard_fresh.yaml): the field's
                      // onSubmitted runs create directly, and the confirm
                      // button below never also fires from this callback.
                      onSubmitted: canConfirm ? (_) => _confirm() : null,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 20),
                  semantic(
                    'welcome.create.confirm',
                    child: FilledButton(
                      onPressed: canConfirm ? _confirm : null,
                      child: _saving
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l10n.welcomeCreateConfirm),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirm() async {
    final name = _nameController.text.trim();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(householdCreateServiceProvider).create(name);
      // No further local state update on success: the moment the create
      // transaction commits, `householdGateProvider`'s stream flips and
      // `ChoreApp` rebuilds straight to the tab shell -- this whole screen
      // (including this State) is torn down as part of that rebuild.
    } on Exception {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = AppLocalizations.of(context).welcomeCreateError;
      });
    }
  }
}

/// One of the welcome screen's two option cards: an icon, title + subtitle,
/// and a trailing chevron, matching the app's `DepthCard` list-tile
/// language (spec `docs/specs/design-language.md`) rather than bespoke
/// chrome.
///
/// [emphasized] makes this the raised, `primaryOutline`-bordered primary
/// card (spec `docs/specs/theme-v2.md` §4.5: "create is a raised
/// primaryOutline card"); otherwise it renders as the quiet secondary row
/// the join option calls for.
class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.emphasized = false,
  });

  final String id;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final famdo = famdoColors(context);
    return DepthCard(
      margin: EdgeInsets.zero,
      shadow: emphasized,
      borderColor: emphasized ? famdo.primaryOutline : null,
      child: semantic(
        id,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(icon, size: 32, color: theme.colorScheme.primary),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
