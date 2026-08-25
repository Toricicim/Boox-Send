# Contributing

Thanks for helping improve BOOX Send.

1. Open an issue before a large behavioral or protocol change.
2. Keep the receiver event-driven. Do not add periodic scans, alarms, or polling
   that would reduce BOOX battery life.
3. Run `./scripts/check.sh` before submitting a pull request.
4. Describe the Mac model, macOS version, BOOX model, and BOOX firmware when
   reporting Bluetooth or wake-up issues.
5. Never commit signing keys, setup codes, Bluetooth addresses, screenshots
   containing personal data, or `android/local.properties`.

Protocol changes must update `protocol/SPEC.md` and remain backward-compatible
or increment the protocol version on both platforms.
