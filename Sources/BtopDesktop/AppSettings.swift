import AppKit
import Combine

/// App settings persisted in UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let defaultFontSize: Double = 12
    static let defaultOpacity: Double = 0.0

    private enum Key {
        static let isVisible = "isVisible"
        static let fontName = "fontName"
        static let fontSize = "fontSize"
        static let backgroundOpacity = "backgroundOpacity"
        static let displayUUID = "displayUUID"
        static let frames = "framesByDisplay"
    }

    private let defaults = UserDefaults.standard

    @Published var isVisible: Bool {
        didSet { defaults.set(isVisible, forKey: Key.isVisible) }
    }

    /// Monospaced font family name. Empty string means the system monospaced font (SF Mono).
    @Published var fontName: String {
        didSet { defaults.set(fontName, forKey: Key.fontName) }
    }

    @Published var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: Key.fontSize) }
    }

    /// Opacity (0...1) of the black window background.
    @Published var backgroundOpacity: Double {
        didSet { defaults.set(backgroundOpacity, forKey: Key.backgroundOpacity) }
    }

    /// UUID of the target display. nil means the primary display.
    @Published var displayUUID: String? {
        didSet { defaults.set(displayUUID, forKey: Key.displayUUID) }
    }

    private init() {
        defaults.register(defaults: [
            Key.isVisible: true,
            Key.fontName: "",
            Key.fontSize: Self.defaultFontSize,
            Key.backgroundOpacity: Self.defaultOpacity,
        ])
        isVisible = defaults.bool(forKey: Key.isVisible)
        fontName = defaults.string(forKey: Key.fontName) ?? ""
        fontSize = defaults.double(forKey: Key.fontSize)
        backgroundOpacity = defaults.double(forKey: Key.backgroundOpacity)
        displayUUID = defaults.string(forKey: Key.displayUUID)
    }

    // MARK: - Per-display window frames (stored relative to the display origin)

    func savedFrame(forDisplay uuid: String) -> NSRect? {
        guard let dict = defaults.dictionary(forKey: Key.frames) as? [String: String],
              let str = dict[uuid] else { return nil }
        let rect = NSRectFromString(str)
        return rect.width > 0 && rect.height > 0 ? rect : nil
    }

    func saveFrame(_ relativeFrame: NSRect, forDisplay uuid: String) {
        var dict = (defaults.dictionary(forKey: Key.frames) as? [String: String]) ?? [:]
        dict[uuid] = NSStringFromRect(relativeFrame)
        defaults.set(dict, forKey: Key.frames)
    }

    func resetAppearance() {
        fontName = ""
        fontSize = Self.defaultFontSize
        backgroundOpacity = Self.defaultOpacity
    }

    /// The NSFont described by the current settings.
    func resolvedFont() -> NSFont {
        let size = CGFloat(fontSize)
        if !fontName.isEmpty {
            if let f = NSFontManager.shared.font(withFamily: fontName, traits: [], weight: 5, size: size) {
                return f
            }
            if let f = NSFont(name: fontName, size: size) {
                return f
            }
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}
