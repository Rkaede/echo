import SwiftUI

struct OverlayWaveformView: View {
  // The only view that observes the meter, so mic ticks re-render the bars and nothing else.
  @EnvironmentObject private var meter: AudioLevelMeter
  let color: Color

  // Default values (used in RELEASE builds)
  private static let defaultBarCount = 11
  private static let defaultMinHeight: CGFloat = 1.0714285714285714
  private static let defaultMaxHeight: CGFloat = 28.238095238095244
  private static let defaultIdleHeight: CGFloat = 0
  private static let defaultBarWidth: CGFloat = 1.9733333333333334
  private static let defaultSpacing: CGFloat = 0.9523809523809523
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

  /// One eased tween of every bar from `from` toward `to`, finishing at `settleDeadline`.
  private struct BarTween {
    var from: [CGFloat]
    var to: [CGFloat]
    var start: Date
    var settleDeadline: Date

    /// The tween's value at `date` rather than at a specific frame, so it stays correct no
    /// matter how often the TimelineView actually redraws.
    func heights(at date: Date) -> [CGFloat] {
      guard date < settleDeadline else { return to }
      let duration = settleDeadline.timeIntervalSince(start)
      guard duration > 0 else { return to }
      let t = min(1, max(0, date.timeIntervalSince(start) / duration))
      let eased = 1 - pow(1 - t, 3)
      return zip(from, to).map { $0 + ($1 - $0) * eased }
    }
  }

  // New metering data only arrives every ~30ms (AudioRecorder's poll rate), which reads as a
  // visible stutter if the bars simply snap to it. Instead every update starts a short tween
  // from wherever the bars currently are toward the new target, and a TimelineView repaints
  // that tween on every display frame — so the waveform looks as smooth as the screen's
  // refresh rate regardless of how often real data actually arrives. The waveform is only on
  // screen while recording, when data never stops arriving, so the timeline simply runs for
  // as long as the view exists.
  @State private var tween: BarTween

  init(color: Color = Color(red: 0.882, green: 0.325, blue: 0.373, opacity: 1.0)) {
    self.color = color
    let idle = Array(repeating: Self.defaultIdleHeight, count: Self.defaultBarCount)
    _tween = State(
      initialValue: BarTween(from: idle, to: idle, start: .distantPast, settleDeadline: .distantPast)
    )
  }

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
      let heights = Array(tween.heights(at: timeline.date).prefix(barCount))
      let barWidth = barWidth
      let pitch = barWidth + spacing
      let color = color
      // One Canvas draw per frame instead of laying out a view per bar.
      Canvas { context, size in
        let scale = context.environment.displayScale
        func pixelAligned(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }

        for (index, height) in heights.enumerated() where height > 0 {
          let rect = CGRect(
            x: pixelAligned(CGFloat(index) * pitch),
            y: (size.height - height) / 2,
            width: max(pixelAligned(barWidth), 1 / scale),
            height: height
          )
          context.fill(Capsule().path(in: rect), with: .color(color))
        }
      }
      .frame(width: totalWidth, height: maxHeight)
    }
    .accessibilityHidden(true)
    .onAppear {
      updateBars(from: meter.samples)
    }
    .onChange(of: meter.samples) { _, samples in
      updateBars(from: samples)
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
    guard tween.to.count != barCount else { return }
    beginTransition(to: Array(repeating: idleHeight, count: barCount), duration: 0)
  }

  /// Starts a new tween from wherever the bars visually are right now toward `heights`.
  private func beginTransition(to heights: [CGFloat], duration: TimeInterval) {
    let now = Date()
    // Already resting on this target (e.g. silence after the bars have decayed): writing the
    // same tween again would only invalidate the view for nothing.
    if heights == tween.to && now >= tween.settleDeadline { return }

    tween = BarTween(
      from: tween.heights(at: now),
      to: heights,
      start: now,
      settleDeadline: now.addingTimeInterval(duration)
    )
  }

  private func updateBars(from samples: [Float]) {
    ensureBarCount()

    // Silence, including the empty history before the first metering tick
    let maxSample = samples.max() ?? 0
    if maxSample <= Float(silenceThreshold) {
      beginTransition(to: Array(repeating: idleHeight, count: barCount), duration: decayDuration)
      return
    }

    // Right-align to the most recently captured samples so the newest reading always lands
    // in the rightmost bar, regardless of how much history AudioLevelMeter keeps around.
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
}

#Preview("Live Level") {
  struct PreviewWrapper: View {
    @StateObject private var meter = AudioLevelMeter()

    var body: some View {
      OverlayWaveformView()
        .environmentObject(meter)
        .padding()
        .background(Color.black)
        .task {
          while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(RecordingSignal.meteringInterval * 1_000_000_000))
            meter.append(Float.random(in: 0...1))
          }
        }
    }
  }

  return PreviewWrapper()
}
