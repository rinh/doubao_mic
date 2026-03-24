import Foundation
import XCTest
@testable import VoiceInput

final class SeedPolishClientTests: XCTestCase {

    func test_makeRequestBody_containsRequiredFields() throws {
        let body = SeedPolishClient.makeRequestBody(inputText: "原始语音文本")

        XCTAssertEqual(body["model"] as? String, "doubao-seed-2-0-mini-260215")
        XCTAssertEqual(body["reasoning_effort"] as? String, "minimal")

        let messages = body["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 2)
    }

    func test_polishText_sendsAuthorizationHeader() {
        let expectation = expectation(description: "request captured")
        let session = MockHTTPSession()
        session.onRequest = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://ark.cn-beijing.volces.com/api/v3/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer seed_key_123")
            expectation.fulfill()
        }
        session.nextResult = .success(
            MockHTTPSession.Response(
                statusCode: 200,
                body: """
                {"choices":[{"message":{"content":"整理后文本"}}]}
                """.data(using: .utf8)!
            )
        )

        let client = SeedPolishClient(session: session)
        client.polishText("原始", apiKey: "seed_key_123") { _ in }

        wait(for: [expectation], timeout: 1.0)
    }

    func test_polishText_parsesOutputTextField() {
        let expectation = expectation(description: "parse output_text")
        let session = MockHTTPSession()
        session.nextResult = .success(
            MockHTTPSession.Response(
                statusCode: 200,
                body: """
                {"choices":[{"message":{"content":"整理后文本"}}]}
                """.data(using: .utf8)!
            )
        )

        let client = SeedPolishClient(session: session)
        client.polishText("原始", apiKey: "seed_key_123") { result in
            if case let .success(text) = result {
                XCTAssertEqual(text, "整理后文本")
            } else {
                XCTFail("Expected success")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func test_polishText_returnsFailureOnServerError() {
        let expectation = expectation(description: "server error")
        let session = MockHTTPSession()
        session.nextResult = .success(
            MockHTTPSession.Response(
                statusCode: 500,
                body: Data()
            )
        )

        let client = SeedPolishClient(session: session)
        client.polishText("原始", apiKey: "seed_key_123") { result in
            if case .failure = result {
                expectation.fulfill()
            } else {
                XCTFail("Expected failure")
            }
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func test_polishText_withLongRawTranscript_returnsSuccess() {
        let expectation = expectation(description: "long transcript polished successfully")
        let session = MockHTTPSession()
        session.nextResult = .success(
            MockHTTPSession.Response(
                statusCode: 200,
                body: """
                {"choices":[{"message":{"content":"我们现在再看一下之前所有关于 UI 和 XCUITest 的测试用例，以及可测试性要求：UI 与逻辑分离、UI 独立测试、单测独立性。主要总结 TDD 原则，并以 Wave 的 UI 测试为例进行说明，最后把原则和例子写到当前目录下的 AGENTS.md。"}}]}
                """.data(using: .utf8)!
            )
        )

        let rawText = """
        我们现在再看一下之前的所有关于 UI，叉 C UI test 的测试用例。然后呢，以及我们之前的对于这个可测试性的要求，也就是说 UI 和逻辑分离。UI 的最单独的这个测试，然后对于这个单测的独立性的要求，我们把这个总结一下。 主要是总结一下 TDD。 的这个原则。然后意义咱们那个 Wave 的 UI test。 作为例子。来说明。然后把这个原则和例子写到这个 哎呀。当前目录下的 Agents.MD 当中。
        """

        let client = SeedPolishClient(session: session)
        client.polishText(rawText, apiKey: "seed_key_123") { result in
            switch result {
            case .success:
                expectation.fulfill()
            case .failure(let error):
                XCTFail("Expected success but got failure: \(error)")
            }
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func test_polishText_retriesWithoutReasoningEffort_whenServerRejectsField() {
        let expectation = expectation(description: "retry without reasoning_effort")
        let session = MockHTTPSession()
        var seenRequestBodies: [[String: Any]] = []
        session.onRequest = { request in
            guard let data = request.httpBody,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            seenRequestBodies.append(json)
        }
        session.queuedResults = [
            .success(
                MockHTTPSession.Response(
                    statusCode: 400,
                    body: """
                    {"error":{"code":"InvalidParameter","message":"json: unknown field \\"reasoning_effort\\""}}
                    """.data(using: .utf8)!
                )
            ),
            .success(
                MockHTTPSession.Response(
                    statusCode: 200,
                    body: """
                    {"output_text":"重试成功文本"}
                    """.data(using: .utf8)!
                )
            )
        ]

        let client = SeedPolishClient(session: session)
        client.polishText("原始文本", apiKey: "seed_key_123") { result in
            switch result {
            case .success(let text):
                XCTAssertEqual(text, "重试成功文本")
                XCTAssertEqual(seenRequestBodies.count, 2)
                XCTAssertEqual(seenRequestBodies[0]["reasoning_effort"] as? String, "minimal")
                XCTAssertNil(seenRequestBodies[1]["reasoning_effort"])
                expectation.fulfill()
            case .failure(let error):
                XCTFail("Expected retry success but got failure: \(error)")
            }
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func test_parsePolishedText_fromChatCompletionsChoices() {
        let data = """
        {"choices":[{"message":{"content":"来自 chat completions 的整理文本"}}]}
        """.data(using: .utf8)!

        let parsed = SeedPolishClient.parsePolishedText(from: data)

        XCTAssertEqual(parsed, "来自 chat completions 的整理文本")
    }
}

private final class MockHTTPSession: SeedPolishHTTPSession {
    struct Response {
        let statusCode: Int
        let body: Data
    }

    enum MockError: Error {
        case noResult
        case transport
    }

    var onRequest: ((URLRequest) -> Void)?
    var nextResult: Result<Response, Error>?
    var queuedResults: [Result<Response, Error>] = []

    func send(request: URLRequest, completion: @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) {
        onRequest?(request)
        let resolvedResult: Result<Response, Error>?
        if !queuedResults.isEmpty {
            resolvedResult = queuedResults.removeFirst()
        } else {
            resolvedResult = nextResult
        }
        guard let resolvedResult else {
            completion(.failure(MockError.noResult))
            return
        }
        switch resolvedResult {
        case .success(let response):
            let http = HTTPURLResponse(
                url: request.url!,
                statusCode: response.statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            completion(.success((response.body, http)))
        case .failure(let error):
            completion(.failure(error))
        }
    }
}
