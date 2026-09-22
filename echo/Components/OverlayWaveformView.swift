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

  // New metering data only arrives every ~30ms (AudioRecorder's poll rate), which reads as a
  // visible stutter if the bars simply snap to it. Instead every update starts a short tween
  // from wherever the bars currently are toward the new target, and a TimelineView repaints
  // that tween on every display frame — so the waveform looks as smooth as the screen's
  // refresh rate regardless of how often real data actually arrives.
  @State private var previousHeights: [CGFloat]
  @State private var targetHeights: [CGFloat]
  @State private var transitionStart = Date()
  @State private var transitionDuration: TimeInterval = 0
  @State private var isAnimating = false
  @State private var animationGeneration = 0

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
    let idle = Array(repeating: Self.defaultIdleHeight, count: Self.defaultBarCount)
    _previousHeights = State(initialValue: idle)
    _targetHeights = State(initialValue: idle)
  }

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isAnimating)) { timeline in
      let heights = currentHeights(at: timeline.date)
      HStack(alignment: .center, spacing: spacing) {
        ForEach(0..<barCount, id: \.self) { index in
          Capsule()
            .fill(color)
            .frame(width: barWidth, height: index < heights.count ? heights[index] : idleHeight)
        }
      }
      .frame(width: totalWidth, height: maxHeight)
    }
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
    guard targetHeights.count != barCount else { return }
    beginTransition(to: Array(repeating: idleHeight, count: barCount), duration: 0)
  }

  /// The tween's current value: `previousHeights` eased toward `targetHeights` over
  /// `transitionDuration`, evaluated at `date` rather than tied to a specific frame so it
  /// stays correct no matter how often the TimelineView actually redraws.
  private func currentHeights(at date: Date) -> [CGFloat] {
    guard transitionDuration > 0 else { return targetHeights }
    let elapsed = date.timeIntervalSince(transitionStart)
    let t = min(1, max(0, elapsed / transitionDuration))
    let eased = 1 - pow(1 - t, 3)
    return zip(previousHeights, targetHeights).map { $0 + ($1 - $0) * eased }
  }

  /// Starts a new tween from wherever the bars visually are right now toward `heights`, and
  /// schedules the TimelineView to stop ticking once it settles — unless a later update
  /// supersedes it first — so the waveform doesn't spin the display link while idle.
  private func beginTransition(to heights: [CGFloat], duration: TimeInterval) {
    let now = Date()
    previousHeights = currentHeights(at: now)
    targetHeights = heights
    transitionStart = now
    transitionDuration = duration
    isAnimating = true

    animationGeneration += 1
    let generation = animationGeneration
    guard duration > 0 else {
      isAnimating = false
      return
    }
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
      if generation == animationGeneration {
        isAnimating = false
      }
    }
  }

  private func updateBarsFromSamples() {
    ensureBarCount()

    // If no samples, fall back to level-based rendering
    guard !samples.isEmpty else {
      updateBars(with: level)
      return
    }

    // Check if all samples are below threshold (silence)
    let maxSample = samples.max() ?? 0
    if maxSample <= Float(silenceThreshold) {
      beginTransition(to: Array(repeating: idleHeight, count: barCount), duration: decayDuration)
      return
    }

    // Right-align to the most recently captured samples so the newest reading always lands
    // in the rightmost bar, regardless of how much history AudioRecorder keeps around.
    let recent = Array(samples.suffix(barCount))
    let padded = recent.count < barCount
      ? Array(repeating: Float(0), count: barCount - recent.count) + recent
      : recent

    let dynamicRange = maxHeight - minHeight
    let newHeights = padded.map { sampleValue -> CGFloat in
      let normalized = max(CGFloat(sampleValue) - noiseFloor, 0) / (1 - noiseFloor)
      let eased = CGFloat(pow(Double(normalized), Double(responseExponent)))
      let height = minHeight + dynamicRange * eased
      return min(max(height, minHeight), maxHeight)
    }

    beginTransition(to: newHeights, duration: updateDuration)
  }

  private func updateBars(with rawLevel: CGFloat) {
    ensureBarCount()
    let clamped = max(0, min(rawLevel, 1))

    if clamped <= silenceThreshold {
      beginTransition(to: Array(repeating: idleHeight, count: barCount), duration: decayDuration)
      return
    }

    // Update all bars in place with slight variations for natural look
    let newHeights = (0..<barCount).map { _ in generateHeight(for: clamped) }
    beginTransition(to: newHeights, duration: updateDuration)
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
