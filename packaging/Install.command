#!/bin/sh
set -eu

package_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
app_source="$package_root/BOOX Send.app"
workflow_source="$package_root/Send to BOOX.workflow"
app_destination="/Applications/BOOX Send.app"
workflow_destination="$HOME/Library/Services/Send to BOOX.workflow"
legacy_workflow_destination="$HOME/Library/Services/BOOX’a Gönder.workflow"
suffix=$(date +%Y%m%d-%H%M%S)

test -d "$app_source" || { echo "BOOX Send.app was not found in the package." >&2; exit 1; }
test -d "$workflow_source" || { echo "The Finder Quick Action was not found in the package." >&2; exit 1; }

killall BooxSend >/dev/null 2>&1 || true

if [ -e "$app_destination" ]; then
    backup="$HOME/.Trash/BOOX Send.app.$suffix"
    if [ -w "/Applications" ]; then mv "$app_destination" "$backup"; else sudo mv "$app_destination" "$backup"; fi
    echo "Previous version moved to Trash: $backup"
fi

if [ -w "/Applications" ]; then ditto "$app_source" "$app_destination"; else sudo ditto "$app_source" "$app_destination"; fi
mkdir -p "$HOME/Library/Services"
if [ -e "$workflow_destination" ]; then mv "$workflow_destination" "$HOME/.Trash/Send to BOOX.workflow.$suffix"; fi
if [ -e "$legacy_workflow_destination" ]; then mv "$legacy_workflow_destination" "$HOME/.Trash/BOOX-a-Gonder.workflow.$suffix"; fi
ditto "$workflow_source" "$workflow_destination"

/System/Library/CoreServices/pbs -flush >/dev/null 2>&1 || true
/System/Library/CoreServices/pbs -update >/dev/null 2>&1 || true
defaults write pbs NSServicesStatus -dict-add \
    "com.aliumutaltas.BooxSend.QuickAction - Send to BOOX - runWorkflowAsService" \
    '{ presentation_modes = { ContextMenu = 1; FinderPreview = 1; ServicesMenu = 1; TouchBar = 0; }; }'

open "$app_destination"
echo
echo "Installation complete. Finder > Quick Actions > Send to BOOX is ready."
echo "You can close this window."
