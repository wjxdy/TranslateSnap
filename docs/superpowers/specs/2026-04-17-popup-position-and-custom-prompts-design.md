# 设计：弹窗位置模式、钉住、可拖动、自定义提示词标签

- 日期：2026-04-17
- 状态：待评审 → 实现
- 涉及模块：UI/PopupWindowController、UI/PopupView、Settings、Translation、Utilities/AppSettings、HotkeyManager

## 背景

TranslateSnap 目前弹窗行为：

- 划词翻译弹窗贴近鼠标，截图翻译弹窗在屏幕中上部
- 弹窗不可移动、不可钉住，点击外部或按 ESC 关闭
- 只有一个硬编码渲染（忽略了 `PopupMode` 的三档枚举）
- 一次 API 调用同时产出"翻译"+"解释"，用 `\n---\n` 分隔

用户希望：

1. 弹窗位置可选"固定 / 跟随指针"，固定时可拖动并记住位置
2. 弹窗可钉住到最前（设置默认 + 弹窗上的大头针按钮）
3. 每个提示词对应弹窗中的一张"卡片"，可自定义名字和 prompt、可隐藏、可添加、可删除（内置除外）
4. 截图和划词共用同一套标签列表

## 目标与非目标

### 目标

- 引入可配置的"提示词标签"数据模型，每个标签独立 API 调用并并行流式
- 弹窗定位统一函数化，支持 `fixed` / `followCursor` 两种模式，记忆拖动位置
- 弹窗增加钉住（pushpin）能力：禁止点外部/ESC 关闭、提升层级、持久化为默认状态
- 设置新增"提示词"分区做标签管理，通用分区补充定位与钉住开关
- 删除未使用的 `PopupMode` 设置

### 非目标

- 快捷键自定义录制（另立任务）
- Keychain 迁移 API Key（另立任务）
- 每个标签绑定不同 AI 模型或语言（YAGNI）
- 多窗口并存（仍然一个 NSPanel，多个卡片）

## 需求确认

| 条目 | 决定 |
|---|---|
| 每标签执行模型 | 每个标签独立 API 调用，并行流式 |
| 位置模式范围 | 全局一个设置，截图和划词共用 |
| 位置记忆粒度 | 全局一个记忆位置 |
| 大头针行为 | 禁外部/ESC 关闭 + 提升层级 + 持久化为默认 |
| 标签作用域 | 截图和划词共用同一套 |
| 弹窗 UI | 竖直堆叠卡片（当前布局的多卡片化） |
| 内置标签处理 | 可编辑名字 + prompt；可隐藏；不可删除 |
| `popupPositionMode` 默认值 | `fixed`（center-top） |
| 现有 `PopupMode` 枚举 | 删除 |

## 总体架构

```
                          ┌──────────────────────────┐
                          │       AppSettings        │
                          │ promptTabs (JSON)        │
                          │ popupPositionMode        │
                          │ fixedPositionX/Y         │
                          │ defaultPinned            │
                          └────────────┬─────────────┘
                                       │ read
┌──────────────────┐     start      ┌──┴──────────────────────┐
│ ScreenshotMgr    │───────────────▶│ PopupSessionViewModel    │
│ SelectionMgr     │ originalText   │ tabs / states / pinned  │
└──────────────────┘                │ spawn Task per tab      │
                                    └──┬──────────────┬───────┘
                                       │              │
                                       ▼              ▼
                            ┌─────────────────┐ ┌─────────────────┐
                            │ TranslationEngine│ │ PopupWindowCtrl │
                            │ renderPrompt()  │ │ show(mode,pos)  │
                            │ provider(for:)  │ │ pin toggle/drag │
                            └────────┬────────┘ └────────┬────────┘
                                     │                   │
                                     ▼                   ▼
                         Provider.translateStream    NSPanel
                         (uses systemPrompt from     .floating / .statusBar
                          request, one call per tab)
```

## 数据模型

### `PromptTab`

```swift
struct PromptTab: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var systemPrompt: String     // 可含 {targetLanguage} {style} 占位符
    var visible: Bool
    var isBuiltin: Bool
}
```

**持久化**：`@AppStorage("promptTabs")` 存 JSON String。加载时解码失败（或空）→ 写入默认两项：

```
id=UUID, name="翻译", isBuiltin=true, visible=true,
systemPrompt="将下列文字翻译为 {targetLanguage}，风格：{style}。只输出翻译结果，不要额外说明。"

id=UUID, name="解释", isBuiltin=true, visible=true,
systemPrompt="解释下列内容（术语、背景、典型用法）。如果没有可解释内容，直接输出'无'。"
```

