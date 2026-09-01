# BOOX Send

Right-click one or more files on a Mac and choose **Quick Actions → Send to
BOOX** to transfer them to the `Books` folder of a BOOX Go 10.3 over
Bluetooth, without a cloud service, internet connection, or cable.

> This project grew out of a real need: sending an occasional file from a Mac
> to a BOOX was needlessly awkward. It was developed with an AI-assisted
> **vibe-coding** workflow and tested iteratively on real hardware. It is being
> shared as free, open-source software for others with the same need. Review
> and test the code before relying on it for important files.

[Turkish README](docs/README.tr.md) · [Installation](docs/INSTALL.en.md) ·
[Changelog](CHANGELOG.md) · [Contributing](CONTRIBUTING.md)

## Features

- A Finder Quick Action for one or more selected files.
- Bluetooth RFCOMM transfer directly between paired devices; no server or
  account.
- Automatic receiver wake-up after a BOOX reboot through Android Companion
  Device presence; the BOOX app does not need to be opened again.
- Resume support for interrupted queue jobs and SHA-256 verification.
- Collision-safe names such as `book (1).pdf` instead of overwriting files.
- A temporary blocking RFCOMM listener with no periodic scan, alarm, or refresh
  loop.
- The Mac app opens for a Quick Action and quits automatically after 60 idle
  seconds.

BOOX Send is not a folder synchronization tool. It sends only files explicitly
selected by the user and never mirrors deletions.

## How it works

```text
Finder Quick Action
        ↓
Local queue on the Mac
        ↓  Bluetooth Classic / SDP + RFCOMM
BOOX boot restores Companion observation
        ↓  Mac connection triggers a presence event
Temporary RFCOMM receiver (two-minute idle window)
        ↓
BOOX Books folder + SHA-256 verification
```

