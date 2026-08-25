#!/bin/sh
set -eu

command -v adb >/dev/null 2>&1 || { echo "Hata: adb bulunamadı." >&2; exit 1; }
adb uninstall com.aliumutaltas.booxsend
echo "BOOX uygulaması ve uygulama verileri kaldırıldı. Books klasörüne gönderilen dosyalar korundu."
