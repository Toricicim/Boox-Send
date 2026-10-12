import Foundation

@main
struct HelperProbe {
    static func main() throws {
        let bundle = Bundle.main
        let root = bundle.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        let behavior = bundle.object(forInfoDictionaryKey: "TestBehavior") as? String ?? "crash"
        if behavior == "old" {
            try Data("restored".utf8).write(to: root.appendingPathComponent("old-opened"), options: .atomic)
            return
        }
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--boox-update-receipt"), args.indices.contains(index + 1),
              let versionIndex = args.firstIndex(of: "--boox-update-version"), args.indices.contains(versionIndex + 1) else { exit(1) }
        let id = args[index + 1]
        let receipt = root.appendingPathComponent("receipts/\(id)")
        try Data(String(ProcessInfo.processInfo.processIdentifier).utf8).write(to: receipt.appendingPathComponent("new-pid"), options: .atomic)
        if behavior == "crash" { exit(1) }
        if behavior == "healthy" {
            try Data("\(id)|\(args[versionIndex + 1])".utf8).write(to: receipt.appendingPathComponent("health"), options: .atomic)
        }
        Thread.sleep(forTimeInterval: 3)
    }
}
