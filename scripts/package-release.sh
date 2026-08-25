#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
version=$(tr -d '[:space:]' < "$project_root/VERSION")
release_root="$project_root/build/release"
package_root="$release_root/BOOX-Send-$version-macOS"

BOOX_SEND_ARCHS="${BOOX_SEND_ARCHS:-arm64 x86_64}" \
    "$project_root/scripts/build-macos.sh" "$release_root"

rm -rf "$package_root"
mkdir -p "$package_root"
ditto "$release_root/BOOX Send.app" "$package_root/BOOX Send.app"
ditto "$project_root/macos/QuickAction/BOOX’a Gönder.workflow" "$package_root/BOOX’a Gönder.workflow"
cp "$project_root/packaging/Install.command" "$package_root/Install.command"
cp "$project_root/packaging/Uninstall.command" "$package_root/Uninstall.command"
cp "$project_root/LICENSE" "$package_root/LICENSE"
chmod 755 "$package_root/Install.command" "$package_root/Uninstall.command"

archive="$release_root/BOOX-Send-$version-macOS-universal.zip"
rm -f "$archive"
ditto -c -k --sequesterRsrc --keepParent "$package_root" "$archive"
echo "Yayın paketi hazır: $archive"
