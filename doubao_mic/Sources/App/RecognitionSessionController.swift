import Foundation

enum RecognitionSessionState: String {
    case idle
    case recording
    case awaitingFinal
    case finalized
    case failed
}

final class RecognitionSessionController {
    private(set) var state: RecognitionSessionState = .idle
    private(set) var latestDraftText: String = ""
    private(set) var finalText: String?
    private var pendingDefiniteFinalText: String?

    var onDraftUpdated: ((String) -> Void)?
    var onFinalReady: ((String) -> Void)?
    var onFinalTimeout: (() -> Void)?
    var onStateChanged: ((RecognitionSessionState) -> Void)?

    private var finalTimeoutWorkItem: DispatchWorkItem?
    private let queue: DispatchQueue

    init(queue: DispatchQueue = .main) {
        self.queue = queue
    }

    func startSession() {
        cancelTimeout()
        latestDraftText = ""
        finalText = nil
        pendingDefiniteFinalText = nil
        transition(to: .recording)
    }

    func updateDraft(_ text: String) {
        guard state == .recording || state == .awaitingFinal else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        latestDraftText = text
        onDraftUpdated?(text)
    }

    func awaitFinal(timeout: TimeInterval) {
        guard state == .recording else { return }
        transition(to: .awaitingFinal)

        if commitIfPossible(using: pendingDefiniteFinalText) {
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.state == .awaitingFinal else { return }
            self.transition(to: .failed)
            self.onFinalTimeout?()
        }
        finalTimeoutWorkItem = work
        queue.asyncAfter(deadline: .now() + timeout, execute: work)
    }

    func handleRecognitionUpdate(_ update: ASRRecognitionUpdate) {
        updateDraft(update.text)

        guard update.hasDefiniteUtterance else {
            return
        }

        // For second-pass recognition, prefer the model's full text output.
        // `definiteText` is kept as fallback if full text is unavailable.
        let resolvedFinalText = update.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (update.definiteText ?? "")
            : update.text
        let trimmedFinalText = resolvedFinalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFinalText.isEmpty else {
            return
        }
        pendingDefiniteFinalText = trimmedFinalText

        guard state == .awaitingFinal else {
            return
        }
        _ = commitIfPossible(using: trimmedFinalText)
    }

    func fail() {
        cancelTimeout()
        transition(to: .failed)
    }

    func reset() {
        cancelTimeout()
        latestDraftText = ""
        finalText = nil
        pendingDefiniteFinalText = nil
        transition(to: .idle)
    }

    @discardableResult
    private func commitIfPossible(using candidateText: String?) -> Bool {
        guard state == .awaitingFinal,
              let candidateText,
              !candidateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        cancelTimeout()
        finalText = candidateText
        transition(to: .finalized)
        onFinalReady?(candidateText)
        return true
    }

    private func transition(to newState: RecognitionSessionState) {
        state = newState
        onStateChanged?(newState)
    }

    private func cancelTimeout() {
        finalTimeoutWorkItem?.cancel()
        finalTimeoutWorkItem = nil
    }
}
