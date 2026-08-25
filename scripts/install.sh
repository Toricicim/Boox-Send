#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

"$project_root/scripts/install-macos.sh"

if command -v adb >/dev/null 2>&1 && adb devices | awk 'NR > 1 && $2 == "device" { found=1 } END { exit !found }'; then
    "$project_root/scripts/install-boox.sh"
else
    echo
    echo "Mac tarafı hazır. BOOX'u USB hata ayıklama ile bağladıktan sonra:"
    echo "  ./scripts/install-boox.sh"
fi
