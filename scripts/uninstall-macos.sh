#!/bin/sh
set -eu

app="/Applications/BOOX Send.app"
workflow="$HOME/Library/Services/BOOX’a Gönder.workflow"
suffix=$(date +%Y%m%d-%H%M%S)

killall BooxSend >/dev/null 2>&1 || true

if [ -e "$app" ]; then
    destination="$HOME/.Trash/BOOX Send.app.uninstalled.$suffix"
    if [ -w "/Applications" ]; then mv "$app" "$destination"; else sudo mv "$app" "$destination"; fi
    echo "Uygulama Çöp'e taşındı: $destination"
fi
if [ -e "$workflow" ]; then
    destination="$HOME/.Trash/BOOX’a Gönder.workflow.uninstalled.$suffix"
    mv "$workflow" "$destination"
    echo "Hızlı İşlem Çöp'e taşındı: $destination"
fi

/System/Library/CoreServices/pbs -flush >/dev/null 2>&1 || true
/System/Library/CoreServices/pbs -update >/dev/null 2>&1 || true

if [ "${1:-}" = "--purge" ]; then
    queue="$HOME/Library/Application Support/BOOX Send"
    preferences="$HOME/Library/Preferences/com.aliumutaltas.BooxSend.plist"
    [ ! -e "$queue" ] || mv "$queue" "$HOME/.Trash/BOOX-Send-data.$suffix"
    [ ! -e "$preferences" ] || mv "$preferences" "$HOME/.Trash/BOOX-Send-preferences.$suffix.plist"
    echo "Kuyruk ve ayarlar da Çöp'e taşındı."
fi
