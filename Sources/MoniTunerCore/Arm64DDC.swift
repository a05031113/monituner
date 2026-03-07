import CoreGraphics
import Foundation
import IOKit

// MARK: - Private IOAVService API declarations

@_silgen_name("IOAVServiceCreateWithService")
func IOAVServiceCreateWithService(
    _ allocator: CFAllocator?,
    _ service: io_service_t
) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOAVServiceReadI2C")
func IOAVServiceReadI2C(
    _ service: CFTypeRef,
    _ chipAddress: UInt32,
    _ offset: UInt32,
    _ outputBuffer: UnsafeMutablePointer<UInt8>,
    _ outputBufferSize: UInt32
) -> IOReturn

@_silgen_name("IOAVServiceWriteI2C")
func IOAVServiceWriteI2C(
    _ service: CFTypeRef,
    _ chipAddress: UInt32,
    _ offset: UInt32,
    _ inputBuffer: UnsafeMutablePointer<UInt8>,
    _ inputBufferSize: UInt32
) -> IOReturn

// MARK: - DDC/CI Constants

private let ddcChipAddress: UInt32 = 0x37
private let ddcDataAddress: UInt32 = 0x51
private let vcpLuminance: UInt8 = 0x10
private let maxRetries = 4
private let writeCycles = 2
private let writeDelay: UInt32 = 10_000   // 10ms between write cycles
private let readDelay: UInt32 = 40_000    // 40ms before reading reply

// MARK: - Arm64DDC

/// Direct DDC/CI communication via IOAVService I2C on Apple Silicon.
/// Packet format follows MonitorControl's approach for HDMI compatibility.
public final class Arm64DDC {

    // MARK: - VCP Write

    /// Set a VCP value on a display identified by its IOAVService-capable service.
    public static func setVCP(
        service: io_service_t,
        code: UInt8,
        value: UInt16
    ) -> Bool {
        guard let avService = IOAVServiceCreateWithService(kCFAllocatorDefault, service) else {
            return false
        }
        let av = avService.takeRetainedValue()

        let valueHigh = UInt8((value >> 8) & 0xFF)
        let valueLow = UInt8(value & 0xFF)

        // Standard DDC/CI Set VCP: [length, opcode=0x03, vcp_code, value_high, value_low, checksum]
        // length = 0x80 | 4 (4 bytes follow: opcode + code + 2 value bytes)
        var packet: [UInt8] = [0x84, 0x03, code, valueHigh, valueLow]

        var checksum = UInt8(ddcChipAddress << 1) ^ UInt8(ddcDataAddress)
        for byte in packet { checksum ^= byte }
        packet.append(checksum)

        // Write with retry logic — multiple cycles per attempt
        for _ in 0..<maxRetries {
            var success = true
            for cycle in 0..<writeCycles {
                let result = IOAVServiceWriteI2C(av, ddcChipAddress, ddcDataAddress, &packet, UInt32(packet.count))
                if result != kIOReturnSuccess {
                    success = false
                    break
                }
                if cycle < writeCycles - 1 {
                    usleep(writeDelay)
                }
            }
            if success { return true }
            usleep(writeDelay)
        }
        return false
    }

    // MARK: - VCP Read

    /// Get a VCP value from a display.
    public static func getVCP(
        service: io_service_t,
        code: UInt8
    ) -> (current: UInt16, max: UInt16)? {
        guard let avService = IOAVServiceCreateWithService(kCFAllocatorDefault, service) else {
            return nil
        }
        let av = avService.takeRetainedValue()

        // Standard DDC/CI Get VCP: [length, opcode=0x01, vcp_code, checksum]
        // length = 0x80 | 2 (2 bytes follow: opcode + code)
        var request: [UInt8] = [0x82, 0x01, code]

        var checksum = UInt8(ddcChipAddress << 1) ^ UInt8(ddcDataAddress)
        for byte in request { checksum ^= byte }
        request.append(checksum)

        for _ in 0..<maxRetries {
            let writeResult = IOAVServiceWriteI2C(av, ddcChipAddress, ddcDataAddress, &request, UInt32(request.count))
            guard writeResult == kIOReturnSuccess else { continue }

            usleep(readDelay)

            // Read response — 11 bytes for VCP reply
            // Reply format: [header, length, 0x02, result, vcp_code, type, max_h, max_l, cur_h, cur_l, checksum]
            var reply = [UInt8](repeating: 0, count: 11)
            let readResult = IOAVServiceReadI2C(av, ddcChipAddress, 0, &reply, UInt32(reply.count))
            guard readResult == kIOReturnSuccess else { continue }

            // Validate: opcode byte should be 0x02 (Get VCP Feature Reply)
            guard reply.count >= 11, reply[2] == 0x02, reply[4] == code else { continue }

            // Verify checksum
            var replyChecksum: UInt8 = 0x50  // reply source address
            for i in 0..<(reply.count - 1) {
                replyChecksum ^= reply[i]
            }
            guard replyChecksum == reply[reply.count - 1] else { continue }

            let maxVal = UInt16(reply[6]) << 8 | UInt16(reply[7])
            let curVal = UInt16(reply[8]) << 8 | UInt16(reply[9])
            return (current: curVal, max: maxVal)
        }

        return nil
    }

    // MARK: - Convenience

    /// Set brightness (VCP 0x10) for a given display service.
    public static func setBrightness(service: io_service_t, value: UInt16) -> Bool {
        return setVCP(service: service, code: vcpLuminance, value: value)
    }

    /// Get brightness (VCP 0x10) for a given display service.
    public static func getBrightness(service: io_service_t) -> (current: UInt16, max: UInt16)? {
        return getVCP(service: service, code: vcpLuminance)
    }

    // MARK: - Service Discovery

    /// Find the framebuffer io_service_t for a display by its CGDirectDisplayID.
    public static func findService(displayID: CGDirectDisplayID) -> io_service_t? {
        let services = findAllExternalServices()
        // Return first service that can communicate
        for (service, _) in services {
            if let _ = getBrightness(service: service) {
                return service
            }
        }
        return nil
    }

    /// Find all external display services that support DDC via DCPAVServiceProxy.
    public static func findAllExternalServices() -> [(service: io_service_t, location: String)] {
        var results: [(io_service_t, String)] = []
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("DCPAVServiceProxy")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != IO_OBJECT_NULL {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            // Check Location property — only "External" entries are external displays
            guard let locationRef = IORegistryEntryCreateCFProperty(
                service, "Location" as CFString, kCFAllocatorDefault, 0
            ) else { continue }
            guard let location = locationRef.takeRetainedValue() as? String else { continue }
            guard location == "External" else { continue }

            // Try to create IOAVService
            guard let avService = IOAVServiceCreateWithService(kCFAllocatorDefault, service) else { continue }
            avService.release()

            IOObjectRetain(service)
            let path = getIOServicePath(service)
            results.append((service, path))
        }

        return results
    }

    private static func getIOServicePath(_ service: io_service_t) -> String {
        var pathBuf = [CChar](repeating: 0, count: 512)
        IORegistryEntryGetPath(service, kIOServicePlane, &pathBuf)
        return String(cString: pathBuf)
    }
}
