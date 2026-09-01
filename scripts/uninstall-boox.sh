#!/bin/sh
set -eu

command -v adb >/dev/null 2>&1 || { echo "Error: adb was not found." >&2; exit 1; }
adb uninstall com.aliumutaltas.booxsend
echo "The BOOX app and its data were removed. Files already sent to Books were preserved."
