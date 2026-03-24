import os.log

enum LogCategory: String {
    case app = "App"
    case audio = "Audio"
    case asr = "ASR"
    case hotkey = "Hotkey"
    case input = "Input"
    case ui = "UI"
    case crash = "Crash"
}

struct AppLog {
    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    private func isEnabled(for level: AppLogLevel) -> Bool {
        AppState().logLevel.rawValue <= level.rawValue
    }

    func debug(_ message: @autoclosure () -> String) {
        guard isEnabled(for: .debug) else { return }
        let text = message()
        logger.log(level: .debug, "\(text, privacy: .public)")
    }

    func info(_ message: @autoclosure () -> String) {
        guard isEnabled(for: .info) else { return }
        let text = message()
        logger.log(level: .info, "\(text, privacy: .public)")
    }

    func warning(_ message: @autoclosure () -> String) {
        guard isEnabled(for: .warning) else { return }
        let text = message()
        logger.log(level: .default, "\(text, privacy: .public)")
    }

    func error(_ message: @autoclosure () -> String) {
        guard isEnabled(for: .error) else { return }
        let text = message()
        logger.log(level: .error, "\(text, privacy: .public)")
    }

    func fault(_ message: @autoclosure () -> String) {
        guard isEnabled(for: .fault) else { return }
        let text = message()
        logger.log(level: .fault, "\(text, privacy: .public)")
    }
}

enum AppLogger {
    static let subsystem = "com.voiceinput.app"

    static func make(_ category: LogCategory) -> AppLog {
        AppLog(logger: Logger(subsystem: subsystem, category: category.rawValue))
    }
}
