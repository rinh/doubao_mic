import XCTest
@testable import VoiceInput

final class WaveformModelTests: XCTestCase {

    func test_updateLevel_zero_returnsMinimumHeights() {
        var model = WaveformModel(minHeight: 4, maxHeight: 22)

        let heights = model.update(level: 0)

        XCTAssertEqual(heights.count, 4)
        XCTAssertTrue(heights.allSatisfy { abs($0 - 4) < 0.001 })
    }

    func test_updateLevel_one_makesCenterBarsHigherThanOuterBars() {
        var model = WaveformModel(minHeight: 4, maxHeight: 22)

        let heights = model.update(level: 1)

        XCTAssertGreaterThan(heights[1], heights[0])
        XCTAssertGreaterThan(heights[2], heights[3])
        XCTAssertLessThanOrEqual(heights[1], 22)
        XCTAssertLessThanOrEqual(heights[2], 22)
    }

    func test_smoothing_appliesAcrossFrames() {
        var model = WaveformModel(minHeight: 4, maxHeight: 22, attack: 0.5, release: 0.2)

        let first = model.update(level: 1)
        let second = model.update(level: 1)

        XCTAssertGreaterThan(second[1], first[1])
        XCTAssertLessThan(second[1], 22)
    }

    func test_inputLevel_isClamped() {
        var model = WaveformModel(minHeight: 4, maxHeight: 22)

        let low = model.update(level: -0.5)
        let high = model.update(level: 1.5)

        XCTAssertTrue(low.allSatisfy { abs($0 - 4) < 0.001 })
        XCTAssertLessThanOrEqual(high[1], 22)
        XCTAssertLessThanOrEqual(high[2], 22)
    }

    func test_reset_returnsMinimumHeights() {
        var model = WaveformModel(minHeight: 4, maxHeight: 22)
        _ = model.update(level: 1)

        let resetHeights = model.reset()

        XCTAssertTrue(resetHeights.allSatisfy { abs($0 - 4) < 0.001 })
    }
}
