import Combine
import SwiftUI

struct OverlayWaveformView: View {
  let level: CGFloat
  let samples: [Float]
  let color: Color

  // Default values (used in RELEASE builds)
  private static let defaultBarCount = 11
  private static let defaultMinHeight: CGFloat = 1.0714285714285714
  private static let defaultMaxHeight: CGFloat = 28.238095238095244
  private static let defaultIdleHeight: CGFloat = 0
  private static let defaultBarWidth: CGFloat = 1.9733333333333334
  private static let defaultSpacing: CGFloat = 0.9523809523809523
  private static let defaultUpdateInterval: TimeInterval = 0.11482142857142859
  private static let defaultNoiseFloor: CGFloat = 0.09523809523809523
  private static let defaultResponseExponent: CGFloat = 0.5
  private static let defaultSilenceThreshold: CGFloat = 0.0035714285714285713
  private static let defaultDecayDuration: TimeInterval = 0.41607142857142854
  private static let defaultUpdateDuration: TimeInterval = 0.10051020408163266

  #if DEBUG
  @ObservedObject private var settings = WaveformSettings.shared

  private var barCount: Int { settings.barCount }
  private var minHeight: CGFloat { settings.minHeight }
  private var maxHeight: CGFloat { settings.maxHeight }
  private var idleHeight: CGFloat { Self.defaultIdleHeight }
  private var barWidth: CGFloat { settings.barWidth }
  private var spacing: CGFloat { settings.spacing }
  private var noiseFloor: CGFloat { settings.noiseFloor }
  private var responseExponent: CGFloat { settings.responseExponent }
  private var silenceThreshold: CGFloat { settings.silenceThreshold }
  private var decayDuration: TimeInterval { settings.decayDuration }
  private var updateDuration: TimeInterval { settings.updateDuration }
  #else
  private var barCount: Int { Self.defaultBarCount }
  private var minHeight: CGFloat { Self.defaultMinHeight }
  private var maxHeight: CGFloat { Self.defaultMaxHeight }
  private var idleHeight: CGFloat { Self.defaultIdleHeight }
  private var barWidth: CGFloat { Self.defaultBarWidth }
  private var spacing: CGFloat { Self.defaultSpacing }
  private var noiseFloor: CGFloat { Self.defaultNoiseFloor }
  private var responseExponent: CGFloat { Self.defaultResponseExponent }
  private var silenceThreshold: CGFloat { Self.defaultSilenceThreshold }
  private var decayDuration: TimeInterval { Self.defaultDecayDuration }
  private var updateDuration: TimeInterval { Self.defaultUpdateDuration }
  #endif

  @State private var barHeights: [CGFloat]
  private let timer = Timer.publish(every: Self.defaultUpdateInterval, on: .main, in: .common)
    .autoconnect()

  init(
    level: CGFloat = 0,
    samples: [Float] = [],
    color: Color = Color(red: 0.882, green: 0.325, blue: 0.373, opacity: 1.0)
  ) {
    self.level = level
    self.samples = samples
    self.color = color
    _barHeights = State(initialValue: Array(repeating: Self.defaultIdleHeight, count: Self.defaultBarCount))
  }

  var body: some View {
    HStack(alignment: .center, spacing: spacing) {
      ForEach(0..<barCount, id: \.self) { index in
        Capsule()
          .fill(color)
          .frame(width: barWidth, height: index < barHeights.count ? barHeights[index] : idleHeight)
      }
    }
    .frame(width: totalWidth, height: maxHeight)
    .accessibilityHidden(true)
    .onAppear {
      ensureBarCount()
      updateBarsFromSamples()
    }
    .onChange(of: samples) { _, _ in
      updateBarsFromSamples()
    }
    .onChange(of: level) {
      // Fallback to level-based if no samples
      if samples.isEmpty {
        updateBars(with: level)
      }
    }
    .onReceive(timer) { _ in
      ensureBarCount()
      // Only use timer-based updates if no samples provided
      if samples.isEmpty {
        updateBars(with: level)
      }
    }
    #if DEBUG
    .onChange(of: settings.barCount) { _, _ in
      ensureBarCount()
    }
    #endif
  }

  private var totalWidth: CGFloat {
    let count = CGFloat(barCount)
    return count * barWidth + (count - 1) * spacing
  }

  private func ensureBarCount() {
    if barHeights.count != barCount {
      barHeights = Array(repeating: idleHeight, count: barCount)
    }
  }

  private func updateBarsFromSamples() {
    // If no samples, fall back to level-based rendering
    guard !samples.isEmpty else {
      updateBars(with: level)
      return
    }

    // Check if all samples are below threshold (silence)
    let maxSample = samples.max() ?? 0
    if maxSample <= Float(silenceThreshold) {
      withAnimation(.easeOut(duration: decayDuration)) {
        barHeights = Array(repeating: idleHeight, count: barCount)
      }
      return
    }

    // Convert samples to bar heights
    let dynamicRange = maxHeight - minHeight
    var newHeights: [CGFloat] = []

    for i in 0..<barCount {
      // Get sample for this bar (with bounds checking)
      let sampleValue: Float
      if i < samples.count {
        sampleValue = samples[i]
      } else if !samples.isEmpty {
        // Wrap around if we have fewer samples than bars
        sampleValue = samples[i % samples.count]
      } else {
        sampleValue = 0
      }

      // Apply noise floor and response curve
      let normalized = max(CGFloat(sampleValue) - noiseFloor, 0) / (1 - noiseFloor)
      let eased = CGFloat(pow(Double(normalized), Double(responseExponent)))
      let height = minHeight + dynamicRange * eased

      // Clamp to valid range
      newHeights.append(min(max(height, minHeight), maxHeight))
    }

    withAnimation(.easeOut(duration: updateDuration)) {
      barHeights = newHeights
    }
  }

  private func updateBars(with rawLevel: CGFloat) {
    let clamped = max(0, min(rawLevel, 1))

    if clamped <= silenceThreshold {
      withAnimation(.easeOut(duration: decayDuration)) {
        barHeights = Array(repeating: idleHeight, count: barCount)
      }
      return
    }

    // Update all bars in place with slight variations for natural look
    var newHeights: [CGFloat] = []
    for _ in 0..<barCount {
      newHeights.append(generateHeight(for: clamped))
    }

    withAnimation(.easeOut(duration: updateDuration)) {
      barHeights = newHeights
    }
  }

  private func generateHeight(for level: CGFloat) -> CGFloat {
    let dynamicRange = maxHeight - minHeight

    // Suppress readings near the noise floor before shaping the curve
    let normalized = max(level - noiseFloor, 0) / (1 - noiseFloor)
    let eased = CGFloat(pow(Double(normalized), Double(responseExponent)))
    let base = minHeight + dynamicRange * eased

    // Keep jitter minimal while still allowing subtle motion
    let varianceScale = eased < 0.25 ? 0.015 : 0.04
    let variance = dynamicRange * varianceScale
    let randomOffset = CGFloat.random(in: -variance...variance)
    let candidate = base + randomOffset
    return min(max(candidate, minHeight), maxHeight)
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
