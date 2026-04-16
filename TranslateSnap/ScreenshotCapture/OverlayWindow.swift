import AppKit

/// macOS 原生截图风格的框选覆盖窗口
class OverlayWindow: NSWindow {
    var onSelection: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: NSPoint = .zero
    private var currentPoint: NSPoint = .zero
    private var isDragging = false

    private let overlayView = OverlayContentView()

    init() {
        let screenFrame = NSScreen.main?.frame ?? .zero
        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.isReleasedWhenClosed = false
        self.contentView = overlayView
        NSCursor.crosshair.set()

        // 入场淡入动画
        self.alphaValue = 0
    }

    func present() {
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.animator().alphaValue = 1.0
        }
    }

    func dismiss(completion: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
            NSCursor.arrow.set()
            completion()
        })
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            let cancel = self.onCancel
            dismiss { cancel?() }
        }
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = event.locationInWindow
        currentPoint = startPoint
        isDragging = true
        overlayView.selectionRect = .zero
        overlayView.needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = event.locationInWindow
        overlayView.selectionRect = selectionRect()
        overlayView.needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        let rect = selectionRect()
        let valid = rect.width > 5 && rect.height > 5
        let onSel = self.onSelection
        let onCan = self.onCancel

        if valid {
            // 转换到屏幕坐标（左下原点 → 左上原点）
            let screenHeight = NSScreen.main?.frame.height ?? 0
            let screenRect = CGRect(
                x: rect.origin.x,
                y: screenHeight - rect.origin.y - rect.height,
                width: rect.width,
                height: rect.height
            )
            dismiss { onSel?(screenRect) }
        } else {
            dismiss { onCan?() }
        }
    }

    private func selectionRect() -> NSRect {
        NSRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
    }
}

/// 绘制暗色遮罩 + 透明选区 + 蓝色边框 + 尺寸标签（仿 macOS 原生截图）
class OverlayContentView: NSView {
    var selectionRect: NSRect = .zero {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 1. 整屏暗色遮罩
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.fill(bounds)

        guard selectionRect.width > 0 && selectionRect.height > 0 else { return }

        // 2. 选区挖空（清除该区域的暗色）
        ctx.setBlendMode(.clear)
        ctx.fill(selectionRect)
        ctx.setBlendMode(.normal)

        // 3. 选区蓝色边框（1.5pt，macOS 系统蓝）
        let borderColor = NSColor.systemBlue
        ctx.setStrokeColor(borderColor.cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(selectionRect.insetBy(dx: 0.75, dy: 0.75))

        // 4. 尺寸标签（右下角）
        drawDimensionLabel()
    }

    private func drawDimensionLabel() {
        let text = "\(Int(selectionRect.width)) × \(Int(selectionRect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let padding: CGFloat = 6
        let labelSize = NSSize(width: size.width + padding * 2, height: size.height + padding)

        // 放在选区右下角下方 8pt
        var origin = NSPoint(
            x: selectionRect.maxX - labelSize.width,
            y: selectionRect.minY - labelSize.height - 8
        )
        // 防止超出屏幕底部
        if origin.y < 4 { origin.y = selectionRect.maxY + 8 }

        let labelRect = NSRect(origin: origin, size: labelSize)
        let path = NSBezierPath(roundedRect: labelRect, xRadius: 4, yRadius: 4)
        NSColor.black.withAlphaComponent(0.75).setFill()
        path.fill()

        let textRect = NSRect(
            x: labelRect.origin.x + padding,
            y: labelRect.origin.y + padding / 2,
            width: size.width,
            height: size.height
        )
        (text as NSString).draw(in: textRect, withAttributes: attrs)
    }
}
