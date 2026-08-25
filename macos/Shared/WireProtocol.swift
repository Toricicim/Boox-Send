import CryptoKit
import Foundation

enum FrameType: UInt8 {
    case hello = 1, helloAck, fileOffer, fileDecision, fileChunk, fileCommit, fileResult, finish
}

struct Hello: Codable { let version: Int; let nonce: String; let proof: String }
struct HelloAck: Codable { let accepted: Bool; let message: String? }
struct FileOffer: Codable {
    let transferId: UUID
    let name: String
    let size: UInt64
    let sha256: String
}
struct FileDecision: Codable {
    let transferId: UUID
    let accepted: Bool
    let destinationName: String?
    let resumeOffset: UInt64
    let message: String?
}
struct FileCommit: Codable { let transferId: UUID }
struct FileResult: Codable { let transferId: UUID; let success: Bool; let message: String? }

struct Frame {
    let type: FrameType
    let payload: Data

    func encoded() -> Data {
        var bodyLength = UInt32(payload.count + 1).bigEndian
        var data = Data(bytes: &bodyLength, count: 4)
        data.append(type.rawValue)
        data.append(payload)
        return data
    }

    static func json<T: Encodable>(_ type: FrameType, _ value: T) throws -> Frame {
        Frame(type: type, payload: try JSONEncoder().encode(value))
    }
}

final class FrameAccumulator {
    private var buffer = Data()

    func append(_ data: Data) throws -> [Frame] {
        buffer.append(data)
        var frames: [Frame] = []
        while buffer.count >= 5 {
            let length = buffer.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard length > 0, length <= 1_048_576 else {
                throw NSError(domain: "BooxProtocol", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid frame size"])
            }
            let total = Int(length) + 4
            guard buffer.count >= total else { break }
            guard let type = FrameType(rawValue: buffer[4]) else {
                throw NSError(domain: "BooxProtocol", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown frame type"])
            }
            frames.append(Frame(type: type, payload: buffer.subdata(in: 5..<total)))
            buffer.removeSubrange(0..<total)
        }
        return frames
    }
}

enum ProtocolCrypto {
    static func key(setupCode: String) -> SymmetricKey {
        SymmetricKey(data: SHA256.hash(data: Data(setupCode.uppercased().utf8)))
    }

    static func proof(setupCode: String, nonce: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: nonce, using: key(setupCode: setupCode)))
    }

    static func sha256(url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hasher.update(data: data) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

extension UUID {
    var bytes: Data {
        var value = uuid
        return withUnsafeBytes(of: &value) { Data($0) }
    }
}
