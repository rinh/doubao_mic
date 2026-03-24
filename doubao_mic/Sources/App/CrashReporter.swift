import Foundation
import Darwin

final class CrashReporter {

    private static let logger = AppLogger.make(.crash)
    private static let handledSignals: [Int32] = [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP]
    private static var crashLogFD: Int32 = -1
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true

        let logURL = crashLogURL()
        prepareCrashLogFile(at: logURL)

        NSSetUncaughtExceptionHandler(uncaughtExceptionHandler)

        for signalNumber in handledSignals {
            signal(signalNumber, crashSignalHandler)
        }

        logger.info("CrashReporter installed. Crash log: \(logURL.path)")
    }

    private static func crashLogURL() -> URL {
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/VoiceInput", isDirectory: true)
        return logsDir.appendingPathComponent("crash.log")
    }

    private static func prepareCrashLogFile(at url: URL) {
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }

            crashLogFD = open(url.path, O_WRONLY | O_APPEND)
            if crashLogFD < 0 {
                logger.error("Failed to open crash log file: \(url.path)")
            }
        } catch {
            logger.error("Failed to prepare crash log file: \(error.localizedDescription)")
        }
    }

    static func handleUncaughtException(_ exception: NSException) {
        let line = "[\(isoTimestamp())] Uncaught NSException name=\(exception.name.rawValue) reason=\(exception.reason ?? "nil")"
        appendCrashLine(line)
        logger.fault("\(line)")
    }

    static func handleSignal(_ signalNumber: Int32) {
        let signalName: String
        switch signalNumber {
        case SIGABRT: signalName = "SIGABRT"
        case SIGILL: signalName = "SIGILL"
        case SIGSEGV: signalName = "SIGSEGV"
        case SIGFPE: signalName = "SIGFPE"
        case SIGBUS: signalName = "SIGBUS"
        case SIGTRAP: signalName = "SIGTRAP"
        default: signalName = "SIGNAL_\(signalNumber)"
        }

        let line = "[\(isoTimestamp())] Fatal signal \(signalName) (\(signalNumber))"
        appendCrashLine(line)

        // Restore default handler and re-raise so macOS still records the original crash report.
        signal(signalNumber, SIG_DFL)
        raise(signalNumber)
    }

    private static func appendCrashLine(_ line: String) {
        guard crashLogFD >= 0 else { return }
        let text = line + "\n"
        text.utf8CString.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            _ = write(crashLogFD, base, max(ptr.count - 1, 0))
        }
        _ = fsync(crashLogFD)
    }

    private static func isoTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: Date())
    }
}

private func crashSignalHandler(_ signalNumber: Int32) {
    CrashReporter.handleSignal(signalNumber)
}

private func uncaughtExceptionHandler(_ exception: NSException) {
    CrashReporter.handleUncaughtException(exception)
}
