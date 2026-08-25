# Release guide

## Versioning

Update these values together:

- `VERSION`
- Android `versionCode` and `versionName` in `android/app/build.gradle.kts`
- `CHANGELOG.md`

## Android signing

Create one release keystore and keep it outside the repository. Losing it means
users cannot install a future APK as an update.

Creating and using this Android key is free and does not require a Google Play
or other paid developer account.

```sh
keytool -genkeypair -v -keystore boox-send-release.jks \
  -alias boox-send -keyalg RSA -keysize 4096 -validity 10000
```

Configure these GitHub Actions secrets:

- `ANDROID_KEYSTORE_BASE64`: `base64 < boox-send-release.jks | pbcopy`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Never commit the keystore.

## macOS signing and notarization

`scripts/package-release.sh` creates an ad-hoc signed universal ZIP by default.
This is suitable for source testing, but public binary releases should be
signed with an Apple **Developer ID Application** certificate and notarized.

If you do not want a paid Apple Developer membership, publish the source
installer as the primary Mac installation method. You may still attach the
ad-hoc ZIP for users who understand the Gatekeeper warning; never instruct
users to disable Gatekeeper globally.

To sign locally before packaging:

```sh
MACOS_SIGN_IDENTITY='Developer ID Application: Name (TEAMID)' \
  BOOX_SEND_ARCHS='arm64 x86_64' \
  ./scripts/build-macos.sh
```

Submit the app archive with `xcrun notarytool`, wait for acceptance, and staple
the ticket with `xcrun stapler staple` before producing the final ZIP. Do not
tell users to disable Gatekeeper.

## GitHub release

1. Run `make check` and the hardware acceptance test.
2. Push the repository and create a `v<version>` tag.
3. The release workflow builds the universal Mac ZIP and stable-key Android
   APK, then creates a draft GitHub Release. Its Mac asset is ad-hoc signed;
   replace it with a Developer ID-signed and notarized ZIP for a public release.
4. Download and test both assets on clean devices.
5. Add release notes from `CHANGELOG.md` and publish the draft.
