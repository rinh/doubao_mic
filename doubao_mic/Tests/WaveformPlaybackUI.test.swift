import XCTest
@testable import VoiceInput

@MainActor
final class WaveformPlaybackUITests: XCTestCase {

    func test_fixturePlayback_drivesWaveformLowHighLow_withoutManualInput() {
        let fixtureURL = Self.fixtureURL()
        let source = FixtureAudioLevelSource(fixtureURL: fixtureURL, updateInterval: 0.03)
        let view = MicView(frame: NSRect(x: 0, y: 0, width: 80, height: 80))
        view.layoutSubtreeIfNeeded()

        var centerHeights: [CGFloat] = []
        let finished = expectation(description: "fixture playback finished")

        source.onAudioLevelUpdate = { level in
            view.updateLevel(level)
            if view.waveBarHeights.count >= 2 {
                centerHeights.append(view.waveBarHeights[1])
            }
        }
        source.onPlaybackFinished = {
            finished.fulfill()
        }

        source.startRecording()
        wait(for: [finished], timeout: 5.0)

        XCTAssertGreaterThan(centerHeights.count, 10)

        let firstSlice = Array(centerHeights.prefix(5))
        let middleStart = centerHeights.count / 3
        let middleEnd = min(middleStart + 10, centerHeights.count)
        let middleSlice = Array(centerHeights[middleStart..<middleEnd])
        let lastSlice = Array(centerHeights.suffix(5))

        let firstAvg = average(firstSlice)
        let middleAvg = average(middleSlice)
        let lastAvg = average(lastSlice)

        XCTAssertGreaterThan(middleAvg, firstAvg + 2.0)
        XCTAssertLessThan(lastAvg, middleAvg)
    }

    func test_fixtureFile_canProduceLevels() {
        let fixtureURL = Self.fixtureURL()
        let levels = FixtureAudioLevelSource.loadLevels(from: fixtureURL)

        XCTAssertFalse(levels.isEmpty)
        XCTAssertGreaterThan(levels.max() ?? 0, 0.4)
    }

    private func average(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / CGFloat(values.count)
    }

    private static func fixtureURL() -> URL {
        let testFile = URL(fileURLWithPath: #filePath)
        return testFile
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("waveform_fixture.wav")
    }
}
