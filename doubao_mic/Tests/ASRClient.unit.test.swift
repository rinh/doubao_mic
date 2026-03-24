import XCTest
@testable import VoiceInput

final class ASRClientTests: XCTestCase {

    func test_asrClient_isNotConnectedInitially() {
        let client = ASRClient()
        XCTAssertFalse(client.isConnected)
    }

    func test_asrClient_disconnect_whenNotConnected() {
        let client = ASRClient()
        client.disconnect()
        XCTAssertFalse(client.isConnected)
    }

    func test_asrClient_sendAudioData_whenNotConnected_doesNotCrash() {
        let client = ASRClient()
        let testData = Data([0x01, 0x02, 0x03, 0x04])

        client.sendAudioData(testData)

        XCTAssertFalse(client.isConnected)
    }

    func test_fullClientPayload_enablesNonstreamAndUtterances() {
        let payload = ASRClient.makeFullClientPayload()
        let request = payload["request"] as? [String: Any]

        XCTAssertEqual(request?["enable_nonstream"] as? Bool, true)
        XCTAssertEqual(request?["enable_ddc"] as? Bool, true)
        XCTAssertEqual(request?["show_utterances"] as? Bool, true)
    }
}

final class ASRProtocol_UnitTest {

    static func test_parseServerResponse_extractsText() -> String? {
        let jsonPayload = """
        {"result":{"text":"你好世界"}}
        """.data(using: .utf8)!

        guard let json = try? JSONSerialization.jsonObject(with: jsonPayload) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let text = result["text"] as? String else {
            return nil
        }
        return text
    }
}
