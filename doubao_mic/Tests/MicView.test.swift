import XCTest
@testable import VoiceInput

@MainActor
final class MicViewTests: XCTestCase {

    func test_initialization_createsFourBars() {
        let view = MicView(frame: NSRect(x: 0, y: 0, width: 80, height: 80))
        view.layoutSubtreeIfNeeded()

        XCTAssertEqual(view.waveBarCount, 4)
    }

    func test_updateLevel_updatesBarHeights() {
        let view = MicView(frame: NSRect(x: 0, y: 0, width: 80, height: 80))
        view.layoutSubtreeIfNeeded()

        view.updateLevel(1.0)
        RunLoop.current.run(until: Date().addingTimeInterval(0.12))

        let heights = view.waveBarHeights
        XCTAssertEqual(heights.count, 4)
        XCTAssertGreaterThan(heights[1], heights[0])
    }

    func test_reset_restoresSilenceHeights() {
        let view = MicView(frame: NSRect(x: 0, y: 0, width: 80, height: 80))
        view.layoutSubtreeIfNeeded()

        view.updateLevel(1.0)
        view.reset()
        RunLoop.current.run(until: Date().addingTimeInterval(0.12))

        XCTAssertTrue(view.waveBarHeights.allSatisfy { abs($0 - 4.0) < 0.1 })
    }
}
