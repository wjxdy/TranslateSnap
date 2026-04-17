# 弹窗位置模式 + 钉住 + 自定义提示词 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 TranslateSnap 增加可配置的弹窗位置模式（固定/跟随指针，固定模式记忆拖动位置）、弹窗钉住置顶、以及可管理的自定义提示词标签（并行 API 调用）。

**Architecture:** 新增 `PromptTab` 数据模型（JSON 存于 UserDefaults）；`PopupSessionViewModel` 为每个 visible tab 并行 spawn 流式 Task；`PopupWindowController` 合并两个 `showStream*` 为统一 `show(session:cursor:)`，支持拖动记忆与 pushpin；设置窗口增加"提示词"分区。旧 `StreamingTranslationViewModel` 与 `PopupMode` 枚举一并移除。

**Tech Stack:** Swift 5.9、SwiftUI、AppKit/NSPanel、@AppStorage/UserDefaults、AsyncThrowingStream，XcodeGen（project.yml 使用 glob 自动收录新文件，需 `xcodegen generate` 刷新 pbxproj）。

**验证策略：** 本项目没有单元测试 target，按 CLAUDE.md "后端 / 前端 验证要求"走：每个任务以 `xcodebuild build` 编译验证；最终任务跑 7 个手动场景覆盖端到端行为。macOS 原生应用 Playwright 不适用。

**Spec：** `docs/superpowers/specs/2026-04-17-popup-position-and-custom-prompts-design.md`

---

## Task 1: PromptTab 数据模型

**Files:**
- Create: `TranslateSnap/Translation/PromptTab.swift`

- [ ] **Step 1: 创建 PromptTab.swift**

```swift
import Foundation

struct PromptTab: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var systemPrompt: String
    var visible: Bool
    var isBuiltin: Bool

    init(id: UUID = UUID(), name: String, systemPrompt: String, visible: Bool = true, isBuiltin: Bool = false) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.visible = visible
        self.isBuiltin = isBuiltin
    }

    static var builtinDefaults: [PromptTab] {
        [
            PromptTab(
                name: "翻译",
                systemPrompt: "将下列文字翻译为 {targetLanguage}，风格：{style}。只输出翻译结果，不要额外说明。",
                visible: true,
                isBuiltin: true
            ),
            PromptTab(
                name: "解释",
                systemPrompt: "解释下列内容（术语、背景、典型用法）。如果没有可解释的内容，直接输出"无"。",
                visible: true,
                isBuiltin: true
            )
        ]
    }
}
```

- [ ] **Step 2: 刷新 Xcode 项目**

Run: `cd /Users/xulei/Documents/TranslateSnap && xcodegen generate`
Expected: `Created project at ...TranslateSnap.xcodeproj`

- [ ] **Step 3: 编译验证**

Run: `xcodebuild -project TranslateSnap.xcodeproj -scheme TranslateSnap -configuration Debug build -quiet`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: commit**

```bash
git add TranslateSnap/Translation/PromptTab.swift TranslateSnap.xcodeproj
git commit -m "feat(prompts): add PromptTab model with builtin defaults"
git push origin main
```

---

## Task 2: AppSettings 扩展新字段

**Files:**
- Modify: `TranslateSnap/Utilities/AppSettings.swift`

- [ ] **Step 1: 新增 PopupPositionMode 枚举（插入到 `enum PopupMode` 之后）**

在 `AppSettings.swift` `enum PopupMode` 的闭合 `}` 之后插入：

```swift
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
```

- [ ] **Step 2: 在 `AppSettings` 类中添加新字段**

在 `class AppSettings` 现有 `@AppStorage` 区块末尾（`@AppStorage("hasLaunchedBefore")` 之后）追加：

```swift
    @AppStorage("popupPositionMode") var popupPositionModeRaw: String = PopupPositionMode.fixed.rawValue
    @AppStorage("fixedPositionX") var fixedPositionX: Double = .nan
    @AppStorage("fixedPositionY") var fixedPositionY: Double = .nan
    @AppStorage("defaultPinned") var defaultPinned: Bool = false
    @AppStorage("promptTabsJSON") var promptTabsJSON: String = ""
```

- [ ] **Step 3: 在 `class AppSettings` 底部（`apiKey` 之后）添加 computed accessor**

```swift
    var popupPositionMode: PopupPositionMode {
        get { PopupPositionMode(rawValue: popupPositionModeRaw) ?? .fixed }
        set { popupPositionModeRaw = newValue.rawValue }
    }

    var savedFixedPosition: NSPoint? {
        get {
            if fixedPositionX.isNaN || fixedPositionY.isNaN { return nil }
            return NSPoint(x: fixedPositionX, y: fixedPositionY)
        }
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
                return PromptTab.builtinDefaults
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
```

- [ ] **Step 4: 在文件顶部补充 AppKit import**

文件开头现有 `import SwiftUI` 后追加一行（若未存在）：

```swift
import AppKit
```

- [ ] **Step 5: 编译验证**

Run: `xcodebuild -project TranslateSnap.xcodeproj -scheme TranslateSnap -configuration Debug build -quiet`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 6: commit**

```bash
git add TranslateSnap/Utilities/AppSettings.swift
git commit -m "feat(settings): add popup position mode, pin default, prompt tabs storage"
git push origin main
```

---

