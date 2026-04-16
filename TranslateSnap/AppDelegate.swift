import AppKit
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("Menu bar app should stay running")
        HotkeyManager.shared.start()

        if !AppSettings.shared.hasLaunchedBefore {
            AppSettings.shared.hasLaunchedBefore = true
            PermissionsManager.shared.checkAll()
        }
        openSettings()
    }

    /// 用户在 Finder 中双击 app 图标时触发（app 已在后台运行的情况）
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    /// 关闭设置窗口后 app 不退出，继续后台运行
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView()
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = "TranslateSnap 设置"
            window.styleMask = [NSWindow.StyleMask.titled, .closable, .resizable]
            window.setContentSize(NSSize(width: 520, height: 360))
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
