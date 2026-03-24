import XCTest
@testable import VoiceInput

final class CredentialManagerTests: XCTestCase {

    private func writeTempConfig(_ content: String) throws -> String {
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("voiceinput-ak-\(UUID().uuidString).yaml")
        try content.write(to: file, atomically: true, encoding: .utf8)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: file)
        }
        return file.path
    }

    func test_loadCredentials_readsFromConfigFile() throws {
        let path = try writeTempConfig(
            """
            appId: 6106408834
            accessToken: test_access_token_123
            seedApiKey: test_seed_api_key
            """
        )
        let manager = CredentialManager(configPath: path)
        let credentials = manager.loadCredentials()

        XCTAssertEqual(credentials.appId, "6106408834")
        XCTAssertEqual(credentials.accessToken, "test_access_token_123")
        XCTAssertEqual(credentials.seedApiKey, "test_seed_api_key")
    }

    func test_credentials_containsValidResourceId() throws {
        let path = try writeTempConfig(
            """
            appId: 6106408834
            accessToken: test_access_token_123
            """
        )
        let manager = CredentialManager(configPath: path)
        let credentials = manager.loadCredentials()

        XCTAssertEqual(credentials.resourceId, "volc.bigasr.sauc.duration")
    }

    func test_credentials_resourceId_canBeOverriddenByConfig() throws {
        let path = try writeTempConfig(
            """
            appId: 6106408834
            accessToken: test_access_token_123
            resourceId: volc.bigasr.sauc.duration
            """
        )
        let manager = CredentialManager(configPath: path)
        let credentials = manager.loadCredentials()

        XCTAssertEqual(credentials.resourceId, "volc.bigasr.sauc.duration")
    }

    func test_credentials_seedApiKey_defaultsToEmpty() throws {
        let path = try writeTempConfig(
            """
            appId: 6106408834
            accessToken: test_access_token_123
            """
        )
        let manager = CredentialManager(configPath: path)
        let credentials = manager.loadCredentials()

        XCTAssertEqual(credentials.seedApiKey, "")
    }
}
