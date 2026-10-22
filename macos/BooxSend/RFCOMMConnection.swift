import Foundation
import IOBluetooth
import OSLog

enum BluetoothTransferError: LocalizedError {
    case deviceNotConfigured, serviceUnavailable, channelOpenFailed(IOReturn)
    case channelClosed, writeFailed(IOReturn), timeout(String), protocolError(String)

    var errorDescription: String? {
        switch self {
        case .deviceNotConfigured: return "A paired BOOX device and setup code are required."
        case .serviceUnavailable: return "BOOX Send service is not available on the device."
        case .channelOpenFailed(let code): return "Could not open Bluetooth channel (\(code))."
        case .channelClosed: return "The Bluetooth connection closed."
        case .writeFailed(let code): return "Bluetooth write failed (\(code))."
        case .timeout(let operation): return "Timed out while waiting for \(operation)."
        case .protocolError(let message): return message
        }
    }
}

protocol TransferConnection: AnyObject {
    func send(_ frame: Frame) throws
    func wait(for expected: FrameType, timeout: TimeInterval) throws -> Frame
    func close()
}

protocol TransferConnecting: AnyObject {
    func connect(completion: @escaping (Result<TransferConnection, Error>) -> Void)
}

struct DiscoveryAttemptGate {
    private var queried = false
    private var opened = false
    mutating func beginQuery() -> Bool {
        guard !queried else { return false }
        queried = true
        return true
    }
    mutating func beginChannel() -> Bool {
        guard queried, !opened else { return false }
        opened = true
        return true
    }
}

final class RFCOMMConnector: NSObject, TransferConnecting {
    private let logger = Logger(subsystem: "com.aliumutaltas.BooxSend", category: "rfcomm")
    private let device: IOBluetoothDevice
    private var completion: ((Result<TransferConnection, Error>) -> Void)?
    private var timeoutWorkItem: DispatchWorkItem?
    private var discovery = DiscoveryAttemptGate()

    init(device: IOBluetoothDevice) { self.device = device }

    func connect(completion: @escaping (Result<TransferConnection, Error>) -> Void) {
        self.completion = completion
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let timeout = DispatchWorkItem { [weak self] in
                self?.finish(.failure(BluetoothTransferError.timeout("Bluetooth service discovery")))
            }
            self.timeoutWorkItem = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timeout)

            // On current macOS versions an SDP query against a disconnected
            // Classic device may never call its delegate. Establish the ACL
            // link first, as Apple's Bluetooth File Exchange does.
            if self.device.isConnected() {
                self.startSDPQuery()
            } else {
                let result = self.device.openConnection(self)
                self.logger.debug("Bluetooth baseband connection start returned \(result, privacy: .public)")
                if result != kIOReturnSuccess {
                    self.finish(.failure(BluetoothTransferError.channelOpenFailed(result)))
                }
            }
        }
    }

    @objc func connectionComplete(_ remoteDevice: IOBluetoothDevice!, status: IOReturn) {
        guard completion != nil else { return }
        logger.debug("Bluetooth baseband connection callback returned \(status, privacy: .public)")
        guard status == kIOReturnSuccess || device.isConnected() else {
            finish(.failure(BluetoothTransferError.channelOpenFailed(status)))
            return
        }
        startSDPQuery()
    }

    private func startSDPQuery() {
        // performSDPQuery can itself deliver connectionComplete again. Starting
        // another query there cancelled/restarted discovery in a callback loop.
        guard completion != nil, discovery.beginQuery() else { return }
        // ACL_CONNECTED wakes Android's temporary receiver asynchronously. An
        // immediate query raced its SDP registration and sometimes never called
        // back. Give that receiver one bounded second to advertise its service.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.completion != nil else { return }
            // The UUID-filtered overload is unreliable on some BOOX firmware.
            let result = self.device.performSDPQuery(self)
            self.logger.debug("SDP query start returned \(result, privacy: .public)")
            if result != kIOReturnSuccess {
                self.finish(.failure(BluetoothTransferError.serviceUnavailable))
            }
        }
    }

    @objc func sdpQueryComplete(_ remoteDevice: IOBluetoothDevice!, status: IOReturn) {
        guard completion != nil else { return }
        logger.debug("SDP query callback returned \(status, privacy: .public)")
        guard status == kIOReturnSuccess,
              let uuid = serviceUUID(),
              let record = device.getServiceRecord(for: uuid) else {
            logger.debug("SDP service record was unavailable")
            finish(.failure(BluetoothTransferError.serviceUnavailable))
            return
        }
        var channelID: BluetoothRFCOMMChannelID = 0
        guard record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess else {
            finish(.failure(BluetoothTransferError.serviceUnavailable))
            return
        }
        guard discovery.beginChannel() else { return }
        let connection = RFCOMMConnection()
        var channel: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelSync(&channel, withChannelID: channelID, delegate: connection)
        logger.debug("RFCOMM channel open returned \(result, privacy: .public)")
        guard result == kIOReturnSuccess, let channel else {
            finish(.failure(BluetoothTransferError.channelOpenFailed(result)))
            return
        }
        connection.attach(channel)
        finish(.success(connection))
    }

    private func serviceUUID() -> IOBluetoothSDPUUID? {
        guard let uuid = UUID(uuidString: BooxConstants.rfcommServiceUUID) else { return nil }
        let data = withUnsafeBytes(of: uuid.uuid) { Data($0) }
        return IOBluetoothSDPUUID(data: data)
    }

    private func finish(_ result: Result<TransferConnection, Error>) {
        // A late SDP callback must never disconnect a subsequent attempt.
        guard let callback = completion else {
            if case .success(let connection) = result { connection.close() }
            return
        }
        completion = nil
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        if case .failure = result, device.isConnected() {
            // A failed SDP attempt can leave the Classic Bluetooth baseband
            // connected. Closing it makes the next retry produce a fresh
            // ACL_CONNECTED event, which wakes BOOX's temporary receiver.
            device.closeConnection()
        }
        callback(result)
    }
}