## Task 3: Translation 层改造（systemPrompt + renderPrompt）

**Files:**
- Modify: `TranslateSnap/Translation/TranslationModels.swift`
- Modify: `TranslateSnap/Translation/OpenAIProvider.swift`
- Modify: `TranslateSnap/Translation/ClaudeProvider.swift`
- Modify: `TranslateSnap/SelectionTranslate/SelectionTranslateManager.swift`
- Modify: `TranslateSnap/ScreenshotCapture/ScreenshotCaptureManager.swift`
- Modify: `TranslateSnap/Settings/SettingsSubViews.swift`

- [ ] **Step 1: 修改 `TranslationRequest`（`TranslationModels.swift`）**

把：

```swift
struct TranslationRequest {
    let text: String
    let targetLanguage: String
    let style: TranslationStyle
}
```

改为：

```swift
struct TranslationRequest {
    let text: String
    let targetLanguage: String
    let style: TranslationStyle
    let systemPrompt: String
}
```

- [ ] **Step 2: 在 `TranslationEngine` 里新增 `renderPrompt`**

在 `class TranslationEngine` 内部（`buildSystemPrompt` 下面）添加：

```swift
    static func renderPrompt(
        _ template: String,
        targetLanguage: String,
        style: TranslationStyle
    ) -> String {
        template
            .replacingOccurrences(of: "{targetLanguage}", with: targetLanguage)
            .replacingOccurrences(of: "{style}", with: style.displayName)
    }
```

**注意**：`buildSystemPrompt` 暂时保留，Task 9 清理。

- [ ] **Step 3: 修改 `OpenAIProvider.buildRequest`**

把 `OpenAIProvider.swift` 第 20 行附近：

```swift
let systemPrompt = TranslationEngine.buildSystemPrompt(targetLanguage: request.targetLanguage, style: request.style)
```

改为：

```swift
let systemPrompt = request.systemPrompt
```

- [ ] **Step 4: 修改 `ClaudeProvider.buildRequest`**

把 `ClaudeProvider.swift` 第 21 行附近：

```swift
let systemPrompt = TranslationEngine.buildSystemPrompt(targetLanguage: request.targetLanguage, style: request.style)
```

改为：

```swift
let systemPrompt = request.systemPrompt
```

- [ ] **Step 5: 修改 `SelectionTranslateManager.translateSelection`**

把 `SelectionTranslateManager.swift` 第 19 行：

```swift
let request = TranslationRequest(text: text, targetLanguage: settings.targetLanguage, style: settings.translationStyle)
```

改为：

```swift
let request = TranslationRequest(
    text: text,
    targetLanguage: settings.targetLanguage,
    style: settings.translationStyle,
    systemPrompt: TranslationEngine.buildSystemPrompt(targetLanguage: settings.targetLanguage, style: settings.translationStyle)
)
```

- [ ] **Step 6: 修改 `ScreenshotCaptureManager.captureAndTranslate`**

把 `ScreenshotCaptureManager.swift` 第 50-54 行：

```swift
let request = TranslationRequest(
    text: text,
    targetLanguage: settings.targetLanguage,
    style: settings.translationStyle
)
```

改为：

```swift
let request = TranslationRequest(
    text: text,
    targetLanguage: settings.targetLanguage,
    style: settings.translationStyle,
    systemPrompt: TranslationEngine.buildSystemPrompt(targetLanguage: settings.targetLanguage, style: settings.translationStyle)
)
```

- [ ] **Step 7: 修改 `APISettingsView` 测试连接**

把 `SettingsSubViews.swift` 第 106 行附近：

```swift
let req = TranslationRequest(text: "hello", targetLanguage: settings.targetLanguage, style: .natural)
```

改为：

```swift
let req = TranslationRequest(
    text: "hello",
    targetLanguage: settings.targetLanguage,
    style: .natural,
    systemPrompt: "Reply with a single short greeting in \(settings.targetLanguage)."
)
```

- [ ] **Step 8: 编译验证**

Run: `xcodebuild -project TranslateSnap.xcodeproj -scheme TranslateSnap -configuration Debug build -quiet`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 9: commit**

```bash
git add TranslateSnap/Translation/TranslationModels.swift \
        TranslateSnap/Translation/OpenAIProvider.swift \
        TranslateSnap/Translation/ClaudeProvider.swift \
        TranslateSnap/SelectionTranslate/SelectionTranslateManager.swift \
        TranslateSnap/ScreenshotCapture/ScreenshotCaptureManager.swift \
        TranslateSnap/Settings/SettingsSubViews.swift
git commit -m "feat(translation): parameterize system prompt via TranslationRequest"
git push origin main
```

---

## Task 4: PopupSessionViewModel

**Files:**
- Create: `TranslateSnap/UI/PopupSessionViewModel.swift`

- [ ] **Step 1: 创建 PopupSessionViewModel.swift**