标签在数组中的顺序即弹窗显示顺序。

### `PopupPositionMode`

```swift
enum PopupPositionMode: String, Codable, CaseIterable {
    case fixed
    case followCursor
}
```

### 新增 `AppSettings` 字段

```
@AppStorage("popupPositionMode") var popupPositionModeRaw = PopupPositionMode.fixed.rawValue
@AppStorage("fixedPositionX") var fixedPositionX: Double = .nan   // nan = 未拖动过
@AppStorage("fixedPositionY") var fixedPositionY: Double = .nan
@AppStorage("defaultPinned") var defaultPinned: Bool = false
@AppStorage("promptTabs") var promptTabsJSON: String = ""         // 空 = 首次启动 seed 默认

// computed
var popupPositionMode: PopupPositionMode { ... }
var savedFixedPosition: NSPoint? { ... }   // 读 NaN 返回 nil
func setSavedFixedPosition(_ point: NSPoint?)
var promptTabs: [PromptTab] { get set }    // get 解码，set 编码并写入
```

删除字段：`popupModeRaw`，删除 `PopupMode` 枚举。

## 组件变更

### `TranslationEngine` / `TranslationRequest`

`TranslationRequest` 新增 `systemPrompt: String`（caller 预渲染）。移除 provider 内部调 `buildSystemPrompt` 的分支。

```swift
struct TranslationRequest {
    let text: String
    let targetLanguage: String
    let style: TranslationStyle
    let systemPrompt: String            // NEW
}

extension TranslationEngine {
    static func renderPrompt(
        _ template: String,
        targetLanguage: String,
        style: TranslationStyle
    ) -> String
    // 替换 {targetLanguage} 和 {style}（style 文案用现有三档描述）
}
```

Provider 逻辑改成直接把 `request.systemPrompt` 作为 system message 塞给 API。

**破坏性变更**：`buildSystemPrompt(targetLanguage:style:)` 的旧固定格式（带 `---` 分隔符）移除。因为每个 tab 现在独立调用独立输出，不再需要分隔符解析。

### `PopupSessionViewModel`（新，替代 `StreamingTranslationViewModel`）

```swift
@MainActor final class PopupSessionViewModel: ObservableObject {
    struct TabState: Equatable {
        var text: String = ""
        var isLoading: Bool = true
        var error: String? = nil
    }

    let originalText: String
    @Published private(set) var tabs: [PromptTab]
    @Published private(set) var states: [UUID: TabState] = [:]
    @Published var pinned: Bool

    private var tasks: [UUID: Task<Void, Never>] = [:]

    init(originalText: String) {
        self.originalText = originalText
        self.tabs = AppSettings.shared.promptTabs.filter { $0.visible }
        self.pinned = AppSettings.shared.defaultPinned
    }

    func start()                      // 为每个 tab spawn 一个 Task
    func retry(tabID: UUID)
    func cancelAll()
    func togglePin()                  // 翻转并持久化
}
```

每个 Task：

```
let prompt = TranslationEngine.renderPrompt(tab.systemPrompt, ...)
let stream = provider.translateStream(TranslationRequest(
    text: originalText,
    targetLanguage: settings.targetLanguage,
    style: settings.translationStyle,
    systemPrompt: prompt
))
for try await chunk in stream {
    states[tab.id]?.text.append(chunk)
}
states[tab.id]?.isLoading = false
// catch: states[tab.id]?.error = ...
```

### `PopupWindowController`

```swift
func show(
    session: PopupSessionViewModel,
    cursor: NSPoint?            // 划词传鼠标位置，截图传 nil
)
```

内部根据 `AppSettings.shared.popupPositionMode` + `savedFixedPosition` + `cursor` 计算 origin（见下）。

**定位决策**

```
computeOrigin(windowSize, cursor?) -> NSPoint:
  switch mode {
    case .followCursor where cursor != nil:
        return constrain(cursor + (+12, -12), to: screen)
    case .fixed:
        if let saved = savedFixedPosition { return constrain(saved, to: screen) }
        return centerTop(of: screen, windowSize)
    default:
        return centerTop(of: screen, windowSize)
  }

centerTop(screen, size):
  x = screenFrame.midX - size.width/2
  y = screenFrame.midY + screenFrame.height*0.1 - size.height/2
```

跨屏：`constrain` 用当前鼠标所在屏幕（followCursor）或 saved 位置命中的屏幕（fixed）；兜底使用 main screen。

**钉住实现**

