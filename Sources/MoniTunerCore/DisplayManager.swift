import AppKit
import CoreGraphics

/// Represents a connected display.
public struct ExternalDisplay {
    public let displayID: CGDirectDisplayID
    public let name: String
    public let isBuiltIn: Bool
    /// m1ddc display name for DDC control (nil for built-in).
    public var ddcName: String?

    public init(displayID: CGDirectDisplayID, name: String, isBuiltIn: Bool, ddcName: String? = nil) {
        self.displayID = displayID
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.ddcName = ddcName
    }
}

/// Manages connected displays and provides mouse-to-display routing.
public final class DisplayManager {
    public static let shared = DisplayManager()

    public private(set) var displays: [ExternalDisplay] = []
    public let ddcService = DDCService()

    private init() {}

    // MARK: - Enumeration

    /// Refresh the list of connected displays and match with m1ddc.
    public func refreshDisplays() {
        ddcService.refreshDisplayMap()
        var result: [ExternalDisplay] = []

        var onlineDisplays = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &onlineDisplays, &displayCount) == CGError.success else {
            return
        }

        let ddcNames = Set(ddcService.displayNames)

        for i in 0..<Int(displayCount) {
            let id = onlineDisplays[i]
            guard id != 0 else { continue }
            let isBuiltIn = CGDisplayIsBuiltin(id) != 0
            let name = Self.displayName(for: id)
            let ddcName = isBuiltIn ? nil : Self.findBestDDCMatch(screenName: name, ddcNames: ddcNames)

            result.append(ExternalDisplay(
                displayID: id,
                name: name,
                isBuiltIn: isBuiltIn,
                ddcName: ddcName
            ))
        }

        displays = result
    }

    // MARK: - Mouse Location

    /// Get the display where the mouse cursor is currently located.
    public func displayUnderMouse() -> ExternalDisplay? {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) else {
            return nil
        }
        let screenDisplayID = screen.displayID
        return displays.first { $0.displayID == screenDisplayID }
    }

    /// Get all external (non-built-in) displays.
    public func externalDisplays() -> [ExternalDisplay] {
        displays.filter { !$0.isBuiltIn }
    }

    /// Check if MacBook lid is open.
    public var isLidOpen: Bool {
        displays.contains { $0.isBuiltIn }
    }

    /// Check if any external displays are connected.
    public var hasExternalDisplays: Bool {
        displays.contains { !$0.isBuiltIn }
    }

    // MARK: - Brightness Control

    public func setBrightness(for display: ExternalDisplay, value: Int) -> Bool {
        guard let ddcName = display.ddcName else { return false }
        return ddcService.setBrightness(displayName: ddcName, value: value)
    }

    public func getBrightness(for display: ExternalDisplay) -> Int? {
        guard let ddcName = display.ddcName else { return nil }
        return ddcService.getBrightness(displayName: ddcName)
    }

    // MARK: - Name Matching

    static func displayName(for displayID: CGDirectDisplayID) -> String {
        if let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) {
            return screen.localizedName
        }
        return "Display \(displayID)"
    }

    /// Find best m1ddc name match for a screen name.
    /// Uses substring matching since NSScreen and m1ddc may report slightly different names.
    static func findBestDDCMatch(screenName: String, ddcNames: Set<String>) -> String? {
        if ddcNames.contains(screenName) { return screenName }
        for ddcName in ddcNames {
            if screenName.localizedCaseInsensitiveContains(ddcName) ||
               ddcName.localizedCaseInsensitiveContains(screenName) {
                return ddcName
            }
        }
        return nil
    }
}

// MARK: - NSScreen extension

public extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
    }
}