```swift
import SwiftUI
import AppKit

@MainActor
final class PopupSessionViewModel: ObservableObject {
    struct TabState: Equatable {
        var text: String = ""
        var isLoading: Bool = true
        var error: String? = nil
    }

    enum TriggerKind {
        case selection(cursor: NSPoint)
        case screenshot
    }

    let originalText: String
    let trigger: TriggerKind
    @Published private(set) var tabs: [PromptTab]
    @Published var states: [UUID: TabState] = [:]
    @Published var pinned: Bool

    private var tasks: [UUID: Task<Void, Never>] = [:]

    init(originalText: String, trigger: TriggerKind) {
        self.originalText = originalText
        self.trigger = trigger
        self.tabs = AppSettings.shared.promptTabs.filter { $0.visible }
        self.pinned = AppSettings.shared.defaultPinned
        for tab in tabs { states[tab.id] = TabState() }
    }

    func start() {
        let settings = AppSettings.shared
        let provider = TranslationEngine.provider(for: settings)
        for tab in tabs {
            spawn(tab: tab, provider: provider, settings: settings)
        }
    }

    func retry(tabID: UUID) {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
        tasks[tabID]?.cancel()
        states[tabID] = TabState()
        let settings = AppSettings.shared
        let provider = TranslationEngine.provider(for: settings)
        spawn(tab: tab, provider: provider, settings: settings)
    }

    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }

    func togglePin() {
        pinned.toggle()
        AppSettings.shared.defaultPinned = pinned
    }

    private func spawn(tab: PromptTab, provider: TranslationProvider, settings: AppSettings) {
        let prompt = TranslationEngine.renderPrompt(
            tab.systemPrompt,
            targetLanguage: settings.targetLanguage,
            style: settings.translationStyle
        )
        let request = TranslationRequest(
            text: originalText,
            targetLanguage: settings.targetLanguage,
            style: settings.translationStyle,
            systemPrompt: prompt
        )
        let stream = provider.translateStream(request)
        let id = tab.id
        tasks[id] = Task { [weak self] in
            do {
                for try await chunk in stream {
                    if Task.isCancelled { return }
                    await MainActor.run {
                        guard var s = self?.states[id] else { return }
                        if s.isLoading { s.isLoading = false }
                        s.text.append(chunk)
                        self?.states[id] = s
                    }
                }
                await MainActor.run {
                    guard var s = self?.states[id] else { return }
                    s.isLoading = false
                    s.text = s.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    self?.states[id] = s
                }
            } catch {
                await MainActor.run {
                    guard var s = self?.states[id] else { return }
                    s.isLoading = false
                    s.error = error.localizedDescription
                    self?.states[id] = s
                }
            }
        }
    }
}
```

- [ ] **Step 2: 刷新 Xcode 项目**

Run: `xcodegen generate`
Expected: `Created project at ...TranslateSnap.xcodeproj`

- [ ] **Step 3: 编译验证**

Run: `xcodebuild -project TranslateSnap.xcodeproj -scheme TranslateSnap -configuration Debug build -quiet`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: commit**

```bash
git add TranslateSnap/UI/PopupSessionViewModel.swift TranslateSnap.xcodeproj
git commit -m "feat(popup): add PopupSessionViewModel with parallel streaming per tab"
git push origin main
```

---

## Task 5: 弹窗子组件

**Files:**
- Create: `TranslateSnap/UI/PopupComponents.swift`

- [ ] **Step 1: 创建 PopupComponents.swift**

```swift
import SwiftUI
import AVFoundation

// MARK: - HeaderBar

struct PopupHeaderBar: View {
    let pinned: Bool
    let onTogglePin: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button(action: onTogglePin) {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .rotationEffect(.degrees(pinned ? 0 : 45))
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help(pinned ? "取消钉住" : "钉住到最前")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("关闭")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.windowBackgroundColor))
    }
}

// MARK: - OriginalCard

struct OriginalCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("原文")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - TabCard

struct TabCard: View {
    let tab: PromptTab
    let state: PopupSessionViewModel.TabState
    let onRetry: () -> Void
    @State private var synthesizer = AVSpeechSynthesizer()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(tab.name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                if state.isLoading {
                    ProgressView().scaleEffect(0.5).frame(height: 10)
                }
                Spacer()
                if !state.text.isEmpty {
                    Button(action: copy) {
                        Image(systemName: "doc.on.doc").font(.system(size: 10))
                    }.buttonStyle(.plain).help("复制")
                    Button(action: speak) {
                        Image(systemName: "speaker.wave.2").font(.system(size: 10))
                    }.buttonStyle(.plain).help("朗读")
                }
            }
            if let err = state.error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                    Spacer()
                    Button("重试", action: onRetry)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            } else if state.isLoading && state.text.isEmpty {
                Text("生成中…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                Text(state.text)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(state.text, forType: .string)
    }

    private func speak() {
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(AVSpeechUtterance(string: state.text))
    }
}

// MARK: - EmptyHint

struct EmptyHintView: View {
    let onOpenSettings: () -> Void
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("暂无可用的提示词")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Button("打开设置", action: onOpenSettings)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(24)
    }
}
```

- [ ] **Step 2: 刷新 Xcode 项目**

Run: `xcodegen generate`

- [ ] **Step 3: 编译验证**

Run: `xcodebuild -project TranslateSnap.xcodeproj -scheme TranslateSnap -configuration Debug build -quiet`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: commit**

```bash
git add TranslateSnap/UI/PopupComponents.swift TranslateSnap.xcodeproj
git commit -m "feat(popup): add header bar, tab card, original card, empty hint components"
git push origin main
```

---

## Task 6: 重写 PopupView + PopupWindowController + 管理器接线（原子提交）

