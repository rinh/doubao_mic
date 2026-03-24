import XCTest
@testable import VoiceInput

final class AppDelegateTests: XCTestCase {

    var appState: AppState!
    var testDefaults: UserDefaults!
    private let suiteName = "com.voiceinput.app.tests.AppDelegateTests"

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: suiteName)
        testDefaults.removePersistentDomain(forName: suiteName)
        appState = AppState(defaults: testDefaults)
        appState.appId = "test_app_id"
        appState.accessToken = "test_token"
        appState.hotkeyKeyCode = 0
        appState.hotkeyModifiers = .option
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        appState = nil
        testDefaults = nil
        super.tearDown()
    }

    func test_appState_loadsConfiguration() {
        XCTAssertEqual(appState.appId, "test_app_id")
        XCTAssertEqual(appState.accessToken, "test_token")
    }

    func test_appState_defaultHotkeyIsOptionA() {
        XCTAssertEqual(appState.hotkeyKeyCode, 0)
        XCTAssertTrue(appState.hotkeyModifiers.contains(.option))
    }

    func test_appState_detectsConfigurationStatus() {
        XCTAssertTrue(appState.isConfigured)
    }

    func test_shouldKeepFloatingUIVisible_isTrue_whenRecording() {
        XCTAssertTrue(
            AppDelegate.shouldKeepFloatingUIVisible(
                isRecording: true,
                isAwaitingFinalASR: false,
                flowState: "idle"
            )
        )
    }

    func test_shouldKeepFloatingUIVisible_isTrue_whenAwaitingFinalASR() {
        XCTAssertTrue(
            AppDelegate.shouldKeepFloatingUIVisible(
                isRecording: false,
                isAwaitingFinalASR: true,
                flowState: "finalized"
            )
        )
    }

    func test_shouldKeepFloatingUIVisible_isTrue_whenFlowStateIsPolishing() {
        XCTAssertTrue(
            AppDelegate.shouldKeepFloatingUIVisible(
                isRecording: false,
                isAwaitingFinalASR: false,
                flowState: "polishing"
            )
        )
    }

    func test_shouldKeepFloatingUIVisible_isFalse_whenSessionIsDone() {
        XCTAssertFalse(
            AppDelegate.shouldKeepFloatingUIVisible(
                isRecording: false,
                isAwaitingFinalASR: false,
                flowState: "finalized"
            )
        )
    }
}
