import SwiftUI

#if DEBUG
/// Observable settings for real-time waveform tuning (DEBUG only)
@MainActor
class WaveformSettings: ObservableObject {
  static let shared = WaveformSettings()

  @Published var barCount: Int = 12
  @Published var minHeight: CGFloat = 1.25
  @Published var maxHeight: CGFloat = 28
  @Published var barWidth: CGFloat = 1.64
  @Published var spacing: CGFloat = 1.37
  @Published var updateInterval: TimeInterval = 0.125
  @Published var noiseFloor: CGFloat = 0.06
  @Published var responseExponent: CGFloat = 0.56
  @Published var silenceThreshold: CGFloat = 0.008
  @Published var decayDuration: TimeInterval = 0.7
  @Published var updateDuration: TimeInterval = 0.07

  private init() {}
}

/// Debug panel with sliders for tuning waveform parameters in real-time
struct WaveformDebugView: View {
  @ObservedObject var settings = WaveformSettings.shared
  @State private var currentLevel: CGFloat = 0
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack {
        Text("Waveform Debug")
          .font(.headline)
        Spacer()
        Button("Done") { dismiss() }
      }
      .padding()
      .background(Color(NSColor.windowBackgroundColor))

      // Preview waveform
      VStack {
        Text("Preview (Current Level: \(String(format: "%.2f", currentLevel)))")
          .font(.caption)
          .foregroundColor(.secondary)

        HStack {
          Spacer()
          OverlayWaveformView(level: currentLevel)
            .frame(height: 40)
          Spacer()
        }
        .padding()
        .background(Color.black.opacity(0.8))
        .cornerRadius(8)

        // Test level slider
        HStack {
          Text("Test Level")
            .frame(width: 120, alignment: .leading)
          Slider(value: $currentLevel, in: 0...1)
          Text("\(String(format: "%.2f", currentLevel))")
            .frame(width: 50)
            .monospacedDigit()
        }
        .padding(.horizontal)
      }
      .padding()
      .background(Color(NSColor.controlBackgroundColor))

      Divider()

      // Settings sliders
      ScrollView {
        VStack(spacing: 16) {
          Group {
            SliderRow(label: "Bar Count", value: Binding(
              get: { Double(settings.barCount) },
              set: { settings.barCount = Int($0) }
            ), range: 3...20, format: "%.0f")

            SliderRow(label: "Min Height", value: $settings.minHeight, range: 0...10, format: "%.1f")
            SliderRow(label: "Max Height", value: $settings.maxHeight, range: 10...50, format: "%.0f")
            SliderRow(label: "Bar Width", value: $settings.barWidth, range: 1...5, format: "%.1f")
            SliderRow(label: "Spacing", value: $settings.spacing, range: 0...5, format: "%.1f")
          }

          Divider()

          Group {
            SliderRow(label: "Update Interval", value: $settings.updateInterval, range: 0.01...0.2, format: "%.2f")
            SliderRow(label: "Noise Floor", value: $settings.noiseFloor, range: 0...0.5, format: "%.2f")
            SliderRow(label: "Response Exp", value: $settings.responseExponent, range: 0.5...4, format: "%.1f")
            SliderRow(label: "Silence Thresh", value: $settings.silenceThreshold, range: 0...0.2, format: "%.3f")
          }

          Divider()

          Group {
            SliderRow(label: "Decay Duration", value: $settings.decayDuration, range: 0.1...1.0, format: "%.2f")
            SliderRow(label: "Update Duration", value: $settings.updateDuration, range: 0.05...0.5, format: "%.2f")
          }

          Divider()

          // Reset button
          Button("Reset to Defaults") {
            settings.barCount = 12
            settings.minHeight = 1.25
            settings.maxHeight = 28
            settings.barWidth = 1.64
            settings.spacing = 1.37
            settings.updateInterval = 0.125
            settings.noiseFloor = 0.06
            settings.responseExponent = 0.56
            settings.silenceThreshold = 0.008
            settings.decayDuration = 0.7
            settings.updateDuration = 0.07
          }
          .padding()

          // Copy current values as code
          Button("Copy Values as Code") {
            let code = """
              private static let barCount = \(settings.barCount)
              private static let minHeight: CGFloat = \(settings.minHeight)
              private static let maxHeight: CGFloat = \(settings.maxHeight)
              private static let barWidth: CGFloat = \(settings.barWidth)
              private static let spacing: CGFloat = \(settings.spacing)
              private static let updateInterval: TimeInterval = \(settings.updateInterval)
              private static let noiseFloor: CGFloat = \(settings.noiseFloor)
              private static let responseExponent: CGFloat = \(settings.responseExponent)
              private static let silenceThreshold: CGFloat = \(settings.silenceThreshold)
              private static let decayDuration: TimeInterval = \(settings.decayDuration)
              private static let updateDuration: TimeInterval = \(settings.updateDuration)
              """
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
          }
          .padding(.bottom)
        }
        .padding()
      }
    }
    .frame(width: 400, height: 600)
  }
}

struct SliderRow: View {
  let label: String
  @Binding var value: Double
  let range: ClosedRange<Double>
  let format: String

  init(label: String, value: Binding<Double>, range: ClosedRange<Double>, format: String = "%.2f") {
    self.label = label
    self._value = value
    self.range = range
    self.format = format
  }

  init(label: String, value: Binding<CGFloat>, range: ClosedRange<Double>, format: String = "%.2f") {
    self.label = label
    self._value = Binding(
      get: { Double(value.wrappedValue) },
      set: { value.wrappedValue = CGFloat($0) }
    )
    self.range = range
    self.format = format
  }

  var body: some View {
    HStack {
      Text(label)
        .frame(width: 120, alignment: .leading)
      Slider(value: $value, in: range)
      Text(String(format: format, value))
        .frame(width: 50)
        .monospacedDigit()
    }
  }
}

#Preview {
  WaveformDebugView()
}
#endif
