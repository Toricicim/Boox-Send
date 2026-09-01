import AppKit
import Foundation
import IOBluetooth
import OSLog
import UserNotifications

final class TransferCoordinator {
    static let shared = TransferCoordinator()

    private let logger = Logger(subsystem: "com.aliumutaltas.BooxSend", category: "transfer")
    private let queue = DispatchQueue(label: "booxsend.transfer", qos: .userInitiated)
    private var isRunning = false
    private var retainedConnector: RFCOMMConnector?
    var onIdle: (() -> Void)?

    func processQueue() {
        queue.async { [weak self] in self?.startIfNeeded() }
    }

    private func startIfNeeded() {
        guard !isRunning else {
            logger.debug("Queue processing is already active")
            return
        }
        let jobs: [TransferJob]
        do {
            jobs = try SharedQueue.shared.jobs()
        } catch {
            logger.error("Could not read transfer queue: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard let job = jobs.first(where: { $0.state != .completed }) else {
            logger.notice("No pending transfer job")
            notifyCoordinatorIdle()
            return
        }
        logger.notice("Starting queued transfer with \(job.files.count, privacy: .public) file(s)")
        isRunning = true

        let defaults = UserDefaults(suiteName: BooxConstants.appGroup)!
        guard let address = defaults.string(forKey: "deviceAddress"), !address.isEmpty,
              let setupCode = defaults.string(forKey: "setupCode"), !setupCode.isEmpty,
              let device = IOBluetoothDevice(addressString: address) else {
            logger.error("BOOX device configuration is unavailable")
            fail(job, error: BluetoothTransferError.deviceNotConfigured)
            return
        }

        logger.notice("BOOX Bluetooth device resolved; beginning SDP discovery")
        connect(device: device, setupCode: setupCode, job: job, deadline: Date(timeIntervalSinceNow: 90))
    }

    private func connect(device: IOBluetoothDevice, setupCode: String, job: TransferJob, deadline: Date) {
        let connector = RFCOMMConnector(device: device)
        retainedConnector = connector
        connector.connect { [weak self] result in
            guard let self else { return }
            self.queue.async {
                switch result {
                case .success(let connection):
                    self.logger.notice("RFCOMM connection established")
                    do {
                        try self.send(job: job, setupCode: setupCode, connection: connection)
                        connection.close()
                        try SharedQueue.shared.remove(job)
                        self.notify(title: "Sent to BOOX", body: "\(job.files.count) file(s) transferred.")
                        self.logger.notice("Queued transfer completed")
                        self.isRunning = false
                        // Give both Bluetooth stacks time to retire the previous
                        // RFCOMM channel before opening one for the next job.
                        self.queue.asyncAfter(deadline: .now() + 1) {
                            self.startIfNeeded()
                        }
                    } catch {
                        self.logger.error("Transfer failed after connection: \(error.localizedDescription, privacy: .public)")
                        connection.close()
                        self.fail(job, error: error)
                    }
                case .failure(let error):
                    self.logger.debug("RFCOMM discovery attempt failed: \(error.localizedDescription, privacy: .public)")
                    if Date() < deadline {
                        self.queue.asyncAfter(deadline: .now() + 2) {
                            self.connect(device: device, setupCode: setupCode, job: job, deadline: deadline)
                        }
                    } else {
                        self.fail(job, error: BluetoothTransferError.timeout("BOOX"))
                    }
                }
            }
        }
    }

    private func send(job: TransferJob, setupCode: String, connection: RFCOMMConnection) throws {
        let nonce = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        let hello = Hello(
            version: BooxConstants.protocolVersion,
            nonce: nonce.base64EncodedString(),
            proof: ProtocolCrypto.proof(setupCode: setupCode, nonce: nonce).base64EncodedString()
        )
        try connection.send(.json(.hello, hello))
        let helloAck = try JSONDecoder().decode(HelloAck.self, from: connection.wait(for: .helloAck).payload)
        guard helloAck.accepted else { throw BluetoothTransferError.protocolError(helloAck.message ?? "Authentication rejected") }

        for file in job.files {
            let url = try SharedQueue.shared.fileURL(jobID: job.id, file: file)
            let digest = try ProtocolCrypto.sha256(url: url)
            let offer = FileOffer(transferId: file.id, name: file.originalName, size: file.byteCount, sha256: digest)
            try connection.send(.json(.fileOffer, offer))
            let decision = try JSONDecoder().decode(FileDecision.self, from: connection.wait(for: .fileDecision).payload)
            guard decision.accepted, decision.transferId == file.id else {
                throw BluetoothTransferError.protocolError(decision.message ?? "File was rejected")
            }
            try sendFile(url: url, id: file.id, from: decision.resumeOffset, connection: connection)
            try connection.send(.json(.fileCommit, FileCommit(transferId: file.id)))
            let result = try JSONDecoder().decode(FileResult.self, from: connection.wait(for: .fileResult, timeout: 90).payload)
            guard result.success, result.transferId == file.id else {
                throw BluetoothTransferError.protocolError(result.message ?? "File verification failed")
            }
        }
        try connection.send(Frame(type: .finish, payload: Data()))
    }

    private func sendFile(url: URL, id: UUID, from offset: UInt64, connection: RFCOMMConnection) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        var cursor = offset
        while let chunk = try handle.read(upToCount: 16_384), !chunk.isEmpty {
            var bigOffset = cursor.bigEndian
            var payload = id.bytes
            payload.append(Data(bytes: &bigOffset, count: 8))
            payload.append(chunk)
            try connection.send(Frame(type: .fileChunk, payload: payload))
            cursor += UInt64(chunk.count)
        }
    }

    private func fail(_ job: TransferJob, error: Error) {
        logger.error("Transfer job failed: \(error.localizedDescription, privacy: .public)")
        var failed = job
        failed.state = .failed
        failed.error = error.localizedDescription
        try? SharedQueue.shared.update(failed)
        notify(title: "Could not send to BOOX", body: "\(error.localizedDescription) The job remains queued.")
        isRunning = false
        notifyCoordinatorIdle()
    }

    private func notifyCoordinatorIdle() {
        let handler = onIdle
        DispatchQueue.main.async {
            handler?()
        }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil),
            withCompletionHandler: nil
        )
    }
}
