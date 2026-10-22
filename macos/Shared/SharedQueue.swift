import Foundation
import OSLog
import Darwin

struct TransferJob: Codable, Identifiable, Sendable {
    enum State: String, Codable, Sendable { case pending, sending, completed, failed }

    let id: UUID
    let createdAt: Date
    var files: [QueuedFile]
    var state: State
    var error: String?
    // Optional for backwards-compatible decoding of queues created before 1.1.0.
    var completedFileIDs: Set<UUID>? = nil
    // Old ISO-8601 metadata rounded to whole seconds, scrambling jobs queued
    // close together. Keep high-resolution ordering without breaking old builds.
    var enqueueOrder: TimeInterval? = nil

    var remainingFiles: [QueuedFile] { files.filter { !(completedFileIDs ?? []).contains($0.id) } }
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
    private let rootOverride: URL?

    init(root: URL? = nil) { rootOverride = root }

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
            if let rootOverride { return rootOverride }
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
        // Finder may launch several helpers concurrently. Serialize duplicate detection
        // across processes; job metadata itself is still published atomically.
        let queueRoot = try root
        try fm.createDirectory(at: queueRoot, withIntermediateDirectories: true)
        let lock = open(queueRoot.appendingPathComponent(".enqueue.lock").path, O_CREAT | O_RDWR, 0o600)
        guard lock >= 0 else { throw POSIXError(.EIO) }
        defer { flock(lock, LOCK_UN); close(lock) }
        guard flock(lock, LOCK_EX) == 0 else { throw POSIXError(.EIO) }
        let existing = try jobs().filter { $0.state != .completed }
        let jobID = UUID()
        let jobDirectory = try root.appendingPathComponent(jobID.uuidString, isDirectory: true)
        try fm.createDirectory(at: jobDirectory, withIntermediateDirectories: true)
        var published = false
        defer { if !published { try? fm.removeItem(at: jobDirectory) } }

        var files: [QueuedFile] = []
        var reused: TransferJob?
        for source in urls {
            let accessed = source.startAccessingSecurityScopedResource()
            defer { if accessed { source.stopAccessingSecurityScopedResource() } }
            guard try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let id = UUID()
            let stagedName = id.uuidString
            let destination = jobDirectory.appendingPathComponent(stagedName)
            try fm.copyItem(at: source, to: destination)
            let values = try destination.resourceValues(forKeys: [.fileSizeKey])
            if let duplicate = existing.first(where: { job in
                job.remainingFiles.contains { file in
                    guard file.originalName == source.lastPathComponent,
                          file.byteCount == UInt64(values.fileSize ?? 0),
                          let staged = try? fileURL(jobID: job.id, file: file) else { return false }
                    return fm.contentsEqual(atPath: staged.path, andPath: destination.path)
                }
            }) {
                try fm.removeItem(at: destination)
                reused = duplicate
                // Only the sender may change an existing job's state. A helper
                // must not overwrite an acknowledgement racing this comparison.
                continue
            }
            if files.contains(where: { file in
                file.originalName == source.lastPathComponent && file.byteCount == UInt64(values.fileSize ?? 0) &&
                    fm.contentsEqual(atPath: jobDirectory.appendingPathComponent(file.stagedName).path, andPath: destination.path)
            }) {
                try fm.removeItem(at: destination)
                continue
            }
            files.append(QueuedFile(
                id: id,
                stagedName: stagedName,
                originalName: source.lastPathComponent,
                byteCount: UInt64(values.fileSize ?? 0)
            ))
        }

        guard !files.isEmpty else {
            if let reused { return reused }
            throw SharedQueueError.noFiles
        }

        var job = TransferJob(id: jobID, createdAt: Date(), files: files, state: .pending, error: nil)
        job.enqueueOrder = job.createdAt.timeIntervalSince1970
        try save(&job)
        published = true
        return job
    }

    func jobs() throws -> [TransferJob] {
        let queueRoot = try root
        try fm.createDirectory(at: queueRoot, withIntermediateDirectories: true)
        let directories = try fm.contentsOfDirectory(at: queueRoot, includingPropertiesForKeys: nil)
        logger.notice("Queue path \(queueRoot.path, privacy: .public) contains \(directories.count, privacy: .public) item(s)")
        return directories.filter { !$0.lastPathComponent.hasPrefix(".") }.compactMap { directory in
                let metadata = directory.appendingPathComponent("job.json")
                do {
                    let data = try Data(contentsOf: metadata)
                    return try decoder.decode(TransferJob.self, from: data)
                } catch {
                    logger.error("Could not load queue metadata at \(metadata.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }
            .sorted {
                let lhs = $0.enqueueOrder ?? $0.createdAt.timeIntervalSince1970
                let rhs = $1.enqueueOrder ?? $1.createdAt.timeIntervalSince1970
                return lhs == rhs ? $0.id.uuidString < $1.id.uuidString : lhs < rhs
            }
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
