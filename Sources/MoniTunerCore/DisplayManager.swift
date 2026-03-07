import AppKit
import CoreGraphics
import IOKit

/// Represents a connected display.
public struct ExternalDisplay {
    public let displayID: CGDirectDisplayID
    public let name: String
    public let isBuiltIn: Bool
    /// m1ddc display name for DDC control (nil for built-in).
    public var ddcName: String?
    /// IOKit framebuffer service for direct DDC I2C (Arm64DDC fallback).
    public var ioService: io_service_t?

    public init(displayID: CGDirectDisplayID, name: String, isBuiltIn: Bool, ddcName: String? = nil, ioService: io_service_t? = nil) {
        self.displayID = displayID
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.ddcName = ddcName
        self.ioService = ioService
    }
}

/// Manages connected displays and provides mouse-to-display routing.
public final class DisplayManager {
    public static let shared = DisplayManager()

    public private(set) var displays: [ExternalDisplay] = []
    public let ddcService = DDCService()
    public let softwareDimming = SoftwareDimming()

    /// Displays where DDC write is confirmed broken (use software dimming instead).
    private var ddcWriteBroken: Set<CGDirectDisplayID> = []

    private init() {}

    // MARK: - Enumeration

    /// Refresh the list of connected displays and match with m1ddc + Arm64DDC.
    public func refreshDisplays() {
        ddcService.refreshDisplayMap()

        // Discover IOAVService-capable framebuffers for direct DDC, sorted by path (dispext0 < dispext1)
        let avServices = Arm64DDC.findAllExternalServices()
            .sorted { $0.location < $1.location }

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

            // Match IOAVService by CG enumeration index (matches IOKit dispextN order)
            let externalIndex = result.filter { !$0.isBuiltIn }.count
            let ioService: io_service_t? = isBuiltIn ? nil : (externalIndex < avServices.count ? avServices[externalIndex].service : nil)

            result.append(ExternalDisplay(
                displayID: id,
                name: name,
                isBuiltIn: isBuiltIn,
                ddcName: ddcName,
                ioService: ioService
            ))
        }

        displays = result

        // Diagnostic: log display-to-service mapping
        for d in result where !d.isBuiltIn {
            let svcPath = d.ioService.flatMap { svc -> String? in
                var buf = [CChar](repeating: 0, count: 512)
                IORegistryEntryGetPath(svc, kIOServicePlane, &buf)
                let path = String(cString: buf)
                return path.components(separatedBy: "/").first { $0.hasPrefix("dispext") }?.components(separatedBy: ":").first
            } ?? "nil"
            NSLog("[MoniTuner] Display \"%@\" (id=%u, unit=%u) ddcName=%@ ioService=%@",
                  d.name, d.displayID, CGDisplayUnitNumber(d.displayID),
                  d.ddcName ?? "nil", svcPath)
        }
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

    /// Set brightness: DDC hardware first, then software gamma fallback.
    public func setBrightness(for display: ExternalDisplay, value: Int) -> Bool {
        let clamped = min(max(value, 0), 100)

        // If DDC is known broken for this display, go straight to software dimming
        if ddcWriteBroken.contains(display.displayID) {
            return softwareDimming.setBrightness(displayID: display.displayID, value: clamped)
        }

        // Try m1ddc first
        if let ddcName = display.ddcName {
            let wrote = ddcService.setBrightness(displayName: ddcName, value: clamped)
            if wrote {
                if let readBack = ddcService.getBrightness(displayName: ddcName),
                   abs(readBack - clamped) <= 2 {
                    return true
                }
                // m1ddc write was silently ignored — fall through
            }
        }

        // Fallback: direct IOAVService I2C with write verification
        if let service = display.ioService {
            let writeOk = Arm64DDC.setBrightness(service: service, value: UInt16(clamped))
            if writeOk {
                usleep(50_000) // allow monitor to process
                if let readBack = Arm64DDC.getBrightness(service: service) {
                    let readPercent = readBack.max > 0
                        ? Int(round(Double(readBack.current) / Double(readBack.max) * 100.0))
                        : Int(readBack.current)
                    if abs(readPercent - clamped) <= 3 {
                        return true
                    }
                }
                // Arm64DDC write accepted but ignored by monitor — mark as broken
                NSLog("[MoniTuner] DDC write broken for \"%@\" — switching to software dimming", display.name)
                ddcWriteBroken.insert(display.displayID)
            }
        }

        // Final fallback: software dimming via gamma
        return softwareDimming.setBrightness(displayID: display.displayID, value: clamped)
    }

    /// Get brightness: DDC hardware first, then software dimming value.
    public func getBrightness(for display: ExternalDisplay) -> Int? {
        // If using software dimming, return the software value
        if ddcWriteBroken.contains(display.displayID) {
            return softwareDimming.getBrightness(displayID: display.displayID)
        }

        if let ddcName = display.ddcName {
            if let val = ddcService.getBrightness(displayName: ddcName) {
                return val
            }
        }

        if let service = display.ioService {
            if let result = Arm64DDC.getBrightness(service: service) {
                let maxVal = max(result.max, 1)
                return min(100, Int(round(Double(result.current) / Double(maxVal) * 100.0)))
            }
        }

        return nil
    }

    /// Check if a display is using software dimming.
    public func isSoftwareDimming(displayID: CGDirectDisplayID) -> Bool {
        ddcWriteBroken.contains(displayID)
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
