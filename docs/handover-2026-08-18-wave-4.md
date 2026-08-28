# Handover: what shipped in v0.7.0 (wave 4)

*Written 2026-08-18 by the agent that orchestrated wave 4, for whoever scopes
the next one. Every claim here was verified against source, CI output, or a
device at the time of writing; where it wasn't, it says so.*

---

## 1. Where things stand

**v0.7.0 (build 10) is released** —
https://github.com/igorzamyslov/chore-app/releases/tag/v0.7.0, signed APK
attached. `main` is at `99029e1`. Schema is at **v12**. 999 tests.

`v0.6.0..v0.7.0` is 103 files, +10379/-1830, across nine plans.

**All four CI jobs are green on `main` at the release commit:** `checks`
(format + `analyze --fatal-infos` + full suite), `android` (Maestro E2E),
`pgtap`, and — for the first time on wave-4 code — **`ios`**.

That `ios` pass also settles the flake recorded as **A-6**: the two failures
seen at `625ea72` (`language_override`, `done_today_reopen`, both on
`welcome.create is visible`) did not reproduce. A-6 stays open because its
substantive point is unchanged — `ios` is gated on `refs/heads/main` and never
runs on a PR, so its failures are always discovered after merge.

---

## 2. What shipped

| Row | What landed |
| --- | --- |
| **B-1** | `catchUpOverdue` returns how many chores it moved, and a self-hiding banner says so. A banner, not a snackbar: four seconds is too thin to de-escalate something that reads as an accusation. Copy closes on the at-most-one-overdue-occurrence-per-chore invariant, which is the fact that actually de-escalates. Neither locale contains "missed" or "failed". |
| **B-3** | The join subpage reopens when a signed-in user lands on the welcome screen with no household, and the last server-accepted code is prefilled from the new `settings.pendingJoinCode`. **Schema v12.** |
| **B-5** | Two ambient signals for a denied notification permission: a factual sub-line on the digest row when the toggle is ON but the OS permission is denied, and a dot on the Settings tab. Both clear themselves on grant or on switching the digest off. A fresh install stays silent — the dot also requires `digestPrepromptShownAt != null`, because a permission never *requested* reads identically to a denied one on iOS and Android 13+. |
| **D-2 / D-3** | Swipe-left-to-delete (`endToStart` only) and a long-press menu on shopping rows. Both reach the same `deleteShoppingItemWithUndo` the edit sheet already used. |
| **D-5** | A non-dismissible `secondaryContainer` banner on both list screens when this device hasn't reached the household. Names pull-to-refresh, no tap target, and never says "offline" — the honest framing is "unsent changes", not a connectivity verdict the app cannot make. Thresholds are named constants (5 min / 3 min) with rationale in `sync-freshness.md` §2.5. |
| **E-1..E-5** | Channel name through l10n on a new id `digest_v2` (legacy `digest` deleted); startup-error escape hatch plus the extracted `confirmTwoStepDestructiveAction`; the privacy disclosure above the sign-in field; `Recurrence` `==`/`hashCode`; pubspec description. |
| **F-1** | Mark a chore done from the digest notification. "Done" only. |
| **C-2 (part)** | The `exit_confirm_sheet` overflow fix, the three exit RPCs, `MemberService.deleteMember` routing by claim state, and `syncRefreshErrorRevoked`. **Slices 5-6 are NOT in.** |

### Two fixes nobody asked for, found while in the area

- **The digest ignored the in-app language override.** `notification_scheduler`
  resolved locale from `PlatformDispatcher.instance.locale` while the UI honours
  `localeOverrideProvider`, so German-in-app on an English phone already got
  English digest notifications. Fixed under E-1 and proven by inversion
  (`Expected: '1 Aufgabe heute' / Actual: '1 chore today'`). The resolver is now
  a per-call closure using `read`, not `watch` — watching would rebuild the
  scheduler and drop `_initialized` and its in-flight apply queue.
- **The `exit_confirm_sheet` had a SECOND overflow.** The v0.5.0 handover flagged
  only the vertical one. The horizontal one is Cancel plus a label as long as
  "Konto löschen" not fitting 288 logical pixels at 2× text scale, which a plain
  `Row` reports as RenderFlex overflow rather than wrapping. Now an
  `OverflowBar`, matching `AlertDialog.actions`.

---

## 3. Verification status — read this before trusting anything above

