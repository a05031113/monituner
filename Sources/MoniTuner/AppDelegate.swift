import AppKit
import MoniTunerCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private let mediaKeyTap = MediaKeyTap()
    private let autoBrightnessLoop = AutoBrightnessLoop()

    // MARK: - UserDefaults Keys
    private static let keyAutoBrightnessEnabled = "autoBrightnessEnabled"
    private static let keySensorInterval = "sensorInterval"

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadSettings()
        DisplayManager.shared.refreshDisplays()
        setupMenuBar()

        mediaKeyTap.onBrightnessChanged = { [weak self] display, brightness in
            self?.autoBrightnessLoop.triggerManualOverride()
            self?.autoBrightnessLoop.recordBrightness(brightness, for: display.displayID)
        }
        mediaKeyTap.start()
        autoBrightnessLoop.start()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displaysChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        showMainWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { showMainWindow() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "sun.max",
                accessibilityDescription: "MoniTuner"
            )
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: "Show MoniTuner",
            action: #selector(showMainWindow),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem.separator())

        let autoItem = NSMenuItem(
            title: "Auto Brightness",
            action: #selector(toggleAutoBrightness),
            keyEquivalent: ""
        )
        autoItem.state = autoBrightnessLoop.isEnabled ? .on : .off
        menu.addItem(autoItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        statusItem.menu = menu
    }

    @objc func showMainWindow() {
        if window == nil {
            let contentView = MainWindowView(
                autoBrightnessLoop: autoBrightnessLoop,
                mediaKeyTap: mediaKeyTap
            )
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window?.title = "MoniTuner"
            window?.contentView = NSHostingView(rootView: contentView)
            window?.center()
            window?.isReleasedWhenClosed = false
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleAutoBrightness() {
        autoBrightnessLoop.isEnabled.toggle()
        if let menu = statusItem.menu,
           let item = menu.items.first(where: { $0.title == "Auto Brightness" }) {
            item.state = autoBrightnessLoop.isEnabled ? .on : .off
        }
        saveSettings()
    }

    @objc private func displaysChanged() {
        DisplayManager.shared.refreshDisplays()
        mediaKeyTap.updateInterception()
    }

    // MARK: - Settings Persistence

    private func loadSettings() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.keyAutoBrightnessEnabled) != nil {
            autoBrightnessLoop.isEnabled = defaults.bool(forKey: Self.keyAutoBrightnessEnabled)
        }
        let interval = defaults.double(forKey: Self.keySensorInterval)
        if interval > 0 {
            autoBrightnessLoop.intervalSeconds = interval
        }
    }

    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(autoBrightnessLoop.isEnabled, forKey: Self.keyAutoBrightnessEnabled)
        defaults.set(autoBrightnessLoop.intervalSeconds, forKey: Self.keySensorInterval)
    }
}
