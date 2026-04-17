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
                (NSApp.delegate as? AppDelegate)?.openSettings()
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

    /// Called by PopupRootView.onChange(of: viewModel.pinned).
    func pinStateDidChange(_ pinned: Bool) {
        guard let panel = panel else { return }
        applyPin(pinned, panel: panel)
    }

    // MARK: - Position

    private func computeOrigin(windowSize: NSSize) -> NSPoint {
        let settings = AppSettings.shared
        let mode = settings.popupPositionMode
        let screen = currentScreen(for: mode)
        let visible = screen.visibleFrame

        switch mode {
        case .followCursor:
            let cursor: NSPoint
            if let session = session, case .selection(let c) = session.trigger {
                cursor = c
            } else {
                cursor = NSEvent.mouseLocation
            }
            let p = NSPoint(x: cursor.x + 12, y: cursor.y - windowSize.height - 12)
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
        // Only persist drag position in fixed mode, and only when not pinned
        // (pinned drags are transient by design).
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
