# A-2b — keep the Settings "Last synced" text fresh while the screen is open

**Row:** `docs/backlog.md` A-2b (and the A-2 scoping note that filed it).
**Written:** 2026-08-28, against the tree at `wave5/small-items` after merging
`integration/wave-5` (C-2 slice 5 landed in `account_section.dart`).

## 1. The problem

`Settings → Account` renders a relative `Last synced …` line under the
linked-household subtitle (spec `docs/specs/sync-freshness.md` §2.4). Its text
is computed from `ref.watch(clockProvider).now()`, and `clockProvider` is a
plain `Provider` that never re-emits. Nothing else in the subtree changes
either — `settingsProvider` only re-emits when the cursor is actually written.
So the line is correct exactly once, at the moment the tile is built, and then
freezes: a Settings screen left open for twenty minutes still says
"Last synced 10 minutes ago".

This is the same class of bug as A-2 (date-derived UI never rolling over at
midnight), and A-2 deliberately left it out: it needs a timer, and this project
has a documented "a Timer is still pending" hazard.

## 2. What was verified before designing (three claims, two of them stale)

### 2.1 `flutter_test`'s pending-timer check runs *after* the tree is unmounted

`todayProvider`'s doc comment in `lib/app/providers.dart` states:

> `flutter_test`'s "a Timer is still pending" leak check runs before the pumped
> tree is torn down — a provider-armed timer would therefore fail every widget
> test that renders the chores list.

**The second half of that is true for `todayProvider` for a different reason,
but the stated mechanism is wrong.** Read
`/opt/homebrew/share/flutter/packages/flutter_test/lib/src/binding.dart`
(`TestWidgetsFlutterBinding._runTest`, ~line 1952):

```dart
await testBody();
asyncBarrier();
if (_pendingExceptionDetails == null) {
  runApp(Container(key: UniqueKey(), child: _postTestMessage)); // Unmount any remaining widgets.
  await pump();
  ...
  _verifyInvariants();      // <- AutomatedTestWidgetsFlutterBinding's override
}                           //    is what counts pendingTimers (~line 2523)
```

The tree — including the `ProviderScope` — is unmounted by that `runApp` +
`pump()` **before** `_verifyInvariants()` counts `FakeAsync`'s pending timers.
The assertion message ("*even after* the widget tree was disposed") says the
same thing. So a timer that is genuinely cancelled on disposal — from
`State.dispose()` or from `ref.onDispose` — is **not** a leak-check failure.
What fails the check is a timer nothing owns, or one owned by something the
teardown does not dispose.

Consequence for this task: a widget-local timer cancelled in `dispose()` is
legitimate here, and does not need the precedent's "never armed in tests"
escape hatch (`syncHealthStatusProvider`, `lib/app/providers.dart` ~541) —
which is fortunate, because that escape hatch does not apply. This surface
*is* exercised: `test/features/settings/account_last_synced_test.dart` renders
this exact line with a 10-minute-old cursor, so any always-armed ticker exists
during that test. It must therefore be *disposed*, not *avoided*.

**This is the crux of the row and the one thing that could still be wrong.** It
is settled by CI, not by argument: if the leak check did fire, it would fire in
`account_last_synced_test.dart` and in the new ticker test, and the RED in step
5 below would name pending timers instead of a stale string. Contingency if
that happens: keep the widget, move the tick to a `Provider` seam the ticker
test overrides, and document it — do **not** touch
`account_last_synced_test.dart`, whose assertions are the reason this row
exists.

### 2.2 The Settings tab is **not** built for every widget test

