import Foundation
import OSLog

struct TransferJob: Codable, Identifiable, Sendable {
    enum State: String, Codable, Sendable { case pending, sending, completed, failed }

    let id: UUID
    let createdAt: Date
    var files: [QueuedFile]
    var state: State
    var error: String?
}

struct QueuedFile: Codable, Identifiable, Sendable {
    let id: UUID
    let stagedName: String
    let originalName: String
    let byteCount: UInt64
}

enum SharedQueueError: LocalizedError {
    case appGroupUnavailable
    case noFiles

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable: return "BOOX Send app group is unavailable."
        case .noFiles: return "No regular files were selected."
        }
    }
}

final class SharedQueue {
    static let shared = SharedQueue()

    private let fm = FileManager.default
    private let logger = Logger(subsystem: "com.aliumutaltas.BooxSend", category: "queue")
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private var root: URL {
        get throws {
#if BOOX_LOCAL_ADHOC
            return fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/BOOX Send/Queue", isDirectory: true)
#else
            guard let container = fm.containerURL(forSecurityApplicationGroupIdentifier: BooxConstants.appGroup) else {
                throw SharedQueueError.appGroupUnavailable
            }
            return container.appendingPathComponent("Queue", isDirectory: true)
#endif
        }
    }

    func enqueue(urls: [URL]) throws -> TransferJob {
        let jobID = UUID()
        let jobDirectory = try root.appendingPathComponent(jobID.uuidString, isDirectory: true)
        try fm.createDirectory(at: jobDirectory, withIntermediateDirectories: true)

        var files: [QueuedFile] = []
        for source in urls where source.hasDirectoryPath == false {
            let id = UUID()
            let stagedName = id.uuidString
            let destination = jobDirectory.appendingPathComponent(stagedName)
            let accessed = source.startAccessingSecurityScopedResource()
            defer { if accessed { source.stopAccessingSecurityScopedResource() } }
            try fm.copyItem(at: source, to: destination)
            let values = try destination.resourceValues(forKeys: [.fileSizeKey])
            files.append(QueuedFile(
                id: id,
                stagedName: stagedName,
                originalName: source.lastPathComponent,
                byteCount: UInt64(values.fileSize ?? 0)
            ))
        }

        guard !files.isEmpty else {
            try? fm.removeItem(at: jobDirectory)
            throw SharedQueueError.noFiles
        }

        var job = TransferJob(id: jobID, createdAt: Date(), files: files, state: .pending, error: nil)
        try save(&job)
        return job
    }

    func jobs() throws -> [TransferJob] {
        let queueRoot = try root
        try fm.createDirectory(at: queueRoot, withIntermediateDirectories: true)
        let directories = try fm.contentsOfDirectory(at: queueRoot, includingPropertiesForKeys: nil)
        logger.notice("Queue path \(queueRoot.path, privacy: .public) contains \(directories.count, privacy: .public) item(s)")
        return directories.compactMap { directory in
                let metadata = directory.appendingPathComponent("job.json")
                do {
                    let data = try Data(contentsOf: metadata)
                    return try decoder.decode(TransferJob.self, from: data)
                } catch {
                    logger.error("Could not load queue metadata at \(metadata.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func fileURL(jobID: UUID, file: QueuedFile) throws -> URL {
        try root.appendingPathComponent(jobID.uuidString, isDirectory: true)
            .appendingPathComponent(file.stagedName)
    }

    func update(_ job: TransferJob) throws {
        var mutable = job
        try save(&mutable)
    }

    func remove(_ job: TransferJob) throws {
        try fm.removeItem(at: try root.appendingPathComponent(job.id.uuidString, isDirectory: true))
    }

    private func save(_ job: inout TransferJob) throws {
        let directory = try root.appendingPathComponent(job.id.uuidString, isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(job)
        try data.write(to: directory.appendingPathComponent("job.json"), options: .atomic)
    }
}
