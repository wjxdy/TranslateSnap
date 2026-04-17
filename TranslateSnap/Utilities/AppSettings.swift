import Foundation
import SwiftUI
import AppKit
import Carbon.HIToolbox

enum PopupPositionMode: String, CaseIterable {
    case fixed = "fixed"
    case followCursor = "followCursor"

    var displayName: String {
        switch self {
        case .fixed: return "固定位置"
        case .followCursor: return "跟随指针"
        }
    }
}

enum TranslationStyle: String, CaseIterable {
    case literal = "literal"
    case natural = "natural"
    case professional = "professional"

    var displayName: String {
        switch self {
        case .literal: return "直译"
        case .natural: return "意译"
        case .professional: return "专业解释"
        }
    }
}

enum AIProvider: String, CaseIterable {
    case claude = "claude"
    case openai = "openai"
    case kimi = "kimi"
    case custom = "custom"

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .openai: return "OpenAI"
        case .kimi: return "Kimi (Moonshot)"
        case .custom: return "自定义"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .claude: return "https://api.anthropic.com"
        case .openai: return "https://api.openai.com"
        case .kimi: return "https://api.moonshot.cn"
        case .custom: return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .claude: return "claude-haiku-4-5-20251001"
        case .openai: return "gpt-4o-mini"
        case .kimi: return "moonshot-v1-8k"
        case .custom: return "gpt-4o-mini"
        }
    }
}

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("targetLanguage") var targetLanguage: String = "简体中文"
    @AppStorage("translationStyle") var translationStyleRaw: String = TranslationStyle.professional.rawValue
    @AppStorage("showOriginal") var showOriginal: Bool = true
    // 截图翻译快捷键: 默认 ⌘⇧1 (keyCode 18)
    @AppStorage("screenshotKeyCode") var screenshotKeyCode: Int = 18
    @AppStorage("screenshotModifiers") var screenshotModifiers: Int = 0  // CGEventFlags raw: Command+Shift
    // 划词翻译快捷键: 默认 ⌘⇧Y (keyCode 16)
    @AppStorage("selectionKeyCode") var selectionKeyCode: Int = 16
    @AppStorage("selectionModifiers") var selectionModifiers: Int = 0
    @AppStorage("aiProvider") var aiProviderRaw: String = AIProvider.openai.rawValue
    @AppStorage("customBaseURL") var customBaseURL: String = ""
    @AppStorage("customModel") var customModel: String = ""
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("hasLaunchedBefore") var hasLaunchedBefore: Bool = false
    @AppStorage("popupPositionMode") var popupPositionModeRaw: String = PopupPositionMode.fixed.rawValue
    @AppStorage("fixedPositionX") var fixedPositionX: Double = .nan
    @AppStorage("fixedPositionY") var fixedPositionY: Double = .nan
    @AppStorage("defaultPinned") var defaultPinned: Bool = false
    @AppStorage("promptTabsJSON") var promptTabsJSON: String = ""

    var translationStyle: TranslationStyle {
        get { TranslationStyle(rawValue: translationStyleRaw) ?? .professional }
        set { translationStyleRaw = newValue.rawValue }
    }

    var aiProvider: AIProvider {
        get { AIProvider(rawValue: aiProviderRaw) ?? .openai }
        set { aiProviderRaw = newValue.rawValue }
    }

    var effectiveBaseURL: String {
        customBaseURL.isEmpty ? aiProvider.defaultBaseURL : customBaseURL
    }

    var effectiveModel: String {
        customModel.isEmpty ? aiProvider.defaultModel : customModel
    }

    @AppStorage("apiKey") var apiKey: String = ""

    var popupPositionMode: PopupPositionMode {
        get { PopupPositionMode(rawValue: popupPositionModeRaw) ?? .fixed }
        set { popupPositionModeRaw = newValue.rawValue }
    }

    var savedFixedPosition: NSPoint? {
        if fixedPositionX.isNaN || fixedPositionY.isNaN { return nil }
        return NSPoint(x: fixedPositionX, y: fixedPositionY)
    }

    func setSavedFixedPosition(_ point: NSPoint?) {
        if let p = point {
            fixedPositionX = Double(p.x)
            fixedPositionY = Double(p.y)
        } else {
            fixedPositionX = .nan
            fixedPositionY = .nan
        }
    }

    var promptTabs: [PromptTab] {
        get {
            guard !promptTabsJSON.isEmpty,
                  let data = promptTabsJSON.data(using: .utf8),
                  let tabs = try? JSONDecoder().decode([PromptTab].self, from: data)
            else {
                let defaults = PromptTab.builtinDefaults
                if let data = try? JSONEncoder().encode(defaults),
                   let s = String(data: data, encoding: .utf8) {
                    promptTabsJSON = s
                }
                return defaults
            }
            return tabs
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let s = String(data: data, encoding: .utf8) {
                promptTabsJSON = s
            }
        }
    }

    var screenshotHotkeyDisplay: String {
        HotkeyUtils.displayString(keyCode: screenshotKeyCode, modifiers: screenshotModifiers)
    }

    var selectionHotkeyDisplay: String {
        HotkeyUtils.displayString(keyCode: selectionKeyCode, modifiers: selectionModifiers)
    }
}

