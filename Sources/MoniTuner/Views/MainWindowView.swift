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

                    if let lux = viewModel.currentLux {
                        HStack {
                            Image(systemName: "light.max")
                                .foregroundColor(.yellow)
                            Text("Ambient: \(Int(round(lux))) lux")
                                .foregroundColor(.secondary)
                        }
                    }
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
    @Published var currentLux: Double?

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
            self?.brightnessCache[displayID] = brightness
            self?.refreshDisplayList()
        }
    }

    func brightness(for display: ExternalDisplay) -> Int {
        brightnessCache[display.displayID]
            ?? DisplayManager.shared.getBrightness(for: display)
            ?? 50
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
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshDisplayList()
        }
    }

    func stopRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func refreshDisplayList() {
        DispatchQueue.main.async { [weak self] in
            self?.externalDisplays = DisplayManager.shared.externalDisplays()
            self?.currentLux = self?.autoBrightnessLoop.currentLux
        }
    }

    private func persistSettings() {
        let defaults = UserDefaults.standard
        defaults.set(autoBrightnessEnabled, forKey: "autoBrightnessEnabled")
        defaults.set(sensorInterval, forKey: "sensorInterval")
    }
}
