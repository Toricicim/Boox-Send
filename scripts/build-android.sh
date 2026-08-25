#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output_root=${1:-"$project_root/build/release"}
variant=${BOOX_SEND_ANDROID_VARIANT:-debug}

case "$variant" in
    debug) gradle_task=assembleDebug; apk_name=app-debug.apk; output_name=BOOX-Send-android-debug.apk ;;
    release) gradle_task=assembleRelease; apk_name=app-release.apk; output_name=BOOX-Send-android.apk ;;
    *) echo "Hata: BOOX_SEND_ANDROID_VARIANT debug veya release olmalı." >&2; exit 1 ;;
esac

if ! command -v java >/dev/null 2>&1; then
    echo "Hata: JDK 17 veya daha yenisi gerekli." >&2
    exit 1
fi

(cd "$project_root/android" && ./gradlew testDebugUnitTest "$gradle_task")

source_apk="$project_root/android/app/build/outputs/apk/$variant/$apk_name"
test -f "$source_apk" || { echo "Hata: APK oluşturulamadı: $source_apk" >&2; exit 1; }
mkdir -p "$output_root"
cp "$source_apk" "$output_root/$output_name"
echo "Android paketi hazır: $output_root/$output_name"
