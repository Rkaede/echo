import Combine
import SwiftUI

struct OverlayWaveformView: View {
  let level: CGFloat
  let color: Color

  private static let barCount = 10
  private static let minHeight: CGFloat = 0.1
  private static let maxHeight: CGFloat = 24
  private static let idleHeight: CGFloat = 0
  private static let barWidth: CGFloat = 1.5
  private static let spacing: CGFloat = 1.5
  private static let updateInterval: TimeInterval = 0.05
  private static let noiseFloor: CGFloat = 0.5
  private static let responseExponent: CGFloat = 1.6
  private static let silenceThreshold: CGFloat = Self.noiseFloor

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
    .onChange(of: level) {
      updateBars(with: level)
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

    // Suppress readings near the noise floor before shaping the curve
    let normalized = max(level - Self.noiseFloor, 0) / (1 - Self.noiseFloor)
    let eased = CGFloat(pow(Double(normalized), Double(Self.responseExponent)))
    let base = Self.minHeight + dynamicRange * eased

    // Keep jitter minimal while still allowing subtle motion
    let varianceScale = eased < 0.25 ? 0.015 : 0.04
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
