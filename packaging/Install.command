#!/bin/sh
set -eu

package_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
app_source="$package_root/BOOX Send.app"
workflow_source="$package_root/BOOX’a Gönder.workflow"
app_destination="/Applications/BOOX Send.app"
workflow_destination="$HOME/Library/Services/BOOX’a Gönder.workflow"
suffix=$(date +%Y%m%d-%H%M%S)

test -d "$app_source" || { echo "BOOX Send.app pakette bulunamadı." >&2; exit 1; }
test -d "$workflow_source" || { echo "Finder Hızlı İşlemi pakette bulunamadı." >&2; exit 1; }

if [ -e "$app_destination" ]; then
    backup="$HOME/.Trash/BOOX Send.app.$suffix"
    if [ -w "/Applications" ]; then mv "$app_destination" "$backup"; else sudo mv "$app_destination" "$backup"; fi
    echo "Önceki sürüm Çöp'e taşındı: $backup"
fi

if [ -w "/Applications" ]; then ditto "$app_source" "$app_destination"; else sudo ditto "$app_source" "$app_destination"; fi
mkdir -p "$HOME/Library/Services"
if [ -e "$workflow_destination" ]; then mv "$workflow_destination" "$HOME/.Trash/BOOX’a Gönder.workflow.$suffix"; fi
ditto "$workflow_source" "$workflow_destination"

/System/Library/CoreServices/pbs -flush >/dev/null 2>&1 || true
/System/Library/CoreServices/pbs -update >/dev/null 2>&1 || true
defaults write pbs NSServicesStatus -dict-add \
    "com.aliumutaltas.BooxSend.QuickAction - BOOX’a Gönder - runWorkflowAsService" \
    '{ presentation_modes = { ContextMenu = 1; FinderPreview = 1; ServicesMenu = 1; TouchBar = 0; }; }'

open "$app_destination"
echo
echo "Kurulum tamamlandı. Finder > Hızlı İşlemler > BOOX’a Gönder hazır."
echo "Bu pencereyi kapatabilirsiniz."