struct HotkeyUtils {
    // Modifier flag constants (CGEventFlags raw bits)
    static let commandFlag = 1 << 20  // 0x100000
    static let shiftFlag   = 1 << 17  // 0x020000
    static let optionFlag  = 1 << 19  // 0x080000
    static let controlFlag = 1 << 18  // 0x040000

    static let defaultModifiers = commandFlag | shiftFlag

    static func displayString(keyCode: Int, modifiers: Int) -> String {
        let mods = modifiers == 0 ? defaultModifiers : modifiers
        var parts: [String] = []
        if mods & controlFlag != 0 { parts.append("⌃") }
        if mods & optionFlag  != 0 { parts.append("⌥") }
        if mods & shiftFlag   != 0 { parts.append("⇧") }
        if mods & commandFlag != 0 { parts.append("⌘") }
        parts.append(keyCodeToString(keyCode))
        return parts.joined()
    }

    static func keyCodeToString(_ keyCode: Int) -> String {
        let map: [Int: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
            36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
            42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
            48: "⇥", 49: "Space", 50: "`",
            51: "⌫", 53: "⎋",
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
            101: "F9", 103: "F11", 105: "F13", 107: "F14",
            109: "F10", 111: "F12", 113: "F15",
            118: "F4", 119: "F2", 120: "F1", 122: "F16",
            123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }

    static func modifiersFromNSEvent(_ event: NSEvent) -> Int {
        var flags = 0
        if event.modifierFlags.contains(.command) { flags |= commandFlag }
        if event.modifierFlags.contains(.shift)   { flags |= shiftFlag }
        if event.modifierFlags.contains(.option)  { flags |= optionFlag }
        if event.modifierFlags.contains(.control)  { flags |= controlFlag }
        return flags
    }

    static func matchesCGEvent(_ event: CGEvent, keyCode: Int, modifiers: Int) -> Bool {
        let mods = modifiers == 0 ? defaultModifiers : modifiers
        let eventKeyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let eventFlags = event.flags
        guard eventKeyCode == keyCode else { return false }
        let hasCmd   = eventFlags.contains(.maskCommand)
        let hasShift = eventFlags.contains(.maskShift)
        let hasOpt   = eventFlags.contains(.maskAlternate)
        let hasCtrl  = eventFlags.contains(.maskControl)
        let wantCmd   = mods & commandFlag != 0
        let wantShift = mods & shiftFlag != 0
        let wantOpt   = mods & optionFlag != 0
        let wantCtrl  = mods & controlFlag != 0
        return hasCmd == wantCmd && hasShift == wantShift && hasOpt == wantOpt && hasCtrl == wantCtrl
    }
}
