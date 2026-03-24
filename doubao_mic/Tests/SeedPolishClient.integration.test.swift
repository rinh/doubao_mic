import XCTest
@testable import VoiceInput

final class SeedPolishClientIntegrationTests: XCTestCase {

    func test_polishText_realAPI_returnsSuccess_whenConfigured() throws {
        guard let apiKey = ProcessInfo.processInfo.environment["SEED_API_KEY"],
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw XCTSkip("Set SEED_API_KEY to run real integration test.")
        }

        let inputText = """
        我们现在再看一下之前的所有关于 UI，叉 C UI test 的测试用例。然后呢，以及我们之前的对于这个可测试性的要求，也就是说 UI 和逻辑分离。UI 的最单独的这个测试，然后对于这个单测的独立性的要求，我们把这个总结一下。 主要是总结一下 TDD。 的这个原则。然后意义咱们那个 Wave 的 UI test。 作为例子。来说明。然后把这个原则和例子写到这个 哎呀。当前目录下的 Agents.MD 当中。
        """

        let client = SeedPolishClient()
        let expectation = expectation(description: "real seed polish call succeeds")

        client.polishText(inputText, apiKey: apiKey) { result in
            switch result {
            case .success(let output):
                XCTAssertFalse(output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                expectation.fulfill()
            case .failure(let error):
                XCTFail("Real API call failed: \(error)")
            }
        }

        wait(for: [expectation], timeout: 30.0)
    }
}
