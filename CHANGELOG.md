# Changelog

All notable changes are documented here. This project follows Semantic
Versioning where practical.

## 1.0.4 - 2026-09-01

- Fix the Mac menu bar **Settings…** action on current macOS versions.
- Show the settings window automatically on first launch when the BOOX device
  or setup code has not been configured.
- Clarify that the BOOX must be awake with Bluetooth enabled before sending.

## 1.0.3 - 2026-09-01

- Translate the Mac app, BOOX app, Finder Quick Action, notifications, and
  installers to English.
- Rename the Finder Quick Action to **Send to BOOX** and migrate the previous
  Turkish workflow during installation.
- Automatically quit the Mac menu bar app 60 seconds after transfer processing
  becomes idle, while preserving failed queue jobs for the next launch.
- Wake the temporary BOOX receiver from the paired Mac's protected Bluetooth
  connection event, with Companion presence as a second event-driven path.
- Make opening the BOOX setup app start the same two-minute receiver window as
  a manual fallback, and reset failed Mac Bluetooth links between retries.
- Expand the installation, Quick Action enablement, lifecycle, and battery
  documentation.

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
