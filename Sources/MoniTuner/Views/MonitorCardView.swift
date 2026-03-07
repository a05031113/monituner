import MoniTunerCore
import SwiftUI

struct MonitorCardView: View {
    let display: ExternalDisplay
    @State private var brightness: Double
    let onBrightnessChanged: (Int) -> Void

    init(display: ExternalDisplay, brightness: Int, onBrightnessChanged: @escaping (Int) -> Void) {
        self.display = display
        self._brightness = State(initialValue: Double(brightness))
        self.onBrightnessChanged = onBrightnessChanged
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "display")
                    .font(.title2)
                Text(display.name)
                    .font(.headline)
                Spacer()
                Text("\(Int(round(brightness)))%")
                    .font(.title3)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                Image(systemName: "sun.min")
                    .foregroundColor(.secondary)
                Slider(value: $brightness, in: 0...100, step: 1) { editing in
                    if !editing {
                        onBrightnessChanged(Int(round(brightness)))
                    }
                }
                Image(systemName: "sun.max")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }
}