**说明：** 这一步是破坏性替换，涉及多个文件必须一次提交确保编译通过。

**Files:**
- Rewrite: `TranslateSnap/UI/PopupView.swift`
- Rewrite: `TranslateSnap/UI/PopupWindowController.swift`
- Modify: `TranslateSnap/SelectionTranslate/SelectionTranslateManager.swift`
- Modify: `TranslateSnap/ScreenshotCapture/ScreenshotCaptureManager.swift`
- Modify: `TranslateSnap/Utilities/HotkeyManager.swift`
- Delete: `TranslateSnap/UI/StreamingTranslationViewModel.swift`

- [ ] **Step 1: 重写 `PopupView.swift`**

完整替换文件内容：

```swift
import SwiftUI

struct PopupRootView: View {
    @ObservedObject var viewModel: PopupSessionViewModel
    @AppStorage("showOriginal") private var showOriginal: Bool = true
    let onClose: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PopupHeaderBar(
                pinned: viewModel.pinned,
                onTogglePin: { viewModel.togglePin() },
                onClose: onClose
            )
            Divider().opacity(0.4)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        if showOriginal {
                            OriginalCard(text: viewModel.originalText)
                            Divider().opacity(0.4)
                        }
                        if viewModel.tabs.isEmpty {
                            EmptyHintView(onOpenSettings: onOpenSettings)
                        } else {
                            ForEach(viewModel.tabs) { tab in
                                TabCard(
                                    tab: tab,
                                    state: viewModel.states[tab.id] ?? PopupSessionViewModel.TabState(),
                                    onRetry: { viewModel.retry(tabID: tab.id) }
                                )
                                if tab.id != viewModel.tabs.last?.id {
                                    Divider().opacity(0.4)
                                }
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(16)
                }
                .onChange(of: viewModel.states) { _ in
                    withAnimation { proxy.scrollTo("bottom") }
                }
            }
            .frame(maxHeight: 400)
        }
        .frame(minWidth: 360, idealWidth: 400, maxWidth: 480)
        .background(Color(.windowBackgroundColor))
    }
}
```

- [ ] **Step 2: 重写 `PopupWindowController.swift`**

完整替换文件内容：

```swift
import AppKit
import SwiftUI

@MainActor
final class PopupWindowController {
    static let shared = PopupWindowController()

    private var panel: NSPanel?
    private var session: PopupSessionViewModel?
    private var eventMonitor: Any?
    private var moveObserver: NSObjectProtocol?

    var isPinned: Bool { session?.pinned ?? false }

    func show(session: PopupSessionViewModel) {
        close()
        self.session = session

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 240),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true

        let root = PopupRootView(
            viewModel: session,
            onClose: { [weak self] in self?.close() },
            onOpenSettings: { [weak self] in
                self?.close()
                NSApp.sendAction(#selector(AppDelegate.openSettings(_:)), to: nil, from: nil)
            }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.frame = panel.contentView!.bounds
        hosting.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(hosting)

        if let cv = panel.contentView {
            cv.wantsLayer = true
            cv.layer?.cornerRadius = 12
            cv.layer?.masksToBounds = true
        }

        let maxHeight: CGFloat = 500
        let fitting = hosting.fittingSize
        let size = NSSize(width: fitting.width, height: min(fitting.height, maxHeight))
        panel.setContentSize(size)

        let origin = computeOrigin(windowSize: size)
        panel.setFrameOrigin(origin)

        applyPin(session.pinned, panel: panel)
        panel.makeKeyAndOrderFront(nil)

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleDidMove() }
        }

        self.panel = panel
        HotkeyManager.shared.activePopupController = self

        session.start()

        // 观察 pinned 状态切换，及时更新 panel.level 与监听
        observePinChange(session: session)
    }

    func close() {
        session?.cancelAll()
        if let obs = moveObserver {
            NotificationCenter.default.removeObserver(obs)
            moveObserver = nil
        }
        removeGlobalMouseDownMonitor()
        panel?.close()
        panel = nil
        session = nil
        HotkeyManager.shared.activePopupController = nil
    }

    // MARK: - Position

    private func computeOrigin(windowSize: NSSize) -> NSPoint {
        let settings = AppSettings.shared
        let mode = settings.popupPositionMode
        let screen = currentScreen(for: mode)
        let visible = screen.visibleFrame

        switch mode {
        case .followCursor:
            if case .selection(let cursor) = session?.trigger ?? .screenshot {
                var p = NSPoint(x: cursor.x + 12, y: cursor.y - windowSize.height - 12)
                return constrain(p, size: windowSize, to: visible)
            }
            // screenshot 在 followCursor 模式下也用鼠标位置
            let cursor = NSEvent.mouseLocation
            var p = NSPoint(x: cursor.x + 12, y: cursor.y - windowSize.height - 12)
            return constrain(p, size: windowSize, to: visible)

        case .fixed:
            if let saved = settings.savedFixedPosition {
                return constrain(saved, size: windowSize, to: visible)
            }
            return NSPoint(
                x: visible.midX - windowSize.width / 2,
                y: visible.midY + visible.height * 0.1 - windowSize.height / 2
            )
        }
    }

    private func currentScreen(for mode: PopupPositionMode) -> NSScreen {
        switch mode {
        case .followCursor:
            let mouse = NSEvent.mouseLocation
            return NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main ?? NSScreen.screens[0]
        case .fixed:
            if let saved = AppSettings.shared.savedFixedPosition,
               let screen = NSScreen.screens.first(where: { $0.frame.contains(saved) }) {
                return screen
            }
            return NSScreen.main ?? NSScreen.screens[0]
        }
    }

    private func constrain(_ origin: NSPoint, size: NSSize, to frame: NSRect) -> NSPoint {
        let x = max(frame.minX + 8, min(origin.x, frame.maxX - size.width - 8))
        let y = max(frame.minY + 8, min(origin.y, frame.maxY - size.height - 8))
        return NSPoint(x: x, y: y)
    }

    private func handleDidMove() {
        guard let panel = panel else { return }
        let settings = AppSettings.shared
        guard settings.popupPositionMode == .fixed,
              !(session?.pinned ?? false)
        else { return }
        settings.setSavedFixedPosition(panel.frame.origin)
    }

    // MARK: - Pin

    private func applyPin(_ pinned: Bool, panel: NSPanel) {
        panel.level = pinned ? .statusBar : .floating
        if pinned {
            removeGlobalMouseDownMonitor()
        } else {
            installGlobalMouseDownMonitor()
        }
    }

    private func observePinChange(session: PopupSessionViewModel) {
        // 轮询式观察：SwiftUI @Published → 由 PopupRootView 调 togglePin 时同步更新。
        // 这里通过 Combine 订阅也行；简单起见暴露一个 apply 接口给 ViewModel 调用：
        // 做法：在 ViewModel.togglePin 里直接调 controller.pinChanged(pinned:)。
        // 为减少双向耦合，这里用 KVO-free 订阅：PopupRootView onChange(of: pinned) 调回。
    }

    /// 由 PopupRootView 在 pinned 变更时回调。
    func pinStateDidChange(_ pinned: Bool) {
        guard let panel = panel else { return }
        applyPin(pinned, panel: panel)
    }

    // MARK: - Outside click monitor

    private func installGlobalMouseDownMonitor() {
        if eventMonitor != nil { return }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    private func removeGlobalMouseDownMonitor() {
        if let m = eventMonitor {
            NSEvent.removeMonitor(m)
            eventMonitor = nil
        }
    }
}
```

