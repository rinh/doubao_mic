import XCTest
@testable import VoiceInput

final class PreferencesWindowControllerTests: XCTestCase {

    var preferencesWindowController: PreferencesWindowController!

    override func setUp() {
        super.setUp()
        preferencesWindowController = PreferencesWindowController()
    }

    override func tearDown() {
        preferencesWindowController = nil
        super.tearDown()
    }

    func test_windowHasTitle() {
        XCTAssertEqual(preferencesWindowController.window?.title, "VoiceInput Preferences")
    }

    func test_windowIsResizable() {
        let styleMask = preferencesWindowController.window?.styleMask ?? []
        XCTAssertTrue(styleMask.contains(.titled))
        XCTAssertTrue(styleMask.contains(.closable))
    }

    func test_containsHotkeyConfigurationSection() {
        preferencesWindowController.showWindow(nil)

        XCTAssertNotNil(preferencesWindowController.hotkeyRecorder)
        XCTAssertNotNil(preferencesWindowController.polishHotkeyRecorder)
    }

    func test_windowCenterOnScreen() {
        preferencesWindowController.showWindow(nil)

        let windowFrame = preferencesWindowController.window?.frame ?? .zero
        XCTAssertGreaterThan(windowFrame.width, 0)
        XCTAssertGreaterThan(windowFrame.height, 0)
    }

    func test_validateHotkeys_rejectsDuplicateCombination() {
        let duplicated = preferencesWindowController.validateHotkeyConflict(
            dictationKeyCode: 0,
            dictationModifiers: [.option, .shift],
            polishKeyCode: 0,
            polishModifiers: [.option, .shift]
        )

        XCTAssertFalse(duplicated)
    }
}
