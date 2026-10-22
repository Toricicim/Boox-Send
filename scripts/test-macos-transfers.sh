#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/boox-send-transfer-tests.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
xcrun swiftc -swift-version 5 -D BOOX_LOCAL_ADHOC -parse-as-library \
    "$project_root/macos/Shared/Constants.swift" \
    "$project_root/macos/Shared/SharedQueue.swift" \
    "$project_root/macos/Shared/WireProtocol.swift" \
    "$project_root/macos/BooxSend/RFCOMMConnection.swift" \
    "$project_root/macos/BooxSend/TransferProgress.swift" \
    "$project_root/macos/BooxSend/TransferCoordinator.swift" \
    "$project_root/scripts/tests/TransferTests.swift" \
    -o "$test_root/TransferTests"
"$test_root/TransferTests"