- [ ] **Step 3: 在 `PopupRootView` 中加 pinned 变化回调**

（Step 1 中 PopupRootView 的 body 末尾补一个 onChange；更新 Step 1 的 VStack，加 `.onChange(of: viewModel.pinned)`）。替换 `.background(Color(.windowBackgroundColor))` 那一行前紧挨着加：

```swift
        .onChange(of: viewModel.pinned) { newValue in
            PopupWindowController.shared.pinStateDidChange(newValue)
        }
```

（即 PopupRootView 的 `body` 尾端）

- [ ] **Step 4: 修改 `SelectionTranslateManager.translateSelection`**

把：

```swift
let viewModel = StreamingTranslationViewModel(original: text)
let popup = PopupWindowController.shared
popup.showStream(viewModel: viewModel, at: NSEvent.mouseLocation)
viewModel.start(stream: provider.translateStream(request))
```

替换为：

```swift
let session = PopupSessionViewModel(originalText: text, trigger: .selection(cursor: NSEvent.mouseLocation))
PopupWindowController.shared.show(session: session)
```

同时删除本函数内不再使用的 `let request = ...` 与 `let provider = ...` 两行（session 内部会自己构造）。

保留前面对空文本的 guard alert 逻辑不变。

- [ ] **Step 5: 修改 `ScreenshotCaptureManager.captureAndTranslate`**

把：

```swift
let settings = AppSettings.shared
let request = TranslationRequest(
    text: text,
    targetLanguage: settings.targetLanguage,
    style: settings.translationStyle,
    systemPrompt: TranslationEngine.buildSystemPrompt(targetLanguage: settings.targetLanguage, style: settings.translationStyle)
)
let provider = TranslationEngine.provider(for: settings)
let viewModel = StreamingTranslationViewModel(original: text)
PopupWindowController.shared.showStreamCentered(viewModel: viewModel)
viewModel.start(stream: provider.translateStream(request))
```

替换为：

```swift
let session = PopupSessionViewModel(originalText: text, trigger: .screenshot)
PopupWindowController.shared.show(session: session)
```

- [ ] **Step 6: 修改 `HotkeyManager.handleEvent` 的 ESC 分支**

把（`HotkeyManager.swift` 第 63-69 行）：

```swift
if keyCode == 53 {
    Task { @MainActor in
        self.activePopupController?.close()
    }
    return Unmanaged.passRetained(event)
}
```

替换为：

```swift
if keyCode == 53 {
    Task { @MainActor in
        guard let controller = self.activePopupController, !controller.isPinned else { return }
        controller.close()
    }
    return Unmanaged.passRetained(event)
}
```

- [ ] **Step 7: 删除 `StreamingTranslationViewModel.swift`**

Run: `git rm TranslateSnap/UI/StreamingTranslationViewModel.swift`

- [ ] **Step 8: 刷新 Xcode 项目**

Run: `xcodegen generate`

- [ ] **Step 9: 编译验证**

Run: `xcodebuild -project TranslateSnap.xcodeproj -scheme TranslateSnap -configuration Debug build -quiet`
Expected: `BUILD SUCCEEDED`

