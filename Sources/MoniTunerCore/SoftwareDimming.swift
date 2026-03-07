import CoreGraphics
import Foundation

/// Software brightness control via gamma table manipulation.
/// Used as fallback when DDC hardware control is unavailable (e.g., HDMI displays).
/// Multiplies the default gamma curve by a brightness factor (0.0 = black, 1.0 = full).
public final class SoftwareDimming {

    /// Stored default gamma tables per display, captured before any modification.
    private var defaults: [CGDirectDisplayID: GammaTable] = [:]

    /// Current software brightness per display (0.0...1.0).
    private var currentValues: [CGDirectDisplayID: Float] = [:]

    /// Minimum brightness floor for software dimming (0...100).
    /// Gamma dimming can't increase hardware backlight, so very low values look unnaturally dark.
    public var minimumBrightness: Int = 50

    private struct GammaTable {
        var red: [CGGammaValue]
        var green: [CGGammaValue]
        var blue: [CGGammaValue]
        var sampleCount: UInt32
    }

    public init() {}

    /// Capture the default gamma table for a display (call once before any dimming).
    public func captureDefaults(displayID: CGDirectDisplayID) {
        guard defaults[displayID] == nil else { return }
        var red = [CGGammaValue](repeating: 0, count: 256)
        var green = [CGGammaValue](repeating: 0, count: 256)
        var blue = [CGGammaValue](repeating: 0, count: 256)
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(displayID, 256, &red, &green, &blue, &count) == .success else { return }
        defaults[displayID] = GammaTable(red: red, green: green, blue: blue, sampleCount: count)
        currentValues[displayID] = 1.0
    }

    /// Set software brightness (0...100 integer, same scale as DDC).
    /// Returns true if successful.
    public func setBrightness(displayID: CGDirectDisplayID, value: Int) -> Bool {
        captureDefaults(displayID: displayID)
        guard let table = defaults[displayID] else { return false }

        // Remap 0-100 input to minimumBrightness-100 output range
        let floor = Float(min(max(minimumBrightness, 0), 100)) / 100.0
        let normalized = Float(min(max(value, 0), 100)) / 100.0
        let factor = floor + normalized * (1.0 - floor)
        currentValues[displayID] = factor

        var red = table.red.map { $0 * CGGammaValue(factor) }
        var green = table.green.map { $0 * CGGammaValue(factor) }
        var blue = table.blue.map { $0 * CGGammaValue(factor) }

        let result = CGSetDisplayTransferByTable(displayID, table.sampleCount, &red, &green, &blue)
        return result == .success
    }

    /// Get current software brightness (0...100).
    public func getBrightness(displayID: CGDirectDisplayID) -> Int {
        Int(round((currentValues[displayID] ?? 1.0) * 100.0))
    }

    /// Restore default gamma (full brightness) for a display.
    public func restore(displayID: CGDirectDisplayID) {
        guard let table = defaults[displayID] else { return }
        var red = table.red
        var green = table.green
        var blue = table.blue
        CGSetDisplayTransferByTable(displayID, table.sampleCount, &red, &green, &blue)
        currentValues[displayID] = 1.0
    }

    /// Restore all displays to default gamma.
    public func restoreAll() {
        for id in defaults.keys {
            restore(displayID: id)
        }
    }
}
