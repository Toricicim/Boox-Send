#!/bin/sh
set -eu

app="/Applications/BOOX Send.app"
workflow="$HOME/Library/Services/Send to BOOX.workflow"
legacy_workflow="$HOME/Library/Services/BOOX’a Gönder.workflow"
suffix=$(date +%Y%m%d-%H%M%S)

killall BooxSend >/dev/null 2>&1 || true
if [ -e "$app" ]; then
    destination="$HOME/.Trash/BOOX Send.app.uninstalled.$suffix"
    if [ -w "/Applications" ]; then mv "$app" "$destination"; else sudo mv "$app" "$destination"; fi
    echo "App moved to Trash."
fi
if [ -e "$workflow" ]; then
    mv "$workflow" "$HOME/.Trash/Send to BOOX.workflow.uninstalled.$suffix"
    echo "Finder Quick Action moved to Trash."
fi
if [ -e "$legacy_workflow" ]; then
    mv "$legacy_workflow" "$HOME/.Trash/BOOX-a-Gonder.workflow.uninstalled.$suffix"
    echo "Legacy Finder Quick Action moved to Trash."
fi
/System/Library/CoreServices/pbs -flush >/dev/null 2>&1 || true
/System/Library/CoreServices/pbs -update >/dev/null 2>&1 || true
echo "Uninstallation complete. The pending queue and settings were preserved."
