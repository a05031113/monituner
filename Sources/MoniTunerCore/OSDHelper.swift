import AppKit
import Foundation

/// Protocol matching Apple's private OSDUIHelper XPC service.
@objc protocol OSDUIHelperProtocol {
    func showImage(
        _ image: Int64,
        onDisplayID displayID: UInt32,
        priority: UInt32,
        msecUntilFade: UInt32,
        filledChiclets: UInt32,
        totalChiclets: UInt32,
        locked: Bool
    )
    func showImage(
        _ image: Int64,
        onDisplayID displayID: UInt32,
        priority: UInt32,
        msecUntilFade: UInt32
    )
}

/// Shows the native macOS brightness/volume OSD on a specific display.
public final class OSDHelper {
    /// OSD image type: 1 = brightness, 3 = volume, 4 = mute.
    public static let brightnessImage: Int64 = 1

    private static var connection: NSXPCConnection?

    /// Show native brightness OSD on a specific display.
    public static func showBrightnessOSD(displayID: CGDirectDisplayID, brightness: Double) {
        let filled = UInt32(BrightnessEngine.brightnessToChiclets(brightness))
        let total: UInt32 = UInt32(BrightnessEngine.chicletCount)

        guard let proxy = getProxy() else {
            print("OSDHelper: failed to get XPC proxy")
            return
        }

        proxy.showImage(
            brightnessImage,
            onDisplayID: displayID,
            priority: 0x1F4,
            msecUntilFade: 1000,
            filledChiclets: filled,
            totalChiclets: total,
            locked: false
        )
    }

    private static func getProxy() -> OSDUIHelperProtocol? {
        if connection == nil {
            connection = NSXPCConnection(machServiceName: "com.apple.OSDUIHelper", options: [])
            connection?.remoteObjectInterface = NSXPCInterface(with: OSDUIHelperProtocol.self)
            connection?.interruptionHandler = { connection = nil }
            connection?.invalidationHandler = { connection = nil }
            connection?.resume()
        }
        return connection?.remoteObjectProxy as? OSDUIHelperProtocol
    }
}
