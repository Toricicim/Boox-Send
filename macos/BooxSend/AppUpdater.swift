import AppKit
import CryptoKit
import Foundation

@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()
    @Published private(set) var availableVersion: String?
    private(set) var isBusy = false
    var onChange: (() -> Void)?
    private let defaults = UserDefaults.standard

    struct Release: Decodable {
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }
    struct Asset: Decodable {
        let name: String
        let browser_download_url: String
        let digest: String?
        let size: Int
    }

    static func isNewer(_ next: String, than current: String) -> Bool {
        func parts(_ value: String) -> [Int]? {
            let text = value.hasPrefix("v") ? String(value.dropFirst()) : value
            let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
            guard pieces.count == 3, pieces.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) else { return nil }
            let numbers = pieces.compactMap { Int($0) }
            return numbers.count == 3 ? numbers : nil
        }
        guard let a = parts(next), let b = parts(current) else { return false }
        return b.lexicographicallyPrecedes(a)
    }

    func check(manual: Bool) {
        guard !isBusy else { return }
        let now = Date().timeIntervalSince1970
        if !manual, now - defaults.double(forKey: "lastUpdateSuccess") < 86400 || now - defaults.double(forKey: "lastUpdateAttempt") < 900 { return }
        defaults.set(now, forKey: "lastUpdateAttempt")
        isBusy = true
        onChange?()
        Task {
            defer { isBusy = false; onChange?() }
            do {
                var request = URLRequest(url: URL(string: "https://api.github.com/repos/Toricicim/Boox-Send/releases/latest")!, cachePolicy: .reloadIgnoringLocalCacheData)
                request.timeoutInterval = 15
                request.setValue("BOOX-Send-Updater", forHTTPHeaderField: "User-Agent")
                request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
                let (data, response) = try await URLSession.shared.data(for: request)
                try Self.validateResponse(response)
                let release = try JSONDecoder().decode(Release.self, from: data)
                guard !release.draft, !release.prerelease else { throw failure("No stable release is available.") }
                let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
                if Self.isNewer(release.tag_name, than: current) {
                    _ = try Self.asset(for: release)
                    availableVersion = release.tag_name
                    if manual { DispatchQueue.main.async { self.offer(release) } }
                } else {
                    availableVersion = nil
                    if manual { message("You're up to date", "BOOX Send \(current) is installed.") }
                }
                defaults.set(now, forKey: "lastUpdateSuccess")
            } catch {
                availableVersion = nil
                if manual { message("Could not check for updates", error.localizedDescription + " Bluetooth transfers still work offline.") }
            }
        }
    }

    static func asset(for release: Release) throws -> Asset {
        let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        let name = "BOOX-Send-\(version)-macOS-universal.zip"
        guard let asset = release.assets.first(where: { $0.name == name }),
              asset.size > 0, asset.size <= 100 * 1024 * 1024,
              asset.browser_download_url == "https://github.com/Toricicim/Boox-Send/releases/download/\(release.tag_name)/\(name)",
              let digest = asset.digest, digest.range(of: "^sha256:[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw NSError(domain: "BOOXUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey: "The Mac update or its checksum is not available."])
        }
        return asset
    }

    private func offer(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = "Update BOOX Send to \(release.tag_name)?"
        alert.informativeText = "Your paired BOOX, setup code, Finder Quick Action and transfer queue will be kept. The app will download the update over the internet, then restart. Finish pending transfers first."
        alert.addButton(withTitle: "Download and Install")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { install(release) }
    }

    private func ensureTransferIdle() throws {
        guard !TransferCoordinator.shared.isProcessing else {
            throw failure("Wait for the active transfer attempt to finish before installing an update. Failed jobs will be kept for retry after updating.")
        }
    }

    private func install(_ release: Release) {
        guard !isBusy else { return }
        isBusy = true
        onChange?()
        Task {
            var staging: URL?
            var handedOff = false
            var installer: Process?
            var receiptDirectory: URL?
            defer {
                if !handedOff, let staging { try? FileManager.default.removeItem(at: staging) }
                isBusy = false
                onChange?()
            }
            do {
                try ensureTransferIdle()
                let asset = try Self.asset(for: release)
                let destination = Bundle.main.bundleURL
                guard FileManager.default.isWritableFile(atPath: destination.deletingLastPathComponent().path) else {
                    throw failure("The app's folder is not writable. Move BOOX Send to a folder you can write to, or update with the installer using an administrator account.")
                }
                let helper = destination.appendingPathComponent("Contents/Resources/InstallUpdate.sh")
                guard FileManager.default.fileExists(atPath: helper.path) else {
                    throw failure("This build does not include the update installer. Update it using the same build method.")
                }
                var request = URLRequest(url: URL(string: asset.browser_download_url)!)
                request.timeoutInterval = 120
                let (download, response) = try await URLSession.shared.download(for: request)
                try Self.validateResponse(response)
                let size = try FileManager.default.attributesOfItem(atPath: download.path)[.size] as? NSNumber
                guard size?.intValue == asset.size else { throw failure("The update download is incomplete.") }
                let digest = SHA256.hash(data: try Data(contentsOf: download)).map { String(format: "%02x", $0) }.joined()
                guard "sha256:\(digest)" == asset.digest else { throw failure("The update checksum did not match. Please retry.") }
                let root = FileManager.default.temporaryDirectory.appendingPathComponent("boox-send-update-\(UUID().uuidString)")
                staging = root
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                let archive = root.appendingPathComponent("update.zip")
                try FileManager.default.moveItem(at: download, to: archive)
                try Self.run("/usr/bin/ditto", ["-x", "-k", archive.path, root.path])
                let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
                let app = root.appendingPathComponent("BOOX-Send-\(version)-macOS/BOOX Send.app")
                let plist = app.appendingPathComponent("Contents/Info.plist")
                let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as? [String: Any]
                guard info?["CFBundleIdentifier"] as? String == "com.aliumutaltas.BooxSend",
                      info?["CFBundleShortVersionString"] as? String == version else { throw failure("The update has an unexpected app identity or version.") }
                try Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
                try ensureTransferIdle()
                let stagedHelper = root.appendingPathComponent("InstallUpdate.sh")
                try FileManager.default.copyItem(at: helper, to: stagedHelper)
                let process = Process()
                installer = process
                let receipt = try UpdateReceipt.create()
                receiptDirectory = receipt
                defaults.set(receipt.lastPathComponent, forKey: "pendingUpdateID")
                defaults.synchronize()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = [stagedHelper.path, app.path, destination.path, String(ProcessInfo.processInfo.processIdentifier), receipt.path, version]
                let log = receipt.appendingPathComponent("install.log")
                FileManager.default.createFile(atPath: log.path, contents: nil)
                let output = try FileHandle(forWritingTo: log)
                process.standardOutput = output
                process.standardError = output
                try process.run()
                // The installed app stays running until its replacement is fully staged.
                var prepared = false
                for _ in 0..<600 {
                    let status = try? String(contentsOf: receipt.appendingPathComponent("status"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
                    if status == "prepared" { prepared = true; break }
                    if status == "failed" || !process.isRunning { break }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                if !prepared {
                    let text = (try? String(contentsOf: receipt.appendingPathComponent("message"), encoding: .utf8))
                        ?? "The installer could not prepare the update. Your current app has been kept."
                    throw failure(text)
                }
                try ensureTransferIdle()
                handedOff = true
                NSApp.terminate(nil)
            } catch {
                if let installer, installer.isRunning {
                    installer.terminate()
                    for _ in 0..<50 {
                        if !installer.isRunning { break }
                        try? await Task.sleep(nanoseconds: 100_000_000)
                    }
                }
                if let receiptDirectory, defaults.string(forKey: "pendingUpdateID") == receiptDirectory.lastPathComponent {
                    defaults.removeObject(forKey: "pendingUpdateID")
                }
                message("Could not install update", error.localizedDescription)
            }
        }
    }

    private static func run(_ command: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "BOOXUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey: "Update validation failed (\(URL(fileURLWithPath: command).lastPathComponent))."])
        }
    }

    private static func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), response.url?.scheme == "https" else {
            throw NSError(domain: "BOOXUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey: "The update server could not be reached over HTTPS."])
        }
    }

    private func failure(_ text: String) -> NSError { NSError(domain: "BOOXUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    private func message(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
