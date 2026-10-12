#!/bin/sh
# Transactional replacement: prepare before the old app quits, then require startup acknowledgement.
set -eu
source_app=$1
destination_app=$2
old_pid=$3
receipt=$4
expected_version=$5
health_timeout=${6:-30}
case "$old_pid" in ''|*[!0-9]*) exit 1 ;; esac
case "$health_timeout" in ''|*[!0-9]*) exit 1 ;; esac
test "$health_timeout" -ge 1 && test "$health_timeout" -le 60
test -d "$receipt"
update_id=$(basename "$receipt")
backup_app=''
update_stage=''
failure_message='The update could not be prepared. The previous app has been kept.'

write_status() {
    printf '%s\n' "$1" > "$receipt/status.new"
    mv "$receipt/status.new" "$receipt/status"
}

finish() {
    result=$?
    trap - EXIT HUP INT TERM
    if [ "$result" -eq 0 ]; then exit 0; fi
    printf '%s\n' "$failure_message" > "$receipt/message"
    if [ -n "$backup_app" ] && [ -e "$backup_app" ]; then
        # Only terminate the new app PID it recorded for this exact transaction.
        if [ -f "$receipt/new-pid" ]; then
            new_pid=$(tr -d '\n' < "$receipt/new-pid")
            case "$new_pid" in ''|*[!0-9]*) new_pid='' ;; esac
            if [ -n "$new_pid" ]; then
                new_command=$(/bin/ps -p "$new_pid" -o command= 2>/dev/null || true)
                case "$new_command" in "$destination_app/Contents/MacOS/"*) kill -TERM "$new_pid" 2>/dev/null || true ;; esac
            fi
        fi
        if [ -e "$destination_app" ]; then mv "$destination_app" "$update_stage/Failed BOOX Send.backup" || true; fi
        if ! mv "$backup_app" "$destination_app"; then
            printf '%s\n' "Could not restore automatically. Previous app retained at: $backup_app" >> "$receipt/message"
        fi
    fi
    write_status failed
    if ! kill -0 "$old_pid" 2>/dev/null && [ -e "$destination_app" ]; then
        /usr/bin/open -n "$destination_app" || true
    fi
    exit "$result"
}
trap finish EXIT
trap 'exit 1' HUP INT TERM

test "$(basename "$source_app")" = 'BOOX Send.app'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$source_app/Contents/Info.plist")" = 'com.aliumutaltas.BooxSend'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination_app/Contents/Info.plist")" = 'com.aliumutaltas.BooxSend'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$source_app/Contents/Info.plist")" = "$expected_version"
/usr/bin/codesign --verify --deep --strict "$source_app"
update_parent=$(dirname "$destination_app")
test -w "$update_parent"
update_stage=$(mktemp -d "$update_parent/.boox-send-update.XXXXXX")
new_app="$update_stage/BOOX Send.app"
backup_app="$update_stage/Previous BOOX Send.backup"
/usr/bin/ditto "$source_app" "$new_app"
/usr/bin/codesign --verify --deep --strict "$new_app"
write_status prepared

failure_message='The old app did not exit; the update was cancelled.'
attempts=0
while kill -0 "$old_pid" 2>/dev/null; do
    attempts=$((attempts + 1))
    test "$attempts" -le 30
    sleep 1
done

failure_message='Could not replace the app. The previous version has been restored.'
mv "$destination_app" "$backup_app"
mv "$new_app" "$destination_app"
write_status launching
failure_message='The updated app did not confirm startup. The previous version has been restored.'
/usr/bin/open -n "$destination_app" --args --boox-update-receipt "$update_id" --boox-update-version "$expected_version"
attempts=0
while [ "$attempts" -lt "$health_timeout" ]; do
    if [ -f "$receipt/health" ] && [ "$(cat "$receipt/health")" = "$update_id|$expected_version" ]; then
        printf '%s\n' "Update $expected_version installed. Previous app retained at: $backup_app" > "$receipt/message"
        write_status success
        trap - EXIT HUP INT TERM
        exit 0
    fi
    attempts=$((attempts + 1))
    sleep 1
done
exit 1
