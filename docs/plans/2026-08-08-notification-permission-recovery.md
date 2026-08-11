# Notification Permission Recovery (B-5) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give a user whose digest notification permission is denied (or was
never granted after dismissing the one-shot pre-prompt) an honest,
non-nagging signal that the digest will never arrive, discoverable without
requiring them to open Settings on their own initiative — and keep the
existing Settings recovery path intact.

**Architecture:** Two independent, additive changes, both driven by state
that already exists and is already live-tracked (`settingsProvider`,
`notificationPermissionGrantedProvider`, `DigestRescheduleController.
refreshPermissionState`): (1) the Settings digest toggle grows a short
factual sub-line when it would otherwise look "on" while nothing is
scheduled; (2) the app's bottom tab bar grows a small ambient attention dot
on the Settings tab — visible from every tab, no dismiss action, ungated by
any one-shot flag, self-clearing the instant permission is granted or the
digest is turned off. Neither change touches `DigestPrepromptBanner`,
`NotificationScheduler`, or the stored `digestEnabled` value.

**Tech Stack:** Flutter 3.44, Riverpod, drift/SQLite, gen_l10n.

**Spec:** `docs/specs/notifications.md` (BINDING) and `docs/specs/
polish-round-1.md` A3 (BINDING). This plan extends both — see Task 3.

## Global Constraints

- Every user-visible string goes through gen_l10n: add to
  `lib/l10n/app_en.arb` (template) AND `lib/l10n/app_de.arb` (German
  du-form). Never hardcode display text. `pubspec.yaml` has `flutter:
  generate: true`, so `flutter test`/`flutter run` regenerates
  `lib/l10n/app_localizations*.dart` automatically — never hand-edit the
  generated files.
- Every interactive widget gets a stable id via the `semantic()` helper
  (`lib/app/semantics.dart`); E2E and widget tests select only by id or a
  `(?s)`-substring of visible text.
- Widget tests are integration-style: pump the real `ChoreApp` via
  `testChoreApp` (`test/test_utils/pump_app.dart`) against a real in-memory
  `AppDatabase` and a fixed `clockProvider`, overriding ONLY
  `notificationPermissionGrantedProvider` (a plain `StateProvider<bool>`,
  default `true`) here — never mock a repository or service.
- Strict lints: `very_good_analysis` with `--fatal-infos`. Public members
  need doc comments (private/underscored members in `app_shell.dart`
  already have none — keep that pattern, don't invent new documentation
  requirements for them).
- Never `await` a drift stream outside a widget pump.
- Never add `Co-Authored-By` (or any co-author) trailers to commits.
- TDD: write a failing test, run it, implement, run it again, commit.

## Why not just re-arm `DigestPrepromptBanner`?

The banner's job (spec `docs/specs/polish-round-1.md` A3) is to explain the
feature *before* the one-shot OS dialog fires — that job is done the moment
it's shown once, whether the user taps "Turn on" or "Not now". Re-showing
the *same* card later, with the same "want a daily summary?" copy, to
someone who already answered that question once reads as not having
listened — exactly the "feels accused" reaction the persona walkthrough
(`docs/research/persona-ben.md` finding 8) flags, and exactly what
`DESIGN.md` §2's "never nag" principle rules out. See "Open product
decisions" below for the one genuinely underivable call this plan leaves
open; everything else here is designed to need no cooldown timer, no new
one-shot flag, and no re-arming logic at all.

## Approaches considered

1. **Re-arm the same pre-prompt banner after a time-based cooldown** (e.g.
   reshow after 14 days if still enabled+denied). Reuses existing
   infrastructure (the banner, its two actions, `digestPrepromptShownAt`).
   Rejected as the primary mechanism: a cooldown is an arbitrary duration
   with no principled value, and a card that keeps coming back after being
   dismissed is the textbook definition of nagging this app's design
   language forbids.
2. **A second, distinctly-worded one-shot notice tied to a concrete
   symptom** (e.g., "you have N overdue chores and won't be notified"),
   shown once, separately from the original pre-prompt. Closer to the
   persona's actual pain (a concrete, current cost rather than an abstract
   feature pitch) but still finite: if the user dismisses this one too, or
   never accumulates enough overdue chores to trigger it, they're back to
   silence with no recovery path outside Settings. Also needs a new
   one-shot flag and a threshold decision.
