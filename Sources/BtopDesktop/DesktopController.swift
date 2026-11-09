import AppKit
import Combine

/// Owns the desktop window, the btop runner, and display tracking.
@MainActor
final class DesktopController {
    private let settings = AppSettings.shared
    private let window: DesktopWindow
    private let container: NSView
    private let overlay: EditOverlayView
    let runner: BtopRunner
    private var cancellables = Set<AnyCancellable>()

    private static let padding: CGFloat = 8

    private(set) var isEditing = false

    init(btopPath: String) {
        let initial = NSRect(x: 0, y: 0, width: 960, height: 600)
        window = DesktopWindow(contentRect: initial)

        container = NSView(frame: initial)
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true
        container.autoresizesSubviews = true

        runner = BtopRunner(btopPath: btopPath, frame: initial.insetBy(dx: Self.padding, dy: Self.padding))
        runner.terminalView.autoresizingMask = [.width, .height]
        // Set the font before btop starts so it launches with the correct rows/columns.
        runner.terminalView.font = settings.resolvedFont()
        container.addSubview(runner.terminalView)

        overlay = EditOverlayView(frame: initial)
        overlay.autoresizingMask = [.width, .height]
        overlay.isHidden = true
        container.addSubview(overlay)

        window.contentView = container

        overlay.onCommit = { [weak self] in self?.handleOverlayCommit() }
        overlay.onExit = { [weak self] in self?.setEditing(false) }
        overlay.infoProvider = { [weak self] in
            guard let self else { return "" }
            let f = self.window.frame
            return "\(Int(f.width))×\(Int(f.height)) pt  \(self.runner.cols) cols × \(self.runner.rows) rows"
        }

        bindSettings()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }

    // MARK: - Visibility

    func start() {
        applyFrame()
        if settings.isVisible { show() }
    }

    func setVisible(_ visible: Bool) {
        settings.isVisible = visible
        visible ? show() : hide()
    }

    private func show() {
        applyFrame()
        window.orderFront(nil)
        runner.start()
    }

    private func hide() {
        if isEditing { setEditing(false) }
        window.orderOut(nil)
        runner.stop() // Stop btop while hidden so it does not use CPU.
    }

    // MARK: - Edit mode

    func setEditing(_ editing: Bool) {
        guard editing != isEditing else { return }
        if editing && !settings.isVisible { setVisible(true) }
        isEditing = editing
        window.isEditing = editing
        overlay.isHidden = !editing
        if editing {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(overlay)
            window.invalidateCursorRects(for: overlay)
        } else {
            window.makeFirstResponder(nil)
            handleOverlayCommit()
            window.resignKey()
            window.orderFront(nil)
        }
        overlay.needsDisplay = true
    }

    private func handleOverlayCommit() {
        // Pick the display the window now mostly sits on (it may have been dragged onto another one),
        // pull the window back inside it, then remember that display and frame.
        guard let screen = screenOverlappingMost(window.frame) ?? targetScreen else { return }
        let clamped = Self.clamp(window.frame, to: screen.frame)
        if clamped != window.frame { window.setFrame(clamped, display: true) }
        if screen.displayUUID != targetScreen?.displayUUID {
            settings.displayUUID = screen.displayUUID
        }
        saveCurrentFrame()
        overlay.needsDisplay = true
    }

    // MARK: - Displays

    /// The selected display, falling back to the primary display (the one with the menu bar)
    /// when nothing is selected or the selected display is disconnected.
    var targetScreen: NSScreen? {
        NSScreen.screen(withUUID: settings.displayUUID) ?? NSScreen.screens.first
    }

    func selectDisplay(_ screen: NSScreen) {
        settings.displayUUID = screen.displayUUID
        applyFrame()
    }

    private func screensChanged() {
        // If the selected display was unplugged we temporarily move to the primary display.
        // The selection is kept, so the window returns when the display is reconnected.
        // Frames are re-clamped, so a resolution change also resizes the window.
        applyFrame()
    }

    private func screenContaining(_ rect: NSRect) -> NSScreen? {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
    }

    private func screenOverlappingMost(_ rect: NSRect) -> NSScreen? {
        func area(_ s: NSScreen) -> CGFloat {
            let i = s.frame.intersection(rect)
            return i.isNull ? 0 : i.width * i.height
        }
        return NSScreen.screens.filter { area($0) > 0 }.max { area($0) < area($1) }
    }

    /// Clamps `frame` so that it fits inside `bounds`.
    private static func clamp(_ frame: NSRect, to bounds: NSRect) -> NSRect {
        var f = frame
        f.size.width = min(max(f.width, EditOverlayView.minSize.width), bounds.width)
        f.size.height = min(max(f.height, EditOverlayView.minSize.height), bounds.height)
        f.origin.x = min(max(f.minX, bounds.minX), bounds.maxX - f.width)
        f.origin.y = min(max(f.minY, bounds.minY), bounds.maxY - f.height)
        return f.integral
    }

    private func applyFrame() {
        guard let screen = targetScreen else { return }
        let sf = screen.frame
        let frame: NSRect
        if let rel = settings.savedFrame(forDisplay: screen.displayUUID) {
            frame = rel.offsetBy(dx: sf.minX, dy: sf.minY)
        } else {
            frame = screen.visibleFrame.insetBy(dx: 40, dy: 40)
        }
        window.setFrame(Self.clamp(frame, to: sf), display: true)
    }

    private func saveCurrentFrame() {
        guard let screen = screenOverlappingMost(window.frame) ?? targetScreen else { return }
        let rel = window.frame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        settings.saveFrame(rel, forDisplay: screen.displayUUID)
    }

    // MARK: - Appearance

    private func bindSettings() {
        Publishers.CombineLatest(settings.$fontName, settings.$fontSize)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                guard let self else { return }
                self.runner.terminalView.font = self.settings.resolvedFont()
                self.overlay.needsDisplay = true
            }
            .store(in: &cancellables)

        settings.$backgroundOpacity
            .receive(on: RunLoop.main)
            .sink { [weak self] opacity in
                self?.container.layer?.backgroundColor = NSColor.black.withAlphaComponent(opacity).cgColor
            }
            .store(in: &cancellables)
    }

    func shutdown() {
        if isEditing { handleOverlayCommit() }
        runner.terminateForQuit()
    }
}
