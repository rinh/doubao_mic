import XCTest
@testable import VoiceInput

final class AppStateTests: XCTestCase {

    var appState: AppState!
    var testDefaults: UserDefaults!
    private let suiteName = "com.voiceinput.app.tests.AppStateTests"

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: suiteName)
        testDefaults.removePersistentDomain(forName: suiteName)
        appState = AppState(defaults: testDefaults)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        appState = nil
        testDefaults = nil
        super.tearDown()
    }

    func test_defaultHotkey_isOptionA() {
        XCTAssertEqual(appState.hotkeyKeyCode, 0)
        XCTAssertTrue(appState.hotkeyModifiers.contains(.option))
    }

    func test_defaultPolishHotkey_isOptionShiftA() {
        XCTAssertEqual(appState.polishHotkeyKeyCode, 0)
        XCTAssertTrue(appState.polishHotkeyModifiers.contains(.option))
        XCTAssertTrue(appState.polishHotkeyModifiers.contains(.shift))
    }

    func test_saveHotkey_updatesConfiguration() {
        appState.saveHotkey(keyCode: 5, modifiers: .command)

        XCTAssertEqual(appState.hotkeyKeyCode, 5)
        XCTAssertTrue(appState.hotkeyModifiers.contains(.command))
    }

    func test_appId_isStored() {
        appState.appId = "test_app_id"

        XCTAssertEqual(appState.appId, "test_app_id")
    }

    func test_accessToken_isStored() {
        appState.accessToken = "test_token"

        XCTAssertEqual(appState.accessToken, "test_token")
    }

    func test_isConfigured_returnsTrueWhenCredentialsPresent() {
        appState.appId = "app_id"
        appState.accessToken = "token"

        XCTAssertTrue(appState.isConfigured)
    }

    func test_isConfigured_returnsFalseWhenCredentialsMissing() {
        appState.appId = ""
        appState.accessToken = ""

        XCTAssertFalse(appState.isConfigured)
    }

    func test_loadFromUserDefaults_restoresConfiguration() {
        appState.hotkeyKeyCode = 12
        appState.hotkeyModifiers = [.command, .shift]
        appState.polishHotkeyKeyCode = 1
        appState.polishHotkeyModifiers = [.control, .option]
        appState.appId = "my_app"
        appState.accessToken = "my_token"

        appState.synchronize()

        let newInstance = AppState(defaults: testDefaults)

        XCTAssertEqual(newInstance.hotkeyKeyCode, 12)
        XCTAssertTrue(newInstance.hotkeyModifiers.contains(.command))
        XCTAssertTrue(newInstance.hotkeyModifiers.contains(.shift))
        XCTAssertEqual(newInstance.polishHotkeyKeyCode, 1)
        XCTAssertTrue(newInstance.polishHotkeyModifiers.contains(.control))
        XCTAssertTrue(newInstance.polishHotkeyModifiers.contains(.option))
        XCTAssertEqual(newInstance.appId, "my_app")
        XCTAssertEqual(newInstance.accessToken, "my_token")
    }
}