3. **An ambient, always-current indicator with no dismiss action** — a
   small dot on the Settings tab icon in the bottom nav, visible from every
   tab, computed live from state that's already tracked
   (`digestEnabled`, `notificationPermissionGrantedProvider`,
   `digestPrepromptShownAt`). **Chosen.** It cannot go stale (it's not a
   snapshot flag, it's a live projection of current truth), needs no
   cooldown tuning, costs the user zero interaction, and structurally
   cannot repeat an already-answered question because it never asks
   anything — it just quietly reflects "this won't arrive right now". It's
   the same pattern iOS/Android system apps use for "needs attention"
   badges, which nobody experiences as nagging. Combined with the toggle
   sub-line (so Settings itself stops looking like the digest is live once
   the user does arrive there), this closes the loop the ticket describes
   without adding any new one-shot bookkeeping.

Approach 3 alone doesn't solve the very first cold launch, though: a brand
new install has `digestEnabled = true` by default and the OS permission
not yet requested, which reads as `!permissionGranted` on iOS/Android 13+
before the user has done anything at all. Gating the badge on
`digestPrepromptShownAt != null` (the one-shot pre-prompt has already
appeared and been acted on, however it was acted on) fixes this for free:
it mirrors the exact rule the pre-prompt banner and `NotificationScheduler`
already follow — never surface anything about the OS permission before an
explicit user interaction (spec `docs/specs/polish-round-1.md` A3: "the OS
permission dialog can NEVER appear except from an explicit user tap"). This
plan extends that same rule to "never surface the *badge* either, before
that first interaction has happened."

## Open product decisions

### Should the pre-prompt banner ever come back, and on what trigger?

This plan's ambient tab badge (Task 2) already gives a persistent,
non-nagging recovery signal, so the banner does not *need* to be
re-armable for this ticket to close the "permanent in practice" gap. But
Igor may still want a second, one-time, more assertive nudge for the
specific cohort that dismissed the pre-prompt without ever reaching
Settings.

- **(a) Never re-arm.** The badge (Task 2) plus the existing Settings hint
  row are the only recovery paths. Simplest, truest to "never nag", but
  relies entirely on the user noticing a small dot.
- **(b) One additional, distinctly-worded one-shot notice**, triggered by a
  concrete symptom (e.g., the first time there's at least one overdue
  occurrence while the digest is enabled and permission is denied),
  separate from the original pre-prompt's copy and id. Bounded (fires at
  most once, ever), but needs a new one-shot flag and a threshold choice.
- **(c) Time-based cooldown re-arm of the original banner** (e.g. every 30
  days while still enabled+denied). Rejected above as nagging-shaped;
  listed here only for completeness.

**Recommendation: (a).** This plan implements (a) only — no new banner
logic, no new one-shot flag beyond what already exists. If Igor wants (b)
later, it's a small additive follow-up (new ARB strings, new settings
column, one new gated widget) that doesn't touch anything in this plan.

**This plan assumes: (a) — the pre-prompt banner (`lib/features/chores/
digest_preprompt_banner.dart`) is not modified at all.**

## File Map

- `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb` — one new string, shared by
  the toggle sub-line and the tab badge's accessibility label.
- `lib/features/settings/digest_section.dart` — `DigestToggleTile` grows an
  optional `permissionDenied` param.
- `lib/features/settings/settings_screen.dart` — wires the already-computed
  `permissionGranted` into the new `DigestToggleTile` param.
- `lib/app/app_shell.dart` — `_BottomTabBar` becomes a `ConsumerWidget`
  reading the digest/permission state; `_TabContent` renders the badge.
- `docs/specs/notifications.md`, `docs/specs/polish-round-1.md` — spec
  updates documenting both new pieces (binding contracts; see Task 3).
- Tests: `test/features/settings/digest_section_test.dart`,
  `test/app/app_shell_test.dart`.

---

## Task 1: Honest digest toggle — sub-line when enabled but not delivering

**Files:**
- Modify: `lib/l10n/app_en.arb` (insert after the `settingsDigestToggleTitle`
  block, i.e. after line 815)
- Modify: `lib/l10n/app_de.arb` (insert after `settingsDigestToggleTitle` on
  line 173)
- Modify: `lib/features/settings/digest_section.dart:12-38`
  (`DigestToggleTile`)
- Modify: `lib/features/settings/settings_screen.dart:95-99` (the
  `DigestToggleTile(...)` call)