final class RFCOMMConnection: NSObject, IOBluetoothRFCOMMChannelDelegate, TransferConnection {
    private var channel: IOBluetoothRFCOMMChannel?
    private let condition = NSCondition()
    private let accumulator = FrameAccumulator()
    private var frames: [Frame] = []
    private var terminalError: Error?

    func attach(_ channel: IOBluetoothRFCOMMChannel) { self.channel = channel }

    func close() {
        let previous = channel
        channel = nil
        setTerminalError(BluetoothTransferError.channelClosed)
        DispatchQueue.main.async {
            let device = previous?.getDevice()
            _ = previous?.close()
            // BOOX needs a fresh ACL_CONNECTED event for the next receiver window.
            _ = device?.closeConnection()
        }
    }

    func send(_ frame: Frame) throws {
        guard let channel else { throw BluetoothTransferError.channelClosed }
        let encoded = frame.encoded()
        let mtu = max(1, Int(channel.getMTU()))
        var offset = 0
        while offset < encoded.count {
            let end = min(encoded.count, offset + mtu)
            var slice = Data(encoded[offset..<end])
            let sliceCount = slice.count
            let result = slice.withUnsafeMutableBytes { bytes -> IOReturn in
                guard let base = bytes.baseAddress else { return kIOReturnBadArgument }
                return channel.writeSync(base, length: UInt16(sliceCount))
            }
            guard result == kIOReturnSuccess else { throw BluetoothTransferError.writeFailed(result) }
            offset = end
        }
    }

    func wait(for expected: FrameType, timeout: TimeInterval = 30) throws -> Frame {
        let deadline = Date(timeIntervalSinceNow: timeout)
        condition.lock()
        defer { condition.unlock() }
        while true {
            if let index = frames.firstIndex(where: { $0.type == expected }) {
                return frames.remove(at: index)
            }
            if let terminalError { throw terminalError }
            if !condition.wait(until: deadline) { throw BluetoothTransferError.timeout(String(describing: expected)) }
        }
    }

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        guard let dataPointer, dataLength > 0 else { return }
        do {
            let incoming = Data(bytes: dataPointer, count: dataLength)
            let parsed = try accumulator.append(incoming)
            condition.lock()
            frames.append(contentsOf: parsed)
            condition.broadcast()
            condition.unlock()
        } catch {
            setTerminalError(error)
        }
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        setTerminalError(BluetoothTransferError.channelClosed)
    }

    private func setTerminalError(_ error: Error) {
        condition.lock()
        terminalError = error
        condition.broadcast()
        condition.unlock()
    }
}
