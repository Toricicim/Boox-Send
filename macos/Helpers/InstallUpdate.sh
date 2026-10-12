#!/bin/sh
# Runs from a private staging folder after the old app exits. Never edits user data.
set -eu
source_app=$1
destination_app=$2
old_pid=$3
case "$old_pid" in ''|*[!0-9]*) exit 1 ;; esac
test "$(basename "$source_app")" = 'BOOX Send.app'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$source_app/Contents/Info.plist")" = 'com.aliumutaltas.BooxSend'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination_app/Contents/Info.plist")" = 'com.aliumutaltas.BooxSend'
/usr/bin/codesign --verify --deep --strict "$source_app"
update_parent=$(dirname "$destination_app")
test -w "$update_parent"
update_stage=$(mktemp -d "$update_parent/.boox-send-update.XXXXXX")
new_app="$update_stage/BOOX Send.app"
backup_app="$update_stage/Previous BOOX Send.backup"
/usr/bin/ditto "$source_app" "$new_app"
/usr/bin/codesign --verify --deep --strict "$new_app"
attempts=0
while kill -0 "$old_pid" 2>/dev/null; do
    attempts=$((attempts + 1))
    if [ "$attempts" -gt 30 ]; then echo 'Old app did not exit; update cancelled.'; exit 1; fi
    sleep 1
done
rollback() {
    if [ -e "$backup_app" ]; then
        if [ -e "$destination_app" ]; then mv "$destination_app" "$update_stage/Failed BOOX Send.backup"; fi
        mv "$backup_app" "$destination_app"
        /usr/bin/open "$destination_app" || true
    fi
}
trap rollback HUP INT TERM
mv "$destination_app" "$backup_app"
if ! mv "$new_app" "$destination_app"; then rollback; exit 1; fi
if ! /usr/bin/open "$destination_app"; then rollback; exit 1; fi
trap - HUP INT TERM
echo "Update installed. Previous app retained at: $backup_app"
# The previous app is retained for recovery. Preferences, queue and workflow stay in place.
