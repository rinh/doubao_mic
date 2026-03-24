import Foundation
import os.log

final class ASRClient: NSObject {

    var onConnectionStatusChanged: ((Bool) -> Void)?
    var onRecognitionResult: ((String) -> Void)?
    var onRecognitionUpdate: ((ASRRecognitionUpdate) -> Void)?
    var onAudioSent: ((Data) -> Void)?
    var onError: ((Error) -> Void)?
    var onStreamFinalized: (() -> Void)?

    private(set) var isConnected = false
    private let logger = AppLogger.make(.asr)
    private var isDisconnecting = false

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var currentSequence: Int32 = 0
    private var audioChunks: [Data] = []
    private var receivedMessageCount = 0
    private var sentAudioPacketCount = 0
    private var hasSentLastPacket = false
    private var didFinalizeStream = false
    private var finalizationTimeoutWorkItem: DispatchWorkItem?

    private let serverURL = URL(string: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async")!
    var currentSentAudioPacketCount: Int { sentAudioPacketCount }

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func connect(appId: String, token: String, resourceId: String = "volc.bigasr.sauc.duration") {
        guard !isConnected else { return }
        isDisconnecting = false
        hasSentLastPacket = false
        didFinalizeStream = false
        sentAudioPacketCount = 0
        finalizationTimeoutWorkItem?.cancel()
        finalizationTimeoutWorkItem = nil
        let connectID = UUID().uuidString

        var request = URLRequest(url: serverURL)
        request.setValue(appId, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(token, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(resourceId, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(connectID, forHTTPHeaderField: "X-Api-Connect-Id")
        request.setValue(connectID, forHTTPHeaderField: "X-Api-Request-Id")

        logger.info("Connecting ASR websocket: url=\(self.serverURL.absoluteString), resourceId=\(resourceId), connectId=\(connectID)")

        webSocketTask = urlSession?.webSocketTask(with: request)
        webSocketTask?.resume()

        isConnected = true
        currentSequence = 0
        receivedMessageCount = 0

        DispatchQueue.main.async { [weak self] in
            self?.onConnectionStatusChanged?(true)
        }

        receiveMessage()
        sendFullClientRequest(appId: appId)
    }

    func disconnect() {
        guard isConnected || hasSentLastPacket else { return }
        isDisconnecting = true
        logger.info("ASR disconnect requested: currentSequence=\(self.currentSequence), bufferedAudioChunks=\(self.audioChunks.count)")

        if currentSequence > 0 && !hasSentLastPacket {
            sendLastPacket()
        }

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        currentSequence = 0
        audioChunks.removeAll()
        logger.info("ASR disconnected locally")

        DispatchQueue.main.async { [weak self] in
            self?.onConnectionStatusChanged?(false)
        }
    }

    func finishStream() {
        guard isConnected else {
            logger.info("finishStream ignored: websocket not connected")
            finalizeStream(reason: "finish_without_connection")
            return
        }
        guard !hasSentLastPacket else {
            logger.info("finishStream ignored: last packet already sent")
            return
        }

        hasSentLastPacket = true
        logger.info("finishStream: currentSequence=\(self.currentSequence), sentAudioPacketCount=\(self.sentAudioPacketCount)")
        sendLastPacket()
        scheduleFinalizeTimeout()
    }

    func sendAudioData(_ data: Data) {
        guard isConnected else {
            logger.debug("sendAudioData ignored: websocket not connected, bytes=\(data.count)")
            return
        }

        currentSequence += 1
        sentAudioPacketCount += 1

        let header = ASRProtocol.createAudioOnlyRequestHeader(
            isLastPacket: false
        )

        let message = ASRProtocol.createMessageWithPayload(
            header: header,
            payload: data,
            sequence: currentSequence
        )
        if sentAudioPacketCount <= 3 || sentAudioPacketCount % 20 == 0 {
            logger.info("Sending audio packet: packetCount=\(self.sentAudioPacketCount), sequence=\(self.currentSequence), payloadBytes=\(data.count), messageBytes=\(message.count)")
        }

        audioChunks.append(data)

        webSocketTask?.send(.data(message)) { [weak self] error in
            if let error = error {
                self?.safeOnError(error)
            } else {
                self?.logger.debug("Audio packet sent: sequence=\(self?.currentSequence ?? -1)")
                DispatchQueue.main.async {
                    self?.onAudioSent?(data)
                }
            }
        }
    }

    private func safeOnError(_ error: Error) {
        if let urlError = error as? URLError {
            logger.error("ASR URL error: code=\(urlError.code.rawValue), reason=\(urlError.localizedDescription)")
        } else {
            let nsError = error as NSError
            if nsError.domain == NSPOSIXErrorDomain && nsError.code == 57 && (!isConnected || isDisconnecting || hasSentLastPacket) {
                logger.debug("Ignoring socket-not-connected during normal disconnect")
                return
            }
            logger.error("ASR error: domain=\(nsError.domain), code=\(nsError.code), reason=\(error.localizedDescription)")
        }

        DispatchQueue.main.async { [weak self] in
            self?.onError?(error)
        }
    }

    private func sendFullClientRequest(appId: String) {
        let payload = Self.makeFullClientPayload()
        if let request = payload["request"] as? [String: Any] {
            let nonstream = request["enable_nonstream"] as? Bool ?? false
            let ddc = request["enable_ddc"] as? Bool ?? false
            let itn = request["enable_itn"] as? Bool ?? false
            let punc = request["enable_punc"] as? Bool ?? false
            let utterances = request["show_utterances"] as? Bool ?? false
            logger.info(
                "ASR request flags: enable_nonstream=\(nonstream), enable_ddc=\(ddc), enable_itn=\(itn), enable_punc=\(punc), show_utterances=\(utterances)"
            )
        }

        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload) else {
            return
        }

        let header = ASRProtocol.createFullClientRequestHeader()
        currentSequence += 1
        let message = ASRProtocol.createMessageWithPayload(
            header: header,
            payload: payloadData,
            sequence: currentSequence
        )
        logger.info("Sending full client request: sequence=\(self.currentSequence), payloadBytes=\(payloadData.count), messageBytes=\(message.count)")

        webSocketTask?.send(.data(message)) { [weak self] error in
            if let error = error {
                self?.safeOnError(error)
            } else {
                self?.logger.info("Full client request sent successfully")
            }
        }
    }

    static func makeFullClientPayload() -> [String: Any] {
        [
            "user": [
                "uid": UUID().uuidString,
                "platform": "macOS",
                "app_version": "1.0.0"
            ],
            "audio": [
                "format": "pcm",
                "codec": "raw",
                "rate": 16000,
                "bits": 16,
                "channel": 1
            ],
            "request": [
                "model_name": "bigmodel",
                "enable_nonstream": true,
                "enable_ddc": true,
                "enable_itn": true,
                "enable_punc": true,
                "show_utterances": true
            ]
        ]
    }

    private func sendLastPacket() {
        let nextSequence = max(currentSequence + 1, 1)
        currentSequence = nextSequence
        let finalSequence = -nextSequence

        let header = ASRProtocol.createAudioOnlyRequestHeader(
            isLastPacket: true
        )

        let emptyPayload = Data()
        let message = ASRProtocol.createMessageWithPayload(
            header: header,
            payload: emptyPayload,
            sequence: finalSequence
        )
        logger.info("Sending last audio packet: sequence=\(finalSequence), messageBytes=\(message.count), sentAudioPacketCount=\(self.sentAudioPacketCount)")

        webSocketTask?.send(.data(message)) { [weak self] error in
            if let error = error {
                self?.safeOnError(error)
            }
        }
    }

    private func receiveMessage() {
        logger.debug("Waiting for ASR message...")
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.receivedMessageCount += 1
                self?.logger.debug("Received ASR message #\(self?.receivedMessageCount ?? -1)")
                self?.handleMessage(message)
                self?.receiveMessage()
            case .failure(let error):
                self?.safeOnError(error)
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        do {
            switch message {
            case .string(let text):
                logger.debug("Handling ASR text message: length=\(text.count)")
                try parseTextResponse(text)
            case .data(let data):
                logger.debug("Handling ASR binary message: bytes=\(data.count)")
                try parseBinaryResponse(data)
            @unknown default:
                logger.error("Handling ASR unknown message type")
                break
            }
        } catch {
            logger.error("Failed to handle ASR message: \(error.localizedDescription)")
            safeOnError(error)
        }
    }

    private func parseTextResponse(_ text: String) throws {
        guard let data = text.data(using: .utf8) else { return }

        if let update = ASRProtocol.parseServerUpdate(payload: data) {
            let sanitizedText = sanitizeForLog(update.text)
            logger.info(
                "Parsed ASR text response: recognizedLength=\(update.text.count), hasDefinite=\(update.hasDefiniteUtterance), text=\(sanitizedText)"
            )
            DispatchQueue.main.async { [weak self] in
                self?.onRecognitionResult?(update.text)
                self?.onRecognitionUpdate?(update)
            }
        } else {
            logger.debug("ASR text response did not contain result.text")
        }
    }

    private func parseBinaryResponse(_ data: Data) throws {
        guard data.count >= 8 else {
            logger.error("ASR binary response too short: bytes=\(data.count)")
            return
        }

        let headerSize = Int((data[0] & 0x0F) * 4)
        guard data.count >= headerSize else {
            logger.error("ASR binary response invalid header size: headerSize=\(headerSize), bytes=\(data.count)")
            return
        }

        let messageType = (data[1] >> 4) & 0x0F
        let flags = data[1] & 0x0F
        let serializationMethod = (data[2] >> 4) & 0x0F
        let compressionMethod = data[2] & 0x0F
        logger.info("ASR binary header: headerSize=\(headerSize), messageType=\(messageType), flags=\(flags), serialization=\(serializationMethod), compression=\(compressionMethod)")

        var offset = headerSize
        var sequence: Int32?
        if (flags & 0b0001) != 0 {
            guard data.count >= offset + 4 else {
                logger.error("ASR binary missing sequence field: bytes=\(data.count), offset=\(offset)")
                return
            }
            sequence = data.withUnsafeBytes {
                $0.load(fromByteOffset: offset, as: Int32.self).bigEndian
            }
            offset += 4
        }

        var event: Int32?
        if (flags & 0b0100) != 0 {
            guard data.count >= offset + 4 else {
                logger.error("ASR binary missing event field: bytes=\(data.count), offset=\(offset)")
                return
            }
            event = data.withUnsafeBytes {
                $0.load(fromByteOffset: offset, as: Int32.self).bigEndian
            }
            offset += 4
        }

        switch messageType {
        case 0b1001:
            guard data.count >= offset + 4 else {
                logger.error("ASR binary missing payload size: bytes=\(data.count), offset=\(offset)")
                return
            }
            let payloadSize = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self).bigEndian }
            offset += 4

            guard data.count >= offset + Int(payloadSize) else {
                logger.error("ASR binary payload truncated: declared=\(payloadSize), bytes=\(data.count), offset=\(offset)")
                return
            }

            let payload = data.subdata(in: offset..<(offset + Int(payloadSize)))
            logger.info("ASR full response metadata: sequence=\(sequence ?? -1), event=\(event ?? -1), payloadBytes=\(payload.count)")

            if let update = ASRProtocol.parseServerUpdate(payload: payload) {
                let sanitizedText = sanitizeForLog(update.text)
                logger.info(
                    "Parsed ASR binary response: recognizedLength=\(update.text.count), hasDefinite=\(update.hasDefiniteUtterance), text=\(sanitizedText)"
                )
                DispatchQueue.main.async { [weak self] in
                    self?.onRecognitionResult?(update.text)
                    self?.onRecognitionUpdate?(update)
                }
            } else {
                logger.info("ASR binary response parsed but no text field found")
                if let payloadText = String(data: payload, encoding: .utf8), !payloadText.isEmpty {
                    let compact = sanitizeForLog(payloadText)
                    let truncated = String(compact.prefix(600))
                    logger.info("ASR payload (no recognized text): \(truncated)")
                } else {
                    logger.info("ASR payload (no recognized text): <non-utf8>")
                }
            }

            if (flags & 0b0010) != 0 {
                logger.info("Received ASR last packet flag from server")
                finalizeStream(reason: "server_last_packet")
            }

        case 0b1111:
            guard data.count >= offset + 8 else {
                logger.error("ASR error response too short: bytes=\(data.count), offset=\(offset)")
                return
            }
            let errorCode = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: Int32.self).bigEndian }
            offset += 4
            let payloadSize = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self).bigEndian }
            offset += 4

            guard data.count >= offset + Int(payloadSize) else {
                logger.error("ASR error payload truncated: declared=\(payloadSize), bytes=\(data.count), offset=\(offset)")
                return
            }

            let payload = data.subdata(in: offset..<(offset + Int(payloadSize)))
            let payloadText = String(data: payload, encoding: .utf8) ?? "<non-utf8>"
            logger.error("ASR server error response: code=\(errorCode), payload=\(payloadText)")
            if hasSentLastPacket {
                logger.info("Finalizing after server error response since last packet was already sent")
                finalizeStream(reason: "server_error_after_last_packet")
            } else {
                let serverError = NSError(
                    domain: "com.voiceinput.app.asr",
                    code: Int(errorCode),
                    userInfo: [NSLocalizedDescriptionKey: payloadText]
                )
                safeOnError(serverError)
            }

        default:
            logger.info("Unhandled ASR binary message: messageType=\(messageType), flags=\(flags), bytes=\(data.count)")
        }
    }

    private func scheduleFinalizeTimeout() {
        finalizationTimeoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.logger.info("Finalize timeout reached after sending last packet")
            self?.finalizeStream(reason: "finalize_timeout")
        }
        finalizationTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0, execute: workItem)
    }

    private func finalizeStream(reason: String) {
        guard !didFinalizeStream else { return }
        didFinalizeStream = true
        finalizationTimeoutWorkItem?.cancel()
        finalizationTimeoutWorkItem = nil
        logger.info("Finalizing ASR stream: reason=\(reason)")

        if isConnected {
            isDisconnecting = true
            webSocketTask?.cancel(with: .normalClosure, reason: nil)
            webSocketTask = nil
            isConnected = false
            currentSequence = 0
            audioChunks.removeAll()

            DispatchQueue.main.async { [weak self] in
                self?.onConnectionStatusChanged?(false)
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.onStreamFinalized?()
        }
    }

    private func sanitizeForLog(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}

extension ASRClient: URLSessionWebSocketDelegate, URLSessionTaskDelegate {

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        logger.info("ASR websocket opened. negotiatedProtocol=\(`protocol` ?? "nil")")
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonText: String
        if let reason, let text = String(data: reason, encoding: .utf8), !text.isEmpty {
            reasonText = text
        } else {
            reasonText = "nil"
        }
        if hasSentLastPacket {
            logger.info("ASR websocket closed after last packet: closeCode=\(closeCode.rawValue), reason=\(reasonText)")
            finalizeStream(reason: "socket_closed_after_last_packet")
        } else if isDisconnecting {
            logger.info("ASR websocket closed during disconnect: closeCode=\(closeCode.rawValue), reason=\(reasonText)")
        } else {
            logger.error("ASR websocket closed: closeCode=\(closeCode.rawValue), reason=\(reasonText)")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let nsError = error as NSError
        logger.debug("ASR URLSession task completed with error: domain=\(nsError.domain), code=\(nsError.code), isDisconnecting=\(self.isDisconnecting), isConnected=\(self.isConnected)")

        if let httpResponse = task.response as? HTTPURLResponse {
            if httpResponse.statusCode == 101 {
                if isDisconnecting || !isConnected {
                    logger.info("ASR websocket task completed after normal disconnect (status=101)")
                    return
                }
                logger.info("ASR websocket task completed with upgraded protocol status=101")
                safeOnError(error)
                return
            }

            let headers = httpResponse.allHeaderFields
            func headerValue(_ key: String) -> String {
                for (headerKey, value) in headers {
                    if String(describing: headerKey).lowercased() == key.lowercased() {
                        return String(describing: value)
                    }
                }
                return "nil"
            }

            let apiStatusCode = headerValue("X-Api-Status-Code")
            let apiMessage = headerValue("X-Api-Message")
            let ttLogId = headerValue("X-Tt-Logid")

            logger.error("ASR handshake failed: httpStatus=\(httpResponse.statusCode), xApiStatusCode=\(apiStatusCode), xApiMessage=\(apiMessage), xTtLogid=\(ttLogId)")
        } else {
            logger.error("ASR task completed with non-HTTP error response")
        }

        safeOnError(error)
    }
}

struct ASRRecognitionUpdate {
    let text: String
    let hasDefiniteUtterance: Bool
    let definiteText: String?
}

enum ASRProtocol {

    enum MessageType: UInt8 {
        case fullClientRequest = 0b0001
        case audioOnlyRequest = 0b0010
        case fullServerResponse = 0b1001
        case errorResponse = 0b1111
    }

    enum SerializationMethod: UInt8 {
        case none = 0b0000
        case json = 0b0001
    }

    enum CompressionMethod: UInt8 {
        case none = 0b0000
        case gzip = 0b0001
    }

    enum MessageTypeSpecificFlags: UInt8 {
        case useSequence = 0b0001
        case lastPacket = 0b0010
        case lastPacketWithSequence = 0b0011
    }

    static func createFullClientRequestHeader() -> Data {
        var header = Data(count: 4)
        header[0] = (0b0001 << 4) | 0b0001
        header[1] = (MessageType.fullClientRequest.rawValue << 4) | MessageTypeSpecificFlags.useSequence.rawValue
        header[2] = (SerializationMethod.json.rawValue << 4) | CompressionMethod.none.rawValue
        header[3] = 0x00
        return header
    }

    static func createAudioOnlyRequestHeader(isLastPacket: Bool) -> Data {
        var header = Data(count: 4)
        header[0] = (0b0001 << 4) | 0b0001

        var flags: UInt8 = 0b0000
        if isLastPacket {
            flags = MessageTypeSpecificFlags.lastPacketWithSequence.rawValue
        } else {
            flags = MessageTypeSpecificFlags.useSequence.rawValue
        }

        header[1] = (MessageType.audioOnlyRequest.rawValue << 4) | flags
        header[2] = (SerializationMethod.none.rawValue << 4) | CompressionMethod.none.rawValue
        header[3] = 0x00

        return header
    }

    static func createMessageWithPayload(header: Data, payload: Data, sequence: Int32? = nil) -> Data {
        var message = Data()
        message.append(header)

        if let seq = sequence {
            var seqBE = seq.bigEndian
            message.append(Data(bytes: &seqBE, count: 4))
        }

        var payloadSize = UInt32(payload.count).bigEndian
        message.append(Data(bytes: &payloadSize, count: 4))
        message.append(payload)

        return message
    }

    static func parseServerResponse(payload: Data) -> String? {
        parseServerUpdate(payload: payload)?.text
    }

    static func parseServerUpdate(payload: Data) -> ASRRecognitionUpdate? {
        guard let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            return nil
        }

        let candidates: [[String]] = [
            ["result", "text"],
            ["result", "final_text"],
            ["result", "transcript"],
            ["payload_msg", "result", "text"],
            ["payload_msg", "result", "final_text"],
            ["payload_msg", "result", "transcript"],
            ["text"]
        ]

        for path in candidates {
            if let text = stringValue(at: path, in: json), !text.isEmpty {
                let definiteText = extractDefiniteUtteranceText(from: json)
                return ASRRecognitionUpdate(
                    text: text,
                    hasDefiniteUtterance: definiteText != nil,
                    definiteText: definiteText
                )
            }
        }

        if let result = json["result"] as? [String: Any],
           let utterances = result["utterances"] as? [[String: Any]] {
            let merged = utterances.compactMap { $0["text"] as? String }.joined()
            if !merged.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let definite = utterances
                    .filter { ($0["definite"] as? Bool) == true }
                    .compactMap { $0["text"] as? String }
                    .joined()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return ASRRecognitionUpdate(
                    text: merged,
                    hasDefiniteUtterance: !definite.isEmpty,
                    definiteText: definite.isEmpty ? nil : definite
                )
            }
        }

        return nil
    }

    private static func extractDefiniteUtteranceText(from root: [String: Any]) -> String? {
        guard let result = root["result"] as? [String: Any],
              let utterances = result["utterances"] as? [[String: Any]] else {
            return nil
        }
        let definite = utterances
            .filter { ($0["definite"] as? Bool) == true }
            .compactMap { $0["text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return definite.isEmpty ? nil : definite
    }

    private static func stringValue(at path: [String], in root: [String: Any]) -> String? {
        guard !path.isEmpty else { return nil }
        var current: Any = root
        for key in path {
            guard let dict = current as? [String: Any], let next = dict[key] else {
                return nil
            }
            current = next
        }
        guard let value = current as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
