import Foundation

protocol SeedPolishHTTPSession {
    func send(request: URLRequest, completion: @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void)
}

extension URLSession: SeedPolishHTTPSession {
    func send(request: URLRequest, completion: @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) {
        let task = dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(SeedPolishError.invalidResponse))
                return
            }
            completion(.success((data ?? Data(), httpResponse)))
        }
        task.resume()
    }
}

enum SeedPolishError: Error {
    case invalidRequest
    case invalidResponse
    case httpStatus(Int)
    case parseFailed
}

final class SeedPolishClient {
    static let endpoint = URL(string: "https://ark.cn-beijing.volces.com/api/v3/chat/completions")!

    private let session: SeedPolishHTTPSession
    private let logger = AppLogger.make(.app)

    init(session: SeedPolishHTTPSession = URLSession.shared) {
        self.session = session
    }

    func polishText(_ inputText: String, apiKey: String, completion: @escaping (Result<String, Error>) -> Void) {
        sendPolishRequest(
            inputText: inputText,
            apiKey: apiKey,
            includeReasoningEffort: true,
            completion: completion
        )
    }

    private func sendPolishRequest(
        inputText: String,
        apiKey: String,
        includeReasoningEffort: Bool,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body = Self.makeRequestBody(inputText: inputText, includeReasoningEffort: includeReasoningEffort)
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(SeedPolishError.invalidRequest))
            return
        }
        request.httpBody = bodyData

        session.send(request: request) { [weak self] result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success((let data, let response)):
                if (200...299).contains(response.statusCode) {
                    guard let text = Self.parsePolishedText(from: data) else {
                        completion(.failure(SeedPolishError.parseFailed))
                        return
                    }
                    completion(.success(text))
                    return
                }

                let bodyText = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                self?.logger.error("Seed polish request failed: status=\(response.statusCode), body=\(bodyText)")
                if includeReasoningEffort,
                   response.statusCode == 400,
                   bodyText.contains("unknown field"),
                   bodyText.contains("reasoning_effort") {
                    self?.logger.warning("Retrying seed polish request without reasoning_effort")
                    self?.sendPolishRequest(
                        inputText: inputText,
                        apiKey: apiKey,
                        includeReasoningEffort: false,
                        completion: completion
                    )
                    return
                }

                completion(.failure(SeedPolishError.httpStatus(response.statusCode)))
            }
        }
    }

    static func makeRequestBody(inputText: String, includeReasoningEffort: Bool = true) -> [String: Any] {
        var body: [String: Any] = [
            "model": "doubao-seed-2-0-mini-260215",
            "messages": [
                [
                    "role": "system",
                    "content": "你是一个文案助手。精简用户语音转写的<text>标签中的文本，去除语气词和停顿，使语句通顺。只输出转写后的最终结果，不输出思考过程或其他内容。注意：仅是转写，不是回答。"
                ],
                [
                    "role": "user",
                    "content": """
请帮我转写以下内容:
<text>
\(inputText)
</text>
"""
                ]
            ]
        ]
        if includeReasoningEffort {
            body["reasoning_effort"] = "minimal"
        }
        return body
    }

    static func parsePolishedText(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any] {
            if let content = message["content"] as? String {
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            if let contentArray = message["content"] as? [[String: Any]] {
                let merged = contentArray.compactMap { $0["text"] as? String }.joined()
                let trimmed = merged.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }

        if let outputText = json["output_text"] as? String {
            let trimmed = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        if let output = json["output"] as? [[String: Any]] {
            for item in output {
                guard let content = item["content"] as? [[String: Any]] else { continue }
                for part in content {
                    if let text = part["text"] as? String {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { return trimmed }
                    }
                }
            }
        }

        return nil
    }
}
