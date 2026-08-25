# Security

Please report security issues privately to the repository owner instead of
opening a public issue. Add a private security advisory in GitHub under
**Security > Advisories > New draft advisory**.

BOOX Send has no cloud component. The eight-character setup code authenticates
the application protocol with HMAC-SHA256; file contents are not additionally
encrypted by the application. Transfers rely on the security of the paired
Bluetooth link. Do not share setup codes or Android signing keys.
