# Changelog

All notable changes are documented here. This project follows Semantic
Versioning where practical.

## 1.0.1 - 2026-08-28

- Start the BOOX RFCOMM listener automatically after a device reboot without
  opening the app.
- Keep the listener available with a blocking socket and no Bluetooth polling
  or periodic wake-up loop.
- Reopen the RFCOMM server after transient Bluetooth stack failures.
- Reuse one destination file descriptor per transfer, substantially improving
  transfer speed while preserving resumable partial files.

## 1.0.0 - 2026-08-25

- Added Finder **BOOX’a Gönder** Quick Action.
- Added a macOS Bluetooth RFCOMM sender with a persistent retry queue.
- Added an Android 12+ BOOX receiver using Companion Device presence events.
- Added resumable, authenticated transfers with SHA-256 verification.
- Added local installers, universal macOS packaging, ADB installation, and CI.
