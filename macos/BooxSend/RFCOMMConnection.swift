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

final class RFCOMMConnector: NSObject {
    private let logger = Logger(subsystem: "com.aliumutaltas.BooxSend", category: "rfcomm")
    private let device: IOBluetoothDevice
    private var completion: ((Result<RFCOMMConnection, Error>) -> Void)?
    private var timeoutWorkItem: DispatchWorkItem?

    init(device: IOBluetoothDevice) { self.device = device }

    func connect(completion: @escaping (Result<RFCOMMConnection, Error>) -> Void) {
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
        logger.debug("Bluetooth baseband connection callback returned \(status, privacy: .public)")
        guard status == kIOReturnSuccess || device.isConnected() else {
            finish(.failure(BluetoothTransferError.channelOpenFailed(status)))
            return
        }
        startSDPQuery()
    }

    private func startSDPQuery() {
        guard completion != nil else { return }
        // Query the full SDP record. The UUID-filtered overload is unreliable
        // with some Android/macOS combinations; the record is filtered below.
        let result = device.performSDPQuery(self)
        logger.debug("SDP query start returned \(result, privacy: .public)")
        if result != kIOReturnSuccess {
            finish(.failure(BluetoothTransferError.serviceUnavailable))
        }
    }

    @objc func sdpQueryComplete(_ remoteDevice: IOBluetoothDevice!, status: IOReturn) {
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

    private func finish(_ result: Result<RFCOMMConnection, Error>) {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        if case .failure = result, device.isConnected() {
            // A failed SDP attempt can leave the Classic Bluetooth baseband
            // connected. Closing it makes the next retry produce a fresh
            // ACL_CONNECTED event, which wakes BOOX's temporary receiver.
            device.closeConnection()
        }
        let callback = completion
        completion = nil
        callback?(result)
    }
}

final class RFCOMMConnection: NSObject, IOBluetoothRFCOMMChannelDelegate {
    private var channel: IOBluetoothRFCOMMChannel?
    private let condition = NSCondition()
    private let accumulator = FrameAccumulator()
    private var frames: [Frame] = []
    private var terminalError: Error?

    func attach(_ channel: IOBluetoothRFCOMMChannel) { self.channel = channel }

    func close() {
        _ = channel?.close()
        channel = nil
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