```swift
func applyPin(_ pinned: Bool) {
    panel?.level = pinned ? .statusBar : .floating
    if pinned {
        removeGlobalMouseDownMonitor()
    } else {
        installGlobalMouseDownMonitor()
    }
}
```

同时 `HotkeyManager` 的 ESC 关闭逻辑需读 `controller.isPinned`，钉住时忽略 ESC。

**拖动**

```swift
panel.isMovableByWindowBackground = true
NotificationCenter 监听 NSWindow.didMoveNotification {
    guard settings.popupPositionMode == .fixed && !session.pinned else { return }
    // pinned 不保存，符合"钉住是临时状态"语义
    settings.setSavedFixedPosition(panel.frame.origin)
}
```

> 注：钉住时也允许拖动，但拖动位置不写入 savedFixedPosition（避免污染"常态"记忆）。取消钉住后拖动才写入。

**关闭**

`close()` 里先 `session.cancelAll()` 再 `panel.orderOut(nil)`。

## UI 变更

### `PopupView`

```
VStack(spacing: 0) {
    HeaderBar()                                // 右上角: pushpin + close
    Divider()
    ScrollView {
        VStack(spacing: 12) {
            if settings.showOriginal { OriginalCard(text) }
            ForEach(session.tabs) { tab in
                TabCard(tab: tab, state: binding)
            }
            if session.tabs.isEmpty {
                EmptyHintView()               // "请到设置中启用至少一个提示词"
            }
        }
        .padding(12)
    }
}
```

- `HeaderBar`：左侧显示触发类型的图标（划词/截图）可选；右侧 pushpin 图标（`pin.slash` / `pin.fill`）+ close 按钮
- `TabCard`：标题行（名字 + loading 小菊花 / 错误图标 + 复制/朗读按钮） + 正文（多行文本，可选中）
- `OriginalCard`：现有原文显示逻辑迁移
- `EmptyHintView`：文案 + 打开设置的按钮

### 设置窗口

`SettingsView` 的 sidebar 由 4 项变 5 项：`通用 / 翻译 / 快捷键 / 提示词 / API`

**`GeneralSettingsView` 补充**：

```
Section("弹窗") {
    Picker("位置模式", popupPositionMode): [固定, 跟随指针]
    if mode == .fixed && savedFixedPosition != nil {
        Button("重置位置", action: clearSavedPosition)
    }
    Toggle("默认钉住", isOn: $defaultPinned)
}
```

删除原有"弹窗模式"Picker。

**新增 `PromptsSettingsView`**：

```
List {
    ForEach(tabs) { tab in
        HStack {
            Toggle("", isOn: $tab.visible)
            Text(tab.name)
            Spacer()
            if tab.isBuiltin { Text("内置").foregroundStyle(.secondary) }
            Button("编辑") { editing = tab }
            if !tab.isBuiltin {
                Button(role: .destructive) { deleteTab(tab) } label: { Image(systemName: "trash") }
            }
        }
    }
    .onMove(perform: moveTabs)    // 拖动排序
}
Button("添加新提示词") { editing = PromptTab.new() }
.sheet(item: $editing) { tab in PromptEditorSheet(tab: tab) }
```

**`PromptEditorSheet`**：

```
Form {
    TextField("名称", text: $draft.name)
    TextEditor(text: $draft.systemPrompt)  // 6 行高
    Text("占位符：{targetLanguage} / {style} 会被替换").caption
    Toggle("在弹窗中显示", isOn: $draft.visible)
}
.toolbar { Button("取消") / Button("保存") }
```

校验：名称非空、systemPrompt 非空。

## 数据流

### 弹窗触发到关闭

```
1. HotkeyManager 捕获 ⌘⇧Y / ⌘⇧1
2. SelectionMgr / ScreenshotMgr 取得 originalText
3. 构造 PopupSessionViewModel(originalText: ...)
4. 调 PopupWindowController.show(session: vm, cursor: ...)
5. show() 计算 origin、配 panel、显示
6. SwiftUI 启动，vm.start() 被 PopupView.onAppear 调用
7. 每个 visible tab 并行 Task → provider.translateStream
8. 每个 chunk 更新 states[tab.id].text → UI 流式刷新
9. 用户交互：
   - 拖动 → NSWindow.didMove → 写 savedFixedPosition
   - 点 pushpin → session.togglePin → controller.applyPin → 持久化 defaultPinned
   - 点外部（未钉住） → close()
   - 按 ESC（未钉住） → HotkeyManager → close()
10. close() → session.cancelAll() → panel.orderOut
```

### 设置 → 数据

