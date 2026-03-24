import AppKit
import os.log

final class ASRErrorHandler {

    private let logger = AppLogger.make(.asr)
    var onErrorOccurred: ((ASRError) -> Void)?

    func handle(error: ASRError) {
        let errorDescription = error.localizedDescription
        logger.error("Received ASR error: \(errorDescription)")

        // Ensure we only interact with UI on main thread and with proper safeguards
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.onErrorOccurred?(error)

            // Only show alert if app is active and can safely show windows
            if NSApp.isActive && NSApp.keyWindow != nil {
                self.showErrorAlert(error: error)
            } else {
                self.logger.info("Skipping error alert: app not in foreground")
            }
        }
    }

    private func showErrorAlert(error: ASRError) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "语音识别错误"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "确定")

        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window) { _ in }
        } else {
            alert.runModal()
        }
    }
}

enum ASRError: Error {
    case authenticationFailed
    case networkError(Error)
    case timeout
    case serverError(Int)
    case unknown(Error)

    var localizedDescription: String {
        switch self {
        case .authenticationFailed:
            return "认证失败，请检查 API 凭证是否正确"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .timeout:
            return "连接超时，请检查网络"
        case .serverError(let code):
            return "服务器错误: \(code)"
        case .unknown(let error):
            return "未知错误: \(error.localizedDescription)"
        }
    }
}