`lefthook.yml`'s `test` job comment (lines 48-56) says "`AppShell`'s
`IndexedStack` builds the Settings tab's Account section for every single
widget test regardless of which tab it navigates to". **Stale since wave 3.**
`lib/app/app_shell.dart` builds the three tabs as a lazy `PageView` (D-1), with
`allowImplicitScrolling` left false — deliberately, per that file's own comment,
because true "widens the viewport's cache extent so the neighbouring page is
laid out". `PageView` passes `cacheExtent: allowImplicitScrolling ? 1.0 : 0.0`
with `CacheExtentStyle.viewport`, so only the visible page is built at all. The
wave-4 handover §4 records the same staleness in another plan ("*it asserted the
shell is an `IndexedStack`* … false since wave 3").

Two consequences: the `SUPABASE_*` dart-defines are still required (any test that
*opens* Settings would construct a live gateway), but the ticker only exists in
tests that actually open the Settings tab — a much smaller set than "every
widget test". The stale comment is corrected as part of this task, since it is a
comment about precisely the mechanism this design depends on.

### 2.3 Tick granularity follows the formatter's bands

`_lastSyncedText` (`account_section.dart` ~244) has four bands: `< 1 min` →
"just now"; `< 1 h` → whole **minutes**; `< 24 h` → whole **hours**; otherwise
`DateFormat.MMMEd(lastPulledAt)` — a **fixed calendar date that never changes
again**. So a constant one-second ticker would be pure waste and a constant
one-minute ticker would still wake 1 380 times a day for nothing. The right
schedule is boundary-aligned and band-derived:

| elapsed | next visible change | wake at |
| --- | --- | --- |
| `< 1 h` | the minute count increments | `lastPulledAt + (elapsed.inMinutes + 1) min` |
| `< 24 h` | the hour count increments | `lastPulledAt + (elapsed.inHours + 1) h` |
| `>= 24 h` | never | **no timer at all** |
| cursor `null` | nothing is rendered | **no timer at all** |

Worst case: 60 wakes in the first hour, 23 more that day, then silence.

## 3. Design

A new file, `lib/features/settings/last_synced_line.dart`, holding a
`LastSyncedLine` `ConsumerStatefulWidget` plus the `_lastSyncedText` formatter
moved out of `account_section.dart`. `account_section.dart` keeps a one-line
hook. This shape is chosen over an in-place `StatefulWidget` conversion of
`_SignedInTile` specifically to keep the diff to `account_section.dart` small —
it is being edited concurrently by C-2 slice 6 — and it is also the better
shape: the ticker's lifetime becomes exactly the lifetime of the line it feeds.

- `build` reads `settingsProvider.valueOrNull?.syncLastPulledAt`. `null` →
  `SizedBox.shrink()`, **no semantics node** (so the existing
  `findsNothing` assertion in `account_last_synced_test.dart` still holds) and
  no timer.
- Otherwise it renders today's exact widget —
  `semantic('settings.account.lastSynced', child: Text(...))` — and arms a
  **one-shot** `Timer` for the next boundary, whose callback `setState`s. The
  next `build` re-arms.
- Re-arming is keyed on the absolute deadline, not on "every build": the
  deadline is a pure function of `(lastPulledAt, elapsed band)`, so unrelated
  rebuilds (theme, locale, a settings write) recompute the *same* deadline and
  leave the running timer alone. Without that, a subtree rebuilding every 59 s
  would postpone the tick indefinitely.
- A negative delay (deadline already passed — reachable via clock skew, or a
  `lastPulledAt` in the future written by another device) is clamped to one
  minute rather than scheduled at zero. A zero/negative `Timer` would fire
  inside the same frame and spin.
- `dispose()` cancels. That is what makes it safe under §2.1.

Why not the `syncHealthStatusProvider` precedent (a self-invalidating
provider)? It would work, but it puts a timer in the global provider graph for a
surface that is one line on one screen, and it survives the screen. The widget
owns the only thing that reads it.

Known and accepted: `_KeepAlivePage` keeps a visited tab alive, so the ticker
keeps running (once a minute, one `Text` rebuild) while the user is on another
tab, until the screen leaves the tree. Both platforms suspend or throttle Dart
timers for a backgrounded app, and the work per wake is a string format, so this
is not worth a lifecycle observer.

## 4. Riverpod note (the wave-4 trap this row could have fallen into)

Nothing here depends on a provider recomputing. The binding constraint — an
equal `AsyncData` re-emission is correctly no change — is exactly why the ticker
must own its own trigger, and it does: `setState`, from a timer, with no
provider involved. `settingsProvider` remains the (independent, correct) trigger
for the *cursor* changing.

## 5. Tasks

1. **(doc)** This plan.
2. **(RED)** `test/features/settings/account_last_synced_ticker_test.dart`:
   - `testChoreApp` with `clock: Clock(() => currentTime)` over a file-scope
     mutable `currentTime` — the seam `pump_app.dart` already documents for
     "now" actually moving, precedent
     `test/features/chores/day_rollover_widget_test.dart`. **This is the answer
     to "the clock is fixed in tests, so how can the text change at all":
     without it the test would be vacuous by construction.**
   - Seed linked + `setSyncLastPulledAt(08:50)` with `today` 09:00, open
     Settings, assert "Last synced 10 minutes ago".
   - Capture the `State` object of `LastSyncedLine` (State **identity**, not
     findability — the `AutomaticKeepAliveClientMixin` constraint).
   - Move `currentTime` forward to 09:15. **Write nothing to the database,
     invalidate no provider, pump no new tree.**
   - `await tester.pump(const Duration(minutes: 1))` — advances `FakeAsync`,
     which is the only thing that can fire the ticker.
   - Assert the rendered text is now "Last synced 25 minutes ago", the old text
     is gone, and the `State` object is **the same instance** (so the update
     came from inside the live widget, not from a remount).
   - Second case: the minutes→hours band crossing (59 min → 61 min renders
     "Last synced 1 hour ago"), which proves the re-arm after a band change and
     pins the pluralized one-hour form.
   - Expected RED: both cases fail on the *assertion after the pump*, still
     finding the pre-move string.
3. **(GREEN)** `lib/features/settings/last_synced_line.dart` per §3; hook it
   into `account_section.dart` (delete the computation and the conditional in
   `_SignedInTile.build`, delete `_lastSyncedText` and the now-unused
   `package:intl/intl.dart` import).
4. **(inversion)** Neuter the re-arm *inside* the widget's method (return no
   deadline for the minutes band) — not by deleting the widget, which would fail
   at `analyze` and never run the tests — and confirm CI goes red at the **test**
   step. Revert with `git revert` (never force-push).
5. Correct `lefthook.yml`'s stale `IndexedStack` comment (§2.2).
6. Close A-2b in `docs/backlog.md` in the A-7/G-12/A-3b house style: strike the
   title, `**CLOSED 2026-08-28**`, what the fix is, and the original wording
   preserved after `Was:`.

## 6. Files

- `lib/features/settings/last_synced_line.dart` (new)
- `lib/features/settings/account_section.dart` (minimal: two small deletions and
  a one-line hook, all inside the last-synced region)
- `test/features/settings/account_last_synced_ticker_test.dart` (new)
- `lefthook.yml` (comment only), `docs/backlog.md`, this plan

No l10n change: all four band strings already exist in both locales with ICU
plurals. No migration. No spec change — §2.4 describes a relative line and says
nothing that this contradicts.
