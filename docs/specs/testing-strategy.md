# Spec: Testing Strategy

*Goal: every user-facing interaction is tested in its happy path AND its
failure/edge paths. The layer where each path is tested is chosen
deliberately — exhaustive combinations live in fast deterministic tests,
full journeys and everything that needs the real stack live in E2E.*

## 1. The layers and what belongs where

| Layer | Tool | What it must cover |
|---|---|---|
| Unit | `flutter test` | All pure logic, exhaustively: recurrence math, rotation, filter/sort, suggestion ranking. Every edge case enumerable in code lives here. |
| Widget | `flutter test` | Every screen/component in isolation: all validation messages, empty states, loading states, error states, long-content truncation, both themes, text scale 1.0 & 2.0. |
| Integration (backend) | Supabase local (`supabase start`) + SQL/pgTAP | RLS isolation (family A can never read family B — tested per table, per operation), invite-code lifecycle, conflict behavior on concurrent writes. |
| E2E | Maestro on Android emulator + iOS simulator | Full user journeys through the real app + real local backend, including the non-happy paths listed in §3. |

Rule of thumb: if a case can be expressed at a lower layer, it MUST be
(speed, determinism) — and E2E then covers the journey that strings the
cases together, not the combinatorics.

## 2. Design-for-testability requirements (bind the app code, from day one)

1. **Stable semantic identifiers on every interactive widget.**
   Convention: `Semantics(identifier: '<screen>.<element>')`, e.g.
   `chore_form.save`, `chore_list.item.<id>.complete`. Maestro selectors use
   ONLY these — never display text (survives copy changes and localization).
   A lint-adjacent CI grep forbids `text:` selectors in flows except for
   asserting visible copy.
2. **Controllable clock.** All "today"/"now" reads go through an injectable
   `Clock` abstraction; a debug/E2E build flag (`--dart-define=E2E=true`)
   exposes a test hook to set the app date. Without this, recurrence E2E
   ("complete → next occurrence appears on the right day") is untestable
   deterministically. Also enables DST-boundary E2E runs.
3. **Seedable, resettable backend.** E2E always runs against local Supabase.
   Every flow starts with a scripted DB reset + named seed fixture
   (`seeds/one_family_three_chores.sql`, …). No test depends on state left
   by another; flows are order-independent and individually re-runnable.
4. **Deterministic animations.** E2E build flag disables shimmer/staggered
   animations that cause screenshot/timing flakiness.
5. **No sleeps.** Flows wait on visible state (`assertVisible` with timeout),
   never fixed delays.

## 3. E2E non-happy-path catalog (minimum, per feature)

Every feature flow ships with its happy path PLUS, as applicable:

- **Form validation**: for each form — every invalid field state (empty
  title, interval 0 / negative / non-numeric, weekly with no weekday when
  required, invalid invite code format) → error visible, submit blocked,
  valid input afterwards succeeds (recovery, not just rejection).
- **Auth/session**: expired/invalid magic link → clear error + retry path;
  sign-out mid-session → protected screens unreachable.
- **Household**: wrong invite code → error; joining twice → idempotent;
  leaving a household → data no longer visible.
- **Offline** (Android emulator: Maestro airplane-mode toggle): add chore,
  complete chore, add shopping items offline → visible "pending sync"
  indicator → reconnect → synced, no duplicates, no loss. App cold-starts
  offline and shows cached data, not a spinner or crash.
  (iOS simulator can't toggle connectivity reliably — offline suite runs on
  Android; iOS gets the cold-start-offline case via network-blocked launch.)
- **Permissions**: notification permission DENIED → app fully usable, digest
  toggle shows "enable in settings" hint. Granted-then-revoked handled.
- **Process death**: kill app mid-form and mid-sync → relaunch → no crash,
  no data corruption, drafts/pending ops behave as specced.
- **Empty & extreme states**: fresh account, empty lists (every list's empty
  state), 200-item shopping list scroll smoke, 40-char chore names.
- **Concurrency (2 sessions)**: same account on two simulators — complete a
  chore on A → appears completed on B; simultaneous check-off of the same
  shopping item → exactly one completion recorded, no crash on either.
- **Recurrence journeys** (using the clock hook): schedule-anchored chore
  completed late → missed slots skipped; completion-anchored chore →
  next due shifts from completion day; DST transition day → due dates stable.

## 4. Suite mechanics

- **Structure**: `e2e/flows/<feature>/<case>.yaml` with shared subflows in
  `e2e/common/` (launch-seeded, login, reset-db). Tags: `happy`, `error`,
  `edge`, `slow`.
- **CI cadence**: Android emulator suite on every push (Linux runner, KVM);
  iOS simulator suite on main + nightly (macOS runner cost). Nightly also
  runs the `slow` tag and the 2-session concurrency suite.
- **Flake policy: zero.** A flaky test is a P1 bug: quarantine tag
  (max age: one week) → fix or delete. Retries exist only to *detect* flakes
  (a pass-on-retry is reported as failure-of-policy, not success).
- **Coverage accounting**: each feature spec (docs/specs/*) must list its
  interaction inventory; PR review checks the matrix — every interaction has
  happy + error coverage at some layer, and the layer is named. "Untested
  interaction" is a review blocker, same severity as a failing check.

## 5. Order of adoption

Maestro + the E2E build flag + clock hook + seed/reset scripts land with the
FIRST screen (app shell), not after features accumulate — retrofitting
testability is how apps end up with happy-path-only suites.
