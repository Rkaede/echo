import Combine
import SwiftUI

struct OverlayWaveformView: View {
  let level: CGFloat
  let color: Color

  private static let barCount = 10
  private static let minHeight: CGFloat = 4
  private static let maxHeight: CGFloat = 24
  private static let idleHeight: CGFloat = 4
  private static let barWidth: CGFloat = 1.5
  private static let spacing: CGFloat = 1.5
  private static let updateInterval: TimeInterval = 0.05
  private static let silenceThreshold: CGFloat = 0.01

  @State private var barHeights: [CGFloat]
  private let timer = Timer.publish(every: Self.updateInterval, on: .main, in: .common)
    .autoconnect()

  init(
    level: CGFloat = 0, color: Color = Color(red: 0.882, green: 0.325, blue: 0.373, opacity: 1.0)
  ) {
    self.level = level
    self.color = color
    _barHeights = State(initialValue: Array(repeating: Self.idleHeight, count: Self.barCount))
  }

  var body: some View {
    HStack(alignment: .center, spacing: Self.spacing) {
      ForEach(Array(barHeights.enumerated()), id: \.offset) { _, height in
        Capsule()
          .fill(color)
          .frame(width: Self.barWidth, height: height)
      }
    }
    .frame(width: totalWidth, height: Self.maxHeight)
    .accessibilityHidden(true)
    .onAppear {
      updateBars(with: level)
    }
    .onChange(of: level) { newValue in
      updateBars(with: newValue)
    }
    .onReceive(timer) { _ in
      updateBars(with: level)
    }
  }

  private var totalWidth: CGFloat {
    let count = CGFloat(Self.barCount)
    return count * Self.barWidth + (count - 1) * Self.spacing
  }

  private func updateBars(with rawLevel: CGFloat) {
    let clamped = max(0, min(rawLevel, 1))

    if clamped <= Self.silenceThreshold {
      withAnimation(.easeOut(duration: 0.18)) {
        barHeights = Array(repeating: Self.idleHeight, count: Self.barCount)
      }
      return
    }

    var updated = barHeights
    if updated.count >= Self.barCount {
      updated.removeFirst()
    }
    updated.append(generateHeight(for: clamped))

    withAnimation(.easeOut(duration: 0.18)) {
      barHeights = updated
    }
  }

  private func generateHeight(for level: CGFloat) -> CGFloat {
    let dynamicRange = Self.maxHeight - Self.minHeight
    // Amplify the input level by 1.5x to make it more visible
    let amplifiedLevel = min(level * 1.5, 1.0)
    let base = Self.minHeight + dynamicRange * amplifiedLevel

    // Reduce variance for low levels to minimize jitter during silence
    let varianceScale = amplifiedLevel < 0.1 ? 0.05 : 0.25
    let variance = dynamicRange * varianceScale
    let randomOffset = CGFloat.random(in: -variance...variance)
    let candidate = base + randomOffset
    return min(max(candidate, Self.minHeight), Self.maxHeight)
  }
}

#Preview("Live Level") {
  struct PreviewWrapper: View {
    @State private var level: CGFloat = 0

    var body: some View {
      OverlayWaveformView(level: level)
        .padding()
        .background(Color.black)
        .onAppear {
          Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            level = CGFloat.random(in: 0...1)
          }
        }
    }
  }

  return PreviewWrapper()
}
