import AppKit
import Foundation
import UniformTypeIdentifiers

final class ActionRequestHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let providers = context.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }

        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        var firstError: Error?

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                defer { group.leave() }
                lock.lock(); defer { lock.unlock() }
                if let error { firstError = firstError ?? error; return }
                if let url = item as? URL { urls.append(url) }
                else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) { urls.append(url) }
            }
        }

        group.notify(queue: .global(qos: .userInitiated)) {
            do {
                if let firstError { throw firstError }
                guard !urls.isEmpty else {
                    throw NSError(domain: "BooxSendFinder", code: 1, userInfo: [NSLocalizedDescriptionKey: "No files selected"])
                }
                _ = try SharedQueue.shared.enqueue(urls: urls)
                DistributedNotificationCenter.default().post(name: BooxConstants.queueNotification, object: nil)
                DispatchQueue.main.async {
                    if let url = URL(string: "booxsend://queue") { NSWorkspace.shared.open(url) }
                    context.completeRequest(returningItems: [], completionHandler: nil)
                }
            } catch {
                context.cancelRequest(withError: error)
            }
        }
    }
}
