import AppKit

@MainActor
class HotkeyManager {
    static let shared = HotkeyManager()
    private var eventTap: CFMachPort?
    /// 供 ESC 关闭弹窗用
    weak var activePopupController: PopupWindowController?

    func start() {
        stop()
        NSLog("[TranslateSnap] HotkeyManager.start called, AX trusted: \(AXIsProcessTrusted())")
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(event)
            },
            userInfo: selfPtr
        )

        guard let tap = eventTap else {
            NSLog("[TranslateSnap] ERROR: CGEvent.tapCreate returned nil (missing Accessibility permission?)")
            let alert = NSAlert()
            alert.messageText = "快捷键注册失败"
            alert.informativeText = "需要辅助功能权限。请在 系统设置 → 隐私与安全性 → 辅助功能 中添加 TranslateSnap 并勾选。\n\n如果已添加过旧版本，请先移除再重新添加本版本。"
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "取消")
            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            return
        }
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[TranslateSnap] HotkeyManager started successfully")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
    }

    func restart() {
        start()
    }

    private nonisolated func handleEvent(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))

        // ESC 关闭弹窗
        if keyCode == 53 {
            Task { @MainActor in
                guard let controller = self.activePopupController, !controller.isPinned else { return }
                controller.close()
            }
            // 不消费 ESC，让其他 app 也能收到
            return Unmanaged.passRetained(event)
        }

        let settings = AppSettings.shared

        // Screenshot hotkey
        if HotkeyUtils.matchesCGEvent(event,
            keyCode: settings.screenshotKeyCode,
            modifiers: settings.screenshotModifiers)
        {
            Task { @MainActor in
                ScreenshotCaptureManager.shared.start()
            }
            return nil
        }

        // Selection translate hotkey
        if HotkeyUtils.matchesCGEvent(event,
            keyCode: settings.selectionKeyCode,
            modifiers: settings.selectionModifiers)
        {
            NSLog("[TranslateSnap] selection hotkey matched")
            Task { @MainActor in
                await SelectionTranslateManager.shared.translateSelection()
            }
            return nil
        }

        return Unmanaged.passRetained(event)
    }
}
