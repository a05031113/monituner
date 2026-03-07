import MoniTunerCore
import SwiftUI

struct MonitorCardView: View {
    let display: ExternalDisplay
    let brightness: Int
    let onBrightnessChanged: (Int) -> Void

    @State private var sliderValue: Double = 50
    @State private var isDragging = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "display")
                    .font(.title2)
                Text(display.name)
                    .font(.headline)
                Spacer()
                Text("\(isDragging ? Int(round(sliderValue)) : brightness)%")
                    .font(.title3)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                Image(systemName: "sun.min")
                    .foregroundColor(.secondary)
                Slider(value: $sliderValue, in: 0...100, step: 1) { editing in
                    isDragging = editing
                    if !editing {
                        onBrightnessChanged(Int(round(sliderValue)))
                    }
                }
                Image(systemName: "sun.max")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
        .onAppear { sliderValue = Double(brightness) }
        .onChange(of: brightness) { newValue in
            if !isDragging {
                sliderValue = Double(newValue)
            }
        }
    }
}
