import AppKit
import Foundation

/// Background loop that reads the ambient light sensor and adjusts external monitor brightness.
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

    /// Duration of manual override after F1/F2 press.
    public var manualOverrideDuration: TimeInterval = 300  // 5 minutes

    /// Current lux reading (for UI display).
    public private(set) var currentLux: Double?

    /// Callback when brightness changes.
    public var onBrightnessUpdated: ((CGDirectDisplayID, Int) -> Void)?

    private let sensor = AmbientSensor()
    private var timer: Timer?
    private var manualOverrideUntil: Date?
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
    public func triggerManualOverride() {
        manualOverrideUntil = Date().addingTimeInterval(manualOverrideDuration)
    }

    /// Record brightness set externally.
    public func recordBrightness(_ value: Int, for displayID: CGDirectDisplayID) {
        currentBrightness[displayID] = value
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

    private func tick() {
        guard isEnabled else { return }

        if let overrideUntil = manualOverrideUntil, Date() < overrideUntil { return }
        manualOverrideUntil = nil

        guard DisplayManager.shared.isLidOpen else { return }
        guard let lux = sensor.readLux() else { return }
        currentLux = lux

        let target = Int(round(BrightnessEngine.luxToBrightness(lux)))

        for display in DisplayManager.shared.externalDisplays() {
            let current = currentBrightness[display.displayID] ?? -1
            guard current != target else { continue }
            smoothTransition(display: display, from: current == -1 ? target : current, to: target)
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
