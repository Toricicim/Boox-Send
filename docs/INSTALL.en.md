# Installation and troubleshooting

## Release package

### Mac

1. Extract `BOOX-Send-<version>-macOS-universal.zip`.
2. Double-click `Install.command`. Enter an administrator password if macOS
   needs it to write to `/Applications`.
3. If an ad-hoc development build is blocked, right-click `Install.command`
   and choose **Open**. Never disable Gatekeeper for an untrusted package.

The installer places the app in `/Applications` and the Finder workflow in
`~/Library/Services` while moving an existing version to Trash.

### BOOX

Copy the APK to the BOOX and open it in the file manager, or use Android
Platform Tools:

```sh
adb devices
adb install -r BOOX-Send-android.apk
```

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
- Enable `BOOX’a Gönder` under **System Settings → General → Login Items &
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
- The BOOX must be powered on with Bluetooth enabled; normal sleep is fine.
- Some BOOX firmware may require Location Services during the initial companion
  association. BOOX Send itself does not request location data.

Failed jobs stay in `~/Library/Application Support/BOOX Send/Queue` and can be
retried from the Mac menu bar.
