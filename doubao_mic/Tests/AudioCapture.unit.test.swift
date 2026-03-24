import XCTest
@testable import VoiceInput

final class AudioCaptureTests: XCTestCase {

    func test_audioCapture_isNotRecordingInitially() {
        let capture = AudioCapture()
        XCTAssertFalse(capture.isRecording)
    }

    func test_audioCapture_stopRecording_whenNotStarted() {
        let capture = AudioCapture()
        capture.stopRecording()
        XCTAssertFalse(capture.isRecording)
    }
}
