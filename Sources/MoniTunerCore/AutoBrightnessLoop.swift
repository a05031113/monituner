import AppKit
import CoreGraphics
import Foundation

// Private API to read MacBook built-in display brightness
@_silgen_name("DisplayServicesGetBrightness")
private func DisplayServicesGetBrightness(_ display: CGDirectDisplayID, _ brightness: UnsafeMutablePointer<Float>) -> Int32

/// Background loop that follows the MacBook's built-in display brightness
/// and applies per-display calibration factors to external monitors.
public final class AutoBrightnessLoop {
    public var isEnabled: Bool = true {
        didSet {
            if isEnabled { startTimer() } else { stopTimer() }
        }
    }

    public var intervalSeconds: TimeInterval = 3.0 {
        didSet {
            if isEnabled { startTimer() }
        }
    }

    /// Per-display calibration factor: how much of Mac's brightness to apply.
    /// Calibrated when all screens look the same brightness.
    /// Key = displayID, Value = factor (e.g., 0.63 means set to 63% of Mac's value).
    public var calibrationFactors: [CGDirectDisplayID: Double] = [:]

    /// Current MacBook brightness (for UI display).
    public private(set) var currentMacBrightness: Double?

    /// Callback when brightness changes.
    public var onBrightnessUpdated: ((CGDirectDisplayID, Int) -> Void)?

    private var timer: Timer?
    private var currentBrightness: [CGDirectDisplayID: Int] = [:]

    public init() {}

    public func start() {
        guard isEnabled else { return }
        startTimer()
    }

    public func stop() {
        stopTimer()
    }

    /// Called when user manually adjusts brightness (F1/F2).
    /// Disables auto brightness until the user re-enables it.
    public func triggerManualOverride() {
        isEnabled = false
    }

    /// Record brightness set externally.
    public func recordBrightness(_ value: Int, for displayID: CGDirectDisplayID) {
        currentBrightness[displayID] = value
    }

    /// Calibrate all external displays based on current state.
    /// Call when all screens visually match in brightness.
    public func calibrate() {
        guard let macBrightness = readMacBrightness(), macBrightness > 0 else { return }
        for display in DisplayManager.shared.externalDisplays() {
            if let current = DisplayManager.shared.getBrightness(for: display) {
                let factor = Double(current) / (macBrightness * 100.0)
                calibrationFactors[display.displayID] = factor
                NSLog("[MoniTuner] Calibrated \"%@\": Mac=%.0f%% display=%d%% → factor=%.2f",
                      display.name, macBrightness * 100, current, factor)
            }
        }
    }

    // MARK: - Private

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tick()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func readMacBrightness() -> Double? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return nil }
        for i in 0..<Int(count) {
            if CGDisplayIsBuiltin(ids[i]) != 0 {
                var brightness: Float = -1
                let result = DisplayServicesGetBrightness(ids[i], &brightness)
                if result == 0, brightness >= 0 {
                    return Double(brightness)
                }
            }
        }
        return nil
    }

    private func tick() {
        guard isEnabled else { return }
        guard DisplayManager.shared.isLidOpen else { return }
        guard let macBrightness = readMacBrightness() else { return }
        currentMacBrightness = macBrightness

        let macPercent = macBrightness * 100.0

        for display in DisplayManager.shared.externalDisplays() {
            let factor = calibrationFactors[display.displayID] ?? 0.63
            let target = Int(round(min(max(macPercent * factor, 0), 100)))
            let current = currentBrightness[display.displayID] ?? -1
            guard current != target else { continue }
            let from = current == -1 ? target : current
            NSLog("AutoBrightness: Mac=%.0f%% → %@ %d%% → %d%% (factor=%.2f)",
                  macPercent, display.name, from, target, factor)
            smoothTransition(display: display, from: from, to: target)
        }
    }

    private func smoothTransition(display: ExternalDisplay, from current: Int, to target: Int) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let step = target > current ? 2 : -2
            var value = current

            while (step > 0 && value < target) || (step < 0 && value > target) {
                value += step
                if (step > 0 && value > target) || (step < 0 && value < target) {
                    value = target
                }
                _ = DisplayManager.shared.setBrightness(for: display, value: min(max(value, 0), 100))
                Thread.sleep(forTimeInterval: 0.05)
            }

            _ = DisplayManager.shared.setBrightness(for: display, value: target)
            self?.currentBrightness[display.displayID] = target
            DispatchQueue.main.async {
                self?.onBrightnessUpdated?(display.displayID, target)
            }
        }
    }
}
