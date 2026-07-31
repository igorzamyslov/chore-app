#!/usr/bin/env bash
# E2E test runner: builds the app with the pinned E2E clock, installs it on
# a simulator/emulator, and runs the Maestro flows.
#
# Usage:
#   tool/e2e.sh ios      [flow-or-dir ...]   # default: e2e/flows
#   tool/e2e.sh android  [flow-or-dir ...]
#
# The app date is pinned via E2E_TODAY (default 2026-07-24, a Friday) so
# flows can assert on Today/Tomorrow sections deterministically — see
# docs/specs/testing-strategy.md and clockProvider in lib/app/providers.dart.
set -euo pipefail

PLATFORM="${1:?usage: tool/e2e.sh <ios|android> [flows...]}"
shift || true
E2E_TODAY="${E2E_TODAY:-2026-07-24}"

# Maestro and Gradle are JVM apps; Homebrew's keg-only JDK isn't on PATH by
# default. Use the LTS JDK 21: the plain `openjdk` formula tracks the
# newest JDK, which Gradle/AGP lag behind (this exact mismatch broke the
# first Android E2E run).
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home}"
export PATH="$HOME/.maestro/bin:$JAVA_HOME/bin:$PATH"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

case "$PLATFORM" in
  ios)
    APP_ID="io.github.igorzamyslov.famdo"
    flutter build ios --simulator --debug --dart-define=E2E_TODAY="$E2E_TODAY"
    if ! xcrun simctl list devices booted | grep -q "(Booted)"; then
      DEVICE_ID="$(xcrun simctl list devices available \
        | grep -oE "iPhone [^(]+\(([0-9A-F-]{36})\)" \
        | grep -oE "[0-9A-F-]{36}" | head -1)"
      [ -n "$DEVICE_ID" ] || { echo "No available iPhone simulator" >&2; exit 1; }
      xcrun simctl boot "$DEVICE_ID"
      xcrun simctl bootstatus "$DEVICE_ID" -b
    fi
    xcrun simctl install booted build/ios/iphonesimulator/Runner.app
    ;;
  android)
    APP_ID="io.github.igorzamyslov.famdo"
    ANDROID_SDK="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}"
    flutter build apk --debug --dart-define=E2E_TODAY="$E2E_TODAY"
    if ! "$ANDROID_SDK/platform-tools/adb" devices | grep -q "emulator-.*device$"; then
      nohup "$ANDROID_SDK/emulator/emulator" -avd e2e_pixel -no-snapshot \
        -no-audio -no-boot-anim >/dev/null 2>&1 &
      "$ANDROID_SDK/platform-tools/adb" wait-for-device
      until "$ANDROID_SDK/platform-tools/adb" shell getprop sys.boot_completed 2>/dev/null | grep -q 1; do
        sleep 2
      done
    fi
    "$ANDROID_SDK/platform-tools/adb" install -r build/app/outputs/flutter-apk/app-debug.apk
    ;;
  *)
    echo "Unknown platform: $PLATFORM (expected ios or android)" >&2
    exit 1
    ;;
esac

# Pin the target device: with an Android emulator AND an iOS simulator
# both alive, an unpinned maestro picks one arbitrarily (flows then fail
# instantly with "Package not installed" on the wrong platform).
case "$PLATFORM" in
  ios)
    DEVICE="$(xcrun simctl list devices booted | grep -oE "[0-9A-F-]{36}" | head -1)"
    ;;
  android)
    DEVICE="$("$ANDROID_SDK/platform-tools/adb" devices | grep -oE "^emulator-[0-9]+" | head -1)"
    ;;
esac

maestro --device "$DEVICE" test --env APP_ID="$APP_ID" "${@:-e2e/flows}"
