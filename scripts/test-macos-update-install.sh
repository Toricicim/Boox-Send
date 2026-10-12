#!/bin/sh
# Real signed test bundles, no user app/configuration changes.
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/boox-send-install-tests.XXXXXX")
cleanup() {
    registry=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
    for scenario in healthy crash cancelled; do
        "$registry" -u "$test_root/$scenario/destination/BOOX Send.app" >/dev/null 2>&1 || true
        "$registry" -u "$test_root/$scenario/source/BOOX Send.app" >/dev/null 2>&1 || true
    done
    rm -rf "$test_root"
    if [ -d '/Applications/BOOX Send.app' ]; then "$registry" -f '/Applications/BOOX Send.app' >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT HUP INT TERM
xcrun swiftc -parse-as-library "$project_root/scripts/tests/HelperProbe.swift" -o "$test_root/BooxSend"

make_app() {
    probe_path=$1
    probe_behavior=$2
    probe_version=$3
    mkdir -p "$probe_path/Contents/MacOS"
    cp "$test_root/BooxSend" "$probe_path/Contents/MacOS/BooxSend"
    cp "$project_root/scripts/tests/HelperProbe.plist" "$probe_path/Contents/Info.plist"
    plutil -replace TestBehavior -string "$probe_behavior" "$probe_path/Contents/Info.plist"
    plutil -replace CFBundleShortVersionString -string "$probe_version" "$probe_path/Contents/Info.plist"
    codesign --force --sign - "$probe_path" 2>/dev/null
}

for scenario in healthy crash cancelled; do
    scenario_root="$test_root/$scenario"
    destination="$scenario_root/destination/BOOX Send.app"
    source_app="$scenario_root/source/BOOX Send.app"
    update_id=$(/usr/bin/uuidgen)
    receipt="$scenario_root/receipts/$update_id"
    mkdir -p "$receipt"
    make_app "$destination" old 1.0.6
    make_app "$source_app" "$scenario" 1.0.7
    if [ "$scenario" = cancelled ]; then
        sh "$project_root/macos/Helpers/InstallUpdate.sh" "$source_app" "$destination" "$$" "$receipt" 1.0.7 5 > "$receipt/log" 2>&1 &
        helper_pid=$!
        attempts=0
        until [ -f "$receipt/status" ] && [ "$(cat "$receipt/status")" = prepared ]; do
            attempts=$((attempts + 1))
            test "$attempts" -lt 100
            sleep 0.1
        done
        kill -TERM "$helper_pid"
        if wait "$helper_pid"; then echo 'Cancelled update unexpectedly succeeded.'; exit 1; fi
        test "$(cat "$receipt/status")" = failed
        test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$destination/Contents/Info.plist")" = 1.0.6
    elif [ "$scenario" = healthy ]; then
        sh "$project_root/macos/Helpers/InstallUpdate.sh" "$source_app" "$destination" 999999 "$receipt" 1.0.7 5 > "$receipt/log" 2>&1
        test "$(cat "$receipt/status")" = success
        test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$destination/Contents/Info.plist")" = 1.0.7
    else
        if sh "$project_root/macos/Helpers/InstallUpdate.sh" "$source_app" "$destination" 999999 "$receipt" 1.0.7 5 > "$receipt/log" 2>&1; then
            echo 'Crashing update unexpectedly succeeded.'; exit 1
        fi
        test "$(cat "$receipt/status")" = failed
        test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$destination/Contents/Info.plist")" = 1.0.6
        attempts=0
        until [ -f "$scenario_root/old-opened" ]; do
            attempts=$((attempts + 1))
            test "$attempts" -lt 50
            sleep 0.1
        done
    fi
    echo "Mac installer scenario passed: $scenario"
done
