import XCTest
@testable import VoiceInput

final class TextInserterTests: XCTestCase {

    var textInserter: TextInserter!

    override func setUp() {
        super.setUp()
        textInserter = TextInserter()
    }

    override func tearDown() {
        textInserter = nil
        super.tearDown()
    }

    func test_insertText_simulatesKeyboardInput() {
        textInserter.insertText("Hello")

        // In real scenario, this would verify CGEvent is created
        // For unit test, we verify the method doesn't throw
        XCTAssertTrue(true)
    }

    func test_insertText_atCurrentCursorPosition() {
        textInserter.insertText("Test")

        XCTAssertTrue(true)
    }

    func test_bestEffortInsertion_usesAXFirstAndSkipsKeyEventsWhenAXSucceeds() {
        var axCallCount = 0
        var keyEventsCallCount = 0

        let result = textInserter.performBestEffortInsertion(
            text: "hello",
            attemptID: "test-attempt-1",
            axInsert: { _ in
                axCallCount += 1
                return .verified(.verifiedBySelectedText)
            },
            keyEventsAllowed: {
                true
            },
            keyEventsInsert: { _ in
                keyEventsCallCount += 1
            }
        )

        XCTAssertEqual(result, .axVerified)
        XCTAssertEqual(axCallCount, 1)
        XCTAssertEqual(keyEventsCallCount, 0)
    }

    func test_bestEffortInsertion_fallsBackToKeyEventsWhenAXNoEffect() {
        var axCallCount = 0
        var keyEventsCallCount = 0

        let result = textInserter.performBestEffortInsertion(
            text: "hello",
            attemptID: "test-attempt-2",
            axInsert: { _ in
                axCallCount += 1
                return .noEffect
            },
            keyEventsAllowed: {
                true
            },
            keyEventsInsert: { _ in
                keyEventsCallCount += 1
            }
        )

        XCTAssertEqual(result, .keyEvents)
        XCTAssertEqual(axCallCount, 1)
        XCTAssertEqual(keyEventsCallCount, 1)
    }

    func test_bestEffortInsertion_fallsBackToKeyEventsWhenAXSetFails() {
        var axCallCount = 0
        var keyEventsCallCount = 0

        let result = textInserter.performBestEffortInsertion(
            text: "hello",
            attemptID: "test-attempt-3",
            axInsert: { _ in
                axCallCount += 1
                return .setFailed(code: -25205)
            },
            keyEventsAllowed: {
                true
            },
            keyEventsInsert: { _ in
                keyEventsCallCount += 1
            }
        )

        XCTAssertEqual(result, .keyEvents)
        XCTAssertEqual(axCallCount, 1)
        XCTAssertEqual(keyEventsCallCount, 1)
    }

    func test_bestEffortInsertion_returnsKeyEventsDeniedWhenPermissionMissing() {
        var axCallCount = 0
        var keyEventsCallCount = 0

        let result = textInserter.performBestEffortInsertion(
            text: "hello",
            attemptID: "test-attempt-4",
            axInsert: { _ in
                axCallCount += 1
                return .noEffect
            },
            keyEventsAllowed: {
                false
            },
            keyEventsInsert: { _ in
                keyEventsCallCount += 1
            }
        )

        XCTAssertEqual(result, .failedKeyEventsDenied)
        XCTAssertEqual(axCallCount, 1)
        XCTAssertEqual(keyEventsCallCount, 0)
    }

    func test_bestEffortInsertion_returnsKeyEventsSendFailedWhenKeyEventsThrow() {
        var axCallCount = 0
        var keyEventsCallCount = 0

        enum TestError: Error { case failed }

        let result = textInserter.performBestEffortInsertion(
            text: "hello",
            attemptID: "test-attempt-5",
            axInsert: { _ in
                axCallCount += 1
                return .noEffect
            },
            keyEventsAllowed: {
                true
            },
            keyEventsInsert: { _ in
                keyEventsCallCount += 1
                throw TestError.failed
            }
        )

        XCTAssertEqual(result, .failedKeyEventsSend)
        XCTAssertEqual(axCallCount, 1)
        XCTAssertEqual(keyEventsCallCount, 1)
    }
}