- Test: `test/features/settings/digest_section_test.dart`

**Interfaces:**
- Produces: `AppLocalizations.settingsDigestToggleDeniedHint` (a `String`
  getter, generated from the ARB key below) — also consumed by Task 2.
- Produces: `DigestToggleTile({required bool value, required
  ValueChanged<bool> onChanged, bool permissionDenied = false, Key? key})`
  — the new `permissionDenied` param is additive and defaults to `false`,
  so no other call site breaks.

- [ ] **Step 1: Write the failing test**

Append to `test/features/settings/digest_section_test.dart` (inside the
existing `void main() { ... }`, after the last `testChoreApp` block):

```dart
  testChoreApp(
    'toggle grows a "not delivering" sub-line when enabled but the OS '
    'permission is denied',
    today: today,
    overrides: [
      notificationPermissionGrantedProvider.overrideWith((ref) => false),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('settings.digest.toggle'),
          matching: find.text('Not delivering — notifications are off'),
        ),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'toggle sub-line disappears once the permission is granted',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('settings.digest.toggle'),
          matching: find.text('Not delivering — notifications are off'),
        ),
        findsNothing,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'toggle sub-line stays hidden when the digest itself is off, even with '
    'the permission denied',
    today: today,
    overrides: [
      notificationPermissionGrantedProvider.overrideWith((ref) => false),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      await tester.tap(find.bySemanticsIdentifier('settings.digest.toggle'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('settings.digest.toggle'),
          matching: find.text('Not delivering — notifications are off'),
        ),
        findsNothing,
      );

      handle.dispose();
    },
  );
```

