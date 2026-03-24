import AppKit

final class KeyRecorderView: NSView {

    var onHotkeyRecorded: ((UInt32, NSEvent.ModifierFlags) -> Void)?

    private(set) var isRecording = false
    private(set) var displayText = "Click to record"
    let placeholderText = "Click to record"

    private var displayedKeyCode: UInt32?
    private var displayedModifiers: NSEvent.ModifierFlags?

    private let textField: NSTextField

    override init(frame frameRect: NSRect) {
        textField = NSTextField(frame: .zero)
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        textField = NSTextField(frame: .zero)
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        wantsLayer = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.cornerRadius = 6

        textField.isEditable = false
        textField.isSelectable = false
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.alignment = .center
        textField.font = .systemFont(ofSize: 14)
        textField.stringValue = placeholderText
        textField.textColor = .secondaryLabelColor

        textField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textField)

        NSLayoutConstraint.activate([
            textField.centerXAnchor.constraint(equalTo: centerXAnchor),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        addGestureRecognizer(clickGesture)
    }

    @objc private func handleClick() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        isRecording = true
        displayText = "Recording..."
        textField.stringValue = displayText
        textField.textColor = .systemBlue

        becomeFirstResponder()
    }

    func stopRecording() {
        isRecording = false
        if displayedKeyCode != nil {
            textField.textColor = .labelColor
        } else {
            textField.stringValue = placeholderText
            textField.textColor = .secondaryLabelColor
        }
    }

    func recordKey(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        displayedKeyCode = keyCode
        displayedModifiers = modifiers
        isRecording = false

        displayText = formatKeyCombination(keyCode: keyCode, modifiers: modifiers)
        textField.stringValue = displayText
        textField.textColor = .labelColor

        onHotkeyRecorded?(keyCode, modifiers)
    }

    func clearKey() {
        displayedKeyCode = nil
        displayedModifiers = nil
        displayText = placeholderText
        textField.stringValue = placeholderText
        textField.textColor = .secondaryLabelColor
    }

    private func formatKeyCombination(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []

        if modifiers.contains(.control) {
            parts.append("⌃")
        }
        if modifiers.contains(.option) {
            parts.append("⌥")
        }
        if modifiers.contains(.shift) {
            parts.append("⇧")
        }
        if modifiers.contains(.command) {
            parts.append("⌘")
        }

        let keyString = keyCodeToString(keyCode)
        parts.append(keyString)

        return parts.joined()
    }

    private func keyCodeToString(_ keyCode: UInt32) -> String {
        let keyCodeMap: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: ".", 49: "Space", 50: "`"
        ]

        return keyCodeMap[keyCode] ?? "Key\(keyCode)"
    }

    override var acceptsFirstResponder: Bool {
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        let keyCode = UInt32(event.keyCode)
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        recordKey(keyCode: keyCode, modifiers: modifiers)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }
    }
}
