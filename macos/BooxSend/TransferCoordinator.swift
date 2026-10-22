import AppKit
import Foundation
import IOBluetooth
import OSLog
import UserNotifications

final class TransferCoordinator {
    static let shared = TransferCoordinator()
    typealias Configuration = (address: String, code: String)
    private let logger = Logger(subsystem: "com.aliumutaltas.BooxSend", category: "transfer")
    private let queue = DispatchQueue(label: "booxsend.transfer", qos: .userInitiated)
    private let stateLock = NSLock()
    private var running = false
    private var queueDirty = false
    var isProcessing: Bool { stateLock.lock(); defer { stateLock.unlock() }; return running }
    private func setRunning(_ value: Bool) { stateLock.lock(); running = value; stateLock.unlock() }
    private let store: SharedQueue
    private let configuration: () -> Configuration?
    private let connectorFactory: (String) throws -> TransferConnecting
    private let retryDelays: [TimeInterval]
    private let connectionWindow: TimeInterval
    private let notifyUser: Bool
    private var retainedConnector: TransferConnecting?
    private var activeConnection: TransferConnection?
    private var activeConfiguration: Configuration?
    private var attempted: Set<UUID> = []
    private var includeFailed = false
    private var lastFailure = ""
    private var batchJobs: [UUID: TransferJob] = [:]
    private var currentJobID: UUID?
    private var progress = TransferProgress()
    private var lastPublish = Date.distantPast
    var onIdle: (() -> Void)?
    var onProgress: ((TransferProgress) -> Void)?

    init(store: SharedQueue = .shared,
         configuration: @escaping () -> Configuration? = {
             let defaults = UserDefaults(suiteName: BooxConstants.appGroup)
             guard let address = defaults?.string(forKey: "deviceAddress"), !address.isEmpty,
                   let code = defaults?.string(forKey: "setupCode"), !code.isEmpty else { return nil }
             return (address, code)
         },
         connectorFactory: @escaping (String) throws -> TransferConnecting = { address in
             guard let device = IOBluetoothDevice(addressString: address) else { throw BluetoothTransferError.deviceNotConfigured }
             return RFCOMMConnector(device: device)
         }, retryDelays: [TimeInterval] = [2, 4, 8], connectionWindow: TimeInterval = 90, notifyUser: Bool = true) {
        self.store = store
        self.configuration = configuration
        self.connectorFactory = connectorFactory
        self.retryDelays = retryDelays
        self.connectionWindow = connectionWindow
        self.notifyUser = notifyUser
    }

    func processQueue(retryFailed: Bool = false) {
        // Ignore retry clicks during an active run, even when send() is blocking
        // this worker. Pending additions are picked up after the current job.
        stateLock.lock()
        let retryRequested = retryFailed && !running
        queueDirty = true
        stateLock.unlock()
        queue.async { [weak self] in
            guard let self else { return }
            self.refreshCounts()
            if self.isProcessing { self.publish(); return }
            self.attempted.removeAll()
            self.lastFailure = ""
            self.includeFailed = retryRequested
            self.batchJobs.removeAll()
            self.currentJobID = nil
            self.refreshCounts()
            self.setRunning(true)
            self.nextJob()
        }
    }

    private func nextJob() {
        do {
            let jobs = try store.jobs()
            refreshCounts(jobs)
            let eligible = jobs.filter {
                !attempted.contains($0.id) && $0.state != .completed && ($0.state != .failed || includeFailed)
            }
            // New work should not wait behind a previously exhausted failure.
            guard var job = eligible.first(where: { $0.state != .failed }) ?? eligible.first else { finishRun(); return }
            attempted.insert(job.id)
            currentJobID = job.id
            if job.remainingFiles.isEmpty {
                job.state = .completed
                try store.update(job)
                try? store.remove(job)
                queue.async { self.nextJob() }
                return
            }
            job.state = .sending
            job.error = nil
            try store.update(job)
            progress.phase = .connecting
            progress.filename = job.remainingFiles.first?.originalName ?? ""
            progress.detail = "Keep BOOX awake with Bluetooth on."
            progress.fileCount = job.files.count
            progress.fileIndex = job.files.count - job.remainingFiles.count + 1
            progress.totalBytes = job.files.reduce(0) { $0 + $1.byteCount }
            progress.sentBytes = confirmedBytes(job)
            publish()
            guard let config = configuration() else { fail(job, error: BluetoothTransferError.deviceNotConfigured); return }
            if let connection = activeConnection, activeConfiguration?.address == config.address,
               activeConfiguration?.code == config.code {
                transmit(job: job, config: config, connection: connection, authenticate: false, sessionAttempt: 0)
            } else {
                closeSession()
                connect(job: job, config: config, deadline: Date(timeIntervalSinceNow: connectionWindow), sessionAttempt: 0)
            }
        } catch {
            progress.phase = .failed
            progress.detail = "Could not read or save the queue: \(error.localizedDescription)"
            finishRun(preserveError: true)
        }
    }