如果报 `AppDelegate.openSettings(_:)` 找不到：先跳过此 step，在 Step 10 commit 之前回到 AppDelegate 检查是否已有此 `@objc` 方法；没有则参考下面"兼容性补丁"。

**兼容性补丁**（只在 AppDelegate 无 `openSettings` 时需要）：

检查 `TranslateSnap/AppDelegate.swift`，若没有 `@objc func openSettings(_:)`，在类里加：

```swift
@objc func openSettings(_ sender: Any?) {
    NSApp.activate(ignoringOtherApps: true)
    if #available(macOS 14.0, *) {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    } else {
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}
```

- [ ] **Step 10: commit**

```bash
git add TranslateSnap/UI/PopupView.swift \
        TranslateSnap/UI/PopupWindowController.swift \
        TranslateSnap/SelectionTranslate/SelectionTranslateManager.swift \
        TranslateSnap/ScreenshotCapture/ScreenshotCaptureManager.swift \
        TranslateSnap/Utilities/HotkeyManager.swift \
        TranslateSnap/AppDelegate.swift \
        TranslateSnap.xcodeproj
git rm TranslateSnap/UI/StreamingTranslationViewModel.swift 2>/dev/null || true
git commit -m "feat(popup): rewrite popup with multi-tab view, drag memory, pin, ESC guard"
git push origin main
```

---

## Task 7: 提示词设置分区

**Files:**
- Create: `TranslateSnap/Settings/PromptsSettingsView.swift`

- [ ] **Step 1: 创建 PromptsSettingsView.swift**

```swift
import SwiftUI

struct PromptsSettingsView: View {
    @State private var tabs: [PromptTab] = AppSettings.shared.promptTabs
    @State private var editing: PromptTab? = nil
    @State private var isNew: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                ForEach($tabs) { $tab in
                    HStack {
                        Toggle("", isOn: $tab.visible)
                            .labelsHidden()
                            .onChange(of: tab.visible) { _ in persist() }
                        Text(tab.name)
                        if tab.isBuiltin {
                            Text("内置")
                                .font(.caption)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(4)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("编辑") {
                            editing = tab
                            isNew = false
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        if !tab.isBuiltin {
                            Button(role: .destructive) {
                                deleteTab(tab.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
                .onMove { src, dst in
                    tabs.move(fromOffsets: src, toOffset: dst)
                    persist()
                }
            }
            .listStyle(.inset)

            Divider()

            HStack {
                Button {
                    editing = PromptTab(name: "新提示词", systemPrompt: "", visible: true, isBuiltin: false)
                    isNew = true
                } label: {
                    Label("添加新提示词", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Text("占位符：{targetLanguage} / {style}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        }
        .sheet(item: $editing) { tab in
            PromptEditorSheet(
                draft: tab,
                isNew: isNew,
                onCancel: { editing = nil },
                onSave: { saved in
                    if isNew {
                        tabs.append(saved)
                    } else if let idx = tabs.firstIndex(where: { $0.id == saved.id }) {
                        tabs[idx] = saved
                    }
                    persist()
                    editing = nil
                }
            )
        }
    }

    private func deleteTab(_ id: UUID) {
        tabs.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        AppSettings.shared.promptTabs = tabs
    }
}

struct PromptEditorSheet: View {
    @State var draft: PromptTab
    let isNew: Bool
    let onCancel: () -> Void
    let onSave: (PromptTab) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "添加提示词" : (draft.isBuiltin ? "编辑内置提示词" : "编辑提示词"))
                .font(.headline)

            Form {
                TextField("名称", text: $draft.name)
                VStack(alignment: .leading, spacing: 4) {
                    Text("System Prompt").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $draft.systemPrompt)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 120)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.secondary.opacity(0.3)))
                }
                Toggle("在弹窗中显示", isOn: $draft.visible)
                Text("占位符 {targetLanguage} 和 {style} 会在调用时替换为当前设置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("保存") {
                    onSave(draft)
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty ||
                          draft.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 480, height: 360)
    }
}
```

- [ ] **Step 2: 刷新 Xcode 项目**

Run: `xcodegen generate`

- [ ] **Step 3: 编译验证**

Run: `xcodebuild -project TranslateSnap.xcodeproj -scheme TranslateSnap -configuration Debug build -quiet`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: commit**

```bash
git add TranslateSnap/Settings/PromptsSettingsView.swift TranslateSnap.xcodeproj
git commit -m "feat(settings): add prompts management view with editor sheet"
git push origin main
```

---

## Task 8: GeneralSettingsView 增设位置/钉住 + SettingsView 增 5th tab + 删除 PopupMode

**Files:**
- Modify: `TranslateSnap/Settings/SettingsSubViews.swift`
- Modify: `TranslateSnap/Settings/SettingsView.swift`
- Modify: `TranslateSnap/Utilities/AppSettings.swift`

- [ ] **Step 1: 修改 `GeneralSettingsView`**

把 `SettingsSubViews.swift` 中 `struct GeneralSettingsView` 整个 body 替换：

