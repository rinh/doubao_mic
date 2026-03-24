import XCTest
@testable import VoiceInput

final class HotkeyManagerTests: XCTestCase {

    func test_defaultHotkeyIsOptionA() {
        let hotkeyManager = HotkeyManager()
        let defaultHotkey = hotkeyManager.defaultHotkey

        XCTAssertEqual(defaultHotkey.keyCode, 0)
        XCTAssertTrue(defaultHotkey.modifiers.contains(.option))
    }

    func test_currentHotkey_isNilInitially() {
        let hotkeyManager = HotkeyManager()
        XCTAssertNil(hotkeyManager.currentHotkey)
    }

    func test_HotkeyConfig_equality() {
        let config1 = HotkeyManager.HotkeyConfig(keyCode: 5, modifiers: [.command, .shift])
        let config2 = HotkeyManager.HotkeyConfig(keyCode: 5, modifiers: [.command, .shift])
        let config3 = HotkeyManager.HotkeyConfig(keyCode: 0, modifiers: [.option])

        XCTAssertEqual(config1, config2)
        XCTAssertNotEqual(config1, config3)
    }

    func test_HotkeyConfig_defaultOptionA() {
        let config = HotkeyManager.HotkeyConfig.defaultOptionA

        XCTAssertEqual(config.keyCode, 0)
        XCTAssertTrue(config.modifiers.contains(.option))
        XCTAssertFalse(config.modifiers.contains(.command))
        XCTAssertFalse(config.modifiers.contains(.control))
    }

    func test_HotkeyConfig_defaultPolishOptionShiftA() {
        let config = HotkeyManager.HotkeyConfig.defaultPolishOptionShiftA

        XCTAssertEqual(config.keyCode, 0)
        XCTAssertTrue(config.modifiers.contains(.option))
        XCTAssertTrue(config.modifiers.contains(.shift))
        XCTAssertFalse(config.modifiers.contains(.command))
        XCTAssertFalse(config.modifiers.contains(.control))
    }
}
