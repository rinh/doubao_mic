import AppKit
import ApplicationServices
import AVFoundation
import os.log

private enum RecordingFlowState: String {
    case idle
    case recording
    case awaitingFinal
    case polishing
    case finalized
    case failed
}

class AppDelegate: NSObject, NSApplicationDelegate {

    private let logger = AppLogger.make(.app)

    private var statusItem: NSStatusItem?
    private var hotkeyManager: HotkeyManager?
    private var preferencesWindowController: PreferencesWindowController?

    private var audioCapture: AudioCapture?
    private var audioLevelSource: AudioLevelSource?
    private var fixtureAudioLevelSource: FixtureAudioLevelSource?
    private var asrClient: ASRClient?
    private var floatingWindowController: FloatingWindowController?
    private var textInserter: TextInserter?
    private var credentialManager: CredentialManager?
    private var errorHandler: ASRErrorHandler?
    private var recognitionSessionController: RecognitionSessionController?
    private var seedPolishClient: SeedPolishClient?

    private var recognizedText = ""
    private var isRecording = false
    private var recordingSessionID: String?
    private var isAwaitingFinalASR = false
    private var recordingTargetApp: NSRunningApplication?
    private var recordingStartTime: Date?
    private var sessionAudioChunkCount = 0
    private var sessionPeakAudioLevel: Float = 0.0
    private let minEffectiveRecordingDuration: TimeInterval = 0.35
    private let finalResultTimeout: TimeInterval = 2.5
    private var flowState: RecordingFlowState = .idle
    private var waveformProbeWindow: NSWindow?
    private var waveformProbeLabel: NSTextField?
    private var draftWidthProbeWindow: NSWindow?
    private var draftWidthProbeLabel: NSTextField?
    private var draftSizeProbeWindow: NSWindow?
    private var draftSizeProbeLabel: NSTextField?
    private var draftSizeProbeHistory: [String] = []
    private var hasShownInputMonitoringAlert = false
    private var currentHotkeyAction: HotkeyAction = .dictation
    private var polishProbeWindow: NSWindow?
    private var polishProbeLabel: NSTextField?
    private var polishProbeHistory: [String] = []