    private func connect(job: TransferJob, config: Configuration, deadline: Date, sessionAttempt: Int) {
        do {
            let connector = try connectorFactory(config.address)
            retainedConnector = connector
            connector.connect { [weak self] result in
                guard let self else { return }
                self.queue.async {
                    self.retainedConnector = nil
                    switch result {
                    case .success(let connection):
                        self.activeConnection = connection
                        self.activeConfiguration = config
                        self.transmit(job: job, config: config, connection: connection, authenticate: true, sessionAttempt: sessionAttempt)
                    case .failure(let error):
                        if self.isTransient(error), Date() < deadline {
                            self.progress.phase = .retrying
                            self.progress.detail = "Waiting for BOOX. Keep it awake with Bluetooth on."
                            self.publish()
                            self.queue.asyncAfter(deadline: .now() + 2) {
                                self.connect(job: job, config: config, deadline: deadline, sessionAttempt: sessionAttempt)
                            }
                        } else { self.fail(job, error: error) }
                    }
                }
            }
        } catch { fail(job, error: error) }
    }

    private func transmit(job: TransferJob, config: Configuration, connection: TransferConnection,
                          authenticate: Bool, sessionAttempt: Int) {
        var updated = job
        do {
            try send(job: &updated, setupCode: config.code, connection: connection, authenticate: authenticate)
            // Commit each job before cleanup, but keep the authenticated channel
            // for the next pending job. FINISH belongs to the whole queue drain.
            updated.state = .completed
            try store.update(updated)
            batchJobs[updated.id] = updated
            try? store.remove(updated)
            logger.notice("Queued transfer completed")
            refreshCounts()
            publish()
            queue.async { self.nextJob() }
        } catch {
            closeSession()
            if isTransient(error), sessionAttempt < retryDelays.count {
                progress.phase = .retrying
                progress.detail = "Connection interrupted. Retrying automatically…"
                progress.sentBytes = confirmedBytes(updated)
                publish()
                let retryJob = updated
                queue.asyncAfter(deadline: .now() + retryDelays[sessionAttempt]) {
                    self.connect(job: retryJob, config: config,
                        deadline: Date(timeIntervalSinceNow: self.connectionWindow), sessionAttempt: sessionAttempt + 1)
                }
            } else { fail(updated, error: error) }
        }
    }

    private func closeSession() {
        activeConnection?.close()
        activeConnection = nil
        activeConfiguration = nil
    }

    private func send(job: inout TransferJob, setupCode: String, connection: TransferConnection, authenticate: Bool) throws {
        if authenticate {
            let nonce = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
            try connection.send(.json(.hello, Hello(version: BooxConstants.protocolVersion,
                nonce: nonce.base64EncodedString(), proof: ProtocolCrypto.proof(setupCode: setupCode, nonce: nonce).base64EncodedString())))
            let ack = try JSONDecoder().decode(HelloAck.self, from: connection.wait(for: .helloAck, timeout: 30).payload)
            guard ack.accepted else { throw BluetoothTransferError.protocolError(ack.message ?? "Authentication rejected") }
        }

        for file in job.remainingFiles {
            progress.filename = file.originalName
            progress.fileIndex = job.files.firstIndex(where: { $0.id == file.id })! + 1
            progress.phase = .preparing
            progress.detail = "File \(progress.fileIndex) of \(job.files.count)"
            publish()
            let url = try store.fileURL(jobID: job.id, file: file)
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            guard size.map(UInt64.init) == file.byteCount else { throw BluetoothTransferError.protocolError("Queued file size changed.") }
            let digest = try ProtocolCrypto.sha256(url: url)
            try connection.send(.json(.fileOffer, FileOffer(transferId: file.id, name: file.originalName, size: file.byteCount, sha256: digest)))
            let decision = try JSONDecoder().decode(FileDecision.self, from: connection.wait(for: .fileDecision, timeout: 30).payload)
            guard decision.accepted, decision.transferId == file.id, decision.resumeOffset <= file.byteCount else {
                throw BluetoothTransferError.protocolError(decision.message ?? "Invalid file decision or resume offset")
            }
            let confirmed = confirmedBytes(job)
            progress.phase = .sending
            progress.sentBytes = confirmed + decision.resumeOffset
            publish()
            try sendFile(url: url, file: file, offset: decision.resumeOffset, connection: connection) { cursor in
                self.progress.sentBytes = confirmed + cursor
                self.publish(throttled: true)
            }
            progress.phase = .verifying
            progress.sentBytes = confirmed + file.byteCount
            publish()
            try connection.send(.json(.fileCommit, FileCommit(transferId: file.id)))
            let result = try JSONDecoder().decode(FileResult.self, from: connection.wait(for: .fileResult, timeout: 90).payload)
            guard result.success, result.transferId == file.id else {
                throw BluetoothTransferError.protocolError(result.message ?? "File verification failed")
            }
            job.completedFileIDs = (job.completedFileIDs ?? []).union([file.id])
            try store.update(job)
            batchJobs[job.id] = job
            refreshCounts()
            publish()
        }
    }

