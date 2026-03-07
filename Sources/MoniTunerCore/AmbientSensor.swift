import Foundation
import IOKit

/// Reads macOS ambient light sensor.
///
/// On Apple Silicon Macs, the ambient light sensor value is exposed as the
/// `AmbientBrightness` property on the built-in display's `IOMobileFramebufferShim`
/// IOKit service. The value is in fixed-point 16.16 format (divide by 65536 for lux).
public final class AmbientSensor {
    public init() {}

    public var isAvailable: Bool {
        readLux() != nil
    }

    /// Read current ambient light in approximate lux.
    public func readLux() -> Double? {
        // Try IOMobileFramebufferShim (Apple Silicon)
        if let lux = readFromFramebuffer() {
            return lux
        }
        // Fallback: AppleLMUController (older Macs)
        return readFromLMU()
    }

    // MARK: - IOMobileFramebufferShim (Apple Silicon)

    private func readFromFramebuffer() -> Double? {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOMobileFramebufferShim"),
            &iterator
        )
        guard result == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var bestLux: Double?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let prop = IORegistryEntryCreateCFProperty(
                service, "AmbientBrightness" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? NSNumber {
                let raw = prop.int64Value
                // Fixed-point 16.16 format: divide by 65536
                let lux = Double(raw) / 65536.0
                // The built-in display has the real sensor value (> 1.0 lux typically)
                // External displays report exactly 65536 (= 1.0 lux)
                if lux > 1.0 {
                    bestLux = lux
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return bestLux
    }

    // MARK: - AppleLMUController (fallback for older Macs)

    private func readFromLMU() -> Double? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleLMUController")
        )
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        var dataPort: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &dataPort) == KERN_SUCCESS else { return nil }
        defer { IOServiceClose(dataPort) }

        var outputCount: UInt32 = 2
        var values = [UInt64](repeating: 0, count: 2)
        let callResult = IOConnectCallMethod(
            dataPort, 0, nil, 0, nil, 0, &values, &outputCount, nil, nil
        )
        guard callResult == KERN_SUCCESS else { return nil }

        let avgRaw = (values[0] + values[1]) / 2
        return Self.rawToLux(avgRaw)
    }

    /// Convert AppleLMUController raw reading to approximate lux.
    static func rawToLux(_ raw: UInt64) -> Double {
        let x = Double(raw)
        let lux = (-3.0e-27) * pow(x, 4)
                + (2.6e-19) * pow(x, 3)
                - (3.4e-12) * pow(x, 2)
                + (3.9e-5) * x
                - 0.19
        return max(lux, 0)
    }
}