**Proven on a real device:** F-1's **GATE 1**. Tapping "Done" on the digest
marks the chore done in the app (Igor, on Android, against build 10). So
`openConnection()`'s `path_provider` channel lookup DOES resolve inside a
background engine, the explicit-`QueryExecutor` fallback is unnecessary, and
Tasks 7-9 of that plan no longer rest on an unverified premise. That single tap
exercised the whole chain: payload codec across the process boundary, occurrence
resolution, attributed completion, and the `ActionBroadcastReceiver` actually
resolving in the shipped manifest.

**Proven by hand for this release, but by nothing in CI:**
- **iOS compiles.** `flutter build ios --simulator` succeeds. No PR job compiles
  Swift, so before this nothing had ever built `AppDelegate.swift`.
- **The release APK carries all three capabilities.** `aapt2` on the actual
  artifact: `INTERNET` ✓, `allowBackup=false` ✓, **`ActionBroadcastReceiver`** ✓.
  The first two are asserted fail-closed in `release.yml`; **the third is not**
  — see §6.
- **The swipe gesture works on iOS**, and the left-edge interactive-pop
  recognizer does not compete with it. Verified on a simulator.

**Still NOT verified:**
- **F-1 GATE 3** — whether the isolate survives long enough to rewrite the
  horizon. The check: a **one-off** chore actioned with the app swiped away,
  then no later notification claiming it overdue. Its fallback is to accept the
  truncation and document it, **not** to call `cancelDigest()`, which would
  trade one wrong notification for up to 83 days of silence.
- **F-1 on iOS end to end.** The AppDelegate wiring compiles and runs without
  crashing at launch; nothing beyond that.
- **D-5 cannot be E2E-tested at all** — the suite runs permanently unlinked.

---

## 4. Plan defects execution caught — the highest-value section

Every one of these was caught by an implementer or reviewer refusing to work
around a bad instruction. Assume the same rate in the next wave and plan for
the review, not just the tasks.

- **The offline-indicator plan would have shipped a feature that never fired.**
  It left recomputation to Riverpod's dependency graph, but an unreachable
  device persists nothing, so a second local write re-emits an *equal*
  `AsyncData` that Riverpod correctly treats as no change — no threshold could
  ever be observed as crossed. The plan called this "can lag a little"; it was
  "never fires". Also, measuring staleness from `syncLastPulledAt` alone would
  have flashed the banner on nearly every cold start, the exact cry-wolf failure
  the thresholds exist to prevent.
- **The notification-actions plan would have re-introduced A-5.** Its
  isolate-side "stored id, else first admin, else first member" chain is only
  `actingMemberProvider`'s *unpinned* branch; in pinned mode the real chain
  returns null rather than guessing. It also planned to recover the actioned
  occurrence from `NotificationResponse.id` — impossible, since ids are
  slot-relative and the background path substitutes `-1`. Both were fixed by a
  doc-only plan refresh **before** execution, which was worth its cost.
- **The small-fixes plan would have dropped A-4's sign-out.** Its Task 5
  instructed a wholesale replacement of `reset_flow.dart` whose replacement
  silently lost the sign-out and digest-cancel — the exact hazard
  `docs/backlog.md` had predicted for that file.
- **The shopping-gestures plan's entire Analysis section was stale** — it
  asserted the shell is an `IndexedStack` and that the shell-navigation plan
  does not exist. Both false since wave 3.
- **The join-wizard plan's auto-resume had no route guard**, so a sign-in while
  the user was already on the join page pushed a second copy over the first, and
  the single post-join pop left them on a stale page. Its prefill also read
  `settingsProvider.valueOrNull`, always `AsyncLoading` on first state, so it
  would have prefilled nothing in exactly the cold-start ordering the feature
  exists for.
- **The catch-up plan** referenced a helper the digest work had renamed, told
  the executor to restore a conditional that is now deliberately unconditional,
  and anchored on a pre-wave-3 test fixture.

**Pattern worth encoding:** every plan was written 2026-08-08. The tree moved a
long way. The two plans that were *refreshed before execution* went smoothly;
the ones executed as written each cost a round trip. Budget a refresh pass.

---

## 5. Process findings that cost real time

