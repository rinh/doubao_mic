import XCTest
@testable import VoiceInput

final class ASRIntegrationTests: XCTestCase {

    func test_fullAudioMessageConstruction_withPcmData() {
        let pcmData = generateTestPcmData(durationMs: 100)

        let sequence: Int32 = 1
        let header = ASRProtocol.createAudioOnlyRequestHeader(
            isLastPacket: false
        )

        let message = ASRProtocol.createMessageWithPayload(
            header: header,
            payload: pcmData,
            sequence: sequence
        )

        XCTAssertGreaterThan(message.count, 0)
        XCTAssertEqual(message.count, 4 + 4 + 4 + pcmData.count)

        XCTAssertEqual(message[0], 0b00010001)
        XCTAssertEqual((message[1] >> 4) & 0x0F, 0b0010)
    }

    func test_fullAudioMessageConstruction_lastPacket() {
        let pcmData = Data()
        let sequence: Int32 = 5

        let header = ASRProtocol.createAudioOnlyRequestHeader(
            isLastPacket: true
        )

        let message = ASRProtocol.createMessageWithPayload(
            header: header,
            payload: pcmData,
            sequence: sequence
        )

        XCTAssertEqual(message[0], 0b00010001)
        XCTAssertEqual((message[1] >> 4) & 0x0F, 0b0010)
        XCTAssertEqual(message[1] & 0x0F, 0b0011)
    }

    func test_fullClientRequestMessageConstruction() {
        let payload: [String: Any] = [
            "user": ["uid": "test-user", "platform": "macOS"],
            "audio": ["format": "pcm", "rate": 16000, "bits": 16, "channel": 1],
            "request": ["model_name": "bigmodel", "enable_itn": true]
        ]

        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload) else {
            XCTFail("Failed to serialize payload")
            return
        }

        let header = ASRProtocol.createFullClientRequestHeader()
        let message = ASRProtocol.createMessageWithPayload(
            header: header,
            payload: payloadData,
            sequence: 1
        )

        XCTAssertEqual(message.count, 4 + 4 + 4 + payloadData.count)

        XCTAssertEqual(message[0], 0b00010001)
        XCTAssertEqual((message[1] >> 4) & 0x0F, 0b0001)
        XCTAssertEqual((message[2] >> 4) & 0x0F, 0b0001)
    }

    func test_sendAudioData_updatesSequence() {
        let client = MockASRClient()
        let testData = generateTestPcmData(durationMs: 50)

        XCTAssertEqual(client.currentSequence, 0)
        XCTAssertFalse(client.isConnected)

        client.connect(appId: "test-app", token: "test-token")

        XCTAssertTrue(client.isConnected)
        XCTAssertEqual(client.currentSequence, 1)
        XCTAssertEqual(client.sentMessages.count, 1)

        client.sendAudioData(testData)

        XCTAssertEqual(client.currentSequence, 2)
        XCTAssertEqual(client.sentMessages.count, 2)

        client.sendAudioData(testData)

        XCTAssertEqual(client.currentSequence, 3)
        XCTAssertEqual(client.sentMessages.count, 3)
    }

    func test_disconnect_sendsLastPacket() {
        let client = MockASRClient()
        let testData = generateTestPcmData(durationMs: 50)

        client.connect(appId: "test-app", token: "test-token")
        client.sendAudioData(testData)

        XCTAssertEqual(client.currentSequence, 2)

        client.disconnect()

        XCTAssertEqual(client.sentMessages.count, 3)
        XCTAssertFalse(client.isConnected)
    }

    func test_audioData_chunksHaveCorrectFormat() {
        let client = MockASRClient()
        let testData = generateTestPcmData(durationMs: 100)

        client.connect(appId: "test-app", token: "test-token")
        client.sendAudioData(testData)

        let audioMessage = client.sentMessages[1]
        XCTAssertEqual(audioMessage.count, 4 + 4 + 4 + testData.count)

        let header = audioMessage.subdata(in: 0..<4)
        XCTAssertEqual((header[1] >> 4) & 0x0F, 0b0010)
        XCTAssertEqual(header[1] & 0x0F, 0b0001)
    }

    private func generateTestPcmData(durationMs: Int) -> Data {
        let sampleRate = 16000
        let numSamples = sampleRate * durationMs / 1000
        let numBytes = numSamples * 2

        var data = Data(count: numBytes)
        for i in 0..<numSamples {
            let sample = Int16(sin(Double(i) * 2.0 * .pi * 440.0 / Double(sampleRate)) * 32767)
            var sampleBE = sample.bigEndian
            data.replaceSubrange((i * 2)..<(i * 2 + 2), with: Data(bytes: &sampleBE, count: 2))
        }
        return data
    }
}

private class MockASRClient: ASRClient {
    private(set) var sentMessages: [Data] = []
    private(set) var currentSequence: Int32 = 0
    private(set) var isConnected = false

    override func connect(appId: String, token: String, resourceId: String = "volc.bigasr.sauc.duration") {
        isConnected = true
        currentSequence = 1
        let payload = #"{"request":{"model_name":"bigmodel"}}"#.data(using: .utf8) ?? Data()
        let header = ASRProtocol.createFullClientRequestHeader()
        let message = ASRProtocol.createMessageWithPayload(header: header, payload: payload, sequence: currentSequence)
        sentMessages.append(message)
    }

    override func sendAudioData(_ data: Data) {
        guard isConnected else { return }

        currentSequence += 1

        let header = ASRProtocol.createAudioOnlyRequestHeader(
            isLastPacket: false
        )

        let message = ASRProtocol.createMessageWithPayload(
            header: header,
            payload: data,
            sequence: currentSequence
        )

        sentMessages.append(message)
    }

    override func disconnect() {
        if currentSequence > 0 {
            let header = ASRProtocol.createAudioOnlyRequestHeader(
                isLastPacket: true
            )
            let message = ASRProtocol.createMessageWithPayload(
                header: header,
                payload: Data(),
                sequence: -max(currentSequence, 1)
            )
            sentMessages.append(message)
        }

        isConnected = false
        currentSequence = 0
    }
}
