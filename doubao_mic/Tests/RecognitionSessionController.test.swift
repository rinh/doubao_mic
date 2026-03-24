import XCTest
@testable import VoiceInput

@MainActor
final class RecognitionSessionControllerTests: XCTestCase {

    func test_draftUpdates_doNotTriggerFinalCommitDuringRecording() {
        let controller = RecognitionSessionController()
        var draftEvents: [String] = []
        var finalEvents: [String] = []
        controller.onDraftUpdated = { draftEvents.append($0) }
        controller.onFinalReady = { finalEvents.append($0) }

        controller.startSession()
        controller.handleRecognitionUpdate(
            ASRRecognitionUpdate(text: "你好", hasDefiniteUtterance: false, definiteText: nil)
        )

        XCTAssertEqual(controller.state, .recording)
        XCTAssertEqual(draftEvents, ["你好"])
        XCTAssertTrue(finalEvents.isEmpty)
    }

    func test_awaitFinal_commitsWhenDefiniteArrives() {
        let controller = RecognitionSessionController()
        var finalEvents: [String] = []
        controller.onFinalReady = { finalEvents.append($0) }

        controller.startSession()
        controller.awaitFinal(timeout: 1.0)
        controller.handleRecognitionUpdate(
            ASRRecognitionUpdate(text: "这是最终结果", hasDefiniteUtterance: true, definiteText: "这是最终结果")
        )

        XCTAssertEqual(controller.state, .finalized)
        XCTAssertEqual(finalEvents, ["这是最终结果"])
    }

    func test_awaitFinal_commitsImmediatelyWhenDefiniteAlreadyArrivedDuringRecording() {
        let controller = RecognitionSessionController()
        var finalEvents: [String] = []
        controller.onFinalReady = { finalEvents.append($0) }

        controller.startSession()
        controller.handleRecognitionUpdate(
            ASRRecognitionUpdate(text: "提前到达的最终结果", hasDefiniteUtterance: true, definiteText: "提前到达的最终结果")
        )

        XCTAssertEqual(controller.state, .recording)
        XCTAssertTrue(finalEvents.isEmpty)

        controller.awaitFinal(timeout: 1.0)

        XCTAssertEqual(controller.state, .finalized)
        XCTAssertEqual(finalEvents, ["提前到达的最终结果"])
    }

    func test_awaitFinal_timeoutDoesNotCommit() {
        let controller = RecognitionSessionController(queue: .main)
        var timedOut = false
        var finalEvents: [String] = []
        controller.onFinalTimeout = { timedOut = true }
        controller.onFinalReady = { finalEvents.append($0) }

        controller.startSession()
        controller.awaitFinal(timeout: 0.05)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(controller.state, .failed)
        XCTAssertTrue(timedOut)
        XCTAssertTrue(finalEvents.isEmpty)
    }

    func test_awaitFinal_prefersFullTextOverDefiniteTextWhenBothExist() {
        let controller = RecognitionSessionController()
        var finalEvents: [String] = []
        controller.onFinalReady = { finalEvents.append($0) }

        controller.startSession()
        controller.awaitFinal(timeout: 1.0)
        controller.handleRecognitionUpdate(
            ASRRecognitionUpdate(
                text: "这是二遍顺滑后的完整结果",
                hasDefiniteUtterance: true,
                definiteText: "这是原始分句结果"
            )
        )

        XCTAssertEqual(controller.state, .finalized)
        XCTAssertEqual(finalEvents, ["这是二遍顺滑后的完整结果"])
    }
}
