#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output_root=${1:-"$project_root/build/release"}
version=$(tr -d '[:space:]' < "$project_root/VERSION")
architectures=${BOOX_SEND_ARCHS:-$(uname -m)}
sdk_path=$(xcrun --sdk macosx --show-sdk-path)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/boox-send-macos.XXXXXX")
stage_app="$temporary_root/BOOX Send.app"

cleanup() {
    rm -rf "$temporary_root"
}
trap cleanup EXIT HUP INT TERM

command -v xcrun >/dev/null 2>&1 || {
    echo "Error: Xcode Command Line Tools are required. Run 'xcode-select --install'." >&2
    exit 1
}

mkdir -p "$stage_app/Contents/MacOS" "$stage_app/Contents/Helpers"
cp "$project_root/macos/BooxSend/Info.plist" "$stage_app/Contents/Info.plist"
plutil -replace CFBundleExecutable -string BooxSend "$stage_app/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string com.aliumutaltas.BooxSend "$stage_app/Contents/Info.plist"
plutil -replace CFBundleName -string "BOOX Send" "$stage_app/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$version" "$stage_app/Contents/Info.plist"
plutil -replace CFBundleVersion -string "${BOOX_SEND_BUILD_NUMBER:-1}" "$stage_app/Contents/Info.plist"
plutil -replace LSMinimumSystemVersion -string "14.0" "$stage_app/Contents/Info.plist"

app_slices=""
helper_slices=""
for architecture in $architectures; do
    case "$architecture" in
        arm64|x86_64) ;;
        *) echo "Error: unsupported architecture: $architecture" >&2; exit 1 ;;
    esac

    app_slice="$temporary_root/BooxSend-$architecture"
    helper_slice="$temporary_root/BooxSendQueue-$architecture"

    xcrun swiftc -O -swift-version 5 -D BOOX_LOCAL_ADHOC -parse-as-library \
        -target "$architecture-apple-macos14.0" -sdk "$sdk_path" \
        -framework AppKit -framework IOBluetooth -framework SwiftUI \
        -framework UserNotifications \
        "$project_root/macos/Shared/Constants.swift" \
        "$project_root/macos/Shared/SharedQueue.swift" \
        "$project_root/macos/Shared/WireProtocol.swift" \
        "$project_root/macos/BooxSend/ConfigurationStore.swift" \
        "$project_root/macos/BooxSend/RFCOMMConnection.swift" \
        "$project_root/macos/BooxSend/TransferCoordinator.swift" \
        "$project_root/macos/BooxSend/BooxSendApp.swift" \
        -o "$app_slice"

    xcrun swiftc -O -swift-version 5 -D BOOX_LOCAL_ADHOC \
        -target "$architecture-apple-macos14.0" -sdk "$sdk_path" \
        -framework Foundation \
        "$project_root/macos/Shared/Constants.swift" \
        "$project_root/macos/Shared/SharedQueue.swift" \
        "$project_root/macos/BooxSendQueue/main.swift" \
        -o "$helper_slice"

    app_slices="$app_slices $app_slice"
    helper_slices="$helper_slices $helper_slice"
done

set -- $app_slices
if [ "$#" -eq 1 ]; then cp "$1" "$stage_app/Contents/MacOS/BooxSend"; else lipo -create "$@" -output "$stage_app/Contents/MacOS/BooxSend"; fi
set -- $helper_slices
if [ "$#" -eq 1 ]; then cp "$1" "$stage_app/Contents/Helpers/BooxSendQueue"; else lipo -create "$@" -output "$stage_app/Contents/Helpers/BooxSendQueue"; fi

chmod 755 "$stage_app/Contents/MacOS/BooxSend" "$stage_app/Contents/Helpers/BooxSendQueue"

sign_identity=${MACOS_SIGN_IDENTITY:--}
if [ "$sign_identity" = "-" ]; then
    codesign --force --sign - "$stage_app/Contents/Helpers/BooxSendQueue"
    codesign --force --sign - "$stage_app"
else
    codesign --force --options runtime --timestamp --sign "$sign_identity" "$stage_app/Contents/Helpers/BooxSendQueue"
    codesign --force --options runtime --timestamp --sign "$sign_identity" "$stage_app"
fi
codesign --verify --deep --strict "$stage_app"

mkdir -p "$output_root"
destination="$output_root/BOOX Send.app"
if [ -e "$destination" ]; then
    old_destination="$output_root/.BOOX Send.app.previous.$$"
    mv "$destination" "$old_destination"
    rm -rf "$old_destination"
fi
ditto "$stage_app" "$destination"

echo "Mac app ready: $destination"
