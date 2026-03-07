import Foundation

public struct BrightnessEngine {
    public static let chicletCount: Double = 16
    public static let stepSize: Double = 100.0 / chicletCount  // 6.25%

    /// Reference points for the lux-to-brightness mapping curve.
    private static let luxCurve: [(lux: Double, brightness: Double)] = [
        (0, 5), (50, 20), (200, 40), (500, 60), (1000, 80), (5000, 100)
    ]

    /// Convert ambient light lux to target brightness percentage (0-100).
    /// Uses piecewise linear interpolation through reference points:
    /// 0 lux -> 5%, 50->20%, 200->40%, 500->60%, 1000->80%, 5000->100%
    public static func luxToBrightness(_ lux: Double) -> Double {
        let clamped = max(lux, 0)
        let curve = luxCurve

        if clamped <= curve[0].lux { return curve[0].brightness }
        if clamped >= curve[curve.count - 1].lux { return curve[curve.count - 1].brightness }

        for i in 1..<curve.count {
            if clamped <= curve[i].lux {
                let (x0, y0) = (curve[i - 1].lux, curve[i - 1].brightness)
                let (x1, y1) = (curve[i].lux, curve[i].brightness)
                let t = (clamped - x0) / (x1 - x0)
                return y0 + t * (y1 - y0)
            }
        }

        return curve[curve.count - 1].brightness
    }

    public static func clampBrightness(_ value: Double) -> Double {
        min(max(value, 0), 100)
    }

    public static func stepBrightness(current: Double, isUp: Bool) -> Double {
        let delta = isUp ? stepSize : -stepSize
        return clampBrightness(current + delta)
    }

    public static func brightnessToChiclets(_ brightness: Double) -> Int {
        Int(round(brightness / 100.0 * chicletCount))
    }
}
