#!/bin/sh
# Creates a future same-key APK as test data only; never installs that candidate.
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root/android"
./gradlew assembleDebug -PbooxUpdaterFixture=true
mkdir -p app/build/generated/updater-test-assets
cp app/build/outputs/apk/debug/app-debug.apk app/build/generated/updater-test-assets/updater-candidate.apk
./gradlew assembleDebug assembleDebugAndroidTest testDebugUnitTest
adb install --no-streaming -r app/build/outputs/apk/debug/app-debug.apk
adb install --no-streaming -r app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
device_test_log=$(mktemp "${TMPDIR:-/tmp}/boox-updater-device-test.XXXXXX")
trap 'rm -f "$device_test_log"' EXIT HUP INT TERM
adb shell am instrument -w -r -e class com.aliumutaltas.booxsend.UpdateDownloadsDeviceTest \
    com.aliumutaltas.booxsend.test/androidx.test.runner.AndroidJUnitRunner > "$device_test_log"
sed -n '1,160p' "$device_test_log"
awk '/^OK \([0-9]+ tests?\)/ { passed=1 } END { exit !passed }' "$device_test_log"
