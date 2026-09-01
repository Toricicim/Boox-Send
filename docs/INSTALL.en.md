# Installation and troubleshooting

## Complete release installation

### 1. Pair Mac and BOOX

1. Turn on Bluetooth on the Mac and BOOX.
2. Pair both devices in their normal system Bluetooth settings.

### 2. Install and configure the Mac app

1. Download and extract `BOOX-Send-<version>-macOS-universal.zip`.
2. Right-click `Install.command` and choose **Open**. Enter an administrator
   password if macOS needs it to write to `/Applications`.
3. If macOS blocks the ad-hoc build, use **System Settings → Privacy & Security
   → Open Anyway** only if you trust the source. Never disable Gatekeeper.
4. Open **System Settings → General → Login Items & Extensions → Finder** and
   enable **Send to BOOX**. This step is required for the Finder menu item to
   work; installing the workflow does not guarantee macOS enables it.
5. Open BOOX Send from `/Applications`. Click **BOOX** in the menu bar, choose
   **Settings…**, select the paired BOOX, and click **Generate**. Keep the
   eight-character code for the BOOX setup.

The installer places the app in `/Applications` and `Send to BOOX.workflow` in
`~/Library/Services`. Existing versions are moved to Trash.

### 3. Install and configure the BOOX app

1. Download `BOOX-Send-android.apk` from the same release.
2. Copy it to the BOOX and open it in the file manager. Allow installation from
   that source if Android asks. Alternatively, use Android Platform Tools:

```sh
adb devices
adb install -r BOOX-Send-android.apk
```

3. Open BOOX Send once, enter the Mac's eight-character code, and tap **Save
   Code**.
4. Tap **Choose Destination Folder**, choose `Books`, then approve **Use this
   folder**.
5. Tap **Associate Mac as Companion Device** and select the already-paired Mac.
6. In BOOX app settings, disable **Freeze** for BOOX Send and enable **App
   Startup**. This permits brief boot and presence callbacks; it does not keep
   the file receiver continuously active.

### 4. Send a file

1. The BOOX may be awake or asleep, but not shut down. Turn on Bluetooth on the
   BOOX immediately before sending; the app does not enable Bluetooth itself.
2. Select one or more regular files in Finder.
3. Right-click and choose **Quick Actions → Send to BOOX**.
4. The Quick Action opens the Mac app automatically. Normally you do not need
   to open the BOOX app; opening it starts a two-minute receiver as a fallback.
5. The BOOX receiver closes immediately after a successful transfer. The Mac
   app quits 60 seconds after processing becomes idle. Failed jobs remain on
   disk and are retried the next time the action opens the app.

## Source installation

Requirements are macOS 14+, Xcode Command Line Tools, and—when building the
BOOX app—JDK 17+, Android SDK 35, and `adb`.

```sh
xcode-select --install
./scripts/install-macos.sh
./scripts/install-boox.sh
```

## Finder action is missing

- Right-click a regular file; folders are not accepted.
- Look under the **Quick Actions** submenu.
- Enable **Send to BOOX** under **System Settings → General → Login Items &
  Extensions → Finder**.
- Refresh the service database:

  ```sh
  /System/Library/CoreServices/pbs -flush
  /System/Library/CoreServices/pbs -update
  ```

## The BOOX does not wake

- Confirm that the devices are paired in both Bluetooth settings.
- Confirm that the same eight-character code is saved on both apps.
- Disable BOOX Freeze for BOOX Send and enable App Startup.
- The BOOX must be powered on; normal sleep is fine. Turn on BOOX Bluetooth
  before invoking the Finder action.
- Some BOOX firmware may require Location Services during the initial companion
  association. BOOX Send itself does not request location data.

Failed jobs stay in `~/Library/Application Support/BOOX Send/Queue`. The Mac
app exits after its idle delay, and the next **Send to BOOX** action opens it
and retries the queue.
