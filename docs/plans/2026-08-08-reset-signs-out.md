# A-4: Reset Signs Out Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make "Reset app data" actually deliver the clean slate its confirm
copy promises: end the Supabase session and cancel the scheduled digest
notification as part of the same operation, and make the confirm copy
accurate in every reachable state (signed-in-linked, signed-in-unlinked,
signed-out).

**Architecture:** `resetAppData` (`lib/application/data_reset.dart`) stays a
pure, DB-only transaction — no new parameters, no new dependencies. The two
new side effects are best-effort steps added to `ResetDataTile.
_confirmAndReset` (`lib/features/settings/reset_flow.dart`), the same call
site that already owns `settingsProvider` invalidation post-wipe. Both new
steps run via existing `Provider`s already reachable from `ref`
(`authGatewayProvider`, `notificationSchedulerProvider`) — no new providers,
no signature changes to any repository/service.

**Tech Stack:** Flutter, Riverpod, drift, gen_l10n (du-form German).

**Spec:** `docs/specs/polish-round-1.md` B2 (BINDING) — Task 3 below updates
it to cover the new behavior.

## Analysis (brainstorming — resolved without needing product input)

**The bug.** `resetAppData` wipes all eight tables; nothing signs the user
out and nothing cancels the digest. `ResetDataTile._confirmAndReset`
(`lib/features/settings/reset_flow.dart:58-75`) is the only call site in
production, and it already does one piece of post-wipe orchestration
(`ref.invalidate(settingsProvider)`) beyond the bare `resetAppData` call —
establishing the precedent this plan follows.

**Where do sign-out and digest-cancel belong: `resetAppData` or the tile?**

| Option | Trade-off |
| --- | --- |
| **A. Add `AuthGateway`/`NotificationScheduler` params to `resetAppData`** | Keeps all reset side effects in one function, but couples a pure `AppDatabase`-transaction helper to two unrelated subsystems. `test/application/data_reset_test.dart` currently constructs a bare `AppDatabase` with no Riverpod/fakes at all (spec: "mirroring `test/application/data_export_test.dart`'s seed") — this would force fakes into a test file that has never needed them, for a concern (auth/notifications) `resetAppData`'s own doc comment explicitly scopes out ("Leaves the database schema itself untouched -- only rows are removed"). |
| **B. Add both calls to `ResetDataTile._confirmAndReset`** (**chosen**) | `ResetDataTile` already documents itself as the orchestration layer for exactly this class of problem: its doc comment already carves out `settingsProvider` invalidation as something `resetAppData` intentionally leaves to its caller. `authGatewayProvider` and `notificationSchedulerProvider` are both already `Provider`s reachable via the widget's own `ref` — no new plumbing. `data_reset_test.dart` stays untouched. |
| C. A new `ResetService` class wrapping all three | Real for a bigger ticket, but three lines of orchestration behind a new class is one indirection this ticket doesn't need — YAGNI. |

**Decision: B.** `resetAppData` stays DB-only; `ResetDataTile` gains the two
calls, matching its existing `settingsProvider`-invalidation precedent.

