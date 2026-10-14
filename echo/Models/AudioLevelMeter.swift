import Combine
import Foundation

/// Live microphone level history that drives the recording overlay's waveform.
///
/// Deliberately kept out of `AppState`: it publishes on every metering tick (~33 times a
/// second while recording), and every view observing it re-renders at that rate. Only
/// `OverlayWaveformView` should observe it, so the app's scenes, menu bar, and the History
/// and Settings windows don't re-run their bodies on every mic tick.
@MainActor
final class AudioLevelMeter: ObservableObject {
  static let shared = AudioLevelMeter()

  /// How many readings `samples` holds. Kept comfortably above the debug waveform's max
  /// bar-count slider (20) so `OverlayWaveformView` can always right-align to its most
  /// recent samples without ever running short of history.
  nonisolated static let historyLength = 32

  /// The most recent `historyLength` normalized levels (0...1), oldest first, zero-padded on
  /// the left so the newest reading is always last. Empty while not recording.
  @Published private(set) var samples: [Float] = []

  private var history: [Float] = []

  init() {}

  /// Records one meter reading and publishes the updated window as a single change.
  func append(_ level: Float) {
    history.append(level)
    if history.count > Self.historyLength {
      history.removeFirst(history.count - Self.historyLength)
    }
    samples = Self.window(of: history, length: Self.historyLength)
  }

  func reset() {
    history = []
    // Skip the publish when already empty so a stop that follows a failed start doesn't
    // wake observers for nothing.
    guard !samples.isEmpty else { return }
    samples = []
  }

  /// The last `length` entries of `history`, zero-padded on the left to exactly `length`.
  nonisolated static func window(of history: [Float], length: Int) -> [Float] {
    guard length > 0 else { return [] }

    let recent = Array(history.suffix(length))
    guard recent.count < length else { return recent }

    return Array(repeating: 0, count: length - recent.count) + recent
  }
}
