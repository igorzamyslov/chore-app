# Android Auto-Backup (A-3 / D-B1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `android:allowBackup="false"` on the release manifest, prove it
on the built APK in CI so it can never silently regress, and close out the
two docs (`app-lifecycle.md` G8, `backlog.md` A-3) that currently describe
this as an open question when it is not — decision D-B1 already settled it.

**Architecture:** This is a config-and-verification change, not an app-code
change. One boolean manifest attribute; one new CI assertion in the existing
release workflow, in the same style as the already-shipped INTERNET
permission check; two doc edits to stop two files from describing a decided
question as open.

**Tech Stack:** Android manifest (AGP-merged, targets `minSdk 24` /
`targetSdk 36` / `compileSdk 36` — read from
`android/app/build.gradle.kts:26-27`, which delegates to the Flutter Gradle
plugin's `FlutterExtension` defaults, not overridden locally), GitHub
Actions release workflow, `aapt2` (already used in `release.yml`).

## Global Constraints

- Decision **D-B1** (`docs/backlog.md`, Igor, 2026-08-08) is final:
  `allowBackup="false"`. Do not re-litigate it.
- A capability boundary must be verified on the **release artifact**, not a
  debug run or an emulator — this is the project's hard-won rule from the
  v0.2.0 `INTERNET`-permission incident, and this finding is explicitly
  "invisible in every emulator and E2E run" (same blind-spot class).
- Every user-visible string still goes through gen_l10n — not touched by
  this plan; there is no new user-visible string here (see Analysis, "Copy
  audit" below — nothing needs correcting).
- Never add `Co-Authored-By` trailers to commits.

---

## Analysis (why this shape, and what I ruled out)

**Manifest scope.** `minSdk = flutter.minSdkVersion` and
`targetSdk = flutter.targetSdkVersion` are not overridden anywhere under
`android/` (verified: `grep -rn "minSdkVersion\|targetSdkVersion" android/`
finds only the two pass-through lines in `build.gradle.kts`). The Flutter
Gradle plugin bundled with the pinned SDK
(`/opt/homebrew/share/flutter/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt:23,26,34`)
sets `compileSdkVersion = 36`, `minSdkVersion = 24`, `targetSdkVersion = 36`.
Confirmed directly against the built artifacts in `build/app/outputs/`: `aapt2
dump badging app-debug.apk` prints `minSdkVersion:'24'` /
`targetSdkVersion:'36'`. So the app spans pre-Android-12 (API 24-30, classic
Auto Backup + `fullBackupContent`) through API 31+ (`dataExtractionRules` +
device-to-device transfer).

That would normally mean both `android:fullBackupContent` (API ≤30) and
`android:dataExtractionRules` (API 31+) need explicit declarations to cover
the whole supported range. **They don't, here, and deliberately aren't
added:** both attributes are backup-content *filters* — the platform only
consults them when `android:allowBackup` is `true`. With
`allowBackup="false"`, Android skips backup (classic Auto Backup) and, as of
Android 12, device-to-device migration entirely, for every API level this
app supports; there is nothing left for a filter to filter. Declaring empty
rules to be enforce-nothing files that never matched only invites the
question this document exists to close — that they'd need updating if
`allowBackup` ever flips back to `true`, which is exactly what `docs/backlog.md`'s
D-B1 rationale (sync + export, not the OS, is this app's backup story) says
won't happen. **Judgment call: manifest-only, one attribute.**

**Copy audit** (l10n, `PRIVACY.md`, `fastlane/metadata/`,
`docs/app-lifecycle.md` G8) — checked all four:

- `lib/l10n/app_en.arb` — every user-facing string that says "backup" (the
  reconnect intro, the join-import body, the reset-confirm dialogs) means
  the **JSON export file**, not OS backup, and already says things like
  *"There is no cloud backup — this can't be undone"* for the unlinked reset
  path. None of these claims become false after this change; if anything,
  `PRIVACY.md`'s "Nothing leaves the device" line (without-account section)
  was arguably slightly optimistic *before* this fix, since a live
  `allowBackup`-defaulted-`true` app can have its data copied off-device by
  Android's backup transport. This change makes that sentence more true, not
  less — no edit needed there.
- `fastlane/metadata/` — zero hits for "backup" anywhere. Nothing to fix.
- `docs/app-lifecycle.md` G8(a) — this is the one place that still poses the
  question as open ("VERIFY OS auto-backup..."). **Task 3 below closes it.**
- `docs/backlog.md` — the "Decisions taken 2026-08-08" section already
  records D-B1 correctly, but the **A-3 table row** in section A still says
  "Needs a product decision — see below," which now contradicts the decision
  two dozen lines above it. **Task 4 below fixes the row and adds the iOS
  follow-up (next paragraph).**

**iOS.** Stating this plainly, as instructed: iOS is not silent on this.
`lib/data/db/app_database.dart:156` opens the database via
`driftDatabase(name: 'chore_app')`, and `drift_flutter`'s own doc comment
(`drift_flutter-0.3.1/lib/drift_flutter.dart:22-24`) says plainly that on
every native platform — no iOS/Android branch — the file lives in
`getApplicationDocumentsDirectory()`. On iOS that resolves under
`<App_Home>/Documents/`, which Apple backs up to iCloud/iTunes **by
default**, with no opt-out declared anywhere (`grep` of
`ios/Runner/Info.plist` for `backup`/`NSURLIsExcludedFromBackupKey` finds
nothing). So `chore_app.sqlite` + its `-wal`/`-shm` sidecars, and the same
`settings` table row carrying `syncLastPulledAt` and `actingMemberId` (see
below), are backed up on iOS today, by default, with the identical
torn-restore and cross-device-clobber shape as the Android problem this plan
fixes.

**Explicitly out of scope for this ticket.** A-3's title, its backlog ID,
and D-B1's decision text are Android-specific, and the iOS fix has different
mechanics: there is no single iOS manifest flag equivalent to `allowBackup`;
excluding files from iCloud backup means setting
`NSURLIsExcludedFromBackupKey` at the *file* level at runtime (e.g. via a
platform channel or a package like `path_provider` doesn't expose this —
it would need `flutter_backup_exclude`-style native code or a small Swift
shim), which is application code, not manifest config, and needs its own
scoping/testing pass. Silently doing it inside an "Android backup" ticket
would blur exactly the kind of scope boundary this project's specs care
about. **Judgment call: track it, don't build it here** — Task 4 adds a
backlog row (`A-3b`) so it isn't lost, per the ticket's instruction not to
leave it unmentioned.

**Precision on what else restores.** The ticket describes
`syncLastPulledAt` and the device-scoped `actingMemberId` as if they might
live in shared preferences alongside the Supabase token. Checked directly:
they don't — both are plain columns on the drift `settings` table
(`lib/data/db/tables.dart:237,288`), read/written via
`SettingsRepository.setActingMember`/`setSyncLastPulledAt`
(`lib/data/repositories/settings_repository.dart:121,224`). They restore as
part of the SQLite file itself, not a separate shared-prefs concern — which
means the single `allowBackup="false"` fix covers them together with the
torn-restore risk, by the same mechanism, not two separate risks. Only the
Supabase refresh token is confirmed to live in shared preferences,
via `supabase_flutter`'s default `SharedPreferencesLocalStorage`
(`supabase_flutter-2.16.0/lib/src/local_storage.dart`) — also covered by
`allowBackup="false"`, since that attribute excludes the *entire* app data
directory from backup, shared-prefs included.

**CI assertion — `dump badging` vs `dump xmltree`.** Tested both directly
against the repo's existing (pre-fix) `build/app/outputs/flutter-apk/app-debug.apk`
locally:

```
$ aapt2 dump badging app-debug.apk | grep -i backup   # exit 1, no output
$ aapt2 dump xmltree app-debug.apk --file AndroidManifest.xml | grep -i allowBackup
                                                        # exit 1, no output today (expected — unset)
```

`dump badging` never surfaces `allowBackup` at all, at any value — it's not
one of the fields that command summarizes. `dump xmltree` prints every
explicitly-declared attribute on the compiled binary manifest, in the form
`A: http://schemas.android.com/apk/res/android:debuggable(0x0101000f)=true`
(confirmed against the real `application` element's `debuggable` and
`extractNativeLibs` attributes in the same dump). So the ticket's
`badging`-or-`xmltree` framing resolves to **`xmltree` only** — `badging`
cannot do this. **Task 2 uses `xmltree`.**

## Open product decisions

None. The backup posture (D-B1) is already decided. The one scoping question
this ticket raised — whether iOS work belongs in A-3 — is resolved above by
engineering judgment (out of scope, tracked as a new backlog row) rather than
escalated, because it isn't a user-facing tradeoff: nothing about *what the
app does* is in question, only *which ticket does the iOS half of it*.

---

## Task 1: Declare `allowBackup="false"` on the release manifest

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml:1-6`

**Interfaces:** None — this task has no Dart-visible interface. Its
"deliverable" is a manifest attribute, verified by inspecting a built APK
(steps below), which is the concrete, non-Dart-test verification the ticket
asked for in place of TDD.

- [ ] **Step 1: Add the attribute and its rationale comment**

Replace:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="Famdo"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
```

with:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Auto-backup posture (decision D-B1, docs/backlog.md; implementation
         plan docs/plans/2026-08-08-android-backup.md): this app's answer to
         "don't lose my data" is sync plus the JSON export (Settings ->
         Export data), not the OS. Left unconfigured, Auto Backup defaults
         to ON with no rules -- Android would copy the live SQLite file
         (chore_app.sqlite) plus its -wal/-shm sidecars uncoordinated (a
         restore can land a torn database) and restore the Supabase
         refresh token, the sync pull cursor (settings.syncLastPulledAt)
         and the device-scoped settings.actingMemberId onto a second
         device -- under this app's last-push-wins conflict rule that
         clobbers data rather than merely confusing.
         allowBackup="false" disables BOTH classic cloud Auto Backup and
         Android 12+'s device-to-device transfer for every API level this
         app supports (minSdk 24). android:fullBackupContent and
         android:dataExtractionRules are backup-content FILTERS the
         platform only consults when allowBackup is true, so they are
         deliberately not declared -- there would be nothing for them to
         filter. Asserted on the built release APK in
         .github/workflows/release.yml so this can never silently
         regress, same pattern as the INTERNET permission check below.
         iOS is a separate, tracked gap (docs/backlog.md A-3b) -- iCloud
         backs up Documents/, where this database also lives, by
         default. -->
    <application
        android:label="Famdo"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:allowBackup="false">
```

- [ ] **Step 2: Build a release APK and inspect the compiled manifest**

Run (needs the Android SDK build-tools already used by `release.yml`; use
whatever `aapt2` the local Android SDK provides, e.g. via
`$ANDROID_HOME/build-tools/*/aapt2` or the one bundled with
`android-commandlinetools`):

```bash
flutter build apk --release
AAPT="$(ls "$ANDROID_HOME"/build-tools/*/aapt2 | tail -1)"
"$AAPT" dump xmltree build/app/outputs/flutter-apk/app-release.apk --file AndroidManifest.xml \
  | grep allowBackup
```

Expected output: exactly one line matching
`allowBackup(0x...)=false` (the hex resource id will print automatically —
don't hardcode it, `aapt2` fills it in from the platform's `public.xml`).
This is the same command Task 2 encodes as a CI gate; running it locally
first catches typos before pushing a tag.

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/AndroidManifest.xml
git commit -m "Disable Android auto-backup (D-B1)"
```

---

## Task 2: Assert `allowBackup=false` on the release APK in CI

**Files:**
- Modify: `.github/workflows/release.yml:47-58`

**Interfaces:**
- Consumes: the manifest attribute from Task 1. If Task 1 is reverted or
  the attribute is ever removed, this step fails the release build closed
  (fail-closed, matching the existing INTERNET check's philosophy stated at
  the top of this workflow file).

- [ ] **Step 1: Insert the new verification step**

Insert a new step immediately after the existing "Verify release APK can
reach the network" step and before "Rename artifact" (i.e. right after the
block ending `exit 1; }` at line 58):

```yaml
      - name: Verify release APK has auto-backup disabled
        # Decision D-B1 (docs/backlog.md; implementation plan
        # docs/plans/2026-08-08-android-backup.md): android:allowBackup
        # must be false so Android never copies the live SQLite file (plus
        # its -wal/-shm sidecars) or the Supabase auth session/sync cursor
        # onto another device uncoordinated. `aapt2 dump badging` does NOT
        # surface this attribute at any value (verified locally against
        # this repo's own build output) -- `dump xmltree` on the compiled
        # manifest does. Same "assert on the shipped artifact, not a debug
        # build" rule as the INTERNET check above -- this is invisible in
        # every emulator and E2E run.
        run: |
          AAPT="$(ls "$ANDROID_HOME"/build-tools/*/aapt2 | tail -1)"
          "$AAPT" dump xmltree build/app/outputs/flutter-apk/app-release.apk --file AndroidManifest.xml \
            | grep -qE "allowBackup\(0x[0-9a-f]+\)=false" \
            || { echo "::error::Release APK does not have allowBackup=false — Android would auto-backup a live SQLite file and the auth session onto other devices"; exit 1; }
```

- [ ] **Step 2: Verify the step is wired correctly**

Since GitHub Actions workflows can't be dry-run locally without `act`, verify
by reading: confirm the new step sits between "Verify release APK can reach
the network" and "Rename artifact" (`build/app/outputs/flutter-apk/app-release.apk`
must still exist at that point in the job — it does, `flutter build apk
--release` already produced it earlier in the same job and neither step
touches it). Confirm indentation matches the surrounding steps (6 spaces for
`- name:`, 8 for `run:` body) — a YAML indentation slip here silently drops
the step from the job rather than erroring.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "Assert allowBackup=false on the release APK (D-B1)"
```

---

## Task 3: Close `docs/app-lifecycle.md` G8(a)

**Files:**
- Modify: `docs/app-lifecycle.md:67-74`

**Interfaces:** None — documentation only.

- [ ] **Step 1: Add a resolution note under G8**

Replace:

```markdown
- **G8 — Data survives only as long as the install.** No export, no
  sync yet: uninstall = everything gone. Mitigations to verify/do:
  (a) VERIFY OS auto-backup actually covers the DB: iOS backs up
  Documents/ (where chore_app.sqlite lives — likely fine, verify);
  Android auto-backup includes databases < 25MB unless allowBackup is
  off — check the manifest/flags. (b) Consider a manual JSON
  export/share as cheap insurance until sync lands (small task,
  debatable value — decide next session).
