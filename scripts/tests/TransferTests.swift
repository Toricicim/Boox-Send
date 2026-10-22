import Foundation

private func expect(_ condition: Bool, _ message: String) {
    if !condition { fatalError(message) }
}

private final class Peer {
    var offers: [String] = []
    var offerIDs: [UUID] = []
    var sizes: [UUID: UInt64] = [:]
    var committed: Set<UUID> = []
    var failResultOnceFor: String?
    var rejectedName: String?
    var invalidOffset = false
    var connections = 0
    var duringChunk: (() -> Void)?
}

private final class MockConnection: TransferConnection {
    let peer: Peer
    var offer: FileOffer?
    init(_ peer: Peer) { self.peer = peer }
    func close() {}
    func send(_ frame: Frame) throws {
        if frame.type == .fileOffer {
            let offer = try JSONDecoder().decode(FileOffer.self, from: frame.payload)
            self.offer = offer
            peer.offers.append(offer.name)
            peer.offerIDs.append(offer.transferId)
        }
        if frame.type == .fileChunk {
            peer.duringChunk?()
            peer.duringChunk = nil
        }
        if frame.type == .finish { throw BluetoothTransferError.channelClosed }
    }
    func wait(for expected: FrameType, timeout: TimeInterval) throws -> Frame {
        if expected == .helloAck { return try .json(.helloAck, HelloAck(accepted: true, message: nil)) }
        guard let offer else { fatalError("Offer expected") }
        if expected == .fileDecision {
            let offset = peer.invalidOffset ? offer.size + 1 : peer.committed.contains(offer.transferId) ? offer.size : 0
            return try .json(.fileDecision, FileDecision(transferId: offer.transferId,
                accepted: peer.rejectedName != offer.name, destinationName: offer.name,
                resumeOffset: offset, message: "Test rejection"))
        }
        peer.committed.insert(offer.transferId)
        if peer.failResultOnceFor == offer.name {
            peer.failResultOnceFor = nil
            throw BluetoothTransferError.timeout("fileResult")
        }
        return try .json(.fileResult, FileResult(transferId: offer.transferId, success: true, message: nil))
    }
}

private final class MockConnector: TransferConnecting {
    let peer: Peer
    init(_ peer: Peer) { self.peer = peer }
    func connect(completion: @escaping (Result<TransferConnection, Error>) -> Void) {
        peer.connections += 1
        completion(.success(MockConnection(peer)))
    }
}

@main
struct TransferTests {
    static func drain(_ coordinator: TransferCoordinator, retry: Bool = false) -> [TransferProgress] {
        var idle = false
        var states: [TransferProgress] = []
        coordinator.onProgress = { states.append($0) }
        coordinator.onIdle = { idle = true }
        coordinator.processQueue(retryFailed: retry)
        let deadline = Date(timeIntervalSinceNow: 15)
        while !idle && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        expect(idle, "Drain timed out")
        expect(!coordinator.isProcessing, "Running flag must clear")
        return states
    }

