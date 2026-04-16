# 项目进度

## 基本信息
- 项目名称：TranslateSnap
- 当前阶段：开发完成，待真机测试
- 最后更新：2026-04-16

## 需求进度
| 需求 | 状态 | 备注 |
|------|------|------|
| Task 1 — Xcode 项目初始化 | ✅ 完成 | LSUIElement, entitlements, Info.plist 均已配置 |
| Task 2 — AppSettings + KeychainHelper | ✅ 完成 | @AppStorage 封装 + Keychain 安全存储 |
| Task 3 — AppDelegate + 菜单栏图标 | ✅ 完成 | NSStatusBar + NSMenu，含截图/划词/设置/退出 |
| Task 4 — PermissionsManager | ✅ 完成 | 屏幕录制 + 辅助功能权限检查与引导 |
| Task 5 — OverlayWindow（框选截图） | ✅ 完成 | 全屏透明窗口，蓝色描边选区，ESC 取消 |
| Task 6 — OCRService | ✅ 完成 | Vision 框架，支持中英日韩 5 语言 |
| Task 7 — ScreenshotCaptureManager | ✅ 完成 | 编排：选区 → 截图 → OCR → 翻译 → 弹窗 |
| Task 8 — TranslationModels + TranslationEngine | ✅ 完成 | Protocol + 工厂方法，支持多 Provider |
| Task 9 — OpenAIProvider | ✅ 完成 | 支持自定义 Base URL，gpt-4o-mini |
| Task 10 — ClaudeProvider | ✅ 完成 | 使用 claude-haiku-4-5-20251001 |
| Task 11 — PopupView（三种模式） | ✅ 完成 | compact / full / expandable，含复制和朗读 |
| Task 12 — PopupWindowController | ✅ 完成 | NSPanel 浮窗，鼠标定位，点击外部/ESC 关闭 |
| Task 13 — SelectionTranslateManager | ✅ 完成 | CGEventTap 全局快捷键 ⌘⇧Y，AX 读取选中文字 |
| Task 14 — Settings UI | ✅ 完成 | 四个分区：通用/翻译/快捷键/API，含测试连接 |
| Task 15 — 整体串联 + 首次启动引导 | ✅ 完成 | 首次启动自动打开设置窗口 |

## 技术架构
- **技术栈：** Swift 5.9+, SwiftUI, Vision, Accessibility API, URLSession, Keychain, AppKit
- **部署目标：** macOS 13.0+
- **构建工具：** XcodeGen (project.yml) + Xcode
- **沙盒：** 关闭（需 CGEventTap + Accessibility API）
- **代码结构：** 17 个 Swift 文件，部分视图合并（PopupModeViews / SettingsSubViews）

## 编译状态
- ✅ `xcodebuild` BUILD SUCCEEDED（2026-04-15）

## 关键决策
- 2026-04-15: 快捷键暂时硬编码为 ⌘⇧Y（划词）和 ⌘⇧1（截图），自定义录制功能标注为后续版本
- 2026-04-15: ClaudeProvider 使用 claude-haiku-4-5-20251001 模型（速度快、成本低）
- 2026-04-15: 沙盒关闭（app-sandbox: false），以支持 CGEventTap 和 Accessibility API
- 2026-04-15: 三个模式视图合并到 PopupModeViews.swift，四个设置视图合并到 SettingsSubViews.swift

## 下次继续
- [ ] 真机运行测试：截图翻译流程端到端验证
- [ ] 真机运行测试：划词翻译流程端到端验证
- [ ] 填写 API Key 后测试"测试连接"功能
- [ ] 可选：实现快捷键自定义录制（KeyRecorderView）
- [ ] 可选：App 图标设计
