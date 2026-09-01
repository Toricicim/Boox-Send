import Foundation

let urls = CommandLine.arguments.dropFirst().map { URL(fileURLWithPath: $0) }

do {
    let job = try SharedQueue.shared.enqueue(urls: urls)
    DistributedNotificationCenter.default().post(name: BooxConstants.queueNotification, object: nil)
    print(job.id.uuidString)
} catch {
    FileHandle.standardError.write(Data("Could not send to BOOX: \(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
