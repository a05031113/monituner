import AppKit
import CoreGraphics
import os.log

private let logger = Logger(subsystem: "com.yanghaoyu.monituner", category: "MediaKeyTap")

private func debugLog(_ message: String) {
    logger.warning("\(message)")  // warning level to avoid being filtered
    // Also write to file for reliable diagnostics
    let line = "\(Date()): \(message)\n"
    let path = NSHomeDirectory() + "/monituner-debug.log"
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
    }
}

public final class MediaKeyTap {
    private static let nxSysDefined: CGEventType = CGEventType(rawValue: 14)!
    private static let nxBrightnessUp: Int = 2
    private static let nxBrightnessDown: Int = 3
    private static let keycodeBrightnessUp: Int64 = 144
    private static let keycodeBrightnessDown: Int64 = 145

    // Standard F-key codes for custom hotkey (⌃F1 / ⌃F2)
    private static let keycodeF1: Int64 = 122
    private static let keycodeF2: Int64 = 120
    // MacBook built-in brightness key keycodes (sent when modifier keys are held)
    private static let keycodeMacBrightnessDown: Int64 = 107  // MacBook brightness down key
    private static let keycodeMacBrightnessUp: Int64 = 113    // MacBook brightness up key

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?

    /// Callback when brightness changes on an external display.
    public var onBrightnessChanged: ((ExternalDisplay, Int) -> Void)?

    /// Track current brightness per display for stepping.
    public var currentBrightness: [CGDirectDisplayID: Double] = [:]

    /// Whether custom hotkeys (⌃F1/⌃F2) are enabled.
    public var customHotkeysEnabled: Bool = true

    public init() {}

    /// Start listening on a dedicated thread.
    public func start() {
        debugLog("start() called")
        let thread = Thread { [weak self] in
            debugLog("thread block executing")
            self?.setupEventTap()
            debugLog("calling CFRunLoopRun")
            CFRunLoopRun()
            debugLog("CFRunLoopRun returned (should not happen)")
        }
        thread.name = "MoniTuner.MediaKeyTap"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        thread.start()
    }

    public func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource, let rl = tapRunLoop {
            CFRunLoopRemoveSource(rl, source, .commonModes)
            CFRunLoopStop(rl)
        }
        eventTap = nil
        runLoopSource = nil
        tapThread?.cancel()
        tapThread = nil
        tapRunLoop = nil
    }

    /// Disable tap when no external displays, re-enable when they appear.
    public func updateInterception() {
        guard let tap = eventTap else { return }
        let shouldIntercept = DisplayManager.shared.hasExternalDisplays
        CGEvent.tapEnable(tap: tap, enable: shouldIntercept)
    }

    // MARK: - Setup

    private func setupEventTap() {
        debugLog("setupEventTap called on thread: \(Thread.current.name ?? "unnamed")")

        // Targeted mask: only keyDown + NX_SYSDEFINED to avoid tap timeout
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << 14)

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
            debugLog("FAILED to create event tap — Accessibility permission not granted")
            return
        }

        eventTap = tap
        tapRunLoop = CFRunLoopGetCurrent()
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        debugLog("event tap created and enabled successfully")
    }

    // MARK: - Event Handling

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // Re-enable tap if disabled by timeout
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            debugLog("tap was disabled (type=\(type.rawValue)), re-enabling")
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passRetained(event)
        }

        // Only log brightness-related events to avoid noise

        guard let direction = extractBrightnessDirection(type: type, event: event) else {
            return Unmanaged.passRetained(event)
        }

        debugLog("brightness direction: \(direction == .up ? "UP" : "DOWN")")

        // NSEvent.mouseLocation must be read on main thread
        var display: ExternalDisplay?
        DispatchQueue.main.sync {
            display = DisplayManager.shared.displayUnderMouse()
        }

        guard let display = display else {
            debugLog("no display under mouse")
            return Unmanaged.passRetained(event)
        }

        debugLog("display under mouse: \(display.name) (builtIn=\(display.isBuiltIn), ddcName=\(display.ddcName ?? "nil"))")

        // Built-in: pass through to let macOS handle natively
        if display.isBuiltIn {
            return Unmanaged.passRetained(event)
        }

        guard display.ddcName != nil || display.ioService != nil else {
            debugLog("display has no ddcName and no ioService — cannot control via DDC")
            return Unmanaged.passRetained(event)
        }

        // External: consume event, adjust via DDC
        let current = currentBrightness[display.displayID]
            ?? Double(DisplayManager.shared.getBrightness(for: display) ?? 50)
        let isUp = direction == .up
        let newBrightness = BrightnessEngine.stepBrightness(current: current, isUp: isUp)
        currentBrightness[display.displayID] = newBrightness

        let intBrightness = Int(round(newBrightness))
        debugLog("setBrightness \(display.name): \(Int(current))% → \(intBrightness)%")

        DispatchQueue.global(qos: .userInteractive).async {
            let ok = DisplayManager.shared.setBrightness(for: display, value: intBrightness)
            debugLog("DDC setBrightness result: \(ok)")
            if ok {
                DispatchQueue.main.async {
                    OSDHelper.showBrightnessOSD(displayID: display.displayID, brightness: newBrightness)
                }
            }
        }
        onBrightnessChanged?(display, intBrightness)

        return nil  // consume event
    }

    private enum BrightnessDirection { case up, down }

    private func extractBrightnessDirection(
        type: CGEventType,
        event: CGEvent
    ) -> BrightnessDirection? {
        if type == .keyDown {
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags

            // Path 1: Native brightness keycodes (external Apple keyboard)
            switch keycode {
            case Self.keycodeBrightnessUp: return .up
            case Self.keycodeBrightnessDown: return .down
            default: break
            }

            // Path 2: Custom hotkey — ⌃ + brightness key (MacBook or standard F1/F2)
            if customHotkeysEnabled && flags.contains(.maskControl) {
                let extraModifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskShift]
                guard flags.intersection(extraModifiers).isEmpty else { return nil }
                switch keycode {
                case Self.keycodeF1, Self.keycodeMacBrightnessDown: return .down
                case Self.keycodeF2, Self.keycodeMacBrightnessUp: return .up
                default: break
                }
            }

            // Path 2b: MacBook brightness keys WITHOUT Control (when fn is held)
            // These arrive as keyDown with fn flag but no other modifiers
            if customHotkeysEnabled {
                switch keycode {
                case Self.keycodeMacBrightnessDown: return .down
                case Self.keycodeMacBrightnessUp: return .up
                default: break
                }
            }

            return nil
        }

        // Path 3: NX_SYSDEFINED media key events
        // Must use NSEvent(cgEvent:) — CGEventField(109/110) returns 0 for these events
        if type == Self.nxSysDefined {
            guard let nsEvent = NSEvent(cgEvent: event) else { return nil }
            guard nsEvent.subtype.rawValue == 8 else { return nil }
            let data1 = nsEvent.data1
            let keyCode = (data1 >> 16) & 0xFF
            let keyFlags = (data1 >> 8) & 0xFF
            guard keyFlags == 0x0A else { return nil }  // key down only
            switch keyCode {
            case Self.nxBrightnessUp: return .up
            case Self.nxBrightnessDown: return .down
            default: return nil
            }
        }
        return nil
    }
}
