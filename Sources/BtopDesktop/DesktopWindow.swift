import AppKit

/// Borderless window placed above the wallpaper and below the desktop icons.
final class DesktopWindow: NSWindow {
    static let desktopLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))

    /// Can become key only while in edit mode.
    var isEditing = false {
        didSet { applyMode() }
    }

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        isRestorable = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        applyMode()
    }

    override var canBecomeKey: Bool { isEditing }
    override var canBecomeMain: Bool { false }

    private func applyMode() {
        if isEditing {
            // At desktop level, Finder's desktop (icon layer) would take the clicks,
            // so raise the window only while editing.
            level = .floating
            ignoresMouseEvents = false
        } else {
            level = Self.desktopLevel
            ignoresMouseEvents = true
        }
    }
}

/// Overlay shown in edit mode; handles dragging to move and edge-dragging to resize.
final class EditOverlayView: NSView {
    struct Edges: OptionSet {
        let rawValue: Int
        static let left = Edges(rawValue: 1 << 0)
        static let right = Edges(rawValue: 1 << 1)
        static let top = Edges(rawValue: 1 << 2)
        static let bottom = Edges(rawValue: 1 << 3)
    }

    static let minSize = NSSize(width: 320, height: 200)
    private let grip: CGFloat = 12

    /// Called when a drag ends.
    var onCommit: (() -> Void)?
    /// Called when Esc is pressed.
    var onExit: (() -> Void)?
    /// Extra text to display (e.g. "120 cols × 40 rows").
    var infoProvider: (() -> String)?

    private var dragEdges: Edges = []
    private var dragStartMouse = NSPoint.zero
    private var dragStartFrame = NSRect.zero

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // Take keyboard focus so keystrokes never reach btop while editing.
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onExit?() } // Esc
    }

    private func edges(at p: NSPoint) -> Edges {
        var e: Edges = []
        if p.x <= grip { e.insert(.left) }
        if p.x >= bounds.width - grip { e.insert(.right) }
        if p.y <= grip { e.insert(.bottom) }
        if p.y >= bounds.height - grip { e.insert(.top) }
        return e
    }

    override func resetCursorRects() {
        let w = bounds.width, h = bounds.height, g = grip
        addCursorRect(bounds.insetBy(dx: g, dy: g), cursor: .openHand)
        addCursorRect(NSRect(x: 0, y: g, width: g, height: h - 2 * g), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: w - g, y: g, width: g, height: h - 2 * g), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: g, y: 0, width: w - 2 * g, height: g), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: g, y: h - g, width: w - 2 * g, height: g), cursor: .resizeUpDown)
        for corner in [NSPoint(x: 0, y: 0), NSPoint(x: w - g, y: 0), NSPoint(x: 0, y: h - g), NSPoint(x: w - g, y: h - g)] {
            addCursorRect(NSRect(origin: corner, size: NSSize(width: g, height: g)), cursor: .crosshair)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        dragEdges = edges(at: convert(event.locationInWindow, from: nil))
        dragStartMouse = NSEvent.mouseLocation
        dragStartFrame = window.frame
        if dragEdges.isEmpty { NSCursor.closedHand.push() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - dragStartMouse.x
        let dy = now.y - dragStartMouse.y
        var f = dragStartFrame
        let minS = Self.minSize

        if dragEdges.isEmpty {
            f.origin.x += dx
            f.origin.y += dy
        } else {
            if dragEdges.contains(.left) {
                let w = max(minS.width, f.width - dx)
                f.origin.x = f.maxX - w
                f.size.width = w
            }
            if dragEdges.contains(.right) {
                f.size.width = max(minS.width, f.width + dx)
            }
            if dragEdges.contains(.bottom) {
                let h = max(minS.height, f.height - dy)
                f.origin.y = f.maxY - h
                f.size.height = h
            }
            if dragEdges.contains(.top) {
                f.size.height = max(minS.height, f.height + dy)
            }
        }
        window.setFrame(f.integral, display: true)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if dragEdges.isEmpty { NSCursor.pop() }
        dragEdges = []
        window?.invalidateCursorRects(for: self)
        onCommit?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor
        accent.withAlphaComponent(0.10).setFill()
        bounds.fill()

        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 10, yRadius: 10)
        border.lineWidth = 3
        border.setLineDash([10, 6], count: 2, phase: 0)
        accent.setStroke()
        border.stroke()

        var text = "Edit mode — drag to move, drag edges to resize, Esc to finish"
        if let info = infoProvider?() { text += "   \(info)" }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let pill = NSRect(x: (bounds.width - size.width) / 2 - 12, y: bounds.height - size.height - 28,
                          width: size.width + 24, height: size.height + 10)
        accent.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        str.draw(at: NSPoint(x: pill.minX + 12, y: pill.minY + 5))
    }
}
