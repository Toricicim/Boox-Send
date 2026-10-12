import AppKit
import Foundation

/// Local, per-update results. Contains no setup code, device address or book data.
enum UpdateReceipt {
    static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/BOOX Send/Updates", isDirectory: true)
    }

    static func directory(id: String) -> URL? {
        guard let uuid = UUID(uuidString: id), uuid.uuidString == id else { return nil }
        return root.appendingPathComponent(id, isDirectory: true)
    }

    static func create() throws -> URL {
        let url = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        return url
    }

    static func startupAcknowledgement() {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--boox-update-receipt"), args.indices.contains(index + 1),
              let versionIndex = args.firstIndex(of: "--boox-update-version"), args.indices.contains(versionIndex + 1),
              let url = directory(id: args[index + 1]),
              let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              version == args[versionIndex + 1], FileManager.default.fileExists(atPath: url.path) else { return }
        try? Data(String(ProcessInfo.processInfo.processIdentifier).utf8)
            .write(to: url.appendingPathComponent("new-pid"), options: .atomic)
        // A bounded startup check, not a recurring update task or background wake-up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            try? Data("\(url.lastPathComponent)|\(version)".utf8)
                .write(to: url.appendingPathComponent("health"), options: .atomic)
        }
    }

    @MainActor static func reportPendingResult() {
        guard let id = UserDefaults.standard.string(forKey: "pendingUpdateID"), let url = directory(id: id) else { return }
        Task {
            for _ in 0..<45 {
                let status = try? String(contentsOf: url.appendingPathComponent("status"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
                if status == "success" || status == "failed" {
                    UserDefaults.standard.removeObject(forKey: "pendingUpdateID")
                    if status == "failed" {
                        let text = (try? String(contentsOf: url.appendingPathComponent("message"), encoding: .utf8))
                            ?? "The update failed. Your settings and transfer queue were kept."
                        let alert = NSAlert()
                        alert.messageText = "BOOX Send update failed"
                        alert.informativeText = text
                        NSApp.activate(ignoringOtherApps: true)
                        alert.runModal()
                    }
                    return
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            // Keep the ID so the next normal launch can display a late result.
        }
    }
}