    private let appState = AppState()
    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
    private var isWaveformUITestMode: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-waveform")
    }
    private var isDraftWindowUITestMode: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-draft-window")
    }
    private var isDraftSizingUITestMode: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-draft-sizing-cap")
    }
    private var isPolishFlowUITestMode: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-polish-flow")
    }
    private var waveformFixturePath: String? {
        ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("--fixture-path=") })?
            .replacingOccurrences(of: "--fixture-path=", with: "")
    }
    private var polishFixtureASRFinalText: String {
        ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("--fixture-asr-final=") })?
            .replacingOccurrences(of: "--fixture-asr-final=", with: "") ?? "语音原始识别文本"
    }
    private var polishFixtureSeedOutputText: String {
        ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("--fixture-seed-output=") })?
            .replacingOccurrences(of: "--fixture-seed-output=", with: "") ?? "语音整理后文本"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        CrashReporter.install()
        credentialManager = CredentialManager()

        setupStatusItem()
        if isWaveformUITestMode || isDraftWindowUITestMode || isDraftSizingUITestMode || isPolishFlowUITestMode {
            logger.info("UI test mode enabled: skipping permission checks and hotkey registration")
        } else {
            checkMicrophonePermission()
            if isRunningTests {
                logger.info("Skipping accessibility permission prompt in test environment")
            } else {
                checkAccessibilityPermission()
            }
            setupHotkey()
        }
        setupComponents()
        if isWaveformUITestMode {
            startWaveformUITestPlayback()
        }
        if isDraftWindowUITestMode {
            startDraftWindowUITestScenario()
        }
        if isDraftSizingUITestMode {
            startDraftSizingUITestScenario()
        }
        if isPolishFlowUITestMode {
            startPolishFlowUITestScenario()
        }

        logger.info("App launched successfully")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
    private func checkAccessibilityPermission() {
        logPermissionSnapshot(stage: "startup_before_prompt")

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            logger.info("Accessibility permission not granted, prompting user")
            let promptOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(promptOptions)
        } else {
            logger.info("Accessibility permission already granted")
        }

        let postEventAllowed = CGPreflightPostEventAccess()
        logger.info("PostEvent permission preflight: allowed=\(postEventAllowed)")
        if !postEventAllowed {
            let requestTriggered = CGRequestPostEventAccess()
            logger.info("PostEvent permission request triggered: result=\(requestTriggered)")
        }

        let listenEventAllowed = CGPreflightListenEventAccess()
        logger.info("ListenEvent permission preflight: allowed=\(listenEventAllowed)")
        if !listenEventAllowed {
            let requestTriggered = CGRequestListenEventAccess()
            logger.info("ListenEvent permission request triggered: result=\(requestTriggered)")
        }

        logPermissionSnapshot(stage: "startup_after_prompt")
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Voice Input")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit VoiceInput", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    private func setupHotkey() {
        hotkeyManager = HotkeyManager()
        hotkeyManager?.onHotkeyPressed = { [weak self] action in
            self?.handleHotkeyPressed(action: action)
        }
        hotkeyManager?.onHotkeyReleased = { [weak self] action in
            self?.handleHotkeyReleased(action: action)
        }
        hotkeyManager?.registerHotkeys(
            dictation: .init(
                keyCode: appState.hotkeyKeyCode,
                modifiers: appState.hotkeyModifiers
            ),
            polish: .init(
                keyCode: appState.polishHotkeyKeyCode,
                modifiers: appState.polishHotkeyModifiers
            )
        )
    }

    private func setupComponents() {
        audioCapture = AudioCapture()
        audioLevelSource = audioCapture
        if isWaveformUITestMode,
           let fixturePath = waveformFixturePath,
           !fixturePath.isEmpty {
            let fixtureURL = URL(fileURLWithPath: fixturePath)
            fixtureAudioLevelSource = FixtureAudioLevelSource(fixtureURL: fixtureURL)
            audioLevelSource = fixtureAudioLevelSource
        } else if isWaveformUITestMode {
            logger.error("Waveform UI test mode enabled but fixture path is missing")
        }
        asrClient = ASRClient()
        floatingWindowController = FloatingWindowController()
        textInserter = TextInserter()
        errorHandler = ASRErrorHandler()
        recognitionSessionController = RecognitionSessionController()
        seedPolishClient = SeedPolishClient()

        setupAudioCapture()
        setupASRClient()
        setupRecognitionSessionController()
    }

    private func setupAudioCapture() {
        audioLevelSource?.onAudioLevelUpdate = { [weak self] level in
            self?.floatingWindowController?.updateAudioLevel(level)
            if level > (self?.sessionPeakAudioLevel ?? 0) {
                self?.sessionPeakAudioLevel = level
            }
            self?.updateWaveformProbeValue()
        }

        audioCapture?.onAudioDataAvailable = { [weak self] data in
            self?.sessionAudioChunkCount += 1
            self?.asrClient?.sendAudioData(data)
        }

        fixtureAudioLevelSource?.onPlaybackFinished = { [weak self] in
            self?.updateStatusIcon(recording: false)
            self?.floatingWindowController?.updateDraftText("Waveform fixture playback finished", phase: .final)
        }
    }

    private func setupASRClient() {
        asrClient?.onRecognitionUpdate = { [weak self] update in
            let sanitizedText = self?.sanitizeForLog(update.text) ?? update.text
            self?.logger.info("ASR recognition update: textLength=\(update.text.count), hasDefinite=\(update.hasDefiniteUtterance), text=\(sanitizedText)")
            self?.recognitionSessionController?.handleRecognitionUpdate(update)
        }

        asrClient?.onStreamFinalized = { [weak self] in
            self?.handleASRStreamFinalized()
        }

        asrClient?.onError = { [weak self] error in
            self?.handleASRError(error)
        }
    }

    private func setupRecognitionSessionController() {
        recognitionSessionController?.onDraftUpdated = { [weak self] text in
            self?.floatingWindowController?.updateDraftText(text, phase: .draft)
        }

        recognitionSessionController?.onFinalReady = { [weak self] text in
            self?.commitFinalRecognizedText(text)
        }

        recognitionSessionController?.onFinalTimeout = { [weak self] in
            guard let self else { return }
            self.logger.warning("ASR final result timeout: sessionId=\(self.recordingSessionID ?? "nil")")
            self.isAwaitingFinalASR = false
            self.transitionFlowState(to: .failed)
            self.floatingWindowController?.updateDraftText("最终结果超时，未回填", phase: .final)
            self.cleanupSessionFields()
            self.asrClient?.disconnect()
            self.hideFloatingUIAfterDelay()
        }
    }

    private func handleASRError(_ error: Error) {
        if isAwaitingFinalASR {
            let nsError = error as NSError
            if nsError.domain == NSPOSIXErrorDomain && nsError.code == 57 {
                logger.info("Ignoring socket-not-connected error while awaiting final ASR result")
                return
            }
        }

        let asrError: ASRError
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                asrError = .timeout
            case .notConnectedToInternet, .networkConnectionLost:
                asrError = .networkError(error)
            case .badServerResponse:
                asrError = .serverError(urlError.errorCode)
            default:
                asrError = .unknown(error)
            }
            logger.error("ASR URLError mapped: code=\(urlError.code.rawValue), desc=\(urlError.localizedDescription)")
        } else {
            asrError = .unknown(error)
            let nsError = error as NSError
            logger.error("ASR non-URLError mapped: domain=\(nsError.domain), code=\(nsError.code), desc=\(nsError.localizedDescription)")
        }

        logger.error("ASR error: \(asrError.localizedDescription)")
        errorHandler?.handle(error: asrError)
        forceStopRecording()
    }

    private func handleHotkeyPressed(action: HotkeyAction) {
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        logger.info(
            "Hotkey pressed, action=\(action.rawValue), isRecording: \(self.isRecording), awaitingFinalASR=\(self.isAwaitingFinalASR), frontmostApp=\(frontmost)"
        )

        guard !isRecording, !isAwaitingFinalASR else {
            logger.info("Hotkey press ignored")
            return
        }
        currentHotkeyAction = action
        startRecording()
    }

    private func handleHotkeyReleased(action: HotkeyAction) {
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        logger.info(
            "Hotkey released, action=\(action.rawValue), isRecording: \(self.isRecording), awaitingFinalASR=\(self.isAwaitingFinalASR), frontmostApp=\(frontmost)"
        )

        guard isRecording else {
            logger.info("Hotkey release ignored")
            return
        }
        guard action == currentHotkeyAction else {
            logger.info("Hotkey release ignored due to action mismatch: current=\(self.currentHotkeyAction.rawValue), released=\(action.rawValue)")
            return
        }
        stopRecording()
    }

    private func startRecording() {
        logger.info("startRecording called")
        guard ensureMicrophonePermissionForRecording() else {
            logger.warning("startRecording blocked: microphone permission unavailable")
            return
        }

        guard let credentials = credentialManager?.loadCredentials(),
              !credentials.appId.isEmpty,
              !credentials.accessToken.isEmpty else {
            logger.warning("No credentials, showing alert")
            showConfigurationAlert()
            return
        }

        logger.info("Credentials loaded, starting recording")
        recordingTargetApp = NSWorkspace.shared.frontmostApplication
        recordingSessionID = UUID().uuidString
        recordingStartTime = Date()
        sessionAudioChunkCount = 0
        sessionPeakAudioLevel = 0.0
        recognizedText = ""
        isAwaitingFinalASR = false
        isRecording = true
        recognitionSessionController?.startSession()
        transitionFlowState(to: .recording)
        updateStatusIcon(recording: true)
        floatingWindowController?.beginSessionScreenLock()
        floatingWindowController?.show()
        floatingWindowController?.resetDraftWindowToDefaultSize()
        floatingWindowController?.updateDraftText("Listening...", phase: .draft)
        logger.info(
            "Recording session started: sessionId=\(self.recordingSessionID ?? "nil"), action=\(self.currentHotkeyAction.rawValue)"
        )
        if let targetApp = recordingTargetApp {
            logger.info("Recording target app captured: bundle=\(targetApp.bundleIdentifier ?? "nil"), pid=\(targetApp.processIdentifier)")
        } else {
            logger.info("Recording target app captured: nil")
        }

        asrClient?.connect(
            appId: credentials.appId,
            token: credentials.accessToken,
            resourceId: credentials.resourceId
        )

        audioLevelSource?.startRecording()
    }

    private func stopRecording() {
        logger.info("stopRecording called: sessionId=\(self.recordingSessionID ?? "nil"), recognizedLength=\(self.recognizedText.count)")
        audioLevelSource?.stopRecording()
        isRecording = false
        updateStatusIcon(recording: false)

        let duration = Date().timeIntervalSince(recordingStartTime ?? Date())
        let sentPackets = asrClient?.currentSentAudioPacketCount ?? 0
        let hasAudioData = sentPackets > 0 || sessionAudioChunkCount > 0
        let shouldSkipASR = duration < minEffectiveRecordingDuration
            || !hasAudioData

        if shouldSkipASR {
            logger.info(
                "Skip ASR finalize for short/empty session: duration=\(duration), sentPackets=\(sentPackets), chunkCount=\(self.sessionAudioChunkCount), peakLevel=\(self.sessionPeakAudioLevel)"
            )
            isAwaitingFinalASR = false
            recordingSessionID = nil
            recordingStartTime = nil
            recordingTargetApp = nil
            recognizedText = ""
            recognitionSessionController?.reset()
            transitionFlowState(to: .finalized)
            floatingWindowController?.updateDraftText("未识别到有效文本", phase: .final)
            floatingWindowController?.endSessionScreenLock()
            hideFloatingUIAfterDelay()
            asrClient?.disconnect()
            return
        }

        isAwaitingFinalASR = true
        transitionFlowState(to: .awaitingFinal)
        floatingWindowController?.updateDraftText(
            recognitionSessionController?.latestDraftText.isEmpty == false
                ? recognitionSessionController?.latestDraftText ?? "Processing final..."
                : "Processing final...",
            phase: .draft
        )
        recognitionSessionController?.awaitFinal(timeout: finalResultTimeout)
        asrClient?.finishStream()
    }

    private func forceStopRecording() {
        logger.info("forceStopRecording called")
        audioLevelSource?.stopRecording()
        asrClient?.disconnect()
        floatingWindowController?.hide()
        isRecording = false
        isAwaitingFinalASR = false
        recognitionSessionController?.fail()
        transitionFlowState(to: .failed)
        updateStatusIcon(recording: false)
        cleanupSessionFields()
        floatingWindowController?.updateDraftText("识别失败，请重试", phase: .final)
        hideFloatingUIAfterDelay()
    }

    private func startWaveformUITestPlayback() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            guard self.fixtureAudioLevelSource != nil else {
                self.floatingWindowController?.show()
                self.floatingWindowController?.updateDraftText("Waveform fixture path missing", phase: .final)
                return
            }
            self.ensureWaveformProbeWindow()
            NSApp.activate(ignoringOtherApps: true)
            self.updateStatusIcon(recording: true)
            self.floatingWindowController?.beginSessionScreenLock()
            self.floatingWindowController?.show()
            self.floatingWindowController?.updateDraftText("Waveform fixture playback", phase: .draft)
            self.audioLevelSource?.startRecording()
        }
    }

    private func ensureWaveformProbeWindow() {
        guard isWaveformUITestMode else { return }
        guard waveformProbeWindow == nil else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 360, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Waveform Probe"
        window.level = .floating
        let content = NSView(frame: window.contentView?.bounds ?? .zero)
        let label = NSTextField(labelWithString: "")
        label.frame = NSRect(x: 20, y: 50, width: 320, height: 22)
        label.alignment = .left
        label.setAccessibilityIdentifier("waveform_probe_value")
        content.addSubview(label)
        window.contentView = content
        window.makeKeyAndOrderFront(nil)

        waveformProbeWindow = window
        waveformProbeLabel = label
        updateWaveformProbeValue()
    }

    private func updateWaveformProbeValue() {
        guard isWaveformUITestMode else { return }
        guard let heights = floatingWindowController?.micView?.waveBarHeights, !heights.isEmpty else { return }
        let text = heights.map { String(format: "%.2f", Double($0)) }.joined(separator: ",")
        waveformProbeLabel?.stringValue = text
        waveformProbeLabel?.setAccessibilityValue(text)
    }

    private func startDraftWindowUITestScenario() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            self.ensureDraftWidthProbeWindow()
            self.floatingWindowController?.beginSessionScreenLock()
            self.floatingWindowController?.show()
            self.floatingWindowController?.updateDraftText("Session-1", phase: .draft)

            self.floatingWindowController?.setDraftWindowWidthForTesting(560)
            self.updateDraftWidthProbeValue(stage: "expanded")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self else { return }
                self.floatingWindowController?.resetDraftWindowToDefaultSize()
                self.floatingWindowController?.updateDraftText("Session-2", phase: .draft)
                self.updateDraftWidthProbeValue(stage: "reset")
            }
        }
    }

    private func ensureDraftWidthProbeWindow() {
        guard isDraftWindowUITestMode else { return }
        guard draftWidthProbeWindow == nil else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 220, y: 260, width: 380, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Draft Width Probe"
        window.level = .floating
        let content = NSView(frame: window.contentView?.bounds ?? .zero)
        let label = NSTextField(labelWithString: "")
        label.frame = NSRect(x: 20, y: 50, width: 340, height: 22)
        label.alignment = .left
        label.setAccessibilityIdentifier("draft_window_width_probe")
        content.addSubview(label)
        window.contentView = content
        window.makeKeyAndOrderFront(nil)

        draftWidthProbeWindow = window
        draftWidthProbeLabel = label
        updateDraftWidthProbeValue(stage: "init")
    }

    private func updateDraftWidthProbeValue(stage: String) {
        guard isDraftWindowUITestMode else { return }
        let width = floatingWindowController?.currentDraftWindowWidthForTesting() ?? 0
        let text = "\(stage):\(String(format: "%.1f", Double(width)))"
        draftWidthProbeLabel?.stringValue = text
        draftWidthProbeLabel?.setAccessibilityValue(text)
    }

    private func startDraftSizingUITestScenario() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            self.ensureDraftSizeProbeWindow()
            self.floatingWindowController?.beginSessionScreenLock()
            self.floatingWindowController?.show()

            let shortText = "短文本"
            self.floatingWindowController?.updateDraftText(shortText, phase: .draft)
            self.updateDraftSizeProbeValue(stage: "case1")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self else { return }
                let wideText = String(repeating: "超长无空格文本ABCDEFGHIJKL1234567890", count: 140)
                self.floatingWindowController?.updateDraftText(wideText, phase: .draft)
                self.updateDraftSizeProbeValue(stage: "case2")

                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    guard let self else { return }
                    let tallerText = wideText + String(repeating: "继续追加超长无空格文本ZYXWVUT9876543210", count: 60)
                    self.floatingWindowController?.updateDraftText(tallerText, phase: .draft)
                    self.updateDraftSizeProbeValue(stage: "case3")
                }
            }
        }
    }

    private func ensureDraftSizeProbeWindow() {
        guard isDraftSizingUITestMode else { return }
        guard draftSizeProbeWindow == nil else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 240, y: 220, width: 520, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Draft Size Probe"
        window.level = .floating
        let content = NSView(frame: window.contentView?.bounds ?? .zero)
        let label = NSTextField(labelWithString: "")
        label.frame = NSRect(x: 20, y: 50, width: 480, height: 22)
        label.alignment = .left
        label.setAccessibilityIdentifier("draft_window_size_probe")
        content.addSubview(label)
        window.contentView = content
        window.makeKeyAndOrderFront(nil)

        draftSizeProbeWindow = window
        draftSizeProbeLabel = label
        draftSizeProbeHistory = []
    }

    private func updateDraftSizeProbeValue(stage: String) {
        guard isDraftSizingUITestMode else { return }
        let contentWidth = floatingWindowController?.currentDraftWindowContentWidthForTesting() ?? 0
        let frameWidth = floatingWindowController?.currentDraftWindowFrameWidthForTesting() ?? 0
        let contentHeight = floatingWindowController?.currentDraftWindowContentHeightForTesting() ?? 0
        let frameHeight = floatingWindowController?.currentDraftWindowFrameHeightForTesting() ?? 0
        let maxFW = floatingWindowController?.currentDraftWindowCapWidthForTesting() ?? 0
        let screenWidth = floatingWindowController?.currentDraftScreenVisibleWidthForTesting() ?? 0
        let screenHeight = floatingWindowController?.currentDraftScreenVisibleHeightForTesting() ?? 0
        let x = floatingWindowController?.currentDraftWindowFrameMinXForTesting() ?? 0
        let y = floatingWindowController?.currentDraftWindowFrameMinYForTesting() ?? 0
        let centerX = floatingWindowController?.currentDraftWindowCenterXForTesting() ?? 0
        let screenMidX = floatingWindowController?.currentDraftScreenMidXForTesting() ?? 0
        let screenSource = floatingWindowController?.currentScreenSourceForTesting() ?? "activeSpace"
        let screenDebug = floatingWindowController?.currentScreenDebugForTesting() ?? "n/a"
        let value = "\(stage):cw=\(String(format: "%.1f", Double(contentWidth)));fw=\(String(format: "%.1f", Double(frameWidth)));ch=\(String(format: "%.1f", Double(contentHeight)));fh=\(String(format: "%.1f", Double(frameHeight)));maxfw=\(String(format: "%.1f", Double(maxFW)));sw=\(String(format: "%.1f", Double(screenWidth)));sh=\(String(format: "%.1f", Double(screenHeight)));x=\(String(format: "%.1f", Double(x)));y=\(String(format: "%.1f", Double(y)));screenMidX=\(String(format: "%.1f", Double(screenMidX)));cx=\(String(format: "%.1f", Double(centerX)));ss=\(screenSource);screenDebug=\(screenDebug)"
        draftSizeProbeHistory.append(value)
        let merged = draftSizeProbeHistory.joined(separator: "|")
        draftSizeProbeLabel?.stringValue = merged
        draftSizeProbeLabel?.setAccessibilityValue(merged)
    }

    private func startPolishFlowUITestScenario() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            self.ensurePolishProbeWindow()
            self.floatingWindowController?.beginSessionScreenLock()
            self.transitionFlowState(to: .recording)
            self.updatePolishProbeValue("state:draft")
            self.floatingWindowController?.show()
            self.floatingWindowController?.updateDraftText(self.polishFixtureASRFinalText, phase: .draft)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self else { return }
                self.transitionFlowState(to: .finalized)
                self.updatePolishProbeValue("state:finish")
                self.floatingWindowController?.updateDraftText(self.polishFixtureASRFinalText, phase: .final)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self else { return }
                self.transitionFlowState(to: .polishing)
                self.updatePolishProbeValue("state:polish")
                self.floatingWindowController?.updateDraftText("整理中...", phase: .draft)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self else { return }
                self.floatingWindowController?.updateDraftText(self.polishFixtureSeedOutputText, phase: .final)
                self.updatePolishProbeValue("inserted:\(self.polishFixtureSeedOutputText)")
                self.transitionFlowState(to: .finalized)
                self.hideFloatingUIAfterDelay()
            }
        }
    }

    private func ensurePolishProbeWindow() {
        guard isPolishFlowUITestMode else { return }
        guard polishProbeWindow == nil else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 240, y: 320, width: 420, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Polish Flow Probe"
        window.level = .floating
        let content = NSView(frame: window.contentView?.bounds ?? .zero)
        let label = NSTextField(labelWithString: "")
        label.frame = NSRect(x: 20, y: 50, width: 380, height: 22)
        label.alignment = .left
        label.setAccessibilityIdentifier("polish_flow_probe")
        content.addSubview(label)
        window.contentView = content
        window.makeKeyAndOrderFront(nil)

        polishProbeWindow = window
        polishProbeLabel = label
        polishProbeHistory = []
    }

    private func updatePolishProbeValue(_ text: String) {
        guard isPolishFlowUITestMode else { return }
        polishProbeHistory.append(text)
        let merged = polishProbeHistory.joined(separator: "|")
        polishProbeLabel?.stringValue = merged
        polishProbeLabel?.setAccessibilityValue(merged)
    }

    private func handleASRStreamFinalized() {
        logger.info("ASR stream finalized event received: sessionId=\(self.recordingSessionID ?? "nil"), awaitingFinal=\(self.isAwaitingFinalASR)")
        if !isAwaitingFinalASR {
            hideFloatingUIAfterDelay()
        }
    }

    private func commitFinalRecognizedText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            logger.info("Skip final insertion: final text empty")
            isAwaitingFinalASR = false
            transitionFlowState(to: .finalized)
            floatingWindowController?.updateDraftText("未识别到有效文本", phase: .final)
            cleanupSessionFields()
            hideFloatingUIAfterDelay()
            return
        }

        recognizedText = trimmed
        let targetApp = recordingTargetApp
        let sanitizedText = sanitizeForLog(trimmed)
        logger.info("Final ASR text ready for insertion: length=\(trimmed.count), text=\(sanitizedText)")
        isAwaitingFinalASR = false
        transitionFlowState(to: .finalized)
        updatePolishProbeValue("state:finish")
        floatingWindowController?.updateDraftText(trimmed, phase: .final)

        if currentHotkeyAction == .polish {
            transitionFlowState(to: .polishing)
            updatePolishProbeValue("state:polish")
            floatingWindowController?.updateDraftText("整理中...", phase: .draft)
            guard let credentials = credentialManager?.loadCredentials(),
                  !credentials.seedApiKey.isEmpty else {
                logger.error("Polish hotkey requires seedApiKey, but config missing")
                floatingWindowController?.updateDraftText("回填失败：请在 ak.yaml 配置 seedApiKey", phase: .final)
                showSeedConfigurationAlert()
                transitionFlowState(to: .failed)
                cleanupSessionFields()
                hideFloatingUIAfterDelay()
                return
            }
            let sourceText = trimmed
            seedPolishClient?.polishText(sourceText, apiKey: credentials.seedApiKey) { [weak self, targetApp] result in
                guard let self else { return }
                DispatchQueue.main.async {
                    switch result {
                    case .success(let polishedText):
                        let finalText = polishedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if finalText.isEmpty {
                            self.logger.warning("Seed polish returned empty text, fallback to ASR final text")
                            self.performTextInsertion(sourceText, targetApp: targetApp) { [weak self] in
                                guard let self else { return }
                                self.transitionFlowState(to: .finalized)
                                self.cleanupSessionFields()
                                self.hideFloatingUIAfterDelay()
                            }
                        } else {
                            self.logger.info("Seed polish success: sourceLength=\(sourceText.count), polishedLength=\(finalText.count)")
                            self.floatingWindowController?.updateDraftText(finalText, phase: .final)
                            self.performTextInsertion(finalText, targetApp: targetApp) { [weak self] in
                                guard let self else { return }
                                self.transitionFlowState(to: .finalized)
                                self.cleanupSessionFields()
                                self.hideFloatingUIAfterDelay()
                            }
                        }
                    case .failure(let error):
                        self.logger.error("Seed polish failed, fallback to ASR final text: \(error.localizedDescription)")
                        self.floatingWindowController?.updateDraftText("整理失败，已回退原识别文本", phase: .final)
                        self.performTextInsertion(sourceText, targetApp: targetApp) { [weak self] in
                            guard let self else { return }
                            self.transitionFlowState(to: .finalized)
                            self.cleanupSessionFields()
                            self.hideFloatingUIAfterDelay()
                        }
                    }
                }
            }
            return
        }

        performTextInsertion(trimmed, targetApp: targetApp) { [weak self] in
            guard let self else { return }
            self.cleanupSessionFields()
            self.hideFloatingUIAfterDelay()
        }
    }

    private func performTextInsertion(
        _ text: String,
        targetApp: NSRunningApplication?,
        completion: (() -> Void)? = nil
    ) {
        let insertionAttemptID = UUID().uuidString
        logger.info(
            "Text insertion attempt begin: attemptId=\(insertionAttemptID), sessionId=\(self.recordingSessionID ?? "nil"), action=\(self.currentHotkeyAction.rawValue)"
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, targetApp] in
            self?.textInserter?.insertRecognizedText(
                text,
                targetApp: targetApp,
                attemptID: insertionAttemptID
            ) { strategy in
                guard let self else { return }
                self.logger.info("Text insertion attempt completed: attemptId=\(insertionAttemptID), strategy=\(String(describing: strategy))")
                self.updatePolishProbeValue("inserted:\(text)")
                switch strategy {
                case .failedKeyEventsDenied:
                    self.floatingWindowController?.updateDraftText("回填失败：请输入监控权限未授权", phase: .final)
                    self.showInputMonitoringPermissionAlertIfNeeded()
                case .failedKeyEventsSend:
                    self.floatingWindowController?.updateDraftText("回填失败：键盘事件发送失败", phase: .final)
                case .failedAXSet:
                    self.floatingWindowController?.updateDraftText("回填失败：AX写入失败", phase: .final)
                case .axNoEffect:
                    self.floatingWindowController?.updateDraftText("回填失败：目标控件拒绝插入", phase: .final)
                case .axVerified, .keyEvents:
                    break
                }
                completion?()
            }
        }
    }

    private func cleanupSessionFields() {
        recordingSessionID = nil
        recordingStartTime = nil
        recordingTargetApp = nil
        currentHotkeyAction = .dictation
        floatingWindowController?.endSessionScreenLock()
    }

    private func updateStatusIcon(recording: Bool) {
        if let button = statusItem?.button {
            if recording {
                button.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")
                button.image?.isTemplate = true
                button.contentTintColor = .systemRed
                logger.info("Status icon switched to recording state")
            } else {
                button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Voice Input")
                button.image?.isTemplate = true
                button.contentTintColor = nil
                logger.info("Status icon switched to idle state")
            }
        }
    }

    private func showConfigurationAlert() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.showConfigurationAlert()
            }
            return
        }

        let alert = NSAlert()
        alert.messageText = "Configuration Required"
        alert.informativeText = "Please configure ~/.voiceinput/ak.yaml with appId and accessToken."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Preferences")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openPreferences()
        }
    }

    private func showSeedConfigurationAlert() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.showSeedConfigurationAlert()
            }
            return
        }

        let alert = NSAlert()
        alert.messageText = "Seed API Key Required"
        alert.informativeText = "语音整理热键需要在 ~/.voiceinput/ak.yaml 中配置 seedApiKey。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Preferences")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openPreferences()
        }
    }

    func reloadHotkey() {
        hotkeyManager?.unregisterHotkey()
        hotkeyManager?.registerHotkeys(
            dictation: .init(
                keyCode: appState.hotkeyKeyCode,
                modifiers: appState.hotkeyModifiers
            ),
            polish: .init(
                keyCode: appState.polishHotkeyKeyCode,
                modifiers: appState.polishHotkeyModifiers
            )
        )
    }

    @objc private func openPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController()
        }
        preferencesWindowController?.onPreferencesSaved = { [weak self] in
            self?.reloadHotkey()
        }
        preferencesWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func sanitizeForLog(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private func logPermissionSnapshot(stage: String) {
        let axTrusted = AXIsProcessTrusted()
        let postEventAllowed = CGPreflightPostEventAccess()
        let listenEventAllowed = CGPreflightListenEventAccess()
        let bundleID = Bundle.main.bundleIdentifier ?? "nil"
        let executablePath = Bundle.main.executableURL?.path ?? "nil"
        logger.info(
            "Permission snapshot[\(stage)]: axTrusted=\(axTrusted), postEvent=\(postEventAllowed), listenEvent=\(listenEventAllowed), bundleId=\(bundleID), executable=\(executablePath)"
        )
    }

    private func checkMicrophonePermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            logger.info("Microphone permission already granted")
        case .notDetermined:
            logger.info("Microphone permission not determined at startup, deferring request until record start")
        case .denied:
            logger.warning("Microphone permission denied")
        case .restricted:
            logger.warning("Microphone permission restricted")
        @unknown default:
            logger.warning("Microphone permission unknown status")
        }
    }

    private func ensureMicrophonePermissionForRecording() -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            logger.info("Microphone permission not determined at record start, requesting access")
            requestMicrophonePermission()
            showMicrophonePermissionAlert()
            return false
        case .denied, .restricted:
            showMicrophonePermissionAlert()
            return false
        @unknown default:
            showMicrophonePermissionAlert()
            return false
        }
    }

    private func showMicrophonePermissionAlert() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.showMicrophonePermissionAlert()
            }
            return
        }

        let alert = NSAlert()
        alert.messageText = "Microphone Permission Required"
        alert.informativeText = "Please allow VoiceInput to use the microphone in System Settings > Privacy & Security > Microphone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    private func requestMicrophonePermission() {
        NSApp.activate(ignoringOtherApps: true)
        let before = AVCaptureDevice.authorizationStatus(for: .audio)
        logger.info("Microphone permission request begin: statusBefore=\(String(describing: before))")
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            let after = AVCaptureDevice.authorizationStatus(for: .audio)
            self?.logger.info("Microphone permission request result: granted=\(granted), statusAfter=\(String(describing: after))")
        }
    }

    private func showInputMonitoringPermissionAlertIfNeeded() {
        guard !hasShownInputMonitoringAlert else { return }
        hasShownInputMonitoringAlert = true
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.showInputMonitoringPermissionAlertIfNeeded()
            }
            return
        }

        let alert = NSAlert()
        alert.messageText = "Input Monitoring Permission Required"
        alert.informativeText = "Please allow VoiceInput in System Settings > Privacy & Security > Input Monitoring."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    private func transitionFlowState(to newState: RecordingFlowState) {
        guard self.flowState != newState else { return }
        logger.info("Flow state transition: \(self.flowState.rawValue) -> \(newState.rawValue)")
        self.flowState = newState
    }

    private func hideFloatingUIAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }

            let shouldKeepVisible = Self.shouldKeepFloatingUIVisible(
                isRecording: self.isRecording,
                isAwaitingFinalASR: self.isAwaitingFinalASR,
                flowState: self.flowState.rawValue
            )
            if shouldKeepVisible {
                self.logger.info(
                    "Skip hiding floating UI: flowState=\(self.flowState.rawValue), isRecording=\(self.isRecording), awaitingFinalASR=\(self.isAwaitingFinalASR)"
                )
                self.hideFloatingUIAfterDelay()
                return
            }

            self.floatingWindowController?.hide()
            if self.isPolishFlowUITestMode {
                self.updatePolishProbeValue("hidden:true")
            }
            self.transitionFlowState(to: .idle)
        }
    }

    static func shouldKeepFloatingUIVisible(
        isRecording: Bool,
        isAwaitingFinalASR: Bool,
        flowState: String
    ) -> Bool {
        isRecording
            || isAwaitingFinalASR
            || flowState == RecordingFlowState.recording.rawValue
            || flowState == RecordingFlowState.awaitingFinal.rawValue
            || flowState == RecordingFlowState.polishing.rawValue
    }
}