The Finder action stages selected files in a local Mac queue. The sender uses
SDP for service discovery and a custom RFCOMM service over Bluetooth Classic
BR/EDR for the byte stream—there is no BLE/GATT transport, internet service, or
cloud relay. See Android’s
[`BluetoothServerSocket` documentation](https://developer.android.com/reference/android/bluetooth/BluetoothServerSocket).

On the BOOX, a boot receiver restores Android Companion Device presence
observation. When the paired Mac appears, Android's Companion callback or its
protected Bluetooth connection event starts a temporary RFCOMM receiver; the
Mac's next SDP retry finds it and completes the transfer. The receiver
blocks in `accept()` without polling and stops as soon as a transfer completes,
or after two minutes if no transfer arrives. Companion association does not
itself create a connection or enable continuous application scanning; see the
official
[Companion Device documentation](https://developer.android.com/develop/connectivity/bluetooth/companion-device-pairing).

## Battery behavior

BOOX Send schedules no periodic Bluetooth scan, WorkManager task, job, alarm,
timer, or refresh loop and does not require a permanent foreground service.
With no send attempt, the app has no receiver service or RFCOMM socket running.
A Mac connection wakes a temporary receiver, which waits up to two minutes for
a file and stays alive only while an active transfer is running. A blocked
`accept()` does not poll or continuously consume CPU. Keeping the system
Bluetooth radio and Companion presence observation enabled still has a
firmware-dependent baseline cost, so this is not a zero-battery-cost design. No
controlled multi-day battery percentage claim is currently made. See Android’s
[background Bluetooth guide](https://developer.android.com/develop/connectivity/bluetooth/ble/background).

## When the apps run

Neither side is designed to remain open continuously:

- **Mac:** the Finder Quick Action adds the selected files to the local queue
  and opens BOOX Send automatically. The app transfers the queue, then quits
  after 60 seconds with no active processing. A failed job remains on disk, but
  the app still quits; the next Quick Action launch retries the queue. The
  automatic quit is postponed while the Settings window is visible.
- **BOOX:** the setup screen does not open during a normal transfer. Android
  uses the paired Mac's Companion or protected Bluetooth connection event to
  start the temporary RFCOMM receiver. Opening BOOX Send manually starts the
  same temporary receiver as a fallback. It stops immediately after success.
  If no transfer arrives, it closes after a two-minute idle window. No permanent
  foreground or background receiver service remains running.
- **Before sending:** turn on Bluetooth on the BOOX. BOOX Send does not enable
  Bluetooth itself. You may leave BOOX Bluetooth off between transfers if you
  prefer, then enable it immediately before using the Finder action.

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
- The BOOX must be awake with Bluetooth enabled before starting a Finder
  action. On the tested Go 10.3 firmware, sleep can turn Bluetooth off, so an
  incoming transfer cannot wake the device from that state.

## Installation and first-time setup

### 1. Pair the devices

1. Turn on Bluetooth on both devices.
2. Pair the Mac and BOOX in their normal system Bluetooth settings.

### 2. Install the Mac side

1. Download `BOOX-Send-<version>-macOS-universal.zip` from **Releases** and
   extract it.
2. Right-click `Install.command` and choose **Open**. If macOS blocks it, open
   **System Settings → Privacy & Security** and choose **Open Anyway** only if
   you trust this project.
3. The installer places `BOOX Send.app` in `/Applications` and `Send to
   BOOX.workflow` in `~/Library/Services`.
4. Enable the action in **System Settings → General → Login Items & Extensions
   → Finder**. Open the Finder extension details if shown, then enable **Send to
   BOOX**. This step is required; installing the workflow alone does not always
   make it available in Finder.
5. Open **BOOX Send** once from Applications. Click the **BOOX** menu bar item,
   choose **Settings…**, select the paired BOOX, and click **Generate** to make
   an eight-character setup code.

### 3. Install the BOOX side

1. Download `BOOX-Send-android.apk` from the same release.
2. Copy it to the BOOX, open it in the BOOX file manager, and approve
   installation from that source if Android asks. Alternatively, install it
   over USB debugging:

   ```sh
   adb install -r BOOX-Send-android.apk
   ```

3. Open BOOX Send once. Enter the same eight-character code from the Mac and
   tap **Save Code**.
4. Tap **Choose Destination Folder**, select `Books`, and approve **Use this
   folder**.
5. Tap **Associate Mac as Companion Device** and select the already-paired Mac.
6. Open BOOX app settings, disable **Freeze** for BOOX Send, and enable **App
   Startup**. These settings let Android deliver the brief boot/presence event;
   they do not keep BOOX Send permanently active.

### 4. Enable and use the Finder action

1. Before each transfer, wake the BOOX and confirm that Bluetooth is enabled.
   If the device has slept, its firmware may have turned Bluetooth off.
2. In Finder, select one or more regular files.
3. Right-click and choose **Quick Actions → Send to BOOX**. If it is absent,
   choose **Customize…** or return to **System Settings → General → Login Items
   & Extensions → Finder** and enable it.
4. The Mac app opens automatically. You do not need to open the BOOX app.
5. After the queue finishes, the Mac app quits after 60 idle seconds. The BOOX
   receiver closes immediately after the transfer.

### One-command source installation

Install Xcode Command Line Tools first:

```sh
xcode-select --install
```

After downloading the repository, run:

```sh
./scripts/install.sh
```

This installs the Mac app and Finder Quick Action. If exactly one BOOX is
connected with USB debugging, it also builds and installs the Android app. To
install each side separately:

```sh
./scripts/install-macos.sh
./scripts/install-boox.sh
```

Building the Android side also requires JDK 17+, Android SDK 35, and `adb`. See
the complete [installation and troubleshooting guide](docs/INSTALL.en.md).

## Development

```sh
make check          # source validation and tests
make build-macos    # Mac app for the current architecture
make build-android  # debug APK
make package        # universal Apple Silicon + Intel release ZIP
```

The signed Finder extension target remains available in the XcodeGen project.
The free local installer uses the more reliable Automator Quick Action so it
does not depend on a paid Apple signing identity.

Docker is deliberately not the primary build path: macOS signing, Finder
services, IOBluetooth, and physical USB/ADB access cannot be supplied by a Linux
container. CI provides repeatable source checks instead.

## Privacy and security

There is no cloud component, account, telemetry, or analytics. The setup code
authenticates the application protocol with HMAC-SHA256. File contents are not
additionally encrypted at the application layer and rely on the paired
Bluetooth link. See [SECURITY.md](SECURITY.md).

## Uninstallation

```sh
./scripts/uninstall-macos.sh          # keep the queue and settings
./scripts/uninstall-macos.sh --purge  # move the queue and settings to Trash
./scripts/uninstall-boox.sh           # uninstall from the BOOX through ADB
```

Files already delivered to the `Books` folder are never removed by these
commands.

## License

[MIT](LICENSE). This project is unofficial and is not affiliated with ONYX,
BOOX, or Apple. BOOX is a trademark of its respective owner.
