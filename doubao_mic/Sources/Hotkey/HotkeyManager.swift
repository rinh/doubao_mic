import AppKit
import Carbon
import os.log

enum HotkeyAction: String {
    case dictation
    case polish
}

final class HotkeyManager {

    private let logger = AppLogger.make(.hotkey)

    struct HotkeyConfig: Equatable {
        let keyCode: UInt32
        let modifiers: NSEvent.ModifierFlags

        static let defaultOptionA = HotkeyConfig(keyCode: 0, modifiers: .option)
        static let defaultPolishOptionShiftA = HotkeyConfig(keyCode: 0, modifiers: [.option, .shift])
    }

    var onHotkeyPressed: ((HotkeyAction) -> Void)?
    var onHotkeyReleased: ((HotkeyAction) -> Void)?

    private var currentDictationConfig: HotkeyConfig?
    private var currentPolishConfig: HotkeyConfig?
    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var hotKeyActions: [UInt32: HotkeyAction] = [:]

    var defaultHotkey: HotkeyConfig {
        return .defaultOptionA
    }

    var defaultPolishHotkey: HotkeyConfig {
        return .defaultPolishOptionShiftA
    }

    var currentHotkey: HotkeyConfig? {
        return currentDictationConfig
    }

    var currentPolishHotkey: HotkeyConfig? {
        return currentPolishConfig
    }

    init() {}

    func registerHotkeys(dictation: HotkeyConfig, polish: HotkeyConfig) {
        unregisterHotkey()
        currentDictationConfig = dictation
        currentPolishConfig = polish

        registerSingleHotkey(id: 1, action: .dictation, config: dictation)
        registerSingleHotkey(id: 2, action: .polish, config: polish)
        installEventHandlerIfNeeded()
    }

    func checkAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func unregisterHotkey() {
        for hotKeyRef in hotKeyRefs.values {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll()
        hotKeyActions.removeAll()
        currentDictationConfig = nil
        currentPolishConfig = nil
    }

    func updateHotkeys(dictation: HotkeyConfig, polish: HotkeyConfig) {
        registerHotkeys(dictation: dictation, polish: polish)
    }

    private func carbonModifierFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbonFlags: UInt32 = 0
        if flags.contains(.option) {
            carbonFlags |= UInt32(optionKey)
        }
        if flags.contains(.command) {
            carbonFlags |= UInt32(cmdKey)
        }
        if flags.contains(.control) {
            carbonFlags |= UInt32(controlKey)
        }
        if flags.contains(.shift) {
            carbonFlags |= UInt32(shiftKey)
        }
        return carbonFlags
    }

    private func registerSingleHotkey(id: UInt32, action: HotkeyAction, config: HotkeyConfig) {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x564F494E) // "VOIN"
        hotKeyID.id = id

        let carbonModifiers = carbonModifierFlags(from: config.modifiers)
        logger.info(
            "Registering hotkey - action=\(action.rawValue), id=\(id), keyCode=\(config.keyCode), modifiers=\(config.modifiers.rawValue), carbonModifiers=\(carbonModifiers)"
        )

        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            config.keyCode,
            carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        logger.info("RegisterEventHotKey status: \(status), action=\(action.rawValue), id=\(id)")

        guard status == noErr, let hotKeyRef else {
            logger.error("Failed to register hotkey, status: \(status), action=\(action.rawValue), id=\(id)")
            return
        }
        hotKeyRefs[id] = hotKeyRef
        hotKeyActions[id] = action
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        logger.info("Installing event handler")
        var eventSpecs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let handler: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }

            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            let eventKind = GetEventKind(event)
            var hotKeyID = EventHotKeyID()
            let paramStatus = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if paramStatus != noErr {
                manager.logger.error("Failed to read hotkey id from event: status=\(paramStatus)")
                return OSStatus(eventNotHandledErr)
            }
            guard let action = manager.hotKeyActions[hotKeyID.id] else {
                manager.logger.warning("Received event for unknown hotkey id=\(hotKeyID.id)")
                return noErr
            }
            manager.logger.info("Received Carbon hotkey event: kind=\(eventKind), id=\(hotKeyID.id), action=\(action.rawValue)")

            DispatchQueue.main.async {
                if eventKind == UInt32(kEventHotKeyPressed) {
                    manager.logger.info("Dispatching hotkey press callback on main thread, action=\(action.rawValue)")
                    manager.onHotkeyPressed?(action)
                } else if eventKind == UInt32(kEventHotKeyReleased) {
                    manager.logger.info("Dispatching hotkey release callback on main thread, action=\(action.rawValue)")
                    manager.onHotkeyReleased?(action)
                }
            }

            return noErr
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetEventDispatcherTarget(),
            handler,
            eventSpecs.count,
            &eventSpecs,
            selfPtr,
            &eventHandler
        )
        logger.info("Event handler installed")
    }

    deinit {
        unregisterHotkey()
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
