import XCTest
@testable import VoiceInput

final class KeyRecorderViewTests: XCTestCase {

    var keyRecorderView: KeyRecorderView!

    override func setUp() {
        super.setUp()
        keyRecorderView = KeyRecorderView()
    }

    override func tearDown() {
        keyRecorderView = nil
        super.tearDown()
    }

    func test_defaultDisplay_showsPlaceholder() {
        let placeholder = keyRecorderView.placeholderText

        XCTAssertEqual(placeholder, "Click to record")
    }

    func test_startRecording_changesToRecordingState() {
        keyRecorderView.startRecording()

        XCTAssertTrue(keyRecorderView.isRecording)
        XCTAssertEqual(keyRecorderView.displayText, "Recording...")
    }

    func test_stopRecording_restoresToDefault() {
        keyRecorderView.startRecording()
        keyRecorderView.stopRecording()

        XCTAssertFalse(keyRecorderView.isRecording)
    }

    func test_recordKey_updatesDisplayWithKeyCombo() {
        keyRecorderView.startRecording()
        keyRecorderView.recordKey(keyCode: 0, modifiers: .option) // Option+A

        XCTAssertEqual(keyRecorderView.displayText, "⌥A")
        XCTAssertFalse(keyRecorderView.isRecording)
    }

    func test_recordKey_firesCallback() {
        var capturedKeyCode: UInt32?
        var capturedModifiers: NSEvent.ModifierFlags?

        keyRecorderView.onHotkeyRecorded = { keyCode, modifiers in
            capturedKeyCode = keyCode
            capturedModifiers = modifiers
        }

        keyRecorderView.startRecording()
        keyRecorderView.recordKey(keyCode: 1, modifiers: .command) // Command+B

        XCTAssertEqual(capturedKeyCode, 1)
        XCTAssertTrue(capturedModifiers?.contains(.command) ?? false)
    }

    func test_clearKey_resetsToPlaceholder() {
        keyRecorderView.startRecording()
        keyRecorderView.recordKey(keyCode: 5, modifiers: [.option, .shift])

        keyRecorderView.clearKey()

        XCTAssertEqual(keyRecorderView.displayText, keyRecorderView.placeholderText)
    }
}
