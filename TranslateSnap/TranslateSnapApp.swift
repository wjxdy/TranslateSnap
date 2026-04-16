import SwiftUI

@main
struct TranslateSnapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("TranslateSnap", systemImage: "text.viewfinder") {
            Button("截图翻译  \(AppSettings.shared.screenshotHotkeyDisplay)") {
                ScreenshotCaptureManager.shared.start()
            }

            Button("划词翻译  \(AppSettings.shared.selectionHotkeyDisplay)") {
                Task { await SelectionTranslateManager.shared.translateSelection() }
            }

            Divider()

            Button("设置") {
                appDelegate.openSettings()
            }
            .keyboardShortcut(",", modifiers: [.command])

            Divider()

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }

        Settings {
            SettingsView()
        }
    }
}