- **`dart format` silently uses the wrong config inside a git worktree.** No
  `.dart_tool/` ⇒ it cannot resolve `include: package:very_good_analysis/...`,
  warns to **stderr**, and falls back to `trailing_commas: automate` instead of
  the project's `preserve`. Bare `dart format .` then reflows ~93 of 255 files.
  **CI cannot catch this**, because `preserve` is *stable* on `automate`'s
  output — so `--set-exit-if-changed` passes on the churn. One agent put 85
  out-of-scope files into its branch this way, including two files other agents
  were concurrently editing. Fix: copy `.dart_tool/package_config.json` from the
  primary checkout into each worktree (gitignored, cannot be committed), or run
  `flutter pub get --enforce-lockfile`. Tracked as **A-7**.
- **A CONFLICTING PR shows no CI runs at all, and looks exactly like an Actions
  outage.** GitHub emits no `pull_request` events for one. An agent lost hours
  waiting for "CI to come back up". Always check `gh pr view N --json mergeable`
  first.
- **Migration tests were vacuous, and had been for eight versions.** Drift maps
  an *absent* nullable column to `null` on read, so `expect(row.col, isNull)`
  passes whether or not the migration ran. Demonstrated by deleting the
  `themeMode` migration: all four `themeMode` tests stayed green, **including the
  one titled "upgrade adds themeMode"**. Ten of ten tests now assert existence
  via `PRAGMA table_info`. The vacuity tracks **nullability, not table age** — an
  absent NON-nullable column throws, which is why `members.deletedAt` needed the
  guard despite `members` existing since v1.
- **pgTAP genuinely runs now** (`db.yml`, on `pull_request`, `supabase db reset`
  before `supabase test db`, fail-closed). One subtlety: it only stands up the
  stack when the diff touches `supabase/**` or `db.yml`, so a Dart-only push
  reports a fast green **without running the suite**. Do not read that as SQL
  verification.
- **The allow list needs `build_runner`.** Any plan that changes a drift table
  needs `dart run build_runner build`; generated drift code cannot be
  hand-written. `flutter pub get --enforce-lockfile` is safe (it cannot rewrite
  the lockfile) and also fixes the formatter.

---

## 6. What is open

- **C-2 slices 5-6** — leave household (F9) + the last-member cascade warning
  (D-L5), and delete account (F11). Wave 4 stopped precisely between the plan's
  Task 14 and Task 15.
  - **Tasks 15 and 16 are a PAIR.** 15 unhides Delete for claimed members; 16
    adds the inline failure surface. `_canDelete` still returns false for
    `userId != null`, so **F10 is not reachable by a user today** even though the
    service supports it. Doing 15 without 16 loses a real network failure on a
    destructive action — `ClaimedMemberRemovalFailure` needs the network, changed
    nothing, and its own doc requires being shown inline. The comment at
    `member_edit_sheet`'s `_delete` now says so explicitly.
  - `leaveHousehold` and `deleteAccount` are on the gateway with **no callers** —
    inert, tested plumbing, deliberately merged so slices 5-6 have a concrete
    entry point.
  - The two-step confirm already exists: **`confirmTwoStepDestructiveAction`**
    (`lib/features/settings/destructive_confirm.dart`). Compose a step pair; do
    not copy a dialog builder. Its semantic ids are per-step and explicit
    because the reset flow's own ids are irregular (`confirm1`/`cancel1`, then
    `confirm2` but plain `cancel`).
  - **The next migration is v13.** Assign it at merge time, never from plan
    text — B-3's plan still said v9→v10 when it was executed.
  - **The revoked-refresh snackbar is a narrow race, not the primary surface.**
    `syncEngineProvider` is gated on `settings.syncHouseholdId`, and the engine's
    own startup/60s probe usually detects revocation first, calling
    `clearSyncLink()` and turning the provider into a `NoopSyncEngine` whose
    `refreshNow()` returns true — so a later pull-to-refresh reports success
    silently. Two tests failed on exactly this and were fixed in the tests, not
    the implementation. The revocation notice (§3.5) is the primary surface.
- **`release.yml` does not assert `ActionBroadcastReceiver`.** It has the two
  existing fail-closed checks; a third beside them would stop a future refactor
  silently dropping F-1's receiver, which looks exactly like a working app until
  someone taps the button.
- **A-6** iOS E2E never runs on a PR. **A-7** the formatter trap. **G-12**
  `cancelDigest()` is now reachable concurrently with `applyDigestPlans`
  (bounded, documented, not fixed).
- **A-3b** iOS backup exclusion and **A-2b** the stale "Last synced" ticker are
  untouched.
