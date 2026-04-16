import AppKit
import SwiftUI

@MainActor
class PopupWindowController {
    static let shared = PopupWindowController()
    private var panel: NSPanel?
    private var eventMonitor: Any?

    /// 划词翻译：弹窗在鼠标附近
    func showStream(viewModel: StreamingTranslationViewModel, at point: NSPoint) {
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        showStreamInternal(viewModel: viewModel) { constrainedSize in
            var origin = NSPoint(x: point.x + 12, y: point.y - constrainedSize.height - 12)
            origin.x = max(screenFrame.minX + 8, min(origin.x, screenFrame.maxX - constrainedSize.width - 8))
            origin.y = max(screenFrame.minY + 8, min(origin.y, screenFrame.maxY - constrainedSize.height - 8))
            return origin
        }
    }

    /// 截图翻译：弹窗在屏幕中间偏上
    func showStreamCentered(viewModel: StreamingTranslationViewModel) {
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        showStreamInternal(viewModel: viewModel) { constrainedSize in
            NSPoint(
                x: screenFrame.midX - constrainedSize.width / 2,
                y: screenFrame.midY + screenFrame.height * 0.1 - constrainedSize.height / 2
            )
        }
    }

    private func showStreamInternal(viewModel: StreamingTranslationViewModel, position: (NSSize) -> NSPoint) {
        close()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 240),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false

        let popupView = StreamPopupView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: popupView)
        hostingView.frame = panel.contentView!.bounds
        hostingView.autoresizingMask = [NSView.AutoresizingMask.width, NSView.AutoresizingMask.height]
        panel.contentView?.addSubview(hostingView)

        let maxHeight: CGFloat = 500
        let fittingSize = hostingView.fittingSize
        let constrainedSize = NSSize(
            width: fittingSize.width,
            height: min(fittingSize.height, maxHeight)
        )
        panel.setContentSize(constrainedSize)
        panel.setFrameOrigin(position(constrainedSize))
        panel.makeKeyAndOrderFront(nil)

        self.panel = panel
        HotkeyManager.shared.activePopupController = self

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    func close() {
        panel?.close()
        panel = nil
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        HotkeyManager.shared.activePopupController = nil
    }
}