This needs `notificationPermissionGrantedProvider` in scope, which requires
adding this import at the top of the file (it isn't there yet):

```dart
import 'package:chore_app/app/providers.dart';
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/settings/digest_section_test.dart`
Expected: the first new test FAILS (`findsOneWidget` sees nothing — the
string doesn't exist yet, and neither does the l10n getter, so this
actually fails to compile first). The other two new tests pass vacuously
(they assert absence, which is already true) — that's fine, they exist to
guard the *other* two directions once Step 3 lands.

- [ ] **Step 3: Add the ARB string**

In `lib/l10n/app_en.arb`, insert immediately after the
`settingsDigestToggleTitle` block (after line 815, before
`settingsDigestTimeLabel`):

```json
  "settingsDigestToggleDeniedHint": "Not delivering — notifications are off",
  "@settingsDigestToggleDeniedHint": {
    "description": "Sub-line shown under the settings screen's digest toggle when it's on but the OS notification permission is denied, so the switch's ON position doesn't look like it's actually working. Also used as the accessibility label for the Settings tab's ambient attention badge (app_shell.dart)."
  },
```

In `lib/l10n/app_de.arb`, insert immediately after
`settingsDigestToggleTitle` (after line 173, before
`settingsDigestTimeLabel`):

```json
  "settingsDigestToggleDeniedHint": "Wird nicht zugestellt – Benachrichtigungen sind aus",
```

- [ ] **Step 4: Add the `permissionDenied` param to `DigestToggleTile`**

Replace the `DigestToggleTile` class in
`lib/features/settings/digest_section.dart` (lines 12-38) with:

```dart
/// The 'Daily summary' on/off switch row.
class DigestToggleTile extends StatelessWidget {
  /// Creates the toggle row.
  const DigestToggleTile({
    required this.value,
    required this.onChanged,
    this.permissionDenied = false,
    super.key,
  });

  /// Whether the digest is currently enabled.
  final bool value;

  /// Called when the switch is flipped.
  final ValueChanged<bool> onChanged;

  /// Whether the OS notification permission is currently denied (spec
  /// `docs/backlog.md` B-5). When [value] is also `true` this grows a
  /// short factual sub-line so the switch's ON position never implies the
  /// digest is actually being delivered when it isn't. Never changes
  /// [value] itself -- the stored `digestEnabled` stays the source of
  /// truth for "the user wants this on" (spec `docs/specs/notifications.md`:
  /// permission state affects PRESENTATION only, never the stored flag).
  final bool permissionDenied;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final showDeniedHint = value && permissionDenied;
    return semantic(
      'settings.digest.toggle',
      child: SettingsRow(
        icon: Icons.notifications_outlined,
        label: l10n.settingsDigestToggleTitle,
        sublabel: showDeniedHint ? l10n.settingsDigestToggleDeniedHint : null,
        switchValue: value,
        onSwitchChanged: onChanged,
      ),
    );
  }
}
```

- [ ] **Step 5: Wire `permissionGranted` into the call site**

In `lib/features/settings/settings_screen.dart`, replace lines 95-99:

```dart
                  DigestToggleTile(
                    value: settings.digestEnabled,
                    onChanged: (enabled) =>
                        settingsRepository.setDigestEnabled(enabled: enabled),
                  ),
```

with:

```dart
                  DigestToggleTile(
                    value: settings.digestEnabled,
                    permissionDenied: !permissionGranted,
                    onChanged: (enabled) =>
                        settingsRepository.setDigestEnabled(enabled: enabled),
                  ),
```

(`permissionGranted` is already read at the top of `build` on line 44 --
no new provider read needed.)

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/features/settings/digest_section_test.dart`
Expected: PASS, all tests including the pre-existing ones (the new
`sublabel` is `null` whenever `permissionDenied` is `false`, so the
"enabled by default, ... no permission hint" test at the top of the file
is unaffected).

- [ ] **Step 7: Commit**

```bash
git add lib/l10n/app_en.arb lib/l10n/app_de.arb \
  lib/features/settings/digest_section.dart \
  lib/features/settings/settings_screen.dart \
  test/features/settings/digest_section_test.dart
git commit -m "Show a factual sub-line on the digest toggle when permission is denied"
```

---

## Task 2: Ambient "needs attention" badge on the Settings tab

**Files:**
- Modify: `lib/app/app_shell.dart`
- Test: `test/app/app_shell_test.dart`

**Interfaces:**
- Consumes: `settingsProvider` (`StreamProvider<DeviceSettings>`,
  `lib/app/providers.dart`), `notificationPermissionGrantedProvider`
  (`StateProvider<bool>`, same file), `AppLocalizations.
  settingsDigestToggleDeniedHint` (from Task 1), `DeviceSettings.
  digestEnabled` / `.digestPrepromptShownAt` (drift-generated,
  `lib/data/db/app_database.g.dart`).
- Produces: semantic id `shell.tab.settings.attentionBadge`, present iff
  `digestEnabled && !permissionGranted && digestPrepromptShownAt != null`.

- [ ] **Step 1: Write the failing tests**

Add these imports to the top of `test/app/app_shell_test.dart` (alongside
the existing two):

```dart
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
```

Append these four `testChoreApp` blocks inside `void main() { ... }`,
after the two existing ones:

```dart
  testChoreApp(
    'no attention badge on a fresh install: digest is enabled by default '
    'but the pre-prompt has never been shown, so an unrequested OS '
    'permission stays silent rather than looking denied',
    today: DateTime(2026, 7, 24, 9),
    overrides: [
      notificationPermissionGrantedProvider.overrideWith((ref) => false),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();

      expect(
        find.bySemanticsIdentifier('shell.tab.settings.attentionBadge'),
        findsNothing,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'attention badge appears once the pre-prompt has been shown and the '
    'permission is still denied -- and stays visible from every tab, not '
    'just Settings',
    today: DateTime(2026, 7, 24, 9),
    overrides: [
      notificationPermissionGrantedProvider.overrideWith((ref) => false),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await SettingsRepository(database).markDigestPrepromptShown();
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('shell.tab.settings.attentionBadge'),
        findsOneWidget,
      );

      await tester.tap(find.bySemanticsIdentifier('shell.tab.shopping'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('shell.tab.settings.attentionBadge'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'attention badge hidden once the permission is granted',
    today: DateTime(2026, 7, 24, 9),
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await SettingsRepository(database).markDigestPrepromptShown();
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('shell.tab.settings.attentionBadge'),
        findsNothing,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'attention badge hidden when the digest itself is off, even with the '
    'pre-prompt shown and permission denied',
    today: DateTime(2026, 7, 24, 9),
    overrides: [
      notificationPermissionGrantedProvider.overrideWith((ref) => false),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final settingsRepository = SettingsRepository(database);
      await settingsRepository.markDigestPrepromptShown();
      await settingsRepository.setDigestEnabled(enabled: false);
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('shell.tab.settings.attentionBadge'),
        findsNothing,
      );

      handle.dispose();
    },
  );
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/app/app_shell_test.dart`
Expected: the second test FAILS (`findsOneWidget` finds nothing — the
badge doesn't exist yet). The other three pass vacuously.

- [ ] **Step 3: Implement the badge in `app_shell.dart`**

Add these two imports to `lib/app/app_shell.dart` (alongside the existing
ones):

```dart
import 'package:chore_app/app/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
```

Replace the `_BottomTabBar` class with:

```dart
class _BottomTabBar extends ConsumerWidget {
  const _BottomTabBar({required this.selected, required this.onSelected});

  final _AppTab selected;
  final ValueChanged<_AppTab> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final famdo = famdoColors(context);
    // Spec docs/backlog.md B-5 / docs/specs/notifications.md: an ambient,
    // always-current "this won't arrive" signal, gated on
    // `digestPrepromptShownAt != null` so it deliberately says nothing on a
    // brand new install -- before the app has ever raised the permission
    // question at all, an unrequested OS permission must not read as a
    // denied one (mirrors the pre-prompt banner's own rule, spec
    // `docs/specs/polish-round-1.md` A3: never surface the permission
    // question before an explicit user interaction).
    final settings = ref.watch(settingsProvider).valueOrNull;
    final permissionGranted = ref.watch(notificationPermissionGrantedProvider);
    final showAttentionBadge =
        settings != null &&
        settings.digestEnabled &&
        !permissionGranted &&
        settings.digestPrepromptShownAt != null;

    return Container(
      // A 1px top hairline (spec docs/specs/theme-v2.md §4.5) sits on this
      // outer Container so the inner Material can keep filling its bounds
      // with `navBarBackground` -- Material's own `shape` has no clean way
      // to draw a single-edge border.
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Material(
        color: famdo.navBarBackground,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 72,
            child: Row(
              children: [
                for (final tab in _AppTab.values)
                  Expanded(
                    child: semantic(
                      'shell.tab.${tab.name}',
                      // The hand-rolled bar must carry the traits
                      // NavigationBar would have provided: without
                      // `selected`, screen readers can't tell which tab is
                      // active (the visual cue is color/icon only).
                      child: Semantics(
                        button: true,
                        selected: tab == selected,
                        // Field feedback 2026-08-07 C2: a bare InkWell
                        // rippled a grey RECTANGLE across the whole tab
                        // column while the active state is a rounded pill --
                        // the two shapes fought each other. InkResponse with
                        // a bounded radius keeps the splash inside a pill
                        // roughly the size of the active one, and tints it
                        // with the accent instead of the default grey.
                        child: InkResponse(
                          onTap: () => onSelected(tab),
                          radius: 44,
                          containedInkWell: true,
                          highlightShape: BoxShape.rectangle,
                          borderRadius: BorderRadius.circular(16),
                          splashColor: colorScheme.primary.withValues(
                            alpha: 0.12,
                          ),
                          highlightColor: colorScheme.primary.withValues(
                            alpha: 0.06,
                          ),
                          child: _TabContent(
                            tab: tab,
                            isSelected: tab == selected,
                            showAttentionBadge:
                                tab == _AppTab.settings && showAttentionBadge,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

Replace the `_TabContent` class with:

```dart
class _TabContent extends StatelessWidget {
  const _TabContent({
    required this.tab,
    required this.isSelected,
    this.showAttentionBadge = false,
  });

  final _AppTab tab;
  final bool isSelected;

  /// Whether to draw the small ambient dot signalling that the digest is
  /// enabled but currently can't be delivered (spec `docs/backlog.md`
  /// B-5). Only ever `true` for the Settings tab.
  final bool showAttentionBadge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // The active destination's 62x30 pill (spec
        // docs/specs/theme-v2.md §4.5); inactive tabs get an equivalent
        // transparent slot so the icon doesn't jump vertically when
        // selection changes.
        Container(
          width: 62,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colorScheme.primaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Icon(isSelected ? tab.filled : tab.outlined, color: color),
              if (showAttentionBadge)
                Positioned(
                  top: -2,
                  right: -6,
                  child: Semantics(
                    label: AppLocalizations.of(
                      context,
                    ).settingsDigestToggleDeniedHint,
                    child: semantic(
                      'shell.tab.settings.attentionBadge',
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _tabLabel(context, tab),
          style: theme.textTheme.labelMedium?.copyWith(color: color),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/app/app_shell_test.dart`
Expected: PASS, all six tests (two pre-existing, four new).

- [ ] **Step 5: Run the full digest-related suite as a regression check**

Run: `flutter test test/app/app_shell_test.dart test/features/settings/digest_section_test.dart test/features/chores/digest_preprompt_banner_test.dart test/app/digest_reschedule_test.dart`
Expected: PASS. This confirms converting `_BottomTabBar` to a
`ConsumerWidget` didn't disturb `DigestRescheduleController` or the
pre-prompt banner (neither reads `_BottomTabBar`, but they share the two
providers this task now also reads).

- [ ] **Step 6: Commit**

```bash
git add lib/app/app_shell.dart test/app/app_shell_test.dart
git commit -m "Add an ambient Settings-tab badge when the digest can't be delivered"
```

---

## Task 3: Document both changes in the binding specs

**Files:**
- Modify: `docs/specs/notifications.md`
- Modify: `docs/specs/polish-round-1.md`

Specs in `docs/specs/` are binding contracts (project convention); both
now under-describe the Settings screen and the tab bar after Tasks 1-2, so
they need updating rather than left to drift from the shipped behavior.

- [ ] **Step 1: Extend `docs/specs/notifications.md`'s Settings section**

In `docs/specs/notifications.md`, the "## Settings (device-level, single
row)" section currently ends with:

```
Settings tab gets its first built-in section (above the category
management entry point when #14 lands): 'Daily summary' toggle
(`settings.digest.toggle`), time row opening a time picker
(`settings.digest.time`), and — when the OS permission is denied — an
inline hint row with a button opening the system settings
(`settings.digest.permission`). Copy per design-language tone; all l10n.
```

Replace that paragraph with:

```
Settings tab gets its first built-in section (above the category
management entry point when #14 lands): 'Daily summary' toggle
(`settings.digest.toggle`), time row opening a time picker
(`settings.digest.time`), and — when the OS permission is denied — an
inline hint row with a button opening the system settings
(`settings.digest.permission`). Copy per design-language tone; all l10n.

Spec `docs/backlog.md` B-5: when the toggle is ON but the OS permission is
denied, `settings.digest.toggle` also grows a short factual sub-line
(`settingsDigestToggleDeniedHint`, e.g. "Not delivering — notifications are
off") so its ON position never implies delivery that isn't happening. This
is presentation only — it never changes the stored `digestEnabled` value
(see the "Permission denied" rule below, unchanged).

Because a user who dismissed the digest pre-prompt (`docs/specs/
polish-round-1.md` A3) may never open Settings again on their own, the
Settings tab icon in the bottom nav (`lib/app/app_shell.dart`) also carries
an ambient attention dot — no dismiss action, no copy of its own, just a
live projection of `digestEnabled && !permissionGranted &&
digestPrepromptShownAt != null` (the last clause keeps it silent before
the pre-prompt has ever been shown, so an unrequested OS permission on a
fresh install never reads as a denied one). It clears itself the instant
the permission is granted or the digest is turned off; nothing about it is
one-shot or requires a flag of its own.
```

- [ ] **Step 2: Cross-reference from `docs/specs/polish-round-1.md` A3**

In `docs/specs/polish-round-1.md`, the "### A3. Digest pre-prompt banner
(G3)" section ends with:

```
- Content: "Want a daily summary of what's due?" + **Turn on** (id
  `digest.preprompt.enable`): mark flag, then `requestPermission()` (the
  one-shot OS dialog), then trigger a digest recompute. **Not now** (id
  `digest.preprompt.dismiss`): mark flag only — the digest stays enabled
  but silent until permission arrives via Settings (existing hint row is
  the recovery path). Banner id `digest.preprompt`.
```

Append immediately after that bullet (still inside the A3 section, before
"## B. Settings data operations"):

```

- **Recovery beyond this one-shot card** (spec `docs/backlog.md` B-5): this
  banner is never re-armed or re-shown after either action. The durable
  recovery path for a user who never returns to Settings on their own is
  the Settings tab's ambient attention badge — see `docs/specs/
  notifications.md`'s Settings section.
```

- [ ] **Step 3: Commit**

```bash
git add docs/specs/notifications.md docs/specs/polish-round-1.md
git commit -m "Document the digest toggle sub-line and Settings-tab attention badge"
```
