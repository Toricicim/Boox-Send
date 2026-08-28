# Changelog

All notable changes are documented here. This project follows Semantic
Versioning where practical.

## 1.0.2 - 2026-08-28

- Restore Companion Device presence observation after a BOOX reboot without
  opening the app.
- Use the system-bound `CompanionDeviceService` callback to start a temporary
  RFCOMM receiver, then stop it after a completed transfer or a two-minute idle
  window.
- Remove the permanent receiver process, foreground notification, Bluetooth
  polling, and periodic wake-up loop.

## 1.0.1 - 2026-08-28

- Added a BOOX boot receiver and automatic listener startup attempt.
- Reopen the RFCOMM server after transient Bluetooth stack failures.
- Reuse one destination file descriptor per transfer, substantially improving
  transfer speed while preserving resumable partial files.

## 1.0.0 - 2026-08-25

- Added Finder **BOOX’a Gönder** Quick Action.
- Added a macOS Bluetooth RFCOMM sender with a persistent retry queue.
- Added an Android 12+ BOOX receiver using Companion Device presence events.
- Added resumable, authenticated transfers with SHA-256 verification.
- Added local installers, universal macOS packaging, ADB installation, and CI.
