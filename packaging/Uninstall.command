#!/bin/sh
set -eu

app="/Applications/BOOX Send.app"
workflow="$HOME/Library/Services/BOOX’a Gönder.workflow"
suffix=$(date +%Y%m%d-%H%M%S)

killall BooxSend >/dev/null 2>&1 || true
if [ -e "$app" ]; then
    destination="$HOME/.Trash/BOOX Send.app.uninstalled.$suffix"
    if [ -w "/Applications" ]; then mv "$app" "$destination"; else sudo mv "$app" "$destination"; fi
    echo "Uygulama Çöp'e taşındı."
fi
if [ -e "$workflow" ]; then
    mv "$workflow" "$HOME/.Trash/BOOX’a Gönder.workflow.uninstalled.$suffix"
    echo "Finder Hızlı İşlemi Çöp'e taşındı."
fi
/System/Library/CoreServices/pbs -flush >/dev/null 2>&1 || true
/System/Library/CoreServices/pbs -update >/dev/null 2>&1 || true
echo "Kaldırma tamamlandı. Bekleyen kuyruk ve ayarlar korunmuştur."
