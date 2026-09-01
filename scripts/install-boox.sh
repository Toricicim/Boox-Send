#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if ! command -v adb >/dev/null 2>&1; then
    echo "Error: adb was not found. Install Android Platform Tools and add adb to PATH." >&2
    exit 1
fi

device_count=$(adb devices | awk 'NR > 1 && $2 == "device" { count++ } END { print count + 0 }')
if [ "$device_count" -ne 1 ]; then
    echo "Error: exactly one Android/BOOX device with USB debugging enabled must be connected." >&2
    adb devices
    exit 1
fi

"$project_root/scripts/build-android.sh" "$project_root/build/local-install"
adb install -r "$project_root/build/local-install/BOOX-Send-android-debug.apk"
adb shell am start -n com.aliumutaltas.booxsend/.MainActivity >/dev/null

echo "BOOX Send was installed and opened. Complete the on-screen setup steps."
