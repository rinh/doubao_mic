import Foundation

final class CredentialManager {

    private static let bigAsrDurationResourceID = "volc.bigasr.sauc.duration"

    struct Credentials {
        let appId: String
        let accessToken: String
        let resourceId: String
        let seedApiKey: String

        static let empty = Credentials(
            appId: "",
            accessToken: "",
            resourceId: CredentialManager.bigAsrDurationResourceID,
            seedApiKey: ""
        )
    }

    private let configPath: String

    init(configPath: String? = nil) {
        if let configPath, !configPath.isEmpty {
            self.configPath = configPath
        } else {
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            self.configPath = "\(homeDir)/.voiceinput/ak.yaml"
        }
    }

    func loadCredentials() -> Credentials {
        guard FileManager.default.fileExists(atPath: configPath) else {
            return .empty
        }

        guard let content = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return .empty
        }

        var appId = ""
        var accessToken = ""
        var resourceId = Self.bigAsrDurationResourceID
        var seedApiKey = ""
        func normalizedValue(_ raw: String) -> String {
            var value = raw.trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            return value
        }

        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("appId:") {
                appId = normalizedValue(String(trimmed.dropFirst(6)))
            } else if trimmed.hasPrefix("accessToken:") {
                accessToken = normalizedValue(String(trimmed.dropFirst(12)))
            } else if trimmed.hasPrefix("resourceId:") {
                let parsed = normalizedValue(String(trimmed.dropFirst(11)))
                if !parsed.isEmpty {
                    resourceId = parsed
                }
            } else if trimmed.hasPrefix("seedApiKey:") {
                seedApiKey = normalizedValue(String(trimmed.dropFirst(11)))
            }
        }

        guard !appId.isEmpty, !accessToken.isEmpty else {
            return .empty
        }

        return Credentials(
            appId: appId,
            accessToken: accessToken,
            resourceId: resourceId,
            seedApiKey: seedApiKey
        )
    }
}
