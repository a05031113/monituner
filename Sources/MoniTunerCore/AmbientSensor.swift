import Foundation
import IOKit

/// Reads macOS ambient light sensor via IOKit AppleLMUController.
public final class AmbientSensor {
    private var sensorAvailable: Bool?

    public init() {}

    public var isAvailable: Bool {
        if let cached = sensorAvailable { return cached }
        let available = probeSensor()
        sensorAvailable = available
        return available
    }

    /// Read current ambient light in approximate lux.
    public func readLux() -> Double? {
        guard isAvailable else { return nil }

        let matching = IOServiceMatching("AppleLMUController")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else {
            sensorAvailable = false
            return nil
        }
        defer { IOObjectRelease(service) }

        var dataPort: io_connect_t = 0
        let openResult = IOServiceOpen(service, mach_task_self_, 0, &dataPort)
        guard openResult == KERN_SUCCESS else { return nil }
        defer { IOServiceClose(dataPort) }

        var outputCount: UInt32 = 2
        var values = [UInt64](repeating: 0, count: 2)

        let callResult = IOConnectCallMethod(
            dataPort,
            0,
            nil, 0,
            nil, 0,
            &values, &outputCount,
            nil, nil
        )

        guard callResult == KERN_SUCCESS else { return nil }

        let avgRaw = (values[0] + values[1]) / 2
        return Self.rawToLux(avgRaw)
    }

    public func resetCache() {
        sensorAvailable = nil
    }

    // MARK: - Private

    private func probeSensor() -> Bool {
        let matching = IOServiceMatching("AppleLMUController")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        if service == IO_OBJECT_NULL { return false }
        IOObjectRelease(service)
        return true
    }

    /// Convert raw sensor reading to approximate lux.
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
