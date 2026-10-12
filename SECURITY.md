# Security

Please report security issues privately to the repository owner instead of
opening a public issue. Add a private security advisory in GitHub under
**Security > Advisories > New draft advisory**.

BOOX Send has no cloud file-transfer component. While already open, the apps
check GitHub's release API at most daily and download only user-approved updates.
No books, Bluetooth addresses or setup codes are sent to GitHub. Update downloads
are checked against GitHub's SHA-256 metadata. The Android updater also verifies
the existing APK signing identity and rejects different keys and downgrades.
Mac release apps use ad-hoc signatures, not Apple Developer ID authentication;
the Mac updater trusts this project's GitHub release metadata over HTTPS and
checks the app ID, version and code-signature integrity before replacement.

The eight-character setup code authenticates
the application protocol with HMAC-SHA256; file contents are not additionally
encrypted by the application. Transfers rely on the security of the paired
Bluetooth link. Do not share setup codes or Android signing keys.
