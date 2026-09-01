#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_root="$project_root/build/local-install"
app_source="$build_root/BOOX Send.app"
app_destination="/Applications/BOOX Send.app"
workflow_source="$project_root/macos/QuickAction/Send to BOOX.workflow"
workflow_destination="$HOME/Library/Services/Send to BOOX.workflow"
legacy_workflow_destination="$HOME/Library/Services/BOOX’a Gönder.workflow"
backup_suffix=$(date +%Y%m%d-%H%M%S)

"$project_root/scripts/build-macos.sh" "$build_root"

killall BooxSend >/dev/null 2>&1 || true

install_app() {
    if [ -e "$app_destination" ]; then
        backup="$HOME/.Trash/BOOX Send.app.$backup_suffix"
        if [ -w "/Applications" ]; then mv "$app_destination" "$backup"; else sudo mv "$app_destination" "$backup"; fi
        echo "Previous Mac app moved to Trash: $backup"
    fi
    if [ -w "/Applications" ]; then ditto "$app_source" "$app_destination"; else sudo ditto "$app_source" "$app_destination"; fi
}

mkdir -p "$HOME/Library/Services"
if [ -e "$workflow_destination" ]; then
    mv "$workflow_destination" "$HOME/.Trash/Send to BOOX.workflow.$backup_suffix"
fi
if [ -e "$legacy_workflow_destination" ]; then
    mv "$legacy_workflow_destination" "$HOME/.Trash/BOOX-a-Gonder.workflow.$backup_suffix"
fi

install_app
ditto "$workflow_source" "$workflow_destination"
/System/Library/CoreServices/pbs -flush >/dev/null 2>&1 || true
/System/Library/CoreServices/pbs -update >/dev/null 2>&1 || true
defaults write pbs NSServicesStatus -dict-add \
    "com.aliumutaltas.BooxSend.QuickAction - Send to BOOX - runWorkflowAsService" \
    '{ presentation_modes = { ContextMenu = 1; FinderPreview = 1; ServicesMenu = 1; TouchBar = 0; }; }'
open "$app_destination"

echo "Installed. In Finder, right-click a file and choose Quick Actions > Send to BOOX."
