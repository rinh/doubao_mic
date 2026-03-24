import AppKit

final class PreferencesWindowController: NSWindowController {

    private(set) var hotkeyRecorder: KeyRecorderView?
    private(set) var polishHotkeyRecorder: KeyRecorderView?
    private var logLevelPopup: NSPopUpButton?

    var onPreferencesSaved: (() -> Void)?
    private let appState = AppState()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "VoiceInput Preferences"
        window.center()

        self.init(window: window)
        setupUI()
        loadPreferences()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 20
        stackView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 30),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 30),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -30)
        ])

        // Hotkey Section
        let hotkeyLabel = NSTextField(labelWithString: "Global Hotkey:")
        hotkeyLabel.font = .boldSystemFont(ofSize: 13)

        hotkeyRecorder = KeyRecorderView(frame: NSRect(x: 0, y: 0, width: 150, height: 32))
        hotkeyRecorder?.translatesAutoresizingMaskIntoConstraints = false
        hotkeyRecorder?.onHotkeyRecorded = { [weak self] keyCode, modifiers in
            self?.appState.saveHotkey(keyCode: keyCode, modifiers: modifiers)
        }

        let hotkeyRow = NSStackView(views: [hotkeyLabel, hotkeyRecorder!])
        hotkeyRow.orientation = .horizontal
        hotkeyRow.spacing = 12
        hotkeyRow.alignment = .centerY

        NSLayoutConstraint.activate([
            hotkeyRecorder!.widthAnchor.constraint(equalToConstant: 150),
            hotkeyRecorder!.heightAnchor.constraint(equalToConstant: 32)
        ])

        stackView.addArrangedSubview(hotkeyRow)

        // Polish Hotkey Section
        let polishHotkeyLabel = NSTextField(labelWithString: "语音整理 Hotkey:")
        polishHotkeyLabel.font = .boldSystemFont(ofSize: 13)

        polishHotkeyRecorder = KeyRecorderView(frame: NSRect(x: 0, y: 0, width: 150, height: 32))
        polishHotkeyRecorder?.translatesAutoresizingMaskIntoConstraints = false
        polishHotkeyRecorder?.onHotkeyRecorded = { [weak self] keyCode, modifiers in
            self?.appState.savePolishHotkey(keyCode: keyCode, modifiers: modifiers)
        }

        let polishHotkeyRow = NSStackView(views: [polishHotkeyLabel, polishHotkeyRecorder!])
        polishHotkeyRow.orientation = .horizontal
        polishHotkeyRow.spacing = 12
        polishHotkeyRow.alignment = .centerY

        NSLayoutConstraint.activate([
            polishHotkeyRecorder!.widthAnchor.constraint(equalToConstant: 150),
            polishHotkeyRecorder!.heightAnchor.constraint(equalToConstant: 32)
        ])

        stackView.addArrangedSubview(polishHotkeyRow)

        // Log Level Section
        let logLevelLabel = NSTextField(labelWithString: "Log Level:")
        logLevelLabel.font = .boldSystemFont(ofSize: 13)

        let logLevelPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 150, height: 28))
        logLevelPopup.translatesAutoresizingMaskIntoConstraints = false
        AppLogLevel.allCases.forEach { level in
            logLevelPopup.addItem(withTitle: level.title)
            logLevelPopup.lastItem?.tag = level.rawValue
        }
        self.logLevelPopup = logLevelPopup

        let logLevelRow = NSStackView(views: [logLevelLabel, logLevelPopup])
        logLevelRow.orientation = .horizontal
        logLevelRow.spacing = 12
        logLevelRow.alignment = .centerY
        NSLayoutConstraint.activate([
            logLevelPopup.widthAnchor.constraint(equalToConstant: 150),
            logLevelPopup.heightAnchor.constraint(equalToConstant: 28)
        ])
        stackView.addArrangedSubview(logLevelRow)

        // Info label
        let infoLabel = NSTextField(labelWithString: "API credentials are configured in ~/.voiceinput/ak.yaml (appId/accessToken/seedApiKey)")
        infoLabel.font = .systemFont(ofSize: 11)
        infoLabel.textColor = .secondaryLabelColor
        stackView.addArrangedSubview(infoLabel)

        // Save Button
        let saveButton = NSButton(title: "Save", target: self, action: #selector(savePreferences))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        let buttonContainer = NSStackView()
        buttonContainer.orientation = .horizontal
        buttonContainer.addArrangedSubview(NSView())
        buttonContainer.addArrangedSubview(saveButton)
        buttonContainer.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(buttonContainer)

        NSLayoutConstraint.activate([
            buttonContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 30),
            buttonContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -30),
            buttonContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            buttonContainer.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    @objc private func savePreferences() {
        if !validateHotkeyConflict(
            dictationKeyCode: appState.hotkeyKeyCode,
            dictationModifiers: appState.hotkeyModifiers,
            polishKeyCode: appState.polishHotkeyKeyCode,
            polishModifiers: appState.polishHotkeyModifiers
        ) {
            showHotkeyConflictAlert()
            return
        }
        if let selectedTag = logLevelPopup?.selectedTag(),
           let level = AppLogLevel(rawValue: selectedTag) {
            appState.logLevel = level
        }
        appState.synchronize()
        onPreferencesSaved?()
        window?.close()
    }

    private func loadPreferences() {
        let keyCode = appState.hotkeyKeyCode
        let modifiers = appState.hotkeyModifiers
        let polishKeyCode = appState.polishHotkeyKeyCode
        let polishModifiers = appState.polishHotkeyModifiers

        hotkeyRecorder?.recordKey(keyCode: keyCode, modifiers: modifiers)
        polishHotkeyRecorder?.recordKey(keyCode: polishKeyCode, modifiers: polishModifiers)
        logLevelPopup?.selectItem(withTag: appState.logLevel.rawValue)
    }

    func validateHotkeyConflict(
        dictationKeyCode: UInt32,
        dictationModifiers: NSEvent.ModifierFlags,
        polishKeyCode: UInt32,
        polishModifiers: NSEvent.ModifierFlags
    ) -> Bool {
        dictationKeyCode != polishKeyCode || dictationModifiers != polishModifiers
    }

    private func showHotkeyConflictAlert() {
        let alert = NSAlert()
        alert.messageText = "Hotkey Conflict"
        alert.informativeText = "Global Hotkey 与 语音整理 Hotkey 不能使用同一组合，请调整后再保存。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
