# TranslateSnap

<p align="center">
  <img src="TranslateSnap/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="TranslateSnap Logo">
</p>

<p align="center">
  <b>macOS 截图翻译 & 划词翻译工具</b><br>
  截图识别文字、选中即翻译，AI 驱动，流式输出
</p>

---

## 功能特性

- **截图翻译** — 框选屏幕区域，OCR 识别文字后自动翻译
- **划词翻译** — 选中任意文字，按快捷键即翻译
- **流式输出** — 翻译结果逐字显示，无需等待
- **多 AI 服务商** — 支持 Claude、OpenAI、Kimi (Moonshot)、自定义接口
- **自定义快捷键** — 可录制任意组合键
- **三种翻译风格** — 直译 / 意译 / 专业解释
- **跟随系统外观** — 自动适配亮色 / 深色模式
- **菜单栏常驻** — 后台运行，随时调用

## 安装

### 从 Release 下载

1. 前往 [Releases](https://github.com/wjxdy/TranslateSnap/releases) 页面
2. 下载最新版 `TranslateSnap.zip`
3. 解压后将 `TranslateSnap.app` 拖到「应用程序」文件夹
4. 双击打开

### 从源码编译

```bash
# 需要 Xcode 16+ 和 XcodeGen
brew install xcodegen
git clone https://github.com/wjxdy/TranslateSnap.git
cd TranslateSnap
xcodegen generate
xcodebuild -scheme TranslateSnap -configuration Release build
```

## 使用说明

### 首次启动

1. 双击打开 TranslateSnap，会自动弹出设置窗口
2. 在 **API** 页面选择 AI 服务商，填写 API Key
3. 点击「测试连接」确认可用
4. 关闭设置窗口，App 在后台运行

### 权限设置

TranslateSnap 需要以下 macOS 权限：

| 权限 | 用途 | 设置路径 |
|------|------|----------|
| **辅助功能** | 全局快捷键 + 读取选中文字 | 系统设置 → 隐私与安全性 → 辅助功能 |
| **屏幕录制** | 截图翻译功能 | 系统设置 → 隐私与安全性 → 屏幕录制 |

> 添加权限后可能需要重启 App 才能生效。

### 截图翻译

1. 按截图快捷键（默认 `⌘⇧1`）
2. 屏幕出现十字光标（macOS 原生截图 UI）
3. 框选包含文字的区域
4. 松开鼠标，弹窗显示翻译结果（流式输出）
5. 按 `ESC` 关闭弹窗

### 划词翻译

1. 在任意 App 中选中一段文字
2. 按划词快捷键（默认 `⌘⇧Y`）
3. 弹窗在鼠标附近显示翻译结果（流式输出）
4. 按 `ESC` 关闭弹窗

### 自定义快捷键

1. 双击 TranslateSnap.app 打开设置
2. 进入「快捷键」页面
3. 点击快捷键区域，按下新的组合键（需包含 ⌘/⌃/⌥ 修饰键）
4. 立即生效

### 设置 API

支持以下 AI 服务商：

| 服务商 | 默认 Base URL | 默认模型 |
|--------|--------------|---------|
| Claude | `https://api.anthropic.com` | `claude-haiku-4-5-20251001` |
| OpenAI | `https://api.openai.com` | `gpt-4o-mini` |
| Kimi | `https://api.moonshot.cn` | `moonshot-v1-8k` |
| 自定义 | 自行填写 | 自行填写 |

- **Base URL** 和 **模型名** 均可自定义覆盖
- API Key 存储在本地 UserDefaults，不会上传

### 退出 App

打开设置窗口（双击 App 图标），点击右下角「退出 TranslateSnap」按钮。

## 技术栈

- Swift 5.9 + SwiftUI
- macOS 13.0+
- Vision (OCR)
- Accessibility API
- URLSession (SSE 流式)

## License

MIT
