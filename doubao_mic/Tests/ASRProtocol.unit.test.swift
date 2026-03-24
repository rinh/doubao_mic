import XCTest
@testable import VoiceInput

final class ASRProtocolTests: XCTestCase {

    func test_createFullClientRequestHeader_hasCorrectFormat() {
        let header = ASRProtocol.createFullClientRequestHeader()

        XCTAssertEqual(header.count, 4)

        let version = (header[0] >> 4) & 0x0F
        XCTAssertEqual(version, 0b0001)

        let headerSize = header[0] & 0x0F
        XCTAssertEqual(headerSize, 0b0001)

        let messageType = (header[1] >> 4) & 0x0F
        XCTAssertEqual(messageType, 0b0001)

        let serialization = (header[2] >> 4) & 0x0F
        XCTAssertEqual(serialization, 0b0001)
    }

    func test_createAudioOnlyRequestHeader_hasCorrectFormat() {
        let header = ASRProtocol.createAudioOnlyRequestHeader(isLastPacket: false)

        XCTAssertEqual(header.count, 4)

        let messageType = (header[1] >> 4) & 0x0F
        XCTAssertEqual(messageType, 0b0010)

        let compression = header[2] & 0x0F
        XCTAssertEqual(compression, 0b0000)
    }

    func test_createAudioOnlyRequestHeader_withSequence() {
        let header = ASRProtocol.createAudioOnlyRequestHeader(isLastPacket: false)

        let messageTypeSpecificFlags = header[1] & 0x0F
        XCTAssertEqual(messageTypeSpecificFlags, 0b0001)
    }

    func test_createAudioOnlyRequestHeader_lastPacket() {
        let header = ASRProtocol.createAudioOnlyRequestHeader(isLastPacket: true)

        let messageTypeSpecificFlags = header[1] & 0x0F
        XCTAssertEqual(messageTypeSpecificFlags, 0b0011)
    }

    func test_parseServerResponse_extractsText() {
        let jsonPayload = """
        {"result":{"text":"你好世界"}}
        """.data(using: .utf8)!

        let text = ASRProtocol.parseServerResponse(payload: jsonPayload)

        XCTAssertEqual(text, "你好世界")
    }

    func test_parseServerResponse_withUtterances() {
        let jsonPayload = """
        {"result":{"text":"你好","utterances":[{"text":"你好","definite":true}]}}
        """.data(using: .utf8)!

        let text = ASRProtocol.parseServerResponse(payload: jsonPayload)

        XCTAssertEqual(text, "你好")
    }

    func test_parseServerUpdate_marksDefiniteUtterance() {
        let jsonPayload = """
        {"result":{"text":"这是最终文本","utterances":[{"text":"这是","definite":true},{"text":"最终文本","definite":true}]}}
        """.data(using: .utf8)!

        let update = ASRProtocol.parseServerUpdate(payload: jsonPayload)

        XCTAssertNotNil(update)
        XCTAssertEqual(update?.text, "这是最终文本")
        XCTAssertEqual(update?.hasDefiniteUtterance, true)
        XCTAssertEqual(update?.definiteText, "这是最终文本")
    }

    func test_parseServerResponse_emptyPayload_returnsNil() {
        let emptyPayload = Data()

        let text = ASRProtocol.parseServerResponse(payload: emptyPayload)

        XCTAssertNil(text)
    }

    func test_parseServerResponse_invalidJson_returnsNil() {
        let invalidPayload = "not json".data(using: .utf8)!

        let text = ASRProtocol.parseServerResponse(payload: invalidPayload)

        XCTAssertNil(text)
    }
}
