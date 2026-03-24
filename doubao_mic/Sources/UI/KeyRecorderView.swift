import AppKit

final class KeyRecorderView: NSView {

    var onHotkeyRecorded: ((UInt32, NSEvent.ModifierFlags) -> Void)?

    private(set) var isRecording = false
    private(set) var displayText: String = ""

    var placeholderText: String { "Click to record" }

    private var localMonitor: Any?
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    convenience init() {
        self.init(frame: NSRect(x: 0, y: 0, width: 150, height: 32))
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        updateDisplay(placeholderText)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existing = trackingArea {
            removeTrackingArea(existing)
        }

        let newTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        trackingArea = newTrackingArea
        addTrackingArea(newTrackingArea)
    }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.borderColor = NSColor.controlAccentColor.cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    func startRecording() {
        isRecording = true
        updateDisplay("Recording...")

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyEvent(event)
            return nil
        }
    }

    func stopRecording() {
        isRecording = false
        if displayText == "Recording..." {
            updateDisplay(placeholderText)
        }

        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    func recordKey(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        stopRecording()
        let text = formatKeyCombo(keyCode: keyCode, modifiers: modifiers)
        updateDisplay(text)
        onHotkeyRecorded?(keyCode, modifiers)
    }

    func clearKey() {
        stopRecording()
        updateDisplay(placeholderText)
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let keyCode = UInt32(event.keyCode)
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])

        if keyCode == 53 { // Escape
            stopRecording()
            return
        }

        if !modifiers.isEmpty {
            recordKey(keyCode: keyCode, modifiers: modifiers)
        }
    }

    private func updateDisplay(_ text: String) {
        displayText = text

        subviews.forEach { $0.removeFromSuperview() }

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13)
        label.textColor = isRecording ? .secondaryLabelColor : .labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    private func formatKeyCombo(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []

        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }

        let keyChar = keyCodeToString(keyCode)
        parts.append(keyChar)

        return parts.joined()
    }

    private func keyCodeToString(_ keyCode: UInt32) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "↩"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "⇥"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "Esc"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return "Key\(keyCode)"
        }
    }
}
