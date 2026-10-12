# Changelog

All notable changes are documented here. This project follows Semantic
Versioning where practical.

## 1.0.7 - 2026-10-12

- Always fetch fresh release metadata for manual update checks. Failed automatic
  checks can retry on a later app opening, without adding scheduled wake-ups.
- Keep BOOX downloads in application-scoped state, detach paused setup screens,
  prevent overlapping operations and replace cached APKs atomically.
- Reuse verified downloaded APKs, including after setup-screen recreation; add
  **Install Downloaded Update** and recover from damaged cached files.
- Prepare Mac replacements before quitting, record persistent install results,
  require a startup acknowledgement, and restore/reopen the previous app on failure.
- Add real Mac installer success/crash/cancellation tests and isolated Go 10.3
  updater tests covering native APK signatures, cache reuse, observer replacement,
  invalid checksums, fresh metadata and FileProvider access.

## 1.0.6 - 2026-10-12

- Add in-app update checks, downloads and user-approved installation on Mac and
  BOOX. Automatic checks run at most once per day while the app is already open;
  no update scheduler, boot check or background wake-up is added.
- Verify GitHub release SHA-256 checksums and reject downgrades; the BOOX updater
  also verifies the APK package, version and signing certificate before installation.
- Preserve setup codes, selected companion devices, folder grants, files and Mac
  queue/Quick Action configuration by updating in place, without uninstalling.
- Retain the previous Mac app for recovery and block installation when Mac queue
  transfer attempts or a BOOX Bluetooth transfer are active. Failed queue jobs
  survive updates so they can be retried with the new version.

## 1.0.5 - 2026-10-12

- Select the Mac from already-paired Bluetooth devices before requesting
  Companion access. Filter the system request by its exact Bluetooth address
  so unpaired nearby devices cannot trigger unrelated permission prompts.
- Reuse an existing association for the selected Mac and preserve the selection
  across setup screen recreation.
- Stop recovering an arbitrary first association left by the old broad scan.

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
