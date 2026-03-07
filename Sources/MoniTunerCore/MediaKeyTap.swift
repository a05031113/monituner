import AppKit
import CoreGraphics

public final class MediaKeyTap {
    private static let nxSysDefined: CGEventType = CGEventType(rawValue: 14)!
    private static let nxBrightnessUp: Int64 = 2
    private static let nxBrightnessDown: Int64 = 3
    private static let eventSubtype: CGEventField = CGEventField(rawValue: 109)!
    private static let eventData1: CGEventField = CGEventField(rawValue: 110)!
    private static let keycodeBrightnessUp: Int64 = 144
    private static let keycodeBrightnessDown: Int64 = 145

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Callback when brightness changes on an external display.
    public var onBrightnessChanged: ((ExternalDisplay, Int) -> Void)?

    /// Track current brightness per display for stepping.
    public var currentBrightness: [CGDirectDisplayID: Double] = [:]

    public init() {}

    /// Start listening. Must be called from main thread.
    public func start() {
        // Listen for all event types to catch brightness keys on modern macOS
        let eventMask: CGEventMask = CGEventMask(bitPattern: ~0)  // all events

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, userInfo in
                guard let userInfo = userInfo else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<MediaKeyTap>.fromOpaque(userInfo).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("""
            MediaKeyTap: Failed to create event tap.
            Grant Accessibility permission in System Settings > \
            Privacy & Security > Accessibility.
            """)
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("MediaKeyTap: started successfully")
    }

    public func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    /// Disable tap when no external displays, re-enable when they appear.
    public func updateInterception() {
        guard let tap = eventTap else { return }
        let shouldIntercept = DisplayManager.shared.hasExternalDisplays
        CGEvent.tapEnable(tap: tap, enable: shouldIntercept)
    }

    // MARK: - Event Handling

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // Re-enable tap if disabled by timeout
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passRetained(event)
        }

        // Debug: log all NX_SYSDEFINED and keyDown events reaching the tap
        if type.rawValue == 14 || type == .keyDown || type == .keyUp {
            print("MediaKeyTap: event type=\(type.rawValue)")
        }
        if type == .keyDown {
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            if keycode == Self.keycodeBrightnessUp || keycode == Self.keycodeBrightnessDown {
                print("MediaKeyTap: keyDown keycode=\(keycode)")
            }
        }
        if type == Self.nxSysDefined {
            let subtype = event.getIntegerValueField(Self.eventSubtype)
            if subtype == 8 {
                let data1 = event.getIntegerValueField(Self.eventData1)
                let keyCode = (data1 >> 16) & 0xFF
                let keyFlags = (data1 >> 8) & 0xFF
                print("MediaKeyTap: NX_SYSDEFINED subtype=8 keyCode=\(keyCode) flags=0x\(String(keyFlags, radix: 16))")
            }
        }

        guard let direction = extractBrightnessDirection(type: type, event: event) else {
            return Unmanaged.passRetained(event)
        }

        guard let display = DisplayManager.shared.displayUnderMouse() else {
            print("MediaKeyTap: no display under mouse")
            return Unmanaged.passRetained(event)
        }

        // Built-in: pass through
        if display.isBuiltIn {
            return Unmanaged.passRetained(event)
        }

        // External: consume event, adjust via DDC
        let current = currentBrightness[display.displayID] ?? 50.0
        let isUp = direction == .up
        let newBrightness = BrightnessEngine.stepBrightness(current: current, isUp: isUp)
        currentBrightness[display.displayID] = newBrightness

        let intBrightness = Int(round(newBrightness))
        print("MediaKeyTap: \(isUp ? "up" : "down") on \(display.name), \(Int(current))% → \(intBrightness)%")

        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            if DisplayManager.shared.setBrightness(for: display, value: intBrightness) {
                DispatchQueue.main.async {
                    OSDHelper.showBrightnessOSD(displayID: display.displayID, brightness: newBrightness)
                }
            }
            self?.onBrightnessChanged?(display, intBrightness)
        }

        return nil  // consume event
    }

    private enum BrightnessDirection { case up, down }

    private func extractBrightnessDirection(
        type: CGEventType,
        event: CGEvent
    ) -> BrightnessDirection? {
        // Path 1: kCGEventKeyDown with brightness keycodes
        if type == .keyDown {
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            switch keycode {
            case Self.keycodeBrightnessUp: return .up
            case Self.keycodeBrightnessDown: return .down
            default: return nil
            }
        }
        // Path 2: NX_SYSDEFINED media key events
        if type == Self.nxSysDefined {
            let subtype = event.getIntegerValueField(Self.eventSubtype)
            guard subtype == 8 else { return nil }
            let data1 = event.getIntegerValueField(Self.eventData1)
            let keyCode = (data1 >> 16) & 0xFF
            let keyFlags = (data1 >> 8) & 0xFF
            // Bit 0 of flags: 0 = key down, 1 = key up
            guard keyFlags & 0x1 == 0 else { return nil }
            switch keyCode {
            case Self.nxBrightnessUp: return .up
            case Self.nxBrightnessDown: return .down
            default: return nil
            }
        }
        return nil
    }
}