    static func main() throws {
        if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--enqueue" {
            let store = SharedQueue(root: URL(fileURLWithPath: CommandLine.arguments[2]))
            _ = try store.enqueue(urls: [URL(fileURLWithPath: CommandLine.arguments[3])])
            return
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("boox-transfer-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func source(_ name: String, _ data: Data = Data(repeating: 42, count: 40_000)) throws -> URL {
            let url = root.appendingPathComponent(name)
            try data.write(to: url)
            return url
        }
        func coordinator(_ store: SharedQueue, _ peer: Peer) -> TransferCoordinator {
            TransferCoordinator(store: store, configuration: { ("test", "TEST1234") },
                connectorFactory: { _ in MockConnector(peer) }, retryDelays: [0.01, 0.01], connectionWindow: 0, notifyUser: false)
        }

        let one = try source("one.pdf")
        let two = try source("two.pdf")
        let third = try source("third.pdf")
        let store = SharedQueue(root: root.appendingPathComponent("resume"))
        let original = try store.enqueue(urls: [one, two])
        let duplicate = try store.enqueue(urls: [one])
        expect(original.id == duplicate.id, "Repeated Send must reuse a pending file's stable ID")
        expect(try store.jobs().count == 1, "Duplicate queue entry")
        expect(original.files.count == 2, "Initial selection must preserve both files")
        let peer = Peer()
        peer.failResultOnceFor = "two.pdf"
        let worker = coordinator(store, peer)
        peer.duringChunk = {
            _ = try! store.enqueue(urls: [third])
            worker.processQueue()
            worker.processQueue(retryFailed: true)
        }
        let states = drain(worker)
        expect(peer.offers.filter { $0 == "one.pdf" }.count == 1, "Confirmed files must not replay")
        expect(peer.offers.filter { $0 == "two.pdf" }.count == 2, "Lost result must trigger an automatic retry")
        expect(Set(peer.offerIDs.filter { $0 == original.files[1].id }).count == 1, "Retry ID must remain stable")
        expect(peer.offers.contains("third.pdf"), "A job queued during transfer must drain automatically")
        expect(peer.connections == 2, "The next job must reuse the authenticated connection")
        expect(try store.jobs().isEmpty, "Successful queue must be empty")
        expect(states.last?.phase == .done && states.last?.remainingFiles == 0, "Done and counts must match verified completion")
        expect(states.contains { $0.phase == .retrying }, "Reconnect progress missing")
        expect(states.filter { $0.phase != .done }.allSatisfy { $0.fraction < 1 }, "100% must require receiver verification")
        expect(states.last?.totalBytes == 120_000, "Progress must cover the whole queue, including new jobs")
        print("PASS: automatic reconnect, stable IDs, confirmed-file resume, enqueue while sending, progress and cleanup")

        let failStore = SharedQueue(root: root.appendingPathComponent("isolation"))
        _ = try failStore.enqueue(urls: [one])
        _ = try failStore.enqueue(urls: [two])
        let failPeer = Peer()
        failPeer.rejectedName = "one.pdf"
        let failWorker = coordinator(failStore, failPeer)
        let failed = drain(failWorker)
        expect(failPeer.offers == ["one.pdf", "two.pdf"], "A rejected job must not block following work or loop: \(failPeer.offers)")
        expect(failed.last?.phase == .failed && failed.last?.failedFiles == 1, "Failed count incorrect")
        _ = try failStore.enqueue(urls: [third])
        _ = drain(failWorker)
        expect(failPeer.offers.filter { $0 == "one.pdf" }.count == 1, "New work must not restart a permanent failure")
        failPeer.rejectedName = nil
        let retried = drain(failWorker, retry: true)
        let jobsAfterRetry = try failStore.jobs()
        expect(retried.last?.phase == .done && jobsAfterRetry.isEmpty, "Explicit Retry must drain retained failures")
        print("PASS: failed-job isolation, no infinite retry, explicit Retry")

        let offsetStore = SharedQueue(root: root.appendingPathComponent("offset"))
        _ = try offsetStore.enqueue(urls: [one])
        let offsetPeer = Peer()
        offsetPeer.invalidOffset = true
        let invalid = drain(coordinator(offsetStore, offsetPeer))
        expect(invalid.last?.phase == .failed && offsetPeer.committed.isEmpty, "Invalid resume offset must never be committed")
        expect(offsetPeer.connections == 1, "Protocol errors must not retry")
        print("PASS: resume offset validation")

        let emptyStore = SharedQueue(root: root.appendingPathComponent("empty"))
        _ = try emptyStore.enqueue(urls: [source("empty.txt", Data())])
        let empty = drain(coordinator(emptyStore, Peer()))
        expect(empty.last?.phase == .done && empty.last?.fraction == 1, "Zero-byte file must still verify and finish")

        let legacy = Data("{\"id\":\"\(UUID())\",\"createdAt\":\"2026-10-12T00:00:00Z\",\"files\":[],\"state\":\"pending\"}".utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        expect(try decoder.decode(TransferJob.self, from: legacy).completedFileIDs == nil, "Old queues must decode")
        print("PASS: empty files and old queue compatibility")

        let rollbackStore = SharedQueue(root: root.appendingPathComponent("enqueue-failure"))
        do {
            _ = try rollbackStore.enqueue(urls: [one, root.appendingPathComponent("missing.pdf")])
            fatalError("Expected staging failure")
        } catch {}
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("enqueue-failure").path)
        expect(leftovers == [".enqueue.lock"], "Failed enqueue must not leave orphaned copies")
        print("PASS: failed staging cleanup")

        let concurrentRoot = root.appendingPathComponent("concurrent")
        var helpers: [Process] = []
        for _ in 0..<8 {
            let helper = Process()
            helper.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            helper.arguments = ["--enqueue", concurrentRoot.path, one.path]
            try helper.run()
            helpers.append(helper)
        }
        for helper in helpers { helper.waitUntilExit(); expect(helper.terminationStatus == 0, "Concurrent helper failed") }
        expect(try SharedQueue(root: concurrentRoot).jobs().count == 1, "Concurrent Finder helpers must not duplicate a file")
        let selectionStore = SharedQueue(root: root.appendingPathComponent("selection"))
        let selection = try selectionStore.enqueue(urls: [one, one, root])
        expect(selection.files.count == 1, "Repeated selection must deduplicate; folders must be ignored")
        let changed = try source("changed.txt", Data("aaa".utf8))
        _ = try selectionStore.enqueue(urls: [changed])
        try Data("bbb".utf8).write(to: changed)
        _ = try selectionStore.enqueue(urls: [changed])
        expect(try selectionStore.jobs().count == 3, "Equal-size but changed files must not be deduplicated")
        print("PASS: concurrent Finder helpers, duplicate selections, folders and changed-file identity")

        var discovery = DiscoveryAttemptGate()
        expect(!discovery.beginChannel(), "Cannot open a channel before discovery")
        expect(discovery.beginQuery(), "First query must start")
        for _ in 0..<100 { expect(!discovery.beginQuery(), "Reentrant connectionComplete must not restart SDP") }
        expect(discovery.beginChannel(), "First channel must open")
        expect(!discovery.beginChannel(), "Duplicate SDP callback must not open two channels")
        print("PASS: reentrant Bluetooth callback guards")
    }
}