    private func sendFile(url: URL, file: QueuedFile, offset: UInt64, connection: TransferConnection,
                          progress: (UInt64) -> Void) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        var cursor = offset
        while let chunk = try handle.read(upToCount: 16_384), !chunk.isEmpty {
            guard cursor + UInt64(chunk.count) <= file.byteCount else { throw BluetoothTransferError.protocolError("Queued file size changed.") }
            var bigOffset = cursor.bigEndian
            var payload = file.id.bytes
            payload.append(Data(bytes: &bigOffset, count: 8))
            payload.append(chunk)
            try connection.send(Frame(type: .fileChunk, payload: payload))
            cursor += UInt64(chunk.count)
            progress(cursor)
        }
        guard cursor == file.byteCount else { throw BluetoothTransferError.protocolError("Queued file ended early.") }
    }

    private func isTransient(_ error: Error) -> Bool {
        guard let error = error as? BluetoothTransferError else { return false }
        switch error {
        case .deviceNotConfigured, .protocolError: return false
        default: return true
        }
    }

    private func confirmedBytes(_ job: TransferJob) -> UInt64 {
        job.files.filter { (job.completedFileIDs ?? []).contains($0.id) }.reduce(0) { $0 + $1.byteCount }
    }

    private func fail(_ job: TransferJob, error: Error) {
        logger.error("Transfer job failed: \(error.localizedDescription, privacy: .public)")
        var failed = job
        failed.state = .failed
        failed.error = error.localizedDescription
        do { try store.update(failed) } catch { logger.error("Could not persist failure: \(error.localizedDescription, privacy: .public)") }
        progress.detail = error.localizedDescription
        lastFailure = error.localizedDescription
        refreshCounts()
        publish()
        // Isolate this job for this drain, then continue without an endless loop.
        queue.async { self.nextJob() }
    }

    private func refreshCounts(_ supplied: [TransferJob]? = nil) {
        guard let jobs = supplied ?? (try? store.jobs()) else { return }
        for job in jobs where job.state != .completed && (job.state != .failed || includeFailed || batchJobs[job.id] != nil) {
            batchJobs[job.id] = job
        }
        progress.remainingFiles = jobs.filter { $0.state != .completed }.reduce(0) { $0 + $1.remainingFiles.count }
        progress.failedFiles = jobs.filter { $0.state == .failed }.reduce(0) { $0 + $1.remainingFiles.count }
    }

    private func finishRun(preserveError: Bool = false) {
        // All acknowledged jobs are durable already; a lost FINISH cannot replay
        // them. The receiver stops once the batch is finished or the link closes.
        try? activeConnection?.send(Frame(type: .finish, payload: Data()))
        closeSession()
        currentJobID = nil
        setRunning(false)
        if !preserveError {
            if progress.remainingFiles > 0 {
                progress.phase = .failed
                let savedError = (try? store.jobs())?.first(where: { $0.state == .failed })?.error ?? ""
                progress.detail = "\(progress.remainingFiles) file(s) queued. \(lastFailure.isEmpty ? savedError : lastFailure)"
            } else if !attempted.isEmpty {
                progress.phase = .done
                progress.detail = "Files received and verified on BOOX."
                notify(title: "Sent to BOOX", body: "Files received and verified.")
            }
        }
        publish()
        let idle = onIdle
        DispatchQueue.main.async { idle?() }
    }

    private func publish(throttled: Bool = false) {
        if throttled && Date().timeIntervalSince(lastPublish) < 0.1 { return }
        lastPublish = Date()
        stateLock.lock()
        let refresh = queueDirty
        queueDirty = false
        stateLock.unlock()
        if refresh { refreshCounts() }
        var snapshot = progress
        // A Finder helper can publish a job just as the drain finishes. Never
        // display Done/100% for that boundary snapshot while work is queued.
        if snapshot.phase == .done, snapshot.remainingFiles > 0 {
            snapshot.phase = snapshot.failedFiles == snapshot.remainingFiles ? .failed : .connecting
            snapshot.detail = "\(snapshot.remainingFiles) file(s) queued"
        }
        if !batchJobs.isEmpty {
            snapshot.totalBytes = batchJobs.values.flatMap(\.files).reduce(0) { $0 + $1.byteCount }
            snapshot.sentBytes = batchJobs.values.filter { $0.id != currentJobID }.reduce(0) { $0 + confirmedBytes($1) }
            if currentJobID != nil { snapshot.sentBytes += progress.sentBytes }
            snapshot.fileCount = batchJobs.values.reduce(0) { $0 + $1.files.count }
            let verified = batchJobs.values.reduce(0) { $0 + ($1.files.count - $1.remainingFiles.count) }
            snapshot.fileIndex = min(snapshot.fileCount, verified + 1)
            if [.sending, .preparing, .verifying].contains(snapshot.phase) {
                snapshot.detail = "\(snapshot.remainingFiles) file(s) remaining"
            }
        }
        let callback = onProgress
        DispatchQueue.main.async { callback?(snapshot) }
    }

    private func notify(title: String, body: String) {
        guard notifyUser else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