```

with:

```markdown
- **G8 — Data survives only as long as the install.** No export, no
  sync yet: uninstall = everything gone. Mitigations to verify/do:
  (a) VERIFY OS auto-backup actually covers the DB: iOS backs up
  Documents/ (where chore_app.sqlite lives — likely fine, verify);
  Android auto-backup includes databases < 25MB unless allowBackup is
  off — check the manifest/flags. (b) Consider a manual JSON
  export/share as cheap insurance until sync lands (small task,
  debatable value — decide next session).
  **Resolved 2026-08-08 (decision D-B1, `docs/backlog.md`):** (a) is
  answered — the manifest had no `allowBackup`/`dataExtractionRules`/
  `fullBackupContent` at all, so Android defaulted to auto-backup ON
  with no rules. The app now ships `android:allowBackup="false"`
  (`docs/plans/2026-08-08-android-backup.md`), asserted on the built
  release APK in `.github/workflows/release.yml` so it can't silently
  regress. iOS still backs up `Documents/` (where the database also
  lives) to iCloud by default; excluding it is tracked separately as
  `docs/backlog.md` A-3b, deliberately out of scope for this fix. (b)
  shipped as the "Export data" settings row and is tracked further as
  `docs/backlog.md` G-3 (restore from a backup file).
```

- [ ] **Step 2: Commit**

```bash
git add docs/app-lifecycle.md
git commit -m "Close app-lifecycle G8(a): Android auto-backup decided (D-B1)"
```

---

## Task 4: Reconcile `docs/backlog.md` — close the A-3 row, add the iOS follow-up

**Files:**
- Modify: `docs/backlog.md:47` (the A-3 row)
- Modify: `docs/backlog.md:47-48` (insert a new A-3b row directly after A-3)

**Interfaces:** None — documentation only.

- [ ] **Step 1: Fix the A-3 row so it stops contradicting the decision above it**

Replace:

```markdown
| **A-3** | **Android auto-backup unconfigured** | No `allowBackup`, no `dataExtractionRules`, no `fullBackupContent` anywhere under `android/`, so backup defaults on with no rules: a live SQLite file plus WAL sidecars copied uncoordinated, and the Supabase refresh token + pull cursor restored onto a second device. Under last-push-wins that is a data-clobbering configuration. Invisible in every emulator and E2E run — same blind-spot class as the v0.2.0 `INTERNET` miss. **Needs a product decision — see below** | `android/app/src/main/AndroidManifest.xml`, `docs/app-lifecycle.md` G8 | XS–S |
```

with:

```markdown
| **A-3** | **Android auto-backup unconfigured** | No `allowBackup`, no `dataExtractionRules`, no `fullBackupContent` anywhere under `android/`, so backup defaults on with no rules: a live SQLite file plus WAL sidecars copied uncoordinated, and the Supabase refresh token + pull cursor restored onto a second device. Under last-push-wins that is a data-clobbering configuration. Invisible in every emulator and E2E run — same blind-spot class as the v0.2.0 `INTERNET` miss. **Decided (D-B1): `allowBackup="false"`. Planned in `docs/plans/2026-08-08-android-backup.md`, ready to execute** | `android/app/src/main/AndroidManifest.xml`, `docs/app-lifecycle.md` G8 | XS–S |
```

- [ ] **Step 2: Add the iOS follow-up row directly after it**

Insert immediately after the A-3 row (before the A-4 row):

```markdown
| **A-3b** | **iOS: no backup exclusion on the local DB** | `chore_app.sqlite` (+ `-wal`/`-shm`) lives under `getApplicationDocumentsDirectory()` (`drift_flutter`'s native default, no iOS/Android branch), which iCloud/iTunes backs up by default — same torn-restore and cross-device session-clobber shape as A-3, but the fix is per-file (`NSURLIsExcludedFromBackupKey` at runtime), not a manifest flag, so it needs its own scoping pass. Deliberately excluded from A-3/D-B1, which is Android-only | `ios/Runner/Info.plist`, wherever the DB file is opened (`lib/data/db/app_database.dart`) | S |
```

- [ ] **Step 3: Commit**

```bash
git add docs/backlog.md
git commit -m "Reconcile backlog A-3 with decision D-B1; track the iOS analog as A-3b"
```

---

## Self-review

- **Manifest change** — Task 1. ✓
- **`dataExtractionRules`/`fullBackupContent` question, resolved with the
  minSdk/targetSdk actually checked** — Analysis section + Task 1 comment.
  ✓ (verified `minSdk 24` / `targetSdk 36` against both `build.gradle.kts`
  and a real build's `aapt2 dump badging` output; concluded neither is
  needed because both are no-ops once `allowBackup` is `false`).
- **Copy/doc audit across l10n, `PRIVACY.md`, `fastlane/metadata/`,
  `app-lifecycle.md` G8** — Analysis section (l10n/PRIVACY.md/fastlane: no
  edit needed, with reasoning) + Task 3 (`app-lifecycle.md`, edited) + Task 4
  (`backlog.md`, edited — found stale even though not explicitly named in
  the ticket's check-list, since it directly contradicts the decision it
  itself records). ✓
- **Release-workflow assertion, verified against the actual tool output
  format, not assumed** — Task 2, with `dump badging` vs `dump xmltree`
  resolved by testing both against this repo's own build artifacts. ✓
- **iOS stated plainly, scope decided explicitly, not left unmentioned** —
  Analysis section ("iOS") + Task 4 Step 2 (backlog row `A-3b`). ✓
- **Placeholder scan** — no TBD/TODO/"add appropriate"/"similar to Task N"
  found in the above; every step has literal file content or literal
  commands.