```
promptTabs 编辑:
  PromptsSettingsView 读写 AppSettings.promptTabs (JSON 编解码)
  保存时立即写回 UserDefaults；不需通知弹窗（弹窗在打开时 snapshot）

位置 / 钉住:
  Picker / Toggle 直接绑 @AppStorage，读写 UserDefaults
```

## 错误处理

- **单标签流失败**：`TabState.error` 写入字符串，UI 在那张卡片上显示错误 + "重试"按钮，其他卡片不受影响
- **所有 visible 为 false**：弹窗仍打开（会被截图/划词触发），展示 EmptyHintView
- **promptTabs JSON 解码失败**：视为空，重新 seed 默认并写回
- **savedFixedPosition 不在当前屏幕范围**：fallback 到 center-top（不删除记忆，用户切屏回去仍可用）
- **设置中保存空提示词**：保存按钮禁用
- **删除内置标签按钮**：不渲染，无法触发
- **pinned 状态下 HotkeyManager 收到 ⌘⇧Y 再次触发**：关掉旧弹窗（含 pinned）新开一个 session，defaultPinned 决定新弹窗是否钉

## 测试策略

项目当前没有单元测试框架。本设计下列测试可在 Swift Testing 或 XCTest 中添加（若引入测试 target）：

- `PromptTab` 编解码：空数组、损坏 JSON、正常路径
- `TranslationEngine.renderPrompt`：占位符替换
- `PopupPositionController.computeOrigin`：fixed+savedNil、fixed+saved、followCursor、跨屏
- `PopupSessionViewModel`：无 visible tab、单 tab 失败、全部失败、cancelAll

**手动验证场景**（对应"验证"任务）：

1. 固定模式：截图 / 划词 触发均居中上方；拖动到左下角；再次触发 → 出现在左下角；"重置位置" → 回居中上方
2. 跟随指针模式：两种触发都贴鼠标，即便上次在某处拖过，第二次仍跟随鼠标
3. 钉住：点大头针 → 点外部不关；按 ESC 不关；再次触发创建新弹窗仍钉住；关闭再触发仍默认钉（defaultPinned=true）
4. 自定义提示词：添加"润色"标签 → 写 prompt → 保存；触发翻译 → 第三张卡片出现并流式
5. 隐藏内置"解释" → 触发 → 只出现"翻译"一张卡
6. 全部隐藏 → 触发 → 显示 EmptyHint 并能点击打开设置
7. 单标签失败（故意给错 API Key 然后切回）→ 该卡片出错，其他卡仍正常

## 迁移与兼容

- 无线上用户，无数据迁移负担
- 首次启动（`promptTabsJSON == ""`）→ seed 两项内置默认
- 旧 `popupModeRaw` 字段静默忽略

## 实现拆分（给 writing-plans 的输入）

> 下面顺序即推荐实现顺序。

1. **数据层**：`PromptTab` 模型、`PopupPositionMode`、`AppSettings` 增删字段、JSON 编解码与默认 seed
2. **Translation 层**：`TranslationRequest.systemPrompt`、`TranslationEngine.renderPrompt`、两个 Provider 改用传入的 prompt
3. **弹窗 VM**：`PopupSessionViewModel` 新建，`StreamingTranslationViewModel` 删除或保留仅作参考
4. **弹窗 UI**：`PopupView` / `TabCard` / `HeaderBar` / `OriginalCard` / `EmptyHintView`；pushpin 切换
5. **PopupWindowController**：统一 `show`、定位函数、可拖动、位置保存、applyPin、HotkeyManager ESC 协同
6. **设置 UI**：`GeneralSettingsView` 调整；新增 `PromptsSettingsView` + `PromptEditorSheet`
7. **连线**：SelectionTranslateManager、ScreenshotCaptureManager、AppDelegate 改为用新签名
8. **验证**：手动跑 7 个场景；xcodebuild 编译通过；若有条件加 Playwright/脚本化 UI 测试（本项目是 macOS 原生，Playwright 不适用 → 改为手动验证清单）

## 待确认 / 风险

- 目前 `Settings/SettingsSubViews.swift` 已合并多个视图，新增 `PromptsSettingsView` 放同一文件还是拆出 `Settings/PromptsSettingsView.swift`：推荐拆出（单一职责）
- NSPanel 在 `isMovableByWindowBackground = true` 的同时是否仍需额外允许某区域不可拖（比如标题行的按钮）：pushpin / close 按钮按下会被 AppKit 自动视作按钮点击不触发 drag；TextEditor 选中文本拖动不会移动窗口；若实测发现冲突，使用自定义 drag area
- 钉住状态下拖动位置不保存 — 待用户实测反馈是否符合预期
