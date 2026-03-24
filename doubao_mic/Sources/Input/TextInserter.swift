import AppKit
import ApplicationServices
import Carbon
import os.log

final class TextInserter {

    private let logger = AppLogger.make(.input)

    enum InsertionStrategy: Equatable {
        case axVerified
        case axNoEffect
        case keyEvents
        case failedAXSet
        case failedKeyEventsDenied
        case failedKeyEventsSend
    }

    enum AXVerificationResult: Equatable {
        case verifiedBySelectedText
        case verifiedByValueGrowth
        case verifiedByValueContainsInsertion
        case noEffect
    }

    enum AXInsertOutcome: Equatable {
        case verified(AXVerificationResult)
        case noEffect
        case setFailed(code: Int32)
        case unavailable(code: Int32)
    }

    func insertText(_ text: String) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.insertText(text)
            }
            return
        }

        do {
            try performKeyEvents(text: text)
        } catch {
            logger.error("Failed to insert text by key events: \(error.localizedDescription)")
        }
    }

    private func performKeyEvents(text: String) throws {
        let source = CGEventSource(stateID: .combinedSessionState)

        for character in text.unicodeScalars {
            guard let unicodeScalar = UnicodeScalar(character.value) else { continue }

            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                continue
            }

            keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: [UniChar(unicodeScalar.value)])
            keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: [UniChar(unicodeScalar.value)])

            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    func insertRecognizedText(
        _ text: String,
        targetApp: NSRunningApplication? = nil,
        attemptID: String? = nil,
        completion: ((InsertionStrategy) -> Void)? = nil
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.insertRecognizedText(text, targetApp: targetApp, attemptID: attemptID, completion: completion)
            }
            return
        }
        let normalizedAttemptID = attemptID ?? UUID().uuidString
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        let sanitizedText = sanitizeForLog(text)
        logger.info("insertRecognizedText called. attemptId=\(normalizedAttemptID), textLength=\(text.count), text=\(sanitizedText), frontmostApp=\(frontmost)")
        logPermissionSnapshot(stage: "before_insert", attemptID: normalizedAttemptID)
        if !AXIsProcessTrusted() {
            logger.warning("Accessibility trust is not granted for current app binary; AX and CGEvent insertion may be blocked. attemptId=\(normalizedAttemptID)")
        }

        if let targetApp {
            let targetBundle = targetApp.bundleIdentifier ?? "nil"
            let activated = targetApp.activate(options: [.activateAllWindows])
            logger.info("Attempted to activate target app before insertion: attemptId=\(normalizedAttemptID), bundle=\(targetBundle), pid=\(targetApp.processIdentifier), activated=\(activated)")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                let nowFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
                self?.logger.info("Insertion execution begins: attemptId=\(normalizedAttemptID), frontmostApp=\(nowFrontmost)")
                let strategy = self?.performBestEffortInsertion(text: text, attemptID: normalizedAttemptID) ?? .failedKeyEventsSend
                completion?(strategy)
            }
            return
        }

        logger.info("No target app provided for insertion; using current frontmost app. attemptId=\(normalizedAttemptID)")
        let strategy = performBestEffortInsertion(text: text, attemptID: normalizedAttemptID)
        completion?(strategy)
    }

    func performBestEffortInsertion(text: String, attemptID: String) -> InsertionStrategy {
        performBestEffortInsertion(
            text: text,
            attemptID: attemptID,
            axInsert: { [weak self] input in self?.performAXInsert(text: input, attemptID: attemptID) ?? .unavailable(code: -1) },
            keyEventsAllowed: {
                CGPreflightPostEventAccess() && CGPreflightListenEventAccess()
            },
            keyEventsInsert: { [weak self] input in try self?.performKeyEvents(text: input) }
        )
    }

    func performBestEffortInsertion(
        text: String,
        attemptID: String,
        axInsert: (String) -> AXInsertOutcome,
        keyEventsAllowed: () -> Bool,
        keyEventsInsert: (String) throws -> Void
    ) -> InsertionStrategy {
        let axOutcome = axInsert(text)
        switch axOutcome {
        case .verified(let verification):
            logger.info("Text insertion strategy succeeded: AXSelectedText, attemptId=\(attemptID), verification=\(String(describing: verification))")
            return .axVerified
        case .noEffect:
            logger.info("AX verify result: AXNoEffect, attemptId=\(attemptID), fallback=KeyEvents")
        case .setFailed(let code):
            logger.info("AX verify result: AXSetFailed, attemptId=\(attemptID), code=\(code), fallback=KeyEvents")
        case .unavailable(let code):
            logger.info("AX verify result: AXUnavailable, attemptId=\(attemptID), code=\(code), fallback=KeyEvents")
        }

        guard keyEventsAllowed() else {
            logger.error("Text insertion strategy failed: KeyEventsDenied, attemptId=\(attemptID), postEvent=\(CGPreflightPostEventAccess()), listenEvent=\(CGPreflightListenEventAccess())")
            return .failedKeyEventsDenied
        }

        do {
            try keyEventsInsert(text)
            logger.info("Text insertion strategy succeeded: KeyEvents, attemptId=\(attemptID), fallbackFrom=\(String(describing: axOutcome))")
            return .keyEvents
        } catch {
            logger.error("Text insertion strategy failed: KeyEventsSendFailed, attemptId=\(attemptID), error=\(error.localizedDescription)")
            return .failedKeyEventsSend
        }
    }

    private func performAXInsert(text: String, attemptID: String) -> AXInsertOutcome {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElementRef: CFTypeRef?
        let copyResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )
        guard copyResult == .success, let focusedElementRef else {
            logger.info("AX insert unavailable: failed to get focused element, result=\(copyResult.rawValue), attemptId=\(attemptID)")
            return .unavailable(code: Int32(copyResult.rawValue))
        }

        let element = focusedElementRef as! AXUIElement
        var roleValue: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &roleValue
        )
        let role = (roleResult == .success ? (roleValue as? String) : nil) ?? "unknown"
        logger.info("AX focused element resolved: attemptId=\(attemptID), role=\(role), roleResult=\(roleResult.rawValue)")

        var isSettable = DarwinBoolean(false)
        let settableResult = AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &isSettable
        )
        logger.info("AX settable check: attemptId=\(attemptID), result=\(settableResult.rawValue), isSettable=\(isSettable.boolValue)")
        if settableResult != .success || !isSettable.boolValue {
            return .unavailable(code: Int32(settableResult.rawValue))
        }

        let beforeSnapshot = captureAXSnapshot(for: element)

        let setResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        guard setResult == .success else {
            logger.info("AX insert failed: set selected text result=\(setResult.rawValue), attemptId=\(attemptID)")
            return .setFailed(code: Int32(setResult.rawValue))
        }
        logger.info("AX set selected text succeeded: attemptId=\(attemptID)")

        let afterSnapshot = captureAXSnapshot(for: element)
        let verification = verifyAXInsertion(
            before: beforeSnapshot,
            after: afterSnapshot,
            insertedText: text
        )
        logger.info("AX verify result: attemptId=\(attemptID), verification=\(String(describing: verification)), beforeValueLength=\(beforeSnapshot.value?.count ?? -1), afterValueLength=\(afterSnapshot.value?.count ?? -1)")
        switch verification {
        case .noEffect:
            return .noEffect
        default:
            return .verified(verification)
        }
    }

    private struct AXSnapshot {
        let value: String?
        let selectedText: String?
        let selectedRange: CFRange?
    }

    private func captureAXSnapshot(for element: AXUIElement) -> AXSnapshot {
        let value = copyStringAttribute(element, attribute: kAXValueAttribute as CFString)
        let selectedText = copyStringAttribute(element, attribute: kAXSelectedTextAttribute as CFString)
        let selectedRange = copyRangeAttribute(element, attribute: kAXSelectedTextRangeAttribute as CFString)
        return AXSnapshot(value: value, selectedText: selectedText, selectedRange: selectedRange)
    }

    private func copyStringAttribute(_ element: AXUIElement, attribute: CFString) -> String? {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &valueRef)
        guard result == .success else { return nil }
        return valueRef as? String
    }

    private func copyRangeAttribute(_ element: AXUIElement, attribute: CFString) -> CFRange? {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &valueRef)
        guard result == .success, let valueRef else { return nil }
        guard CFGetTypeID(valueRef) == AXValueGetTypeID() else { return nil }
        let casted = valueRef as! AXValue
        guard AXValueGetType(casted) == .cfRange else { return nil }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(casted, .cfRange, &range) else { return nil }
        return range
    }

    private func verifyAXInsertion(before: AXSnapshot, after: AXSnapshot, insertedText: String) -> AXVerificationResult {
        if let selected = after.selectedText,
           !selected.isEmpty,
           selected.contains(insertedText) {
            return .verifiedBySelectedText
        }

        if let beforeValue = before.value,
           let afterValue = after.value,
           beforeValue != afterValue {
            if !beforeValue.contains(insertedText), afterValue.contains(insertedText) {
                return .verifiedByValueContainsInsertion
            }
            if afterValue.count > beforeValue.count {
                return .verifiedByValueGrowth
            }
        }

        if before.value == nil,
           let afterValue = after.value,
           afterValue.contains(insertedText) {
            return .verifiedByValueContainsInsertion
        }

        if let beforeRange = before.selectedRange,
           let afterRange = after.selectedRange,
           beforeRange.location != afterRange.location || beforeRange.length != afterRange.length {
            return .verifiedByValueGrowth
        }

        return .noEffect
    }

    private func sanitizeForLog(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private func logPermissionSnapshot(stage: String, attemptID: String) {
        let axTrusted = AXIsProcessTrusted()
        let postEventAllowed = CGPreflightPostEventAccess()
        let listenEventAllowed = CGPreflightListenEventAccess()
        logger.info(
            "Input permission snapshot[\(stage)]: attemptId=\(attemptID), axTrusted=\(axTrusted), postEvent=\(postEventAllowed), listenEvent=\(listenEventAllowed)"
        )
    }
}
