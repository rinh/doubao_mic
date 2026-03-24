import AppKit
import Foundation

enum AppLogLevel: Int, CaseIterable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    case fault = 4

    var title: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        case .fault: return "FAULT"
        }
    }
}

final class AppState {

    private let defaults: UserDefaults

    private enum Keys {
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let polishHotkeyKeyCode = "polishHotkeyKeyCode"
        static let polishHotkeyModifiers = "polishHotkeyModifiers"
        static let appId = "appId"
        static let accessToken = "accessToken"
        static let logLevel = "logLevel"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hotkeyKeyCode: UInt32 {
        get {
            if defaults.object(forKey: Keys.hotkeyKeyCode) == nil {
                return 0
            }
            return UInt32(defaults.integer(forKey: Keys.hotkeyKeyCode))
        }
        set {
            defaults.set(Int(newValue), forKey: Keys.hotkeyKeyCode)
        }
    }

    var hotkeyModifiers: NSEvent.ModifierFlags {
        get {
            if defaults.object(forKey: Keys.hotkeyModifiers) == nil {
                return .option
            }
            let rawValue = UInt(defaults.integer(forKey: Keys.hotkeyModifiers))
            return NSEvent.ModifierFlags(rawValue: rawValue)
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.hotkeyModifiers)
        }
    }

    var polishHotkeyKeyCode: UInt32 {
        get {
            if defaults.object(forKey: Keys.polishHotkeyKeyCode) == nil {
                return 0
            }
            return UInt32(defaults.integer(forKey: Keys.polishHotkeyKeyCode))
        }
        set {
            defaults.set(Int(newValue), forKey: Keys.polishHotkeyKeyCode)
        }
    }

    var polishHotkeyModifiers: NSEvent.ModifierFlags {
        get {
            if defaults.object(forKey: Keys.polishHotkeyModifiers) == nil {
                return [.option, .shift]
            }
            let rawValue = UInt(defaults.integer(forKey: Keys.polishHotkeyModifiers))
            return NSEvent.ModifierFlags(rawValue: rawValue)
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.polishHotkeyModifiers)
        }
    }

    var appId: String {
        get {
            return defaults.string(forKey: Keys.appId) ?? ""
        }
        set {
            defaults.set(newValue, forKey: Keys.appId)
        }
    }

    var accessToken: String {
        get {
            return defaults.string(forKey: Keys.accessToken) ?? ""
        }
        set {
            defaults.set(newValue, forKey: Keys.accessToken)
        }
    }

    var isConfigured: Bool {
        return !appId.isEmpty && !accessToken.isEmpty
    }

    var logLevel: AppLogLevel {
        get {
            guard defaults.object(forKey: Keys.logLevel) != nil else {
                return .info
            }
            let rawValue = defaults.integer(forKey: Keys.logLevel)
            return AppLogLevel(rawValue: rawValue) ?? .info
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.logLevel)
        }
    }

    func saveHotkey(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        hotkeyKeyCode = keyCode
        hotkeyModifiers = modifiers
    }

    func savePolishHotkey(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        polishHotkeyKeyCode = keyCode
        polishHotkeyModifiers = modifiers
    }

    func synchronize() {
        defaults.synchronize()
    }
}
