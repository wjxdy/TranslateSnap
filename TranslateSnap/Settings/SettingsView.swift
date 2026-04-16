import SwiftUI

struct SettingsView: View {
    enum Tab: String, CaseIterable {
        case general, translation, shortcuts, api

        var label: String {
            switch self {
            case .general: return "通用"
            case .translation: return "翻译"
            case .shortcuts: return "快捷键"
            case .api: return "API"
            }
        }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .translation: return "globe"
            case .shortcuts: return "keyboard"
            case .api: return "key"
            }
        }
    }

    @State private var selectedTab: Tab = .general

    var body: some View {
        NavigationSplitView {
            List(Tab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.label, systemImage: tab.icon)
            }
            .navigationSplitViewColumnWidth(160)
        } detail: {
            VStack(spacing: 0) {
                Group {
                    switch selectedTab {
                    case .general: GeneralSettingsView()
                    case .translation: TranslationSettingsView()
                    case .shortcuts: ShortcutsSettingsView()
                    case .api: APISettingsView()
                    }
                }
                Spacer(minLength: 0)
                Divider()
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Label("退出 TranslateSnap", systemImage: "power")
                    }
                    .controlSize(.regular)
                }
                .padding(12)
            }
        }
        .frame(minWidth: 520, minHeight: 360)
    }
}
