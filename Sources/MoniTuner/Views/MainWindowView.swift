import MoniTunerCore
import SwiftUI

struct MainWindowView: View {
    @StateObject var viewModel: MainWindowViewModel

    init(autoBrightnessLoop: AutoBrightnessLoop, mediaKeyTap: MediaKeyTap) {
        self._viewModel = StateObject(wrappedValue: MainWindowViewModel(
            autoBrightnessLoop: autoBrightnessLoop,
            mediaKeyTap: mediaKeyTap
        ))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(viewModel.externalDisplays, id: \.displayID) { display in
                    MonitorCardView(
                        display: display,
                        brightness: viewModel.brightness(for: display),
                        onBrightnessChanged: { value in
                            viewModel.setBrightness(value, for: display)
                        }
                    )
                }

                if viewModel.externalDisplays.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "display.trianglebadge.exclamationmark")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No External Displays")
                            .font(.headline)
                        Text("Connect an external monitor to get started.")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Auto Brightness")
                        .font(.headline)

                    Toggle("Enabled", isOn: $viewModel.autoBrightnessEnabled)

                    HStack {
                        Text("Sensor interval:")
                        Picker("", selection: $viewModel.sensorInterval) {
                            Text("1 sec").tag(1.0)
                            Text("3 sec").tag(3.0)
                            Text("5 sec").tag(5.0)
                            Text("10 sec").tag(10.0)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 250)
                    }

                    if let macBrightness = viewModel.currentMacBrightness {
                        HStack {
                            Image(systemName: "sun.max")
                                .foregroundColor(.yellow)
                            Text("Mac brightness: \(Int(round(macBrightness * 100)))%")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(.background))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Keyboard Shortcuts")
                        .font(.headline)

                    HStack(spacing: 4) {
                        KeyCap("⌃")
                        KeyCap("F2")
                        Text("Brightness Up")
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 4) {
                        KeyCap("⌃")
                        KeyCap("F1")
                        Text("Brightness Down")
                            .foregroundColor(.secondary)
                    }

                    Text("Controls the external monitor under your mouse cursor.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(.background))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
            }
            .padding()
        }
        .frame(minWidth: 380, minHeight: 300)
        .onAppear { viewModel.startRefresh() }
        .onDisappear { viewModel.stopRefresh() }
    }
}

// MARK: - KeyCap

private struct KeyCap: View {
    let label: String
    init(_ label: String) { self.label = label }

    var body: some View {
        Text(label)
            .font(.system(.caption, design: .rounded).bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15)))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
    }
}

// MARK: - ViewModel

final class MainWindowViewModel: ObservableObject {
    @Published var externalDisplays: [ExternalDisplay] = []
    @Published var autoBrightnessEnabled: Bool {
        didSet {
            autoBrightnessLoop.isEnabled = autoBrightnessEnabled
            persistSettings()
        }
    }
    @Published var sensorInterval: TimeInterval {
        didSet {
            autoBrightnessLoop.intervalSeconds = sensorInterval
            persistSettings()
        }
    }
    @Published var currentMacBrightness: Double?

    private var brightnessCache: [CGDirectDisplayID: Int] = [:]
    private let autoBrightnessLoop: AutoBrightnessLoop
    private let mediaKeyTap: MediaKeyTap
    private var refreshTimer: Timer?

    init(autoBrightnessLoop: AutoBrightnessLoop, mediaKeyTap: MediaKeyTap) {
        self.autoBrightnessLoop = autoBrightnessLoop
        self.mediaKeyTap = mediaKeyTap
        self.autoBrightnessEnabled = autoBrightnessLoop.isEnabled
        self.sensorInterval = autoBrightnessLoop.intervalSeconds

        autoBrightnessLoop.onBrightnessUpdated = { [weak self] displayID, brightness in
            DispatchQueue.main.async {
                self?.brightnessCache[displayID] = brightness
                self?.objectWillChange.send()
            }
        }
    }

    func brightness(for display: ExternalDisplay) -> Int {
        brightnessCache[display.displayID] ?? 50
    }

    func setBrightness(_ value: Int, for display: ExternalDisplay) {
        brightnessCache[display.displayID] = value
        autoBrightnessLoop.triggerManualOverride()
        autoBrightnessLoop.recordBrightness(value, for: display.displayID)
        DispatchQueue.global(qos: .userInitiated).async {
            _ = DisplayManager.shared.setBrightness(for: display, value: value)
        }
    }

    func startRefresh() {
        refreshDisplayList()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refreshDisplayList()
        }
    }

    func stopRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func refreshDisplayList() {
        let displays = DisplayManager.shared.externalDisplays()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Always read fresh brightness from DDC
            var freshBrightness: [CGDirectDisplayID: Int] = [:]
            for display in displays {
                if let value = DisplayManager.shared.getBrightness(for: display) {
                    freshBrightness[display.displayID] = value
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                // DDC-read values always win
                self.brightnessCache.merge(freshBrightness) { _, ddcValue in ddcValue }
                self.externalDisplays = displays
                self.currentMacBrightness = self.autoBrightnessLoop.currentMacBrightness
            }
        }
    }

    private func persistSettings() {
        let defaults = UserDefaults.standard
        defaults.set(autoBrightnessEnabled, forKey: "autoBrightnessEnabled")
        defaults.set(sensorInterval, forKey: "sensorInterval")
    }
}
