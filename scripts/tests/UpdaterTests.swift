import Foundation

@main
struct UpdaterTests {
    @MainActor static func main() {
        precondition(AppUpdater.isNewer("v1.0.10", than: "1.0.9"))
        precondition(AppUpdater.isNewer("v2.0.0", than: "1.99.99"))
        precondition(!AppUpdater.isNewer("v1.0.6", than: "1.0.6"))
        precondition(!AppUpdater.isNewer("v1.0.5", than: "1.0.6"))
        precondition(!AppUpdater.isNewer("v1.0.7-beta", than: "1.0.6"))
        precondition(!AppUpdater.isNewer("v1..7", than: "1.0.6"))
        precondition(!AppUpdater.isNewer("v999999999999999999999.0.1", than: "1.0.6"))
        func assetAccepted(_ url: String, digest: String?) -> Bool {
            let release = AppUpdater.Release(tag_name: "v1.0.6", draft: false, prerelease: false,
                assets: [AppUpdater.Asset(name: "BOOX-Send-1.0.6-macOS-universal.zip", browser_download_url: url,
                    digest: digest, size: 1000)])
            return (try? AppUpdater.asset(for: release)) != nil
        }
        let url = "https://github.com/Toricicim/Boox-Send/releases/download/v1.0.6/BOOX-Send-1.0.6-macOS-universal.zip"
        let digest = "sha256:" + String(repeating: "a", count: 64)
        precondition(assetAccepted(url, digest: digest))
        precondition(!assetAccepted(url.replacingOccurrences(of: "https", with: "http"), digest: digest))
        precondition(!assetAccepted(url.replacingOccurrences(of: "github.com", with: "github.com.evil.test"), digest: digest))
        precondition(!assetAccepted(url.replacingOccurrences(of: "Toricicim", with: "other"), digest: digest))
        precondition(!assetAccepted(url, digest: nil))
        precondition(UpdateReceipt.directory(id: "../../Applications") == nil)
        precondition(UpdateReceipt.directory(id: UUID().uuidString) != nil)
        print("Mac updater version and download validation checks passed.")
    }
}