```swift
struct GeneralSettingsView: View {
    @AppStorage("targetLanguage") private var targetLanguage = "简体中文"
    @AppStorage("popupPositionMode") private var positionModeRaw = PopupPositionMode.fixed.rawValue
    @AppStorage("defaultPinned") private var defaultPinned = false
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @ObservedObject private var settings = AppSettings.shared

    private let languages = ["简体中文", "繁體中文", "English", "日本語", "한국어", "Français", "Deutsch", "Español"]

    var body: some View {
        Form {
            Section("语言") {
                Picker("目标语言", selection: $targetLanguage) {
                    ForEach(languages, id: \.self) { Text($0).tag($0) }
                }
            }

            Section("弹窗") {
                Picker("位置模式", selection: $positionModeRaw) {
                    ForEach(PopupPositionMode.allCases, id: \.rawValue) {
                        Text($0.displayName).tag($0.rawValue)
                    }
                }
                if PopupPositionMode(rawValue: positionModeRaw) == .fixed,
                   settings.savedFixedPosition != nil {
                    Button("重置位置（回到默认中上位置）") {
                        settings.setSavedFixedPosition(nil)
                    }
                }
                Toggle("默认钉住弹窗", isOn: $defaultPinned)
                Text("钉住后点击外部与 ESC 都不会关闭；大头针按钮可在弹窗里切换。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("启动") {
                Toggle("开机启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        if #available(macOS 13.0, *) {
                            let service = SMAppService.mainApp
                            try? newValue ? service.register() : service.unregister()
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
```

- [ ] **Step 2: 修改 `SettingsView.Tab`**

在 `SettingsView.swift` 中：

把：

```swift
enum Tab: String, CaseIterable {
    case general, translation, shortcuts, api
    ...
}
```

扩展为：

```swift
enum Tab: String, CaseIterable {
    case general, translation, shortcuts, prompts, api

    var label: String {
        switch self {
        case .general: return "通用"
        case .translation: return "翻译"
        case .shortcuts: return "快捷键"
        case .prompts: return "提示词"
        case .api: return "API"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .translation: return "globe"
        case .shortcuts: return "keyboard"
        case .prompts: return "text.bubble"
        case .api: return "key"
        }
    }
}
```

`switch selectedTab` 里添加：

```swift
case .prompts: PromptsSettingsView()
```

（紧挨 `case .shortcuts:` 之后、`case .api:` 之前。）

- [ ] **Step 3: 删除 `AppSettings.swift` 里的 PopupMode 枚举与 `popupModeRaw` 属性**

删除整个 `enum PopupMode { ... }` 块（`AppSettings.swift` 第 5-17 行）。

删除这行（现 `@AppStorage("popupMode") var popupModeRaw` 一行）：

```swift
@AppStorage("popupMode") var popupModeRaw: String = PopupMode.expandable.rawValue
```

删除 computed：

```swift
var popupMode: PopupMode {
    get { PopupMode(rawValue: popupModeRaw) ?? .expandable }
    set { popupModeRaw = newValue.rawValue }
}
```

- [ ] **Step 4: 编译验证**

Run: `xcodebuild -project TranslateSnap.xcodeproj -scheme TranslateSnap -configuration Debug build -quiet`
Expected: `BUILD SUCCEEDED`

如编译报 `PopupMode` 某处仍被引用，grep 定位后删除该引用。

Run: `grep -rn "PopupMode\|popupMode" TranslateSnap/ || true`
Expected: 只剩 `PopupPositionMode` 相关命中。

- [ ] **Step 5: commit**

```bash
git add TranslateSnap/Settings/SettingsSubViews.swift \
        TranslateSnap/Settings/SettingsView.swift \
        TranslateSnap/Utilities/AppSettings.swift
git commit -m "feat(settings): wire position/pin toggles, add prompts tab, remove PopupMode"
git push origin main
```

---

## Task 9: 清理 `buildSystemPrompt` 死代码

**Files:**
- Modify: `TranslateSnap/Translation/TranslationModels.swift`
- Modify: `TranslateSnap/SelectionTranslate/SelectionTranslateManager.swift`
- Modify: `TranslateSnap/ScreenshotCapture/ScreenshotCaptureManager.swift`

> Task 6 之后 SelectionTranslateManager/ScreenshotCaptureManager 已不再直接构造 `TranslationRequest`。本 Task 确认并清理。

- [ ] **Step 1: grep 检查 `buildSystemPrompt` 剩余调用**

Run: `grep -rn "buildSystemPrompt" TranslateSnap/`
Expected: 只有 `TranslationModels.swift` 自己的定义。（若还有其他文件出现则删除）

- [ ] **Step 2: 删除 `buildSystemPrompt` 定义**

删除 `TranslationModels.swift` 中 `class TranslationEngine` 的整个 `buildSystemPrompt` 静态方法（约第 46-60 行）。保留 `renderPrompt`。

- [ ] **Step 3: 编译验证**

Run: `xcodebuild -project TranslateSnap.xcodeproj -scheme TranslateSnap -configuration Debug build -quiet`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: commit**

```bash
git add TranslateSnap/Translation/TranslationModels.swift
git commit -m "refactor(translation): remove dead buildSystemPrompt"
git push origin main
```

---

## Task 10: 手动验证 + 更新 PROJECT_STATUS.md

**Files:**
- Modify: `PROJECT_STATUS.md`

- [ ] **Step 1: 运行应用**

Run: `xcodebuild -project TranslateSnap.xcodeproj -scheme TranslateSnap -configuration Debug -derivedDataPath .build build && open .build/Build/Products/Debug/TranslateSnap.app`

