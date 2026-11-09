import AppKit
import SwiftUI

/// Settings for font, font size and background opacity (applied immediately).
struct AppearanceView: View {
    @ObservedObject var settings: AppSettings

    private let families: [String] = AppearanceView.monospacedFamilies()

    var body: some View {
        Form {
            Picker("Font", selection: $settings.fontName) {
                Text("System Monospaced (SF Mono)").tag("")
                Divider()
                ForEach(families, id: \.self) { family in
                    Text(family).font(.custom(family, size: 13)).tag(family)
                }
            }

            LabeledContent("Font Size") {
                HStack {
                    Slider(value: $settings.fontSize, in: 8...28, step: 1)
                    Stepper(value: $settings.fontSize, in: 8...28, step: 1) {
                        Text("\(Int(settings.fontSize)) pt")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }

            LabeledContent("Background Opacity") {
                HStack {
                    Slider(value: $settings.backgroundOpacity, in: 0...1)
                    Text("\(Int((settings.backgroundOpacity * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }

            HStack {
                Spacer()
                Button("Restore Defaults") { settings.resetAppearance() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Installed monospaced font families.
    static func monospacedFamilies() -> [String] {
        let fm = NSFontManager.shared
        return fm.availableFontFamilies.filter { family in
            guard !family.hasPrefix("."),
                  let font = fm.font(withFamily: family, traits: [], weight: 5, size: 12) else { return false }
            return font.isFixedPitch
        }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

@MainActor
final class AppearanceWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: AppearanceView(settings: .shared))
            let w = NSWindow(contentViewController: hosting)
            w.title = "Appearance"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.level = .floating
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