**Ordering: cancel digest → sign out → wipe → invalidate `settingsProvider`.**
The two new steps are independent of each other and of the wipe (the digest
notification lives in the OS notification plugin, the Supabase session lives
in `supabase_flutter`'s own storage — neither touches `AppDatabase`), so
there is no *technical* ordering requirement between them. What matters is
that both complete, best-effort, before the tile's async function returns
(so that by the time the user can act again — e.g. tapping *Join* on the now
reactively-shown welcome screen — the session is already gone). They are
placed *before* `resetAppData` and each wrapped in its own `try`/`catch` so
that a network hiccup signing out, or an OS-plugin hiccup cancelling a
notification, can never prevent the wipe itself from running — the
double-confirmed delete is the one promise in this flow that must always be
kept. `resetAppData` and the subsequent `ref.invalidate(settingsProvider)`
are deliberately left un-wrapped, unchanged from today: a failure there is a
real bug, not an expected runtime condition, and should surface (crash) same
as it does today rather than be silently swallowed.

**Is calling `authGateway.signOut()` safe when already signed out?**
Yes, and this matters because Reset is reachable from a signed-out-but-linked
device too (field-feedback A1's `_SignedOutLinkedSection`). `NoopAuthGateway.
signOut()` is an unconditional no-op. `SupabaseAuthGateway.signOut()` calls
through to `_client.auth.signOut()`; the call is wrapped in the same
`try`/`catch` as the linked-but-signed-in case regardless, so even a version
of `supabase_flutter` that throws on a missing session degrades to a no-op
here, not a blocked reset. No conditional "only sign out if currently signed
in" check is needed in `ResetDataTile` — always calling `signOut()`
unconditionally is simpler and exactly as safe.

**Confirm copy: checked in both variants, one gap found and fixed.**
- **Linked variant** (`settingsResetConfirm1BodyLinked`) — this is the
  string the P3 audit finding quotes as false ("You can reconnect by signing
  in again"). Once this plan lands, it becomes literally true: the code now
  actually signs out, and the household really does stay on the server for a
  linked device. **No copy change needed** — the existing string already
  says the right thing; the code was the thing that was wrong.
- **Unlinked variant** (`settingsResetConfirm1Body`) — shown whenever
  `settings.syncHouseholdId` is `null`, which conflates two real states:
  truly-local (never touched auth) and signed-in-but-not-yet-linked (mid
  P2b/P2c adopt-or-join choice in `AccountSectionBody`, reachable from the
  same Settings screen). The existing copy never mentions an account at all,
  so a user in the second state who resets is not told their session is
  about to end. Fix: append one unconditional sentence that is true in both
  sub-cases ("If you're signed in, this also signs you out of this phone.")
  rather than forking a third dialog variant — cheaper, and correct for
  users who were never signed in too (a true statement that just doesn't
  apply to them, same pattern as "if you have a card on file..." copy
  elsewhere). Task 2 makes this change in both `app_en.arb` and
  `app_de.arb`.

## Global Constraints

- Every user-visible string goes through gen_l10n: add/edit in
  `lib/l10n/app_en.arb` (template) AND `lib/l10n/app_de.arb` (du-form).
  Never inline English. `pubspec.yaml` has `generate: true`, so
  `flutter test`/`flutter run` regenerate `app_localizations.dart`
  automatically — no separate `flutter gen-l10n` step.
- Every interactive widget needs a stable `semantic()` id — this plan adds
  no new widgets, so no new ids are needed.
- Widget tests are integration-style: real in-memory `AppDatabase` + fixed
  clock, overriding ONLY `appDatabaseProvider`/`clockProvider` plus
  documented seams — here, `authGatewayProvider` (fake at
  `test/features/settings/fake_auth_gateway.dart`) and
  `digestNotificationPluginProvider` (fake at
  `test/application/fake_digest_notification_plugin.dart`), both
  already-established seams. Never mock repositories or services.
- Strict lints (`very_good_analysis`, `--fatal-infos`); public members need
  doc comments.
- TDD: write failing test → run → implement → run → commit.
- Never run destructive git operations; create plain commits, no
  `Co-Authored-By` trailers (repo-wide convention already in effect).

---

## Task 1: `ResetDataTile` signs out and cancels the digest

**Files:**
- Modify: `lib/features/settings/reset_flow.dart:58-75` (`_confirmAndReset`)
- Modify: `lib/application/data_reset.dart` (doc comment only — no behavior
  change)
- Test: `test/features/settings/reset_flow_test.dart`

**Interfaces:**
- Consumes: `authGatewayProvider` (`Provider<AuthGateway>`,
  `lib/app/providers.dart:217`), whose `AuthGateway.signOut()` returns
  `Future<void>`. `notificationSchedulerProvider`
  (`Provider<NotificationScheduler>`, `lib/app/providers.dart:423`), whose
  `NotificationScheduler.cancelDigest()` returns `Future<void>`
  (`lib/application/notification_scheduler.dart:234-237`). Both already
  imported transitively via `package:chore_app/app/providers.dart`, already
  imported in `reset_flow.dart:14`.
- Produces: no new public symbols; `_confirmAndReset`'s external behavior
  (still `Future<void>`, still gated by the same two confirm dialogs) is
  unchanged from the caller's perspective.

- [ ] **Step 1: Write the failing test for sign-out**

Add to `test/features/settings/reset_flow_test.dart`, after the existing
imports add:

```dart
import 'package:chore_app/application/auth_gateway.dart';

import '../../application/fake_digest_notification_plugin.dart';
import 'fake_auth_gateway.dart';
```

(These go alongside the existing `import '../../test_utils/pump_app.dart';`
and `import 'settings_test_utils.dart';` lines at the top of the file.)

Then add this test, anywhere after the existing four `testChoreApp` blocks.
Note the `fakeAuth` variable is declared OUTSIDE the `testChoreApp` call (at
`main()`'s top level) and referenced from inside the test body afterwards —
the exact pattern `test/features/chores/digest_preprompt_banner_test.dart`
already uses for its `FakeDigestNotificationPlugin` (`dismissPlugin`/
`enablePlugin`), so the fake instance passed to `overrideWithValue` is the
same instance the assertions read back from:

```dart
  final fakeAuth = FakeAuthGateway(
    currentUser: const AuthUser(id: 'u1', email: 'me@example.com'),
  );
  testChoreApp(
    'confirming both dialogs signs out the current user (spec '
    'docs/feedback/2026-08-08-prerelease-audit.md P3): Reset is the '
    'opposite of Disconnect, which deliberately keeps the session',
    today: today,
    overrides: [authGatewayProvider.overrideWithValue(fakeAuth)],
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await openSettingsTab(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.reset'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('settings.reset.confirm1'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('settings.reset.confirm2'));
      await tester.pumpAndSettle();

      expect(fakeAuth.currentUser, isNull);

      handle.dispose();
    },
  );
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/settings/reset_flow_test.dart`
Expected: the new test FAILS with `fakeAuth.currentUser` still equal to
`const AuthUser(id: 'u1', email: 'me@example.com')` (sign-out never
happened) — every other test in the file still passes.

- [ ] **Step 3: Write the failing test for digest cancellation**

Add a second test to the same file, using the same fake-instance-declared-
outside-the-call pattern as Step 1:

```dart
  final fakePlugin = FakeDigestNotificationPlugin();
  testChoreApp(
    'confirming both dialogs cancels the scheduled digest notification '
    '(spec docs/feedback/2026-08-08-prerelease-audit.md P3)',
    today: today,
    overrides: [
      digestNotificationPluginProvider.overrideWithValue(fakePlugin),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await openSettingsTab(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.reset'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('settings.reset.confirm1'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('settings.reset.confirm2'));
      await tester.pumpAndSettle();

      expect(fakePlugin.cancelCallCount, greaterThanOrEqualTo(1));

      handle.dispose();
    },
  );
```

Import `digestNotificationPluginProvider` — it's exported from
`package:chore_app/app/providers.dart`, already imported.

- [ ] **Step 4: Run the tests to verify they fail**

Run: `flutter test test/features/settings/reset_flow_test.dart`
Expected: the digest-cancellation test FAILS with `cancelCallCount` equal to
`0`.

- [ ] **Step 5: Implement sign-out and digest cancellation in `ResetDataTile`**

In `lib/features/settings/reset_flow.dart`, replace `_confirmAndReset` and
add two new private methods:

```dart
  Future<void> _confirmAndReset(
    BuildContext context,
    WidgetRef ref, {
    required bool linked,
  }) async {
    final firstConfirmed = await _showFirstDialog(context, linked: linked);
    if (!firstConfirmed || !context.mounted) {
      return;
    }
    final secondConfirmed = await _showSecondDialog(context);
    if (!secondConfirmed || !context.mounted) {
      return;
    }

    // Two side effects that live OUTSIDE the database transaction
    // resetAppData wipes (spec docs/feedback/2026-08-08-prerelease-audit.md
    // P3): the scheduled digest notification, and -- unlike Disconnect
    // (household_link_service.dart's deliberate keep-the-session inverse
    // of this action) -- the Supabase session itself. Reset is the "clean
    // slate" operation: double-confirmed, and the one most likely to be
    // used right before handing a phone to someone else, so a surviving
    // session for the previous account is the wrong default here, unlike
    // for Disconnect. Both run BEFORE the wipe and are individually
    // best-effort (wrapped below): a network hiccup signing out, or an OS
    // plugin hiccup cancelling a notification, must never block the wipe
    // itself -- the double-confirmed delete is the one promise in this
    // flow that must always be kept.
    await _cancelDigest(ref);
    await _signOut(ref);

    final database = ref.read(appDatabaseProvider);
    await resetAppData(database);
    ref.invalidate(settingsProvider);
  }

  /// Cancels the scheduled digest notification, if any. Best-effort: see
  /// the doc comment in [_confirmAndReset] on why a failure here must
  /// never block the wipe that follows.
  Future<void> _cancelDigest(WidgetRef ref) async {
    try {
      await ref.read(notificationSchedulerProvider).cancelDigest();
    } on Exception {
      // Best-effort -- see doc comment above.
    }
  }

  /// Signs out of the current Supabase session, if any. Safe to call
  /// unconditionally even when already signed out (spec's analysis:
  /// `NoopAuthGateway.signOut()` is a no-op; `SupabaseAuthGateway.
  /// signOut()` is wrapped the same way regardless). Best-effort: see the
  /// doc comment in [_confirmAndReset] on why a failure here must never
  /// block the wipe that follows.
  Future<void> _signOut(WidgetRef ref) async {
    try {
      await ref.read(authGatewayProvider).signOut();
    } on Exception {
      // Best-effort -- see doc comment above.
    }
  }
```

Also update the class-level doc comment (currently lines 22-37) to mention
the new behavior. Replace the sentence "Only after both confirms does it
call `resetAppData` and invalidate `settingsProvider`" with:

```dart
/// Only after both confirms does it cancel the scheduled digest
/// notification, sign out of the current Supabase session (spec
/// `docs/feedback/2026-08-08-prerelease-audit.md` P3 -- unlike the A1.2
/// Disconnect action in `account_section.dart`, which deliberately keeps
/// the session and only unlinks the device, Reset is the clean-slate
/// operation and ends it), call [resetAppData], and invalidate
/// [settingsProvider]
```

- [ ] **Step 6: Add the scoping doc comment to `resetAppData`**

In `lib/application/data_reset.dart`, extend the existing doc comment on
`resetAppData` (after the paragraph ending "...was also just deleted out
from under its already-running watch stream.") with:

```dart
///
/// Deliberately does not touch the Supabase session or the scheduled
/// digest notification -- both are the caller's responsibility
/// (`ResetDataTile._confirmAndReset` in production, spec
/// `docs/feedback/2026-08-08-prerelease-audit.md` P3), the same pattern
/// this function already follows for `settingsProvider` invalidation.
/// Keeping this function DB-only means its own tests
/// (`test/application/data_reset_test.dart`) never need an `AuthGateway`
/// or `NotificationScheduler` fake.
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `flutter test test/features/settings/reset_flow_test.dart`
Expected: all 6 tests PASS (the 4 pre-existing ones plus the 2 new ones).

Run: `flutter test test/application/data_reset_test.dart`
Expected: both pre-existing tests still PASS unchanged (this file was not
modified, confirming Step 6 was doc-only).

- [ ] **Step 8: Commit**

```bash
git add lib/features/settings/reset_flow.dart lib/application/data_reset.dart test/features/settings/reset_flow_test.dart
git commit -m "Sign out and cancel the digest when resetting app data"
```

---

## Task 2: Fix the unlinked confirm copy to mention sign-out

**Files:**
- Modify: `lib/l10n/app_en.arb` (`settingsResetConfirm1Body` + its `@`
  description, around line 1374)
- Modify: `lib/l10n/app_de.arb` (`settingsResetConfirm1Body`, around line
  300)
- Test: `test/features/settings/reset_flow_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: `AppLocalizations.settingsResetConfirm1Body` (existing getter,
  generated from the `.arb` files by `gen_l10n` — signature unchanged, only
  the returned string content changes), already read at
  `lib/features/settings/reset_flow.dart:91`.

- [ ] **Step 1: Write the failing test**

Add to `test/features/settings/reset_flow_test.dart`:

```dart
  testChoreApp(
    'unlinked device: the first dialog also states that an active '
    "session ends too (spec docs/feedback/2026-08-08-prerelease-audit.md "
    'P3 -- the copy used to never mention an account at all, even though '
    'Reset is reachable while signed in but not yet linked, e.g. mid the '
    'P2b/P2c adopt-or-join choice)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await openSettingsTab(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.reset'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining("If you're signed in, this also signs you out"),
        findsOneWidget,
      );

      handle.dispose();
    },
  );
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/settings/reset_flow_test.dart`
Expected: the new test FAILS — no such text exists yet.

- [ ] **Step 3: Update the English copy**

In `lib/l10n/app_en.arb`, replace:

```json
  "settingsResetConfirm1Body": "This permanently deletes your household, members, chores, and shopping list. There is no cloud backup -- this can't be undone.",
  "@settingsResetConfirm1Body": {
    "description": "Body of the first reset confirmation dialog on an UNLINKED device, stating the deletion is permanent and there is no cloud copy (spec docs/specs/polish-round-1.md B2)."
  },
```

with:

```json
  "settingsResetConfirm1Body": "This permanently deletes your household, members, chores, and shopping list. There is no cloud backup -- this can't be undone. If you're signed in, this also signs you out of this phone.",
  "@settingsResetConfirm1Body": {
    "description": "Body of the first reset confirmation dialog on an UNLINKED device, stating the deletion is permanent, there is no cloud copy, and (spec docs/feedback/2026-08-08-prerelease-audit.md P3) any active session on this phone ends too (spec docs/specs/polish-round-1.md B2)."
  },
```

- [ ] **Step 4: Update the German copy**

In `lib/l10n/app_de.arb`, replace:

```json
  "settingsResetConfirm1Body": "Damit löschst du deinen Haushalt, alle Mitglieder, Aufgaben und die Einkaufsliste endgültig. Es gibt keine Cloud-Sicherung – das lässt sich nicht rückgängig machen.",
```

with:

```json
  "settingsResetConfirm1Body": "Damit löschst du deinen Haushalt, alle Mitglieder, Aufgaben und die Einkaufsliste endgültig. Es gibt keine Cloud-Sicherung – das lässt sich nicht rückgängig machen. Falls du angemeldet bist, wirst du dabei auch auf diesem Gerät abgemeldet.",
```

(du-form, matching the rest of the file; leave every other line in
`app_de.arb` untouched.)

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/features/settings/reset_flow_test.dart`
Expected: all 7 tests PASS (the 6 from Task 1 plus this one). Also re-run
the pre-existing "linked device" test in this same run and confirm it still
passes unchanged — it asserts the *linked* body's exact text and that the
unlinked "There is no cloud backup" substring is absent when linked, neither
of which this task touches.

- [ ] **Step 6: Commit**

```bash
git add lib/l10n/app_en.arb lib/l10n/app_de.arb test/features/settings/reset_flow_test.dart
git commit -m "State in the reset confirm dialog that an active session ends too"
```

---

## Task 3: Update the binding spec

**Files:**
- Modify: `docs/specs/polish-round-1.md` (§B2)

**Interfaces:**
- Consumes: nothing (documentation only).
- Produces: nothing (documentation only).

- [ ] **Step 1: Add the new behavior to §B2**

In `docs/specs/polish-round-1.md`, the `### B2. Reset app data (G9)`
section currently ends with:

```
- Confirmed: inside one transaction delete ALL rows from every table
  (FK-safe order: occurrences, assignees, chores, shopping items,
  categories, members, settings, households), then re-run bootstrap
  (invalidate `bootstrapProvider`) so the app lands in the fresh-install
  state (including the A2 banner — the flags live in the deleted
  settings row, which is exactly right).
```

Append a new bullet directly after it:

```
- Confirmed also cancels the scheduled digest notification and signs out
  of the current Supabase session, if any (spec
  `docs/feedback/2026-08-08-prerelease-audit.md` P3) — both best-effort,
  run before the wipe, and never blocking it. This is the deliberate
  opposite of the A1.2 Disconnect action (spec
  `docs/feedback/2026-08-07-field-feedback.md` A1), which keeps the
  session and only unlinks the device: Reset is the clean-slate operation,
  Disconnect is the "keep working, just not with this household" one.
```

- [ ] **Step 2: Commit**

```bash
git add docs/specs/polish-round-1.md
git commit -m "Document that Reset app data signs out and cancels the digest"
```

---

## Self-review

- **Spec coverage:** all four scope bullets from the ticket are covered —
  sign-out placement/justification (Task 1, Analysis), digest cancellation
  (Task 1), confirm-copy re-check in both variants (Analysis; fix in Task
  2), and the Disconnect-vs-Reset contrast (code comments in Task 1 Step 5,
  spec bullet in Task 3).
- **Placeholder scan:** no TBD/"add appropriate"/elided code — every step
  shows complete, exact code or exact `.arb` text.
- **Type consistency:** `_cancelDigest`/`_signOut` both take `WidgetRef` and
  return `Future<void>`, matching how they're awaited in `_confirmAndReset`;
  `FakeAuthGateway.currentUser` and `FakeDigestNotificationPlugin.
  cancelCallCount` are both read directly off the same fake instance passed
  to `overrideWithValue` (the `fakeAuth`/`fakePlugin` variables declared
  outside each `testChoreApp` call), matching those classes' existing
  public fields and the established pattern in
  `test/features/chores/digest_preprompt_banner_test.dart` (verified
  against `test/features/settings/fake_auth_gateway.dart` and
  `test/application/fake_digest_notification_plugin.dart`).

## Open product decisions

None. Every choice above (orchestration location, ordering, the
unconditional-`signOut()` safety argument, and the copy fix) was resolvable
from the existing code and specs without needing a call only Igor could
make.