Expected: 应用启动，菜单栏出现图标。（若提示权限，允许辅助功能与屏幕录制。）

- [ ] **Step 2: 场景 1 — 固定模式 + center-top 默认**

1. 设置 → 通用 → 位置模式 = "固定位置"
2. 触发截图翻译 → 弹窗应出现在屏幕中上方
3. 触发划词翻译 → 也出现在屏幕中上方

Expected: 两种触发位置一致。

- [ ] **Step 3: 场景 2 — 固定模式拖动 + 记忆**

1. 在弹窗可视区域拖动到屏幕左下角
2. 关闭弹窗
3. 再次触发（任一种）

Expected: 弹窗出现在上一次拖动的位置（左下角）。

- [ ] **Step 4: 场景 3 — 重置位置**

1. 设置 → 通用 → "重置位置"按钮
2. 再次触发

Expected: 弹窗回到 center-top。

- [ ] **Step 5: 场景 4 — 跟随指针模式**

1. 设置 → 位置模式 = "跟随指针"
2. 触发划词翻译 → 弹窗贴鼠标
3. 拖动弹窗到其他地方，关闭
4. 再次触发

Expected: 依然贴鼠标（不记拖动位置）。

- [ ] **Step 6: 场景 5 — 钉住**

1. 打开弹窗，点击大头针图标
2. 点击屏幕其他位置 → 弹窗不关闭
3. 按 ESC → 弹窗不关闭
4. 再次触发翻译快捷键 → 旧弹窗关闭（被新 session 取代），新弹窗也处于钉住状态（defaultPinned=true 持久化了）
5. 点一下大头针取消钉住，关闭，再触发 → 新弹窗回到默认非钉住

Expected: 符合上述行为。

- [ ] **Step 7: 场景 6 — 自定义提示词增删改**

1. 设置 → 提示词 → 添加
2. 名称 "润色"，prompt "对下列内容进行润色，使其更自然流畅。只输出润色结果。"
3. 保存，触发翻译 → 弹窗多出第三张"润色"卡片并并行流式
4. 设置 → 关闭"解释"的 toggle → 再次触发 → 只剩"翻译"和"润色"
5. 拖动"润色"到第一位 → 再次触发 → 顺序变化
6. 删除"润色" → 恢复 2 张

Expected: 每步都按预期反应。

- [ ] **Step 8: 场景 7 — 错误卡片不影响其他卡片**

1. 设置 → API → 把 Base URL 改为 `https://invalid.example.com`
2. 触发翻译

Expected: 所有卡片都错误（因为 provider 同一个）。把一张的"重试"点一下验证 retry 入口存在。恢复 Base URL。

**（可选增强）**：若想测试"单卡失败其他成功"，需要更精细——例如一个合法 Base URL 但一个自定义 tab 用了触发 provider 拒绝的内容。此点放到后续增强。

- [ ] **Step 9: 场景 8 — 全部隐藏时的空提示**

1. 设置 → 提示词 → 把两个内置都关掉
2. 触发翻译

Expected: 弹窗显示"暂无可用的提示词"+"打开设置"按钮。

- [ ] **Step 10: 更新 PROJECT_STATUS.md**

修改 `PROJECT_STATUS.md`：

1. "最后更新" 改为 `YYYY-MM-DD`（当天）
2. 需求进度表新增一行：`| 弹窗位置/钉住/自定义提示词 | ✅ 完成 | spec + 10 tasks，手动验证 8 场景通过 |`
3. 关键决策追加一行：`- YYYY-MM-DD: PopupMode 删除；StreamingTranslationViewModel 删除；TranslationRequest 加 systemPrompt 字段；每标签独立 API 调用`
4. "下次继续" 下把 `【进行中 P0】` 那一条改成已完成并勾选

- [ ] **Step 11: 最终 commit**

```bash
git add PROJECT_STATUS.md
git commit -m "docs: mark popup position + custom prompts feature complete"
git push origin main
```

---

## Self-Review 结果

- **Spec 覆盖**：PromptTab → Task 1；AppSettings → Task 2、Task 8；TranslationRequest.systemPrompt → Task 3；PopupSessionViewModel → Task 4；popup 子组件 → Task 5；PopupView + PopupWindowController + 拖动 + pin + ESC → Task 6；PromptsSettingsView → Task 7；GeneralSettingsView 调整 + 5-tab + 删 PopupMode → Task 8；死代码清理 → Task 9；手动验证 8 场景 + 文档 → Task 10。全部覆盖。

- **Placeholder 扫描**：无 TBD/TODO。Task 6 Step 2 内 `observePinChange` 方法里的注释说明"由 PopupRootView onChange 回调"，Step 3 已显式加了 `.onChange(of: viewModel.pinned)` 的代码。没有未填充区。

- **类型一致性**：`PopupSessionViewModel` / `PopupSessionViewModel.TabState` / `PopupSessionViewModel.TriggerKind` / `PromptTab` / `PopupPositionMode` / `renderPrompt` 在各 Task 中的使用签名一致。`PopupWindowController.show(session:)` 单一入口，全部 caller 一致。

- **范围**：单一 plan 交付一组关联功能；未超纲（不含快捷键自定义录制与 Keychain 迁移）。
