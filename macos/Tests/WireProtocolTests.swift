import CryptoKit
import XCTest
@testable import BooxSend

final class WireProtocolTests: XCTestCase {
    func testFragmentedFramesAreReassembled() throws {
        let expected = HelloAck(accepted: true, message: nil)
        let data = try Frame.json(.helloAck, expected).encoded()
        let accumulator = FrameAccumulator()
        XCTAssertTrue(try accumulator.append(data.prefix(2)).isEmpty)
        XCTAssertTrue(try accumulator.append(data.subdata(in: 2..<5)).isEmpty)
        let frames = try accumulator.append(data.dropFirst(5))
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].type, .helloAck)
        XCTAssertTrue(try JSONDecoder().decode(HelloAck.self, from: frames[0].payload).accepted)
    }

    func testSetupCodeIsCaseInsensitive() {
        let nonce = Data("nonce".utf8)
        let proof = ProtocolCrypto.proof(setupCode: "ab12cd34", nonce: nonce)
        XCTAssertEqual(proof, ProtocolCrypto.proof(setupCode: "AB12CD34", nonce: nonce))
        XCTAssertEqual(proof.base64EncodedString(), "0uJFxA6IH4nZmsuD0uTfTlk47Yp+JZJsdWKkyPAbUaI=")
    }

    func testRejectsOversizedFrame() {
        var invalid = UInt32(1_048_577).bigEndian
        let data = Data(bytes: &invalid, count: 4) + Data([FrameType.hello.rawValue])
        XCTAssertThrowsError(try FrameAccumulator().append(data))
    }
}
