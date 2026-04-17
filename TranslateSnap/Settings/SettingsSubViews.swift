import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @AppStorage("targetLanguage") private var targetLanguage = "简体中文"
    @AppStorage("popupMode") private var popupModeRaw = PopupMode.expandable.rawValue
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    private let languages = ["简体中文", "繁體中文", "English", "日本語", "한국어", "Français", "Deutsch", "Español"]

    var body: some View {
        Form {
            Picker("目标语言", selection: $targetLanguage) {
                ForEach(languages, id: \.self) { Text($0).tag($0) }
            }

            Picker("弹窗模式", selection: $popupModeRaw) {
                ForEach(PopupMode.allCases, id: \.rawValue) {
                    Text($0.displayName).tag($0.rawValue)
                }
            }

            Toggle("开机启动", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { newValue in
                    if #available(macOS 13.0, *) {
                        let service = SMAppService.mainApp
                        try? newValue ? service.register() : service.unregister()
                    }
                }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct TranslationSettingsView: View {
    @AppStorage("translationStyle") private var styleRaw = TranslationStyle.professional.rawValue
    @AppStorage("showOriginal") private var showOriginal = true

    var body: some View {
        Form {
            Picker("翻译风格", selection: $styleRaw) {
                ForEach(TranslationStyle.allCases, id: \.rawValue) {
                    Text($0.displayName).tag($0.rawValue)
                }
            }
            Toggle("显示原文", isOn: $showOriginal)
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct ShortcutsSettingsView: View {
    @AppStorage("screenshotKeyCode") private var screenshotKeyCode = 18
    @AppStorage("screenshotModifiers") private var screenshotModifiers = 0
    @AppStorage("selectionKeyCode") private var selectionKeyCode = 16
    @AppStorage("selectionModifiers") private var selectionModifiers = 0

    var body: some View {
        Form {
            KeyRecorderView(label: "截图翻译", keyCode: $screenshotKeyCode, modifiers: $screenshotModifiers)
            KeyRecorderView(label: "划词翻译", keyCode: $selectionKeyCode, modifiers: $selectionModifiers)
            Text("点击快捷键区域后，按下新的组合键即可录制（需包含 ⌘/⌃/⌥ 修饰键）")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct APISettingsView: View {
    @AppStorage("aiProvider") private var providerRaw = AIProvider.openai.rawValue
    @AppStorage("customBaseURL") private var customBaseURL = ""
    @AppStorage("customModel") private var customModel = ""
    @State private var apiKey = ""
    @State private var testStatus: String? = nil
    @State private var isTesting = false

    var body: some View {
        Form {
            Picker("AI 服务商", selection: $providerRaw) {
                ForEach(AIProvider.allCases, id: \.rawValue) {
                    Text($0.displayName).tag($0.rawValue)
                }
            }

            SecureField("API Key", text: $apiKey)
                .onAppear { apiKey = AppSettings.shared.apiKey }
                .onChange(of: apiKey) { v in AppSettings.shared.apiKey = v }

            let currentProvider = AIProvider(rawValue: providerRaw) ?? .openai
            TextField("Base URL（留空使用 \(currentProvider.defaultBaseURL)）", text: $customBaseURL)
                .textFieldStyle(.roundedBorder)
            TextField("模型名（留空使用 \(currentProvider.defaultModel)）", text: $customModel)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("测试连接") {
                    isTesting = true
                    testStatus = nil
                    Task {
                        do {
                            let settings = AppSettings.shared
                            let req = TranslationRequest(
                                text: "hello",
                                targetLanguage: settings.targetLanguage,
                                style: .natural,
                                systemPrompt: "Reply with a single short greeting in \(settings.targetLanguage)."
                            )
                            let provider = TranslationEngine.provider(for: settings)
                            _ = try await provider.translate(req)
                            testStatus = "✅ 连接成功"
                        } catch {
                            testStatus = "❌ \(error.localizedDescription)"
                        }
                        isTesting = false
                    }
                }
                .disabled(isTesting || apiKey.isEmpty)

                if isTesting { ProgressView().scaleEffect(0.7) }
                if let status = testStatus { Text(status).font(.caption) }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
