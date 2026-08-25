#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

plutil -lint \
  "$project_root/macos/BooxSend/Info.plist" \
  "$project_root/macos/BooxSend/BooxSend.entitlements" \
  "$project_root/macos/BooxSendFinder/Info.plist" \
  "$project_root/macos/BooxSendFinder/BooxSendFinder.entitlements" \
  "$project_root/macos/QuickAction/BOOX’a Gönder.workflow/Contents/Info.plist" \
  "$project_root/macos/QuickAction/BOOX’a Gönder.workflow/Contents/document.wflow"
xmllint --noout \
  "$project_root/android/app/src/main/AndroidManifest.xml" \
  "$project_root/android/app/src/main/res/values/styles.xml"
for script in "$project_root"/scripts/*.sh "$project_root"/packaging/*.command; do
  sh -n "$script"
done
swiftc -frontend -parse \
  "$project_root"/macos/Shared/*.swift \
  "$project_root"/macos/BooxSend/*.swift \
  "$project_root"/macos/BooxSendFinder/*.swift \
  "$project_root"/macos/Tests/*.swift
swiftc -frontend -parse \
  "$project_root"/macos/Shared/Constants.swift \
  "$project_root"/macos/Shared/SharedQueue.swift \
  "$project_root"/macos/BooxSendQueue/main.swift

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$project_root"/scripts/*.sh "$project_root"/packaging/*.command
fi

if command -v xcodegen >/dev/null 2>&1 && command -v xcodebuild >/dev/null 2>&1; then
  (cd "$project_root/macos" && xcodegen generate && xcodebuild test -project BooxSend.xcodeproj -scheme BooxSend -destination 'platform=macOS')
else
  echo "Skipping Xcode tests: full Xcode and XcodeGen are required."
fi

if [ -x "$project_root/android/gradlew" ]; then
  (cd "$project_root/android" && ./gradlew testDebugUnitTest)
else
  echo "Skipping Android tests: generate the Gradle wrapper from Android Studio first."
fi
