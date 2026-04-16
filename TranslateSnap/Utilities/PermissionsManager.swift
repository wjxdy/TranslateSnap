import AppKit

class PermissionsManager {
    static let shared = PermissionsManager()

    func checkAccessibility() -> Bool {
        return AXIsProcessTrusted()
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// 只检查辅助功能，不再主动触发屏幕录制权限弹窗
    func checkAll() {
        if !checkAccessibility() {
            let alert = NSAlert()
            alert.messageText = "需要授权"
            alert.informativeText = "TranslateSnap 需要辅助功能权限才能使用全局快捷键和划词翻译。\n\n请在系统设置中授权后重启 App。"
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "稍后")
            if alert.runModal() == .alertFirstButtonReturn {
                requestAccessibility()
            }
        }
    }
}
