import AppKit

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// Display identifier that is stable across reconnects and reboots.
    var displayUUID: String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let str = CFUUIDCreateString(nil, uuid) as String? else {
            return "display-\(displayID)"
        }
        return str
    }

    static func screen(withUUID uuid: String?) -> NSScreen? {
        guard let uuid else { return nil }
        return screens.first { $0.displayUUID == uuid }
    }
}
