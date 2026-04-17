import AppKit

class SelectionTranslateManager {
    static let shared = SelectionTranslateManager()

    @MainActor
    func translateSelection() async {
        NSLog("[TranslateSnap] translateSelection triggered")
        let text = await getSelectedText()
        NSLog("[TranslateSnap] selected text: \(text ?? "<nil>")")
        guard let text = text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let alert = NSAlert()
            alert.messageText = "未获取到选中文字"
            alert.informativeText = "请先选中一段文字再触发划词翻译"
            alert.runModal()
            return
        }
        let settings = AppSettings.shared
        let request = TranslationRequest(
            text: text,
            targetLanguage: settings.targetLanguage,
            style: settings.translationStyle,
            systemPrompt: TranslationEngine.buildSystemPrompt(targetLanguage: settings.targetLanguage, style: settings.translationStyle)
        )
        let provider = TranslationEngine.provider(for: settings)
        let viewModel = StreamingTranslationViewModel(original: text)
        let popup = PopupWindowController.shared
        popup.showStream(viewModel: viewModel, at: NSEvent.mouseLocation)
        viewModel.start(stream: provider.translateStream(request))
    }

    private func getSelectedText() async -> String? {
        NSLog("[TranslateSnap] getSelectedText: START")
        let axText = getAXSelectedText()
        NSLog("[TranslateSnap] getSelectedText: AX returned: \(axText ?? "<nil>")")
        if let text = axText, !text.isEmpty { return text }

        NSLog("[TranslateSnap] getSelectedText: falling back to Cmd+C")
        let result = await fallbackCopy()
        NSLog("[TranslateSnap] getSelectedText: fallback returned: \(result ?? "<nil>")")
        return result
    }

    private func getAXSelectedText() -> String? {
        let systemElement = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(systemElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else {
            return nil
        }
        var selectedText: AnyObject?
        let result = AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText)
        if result == .success, let text = selectedText as? String, !text.isEmpty { return text }
        return nil
    }

    private func fallbackCopy() async -> String? {
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        // 清空剪贴板，用 changeCount 检测变化
        pasteboard.clearContents()
        let countBefore = pasteboard.changeCount

        // 获取当前最前 app 的 PID，把 Cmd+C 直接发给它
        let frontApp = NSWorkspace.shared.frontmostApplication
        let pid = frontApp?.processIdentifier ?? 0
        NSLog("[TranslateSnap] fallbackCopy: frontApp=\(frontApp?.localizedName ?? "nil"), pid=\(pid)")

        // 发送 Cmd+C 到前台 app
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: true) // 8 = C key
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: false)
        up?.flags = .maskCommand

        if pid != 0 {
            down?.postToPid(pid)
            up?.postToPid(pid)
        } else {
            down?.post(tap: .cgAnnotatedSessionEventTap)
            up?.post(tap: .cgAnnotatedSessionEventTap)
        }

        // 等 app 处理复制
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 秒

        let text = pasteboard.string(forType: .string)
        let copied = pasteboard.changeCount != countBefore
        NSLog("[TranslateSnap] fallbackCopy: copied=\(copied), changeCount before=\(countBefore) after=\(pasteboard.changeCount)")

        restorePasteboard(previous: previousContents)
        return copied ? text : nil
    }

    private func restorePasteboard(previous: String?) {
        if let prev = previous {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(prev, forType: .string)
        }
    }
}
