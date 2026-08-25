# BOOX Send

Right-click one or more files on a Mac and choose **Quick Actions → BOOX’a
Gönder** to transfer them to the `Books` folder of a BOOX Go 10.3 over
Bluetooth, without a cloud service, internet connection, or cable.

> This project grew out of a real need: sending an occasional file from a Mac
> to a BOOX was needlessly awkward. It was developed with an AI-assisted
> **vibe-coding** workflow and tested iteratively on real hardware. It is being
> shared as free, open-source software for others with the same need. Review
> and test the code before relying on it for important files.

[Türkçe README](../README.md) · [Installation](INSTALL.en.md) ·
[Changelog](../CHANGELOG.md) · [Contributing](../CONTRIBUTING.md)

## Features

- A Finder Quick Action for one or more selected files.
- Bluetooth RFCOMM transfer directly between paired devices; no server or
  account.
- Event-driven wake-up through Android Companion Device presence callbacks.
- Resume support for interrupted queue jobs and SHA-256 verification.
- Collision-safe names such as `book (1).pdf` instead of overwriting files.
- The BOOX receiver stops after 15 idle seconds and uses no periodic scan,
  alarm, or refresh loop.

BOOX Send is not a folder synchronization tool. It sends only files explicitly
selected by the user and never mirrors deletions.

## How it works and why it stays idle

The Finder action stages selected files in a local Mac queue. The sender uses
SDP for service discovery and a custom RFCOMM service over Bluetooth Classic
BR/EDR for the byte stream—there is no BLE/GATT transport, internet service, or
cloud relay. See Android’s
[`BluetoothServerSocket` documentation](https://developer.android.com/reference/android/bluetooth/BluetoothServerSocket).

On the BOOX, an Android Companion Device presence event starts a short-lived
`connectedDevice` foreground service. It accepts the RFCOMM session, verifies
the file with SHA-256, and stops after 15 seconds without another connection.
Companion association does not itself create a connection or enable continuous
application scanning; see the official
[Companion Device documentation](https://developer.android.com/develop/connectivity/bluetooth/companion-device-pairing).

BOOX Send schedules no periodic Bluetooth scan, WorkManager task, job, alarm,
timer, or refresh loop and keeps no permanent foreground service or socket.
Hardware checks confirmed that no BOOX Send service remained running while
idle. This minimizes the app’s idle overhead, but it does not make Bluetooth
free: keeping the system radio enabled still has a firmware-dependent baseline
cost. No controlled multi-day battery percentage claim is currently made. The
design follows Android’s advice to wake for device presence instead of
periodically waking the app to scan; see the
[background Bluetooth guide](https://developer.android.com/develop/connectivity/bluetooth/ble/background).

## Distribution without paid certificates

- **Android/BOOX:** APK signing is required but free. A self-generated release
  keystore can be stored as GitHub Actions secrets so every update uses the same
  identity.
- **macOS:** Apple-recognized Developer ID signing and notarization require a
  paid Apple Developer membership. The free recommended path is to build
  locally with `./scripts/install-macos.sh`. The ad-hoc release ZIP also works,
  but macOS can require **Privacy & Security → Open Anyway** on first launch.
  Follow [Apple’s guidance](https://support.apple.com/guide/mac-help/mh40616/mac)
  and override the warning only for source you trust.

Paid Apple signing improves the downloaded-binary experience; it is not needed
for source installation or Bluetooth transfers.

## Compatibility

- Hardware-tested on a **BOOX Go 10.3 with Android 12-based firmware**.
- Requires **macOS 14 or later** on Apple Silicon or Intel.
- Other Android 12+ BOOX devices may work but are currently unverified.
- A BOOX can be asleep, but it must be powered on with Bluetooth enabled.

## Quick installation

Download the macOS ZIP and Android APK from GitHub **Releases**. Extract the ZIP
and double-click `Install.command`, then install the APK on the BOOX. For a
source installation, install Xcode Command Line Tools and run:

```sh
./scripts/install.sh
```

See the complete [installation and troubleshooting guide](INSTALL.en.md).

## First-time setup

1. Pair the Mac and BOOX in their normal system Bluetooth settings.
2. Open BOOX Send settings from the Mac menu bar, select the paired BOOX, and
   generate an eight-character setup code.
3. Open BOOX Send on the BOOX and save the same code.
4. Select the `Books` destination folder.
5. Associate the Mac as the companion device.
6. Disable BOOX Freeze for the app and enable App Startup.

Use **Quick Actions → BOOX’a Gönder** in Finder. Unavailable transfers remain in
the Mac queue and can be retried from the menu bar.

## Development

```sh
make check
make build-macos
make build-android
make package
```

Docker is deliberately not the primary build path: macOS signing, Finder
services, IOBluetooth, and physical USB/ADB access cannot be supplied by a Linux
container. CI provides repeatable source checks instead.

## Privacy and security

There is no cloud component, account, telemetry, or analytics. The setup code
authenticates the application protocol with HMAC-SHA256. File contents are not
additionally encrypted at the application layer and rely on the paired
Bluetooth link. See [SECURITY.md](../SECURITY.md).

## License

[MIT](../LICENSE). This project is unofficial and is not affiliated with ONYX,
BOOX, or Apple. BOOX is a trademark of its respective owner.
