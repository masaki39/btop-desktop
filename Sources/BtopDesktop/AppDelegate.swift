import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = AppSettings.shared
    private var controller: DesktopController?
    private var statusItem: NSStatusItem?
    private let appearance = AppearanceWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let btopPath = locateBtopOrAsk() else {
            NSApp.terminate(nil)
            return
        }
        do {
            try BtopEnvironment.ensureConfig(btopPath: btopPath)
        } catch {
            showError("Could not create the btop configuration file", error)
        }

        setUpStatusItem()
        let controller = DesktopController(btopPath: btopPath)
        self.controller = controller
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.shutdown()
    }

    // MARK: - Locating btop

    private func locateBtopOrAsk() -> String? {
        while true {
            if let path = BtopEnvironment.locateBtop() { return path }
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "btop was not found"
            alert.informativeText = """
            This app uses btop from Homebrew. Install it by running the following command in Terminal:

                brew install btop

            Then click "Check Again".
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Check Again")
            alert.addButton(withTitle: "Copy Command")
            alert.addButton(withTitle: "Quit")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                continue
            case .alertSecondButtonReturn:
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("brew install btop", forType: .string)
                continue
            default:
                return nil
            }
        }
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: "btop Desktop")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
    }

    /// Rebuilds the menu from the current state every time it opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let controller else { return }

        let header = NSMenuItem(title: "btop Desktop", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        menu.addItem(item("Show on Desktop", #selector(toggleVisible), state: settings.isVisible))
        menu.addItem(item("Edit Mode (Move & Resize)", #selector(toggleEditing), state: controller.isEditing))

        // Display selection
        let displayItem = NSMenuItem(title: "Display", action: nil, keyEquivalent: "")
        let displayMenu = NSMenu()
        let current = controller.targetScreen?.displayUUID
        for screen in NSScreen.screens {
            let size = screen.frame.size
            let title = "\(screen.localizedName)  (\(Int(size.width))×\(Int(size.height)))"
            let mi = item(title, #selector(selectDisplay(_:)), state: screen.displayUUID == current)
            mi.representedObject = screen.displayUUID
            displayMenu.addItem(mi)
        }
        displayItem.submenu = displayMenu
        menu.addItem(displayItem)

        // Quick font size
        let sizeItem = NSMenuItem(title: "Font Size", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        for size in [9, 10, 11, 12, 13, 14, 16, 18, 20, 24] {
            let mi = item("\(size) pt", #selector(selectFontSize(_:)), state: Int(settings.fontSize) == size)
            mi.tag = size
            sizeMenu.addItem(mi)
        }
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        // Quick background opacity
        let opacityItem = NSMenuItem(title: "Background Opacity", action: nil, keyEquivalent: "")
        let opacityMenu = NSMenu()
        for pct in [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100] {
            let mi = item("\(pct)%", #selector(selectOpacity(_:)),
                          state: Int((settings.backgroundOpacity * 100).rounded()) == pct)
            mi.tag = pct
            opacityMenu.addItem(mi)
        }
        opacityItem.submenu = opacityMenu
        menu.addItem(opacityItem)

        menu.addItem(item("Appearance…", #selector(openAppearance)))
        menu.addItem(.separator())

        menu.addItem(item("Open btop Config File", #selector(openBtopConfig)))
        menu.addItem(item("Restart btop", #selector(restartBtop)))
        menu.addItem(.separator())

        menu.addItem(item("Launch at Login", #selector(toggleLoginItem),
                          state: SMAppService.mainApp.status == .enabled))
        menu.addItem(.separator())
        menu.addItem(item("Quit btop Desktop", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, state: Bool? = nil, key: String = "") -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = self
        if let state { mi.state = state ? .on : .off }
        return mi
    }

    // MARK: - Actions

    @objc private func toggleVisible() {
        controller?.setVisible(!settings.isVisible)
    }

    @objc private func toggleEditing() {
        guard let controller else { return }
        controller.setEditing(!controller.isEditing)
    }

    @objc private func selectDisplay(_ sender: NSMenuItem) {
        // Look the display up by UUID: the screen list may have changed since the menu opened.
        guard let uuid = sender.representedObject as? String,
              let screen = NSScreen.screen(withUUID: uuid) else { return }
        controller?.selectDisplay(screen)
    }

    @objc private func selectFontSize(_ sender: NSMenuItem) {
        settings.fontSize = Double(sender.tag)
    }

    @objc private func selectOpacity(_ sender: NSMenuItem) {
        settings.backgroundOpacity = Double(sender.tag) / 100
    }

    @objc private func openAppearance() {
        appearance.show()
    }

    @objc private func openBtopConfig() {
        let url = BtopEnvironment.btopConfigFile
        let ws = NSWorkspace.shared
        let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        let app = ws.urlForApplication(toOpen: url) ?? textEdit
        ws.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard error != nil else { return }
            DispatchQueue.main.async {
                NSWorkspace.shared.open([url], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }

    @objc private func restartBtop() {
        guard settings.isVisible else { return }
        controller?.runner.restart()
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            showError("Could not change the login item", error)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showError(_ message: String, _ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
