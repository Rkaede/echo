@preconcurrency import AVFoundation
import Foundation

/// A sound a recording event can play: one Cuelume cue, or none.
struct SoundOption: Identifiable, Equatable {
  let id: String
  let label: String
  let cue: CuelumeCue?

  init(cue: CuelumeCue) {
    id = cue.rawValue
    label = cue.label
    self.cue = cue
  }

  private init(id: String, label: String) {
    self.id = id
    self.label = label
    cue = nil
  }

  static let none = SoundOption(id: "none", label: "None")

  /// The cues offered for Echo's events, in Cuelume's order of jobs: input, motion, outcomes.
  /// `type` and `count` are left out: a keystroke and a rolling number don't describe a recording.
  static let pickerCues: [CuelumeCue] = [
    .tap, .select, .toggle, .open, .close, .navigate, .loading, .ready, .success, .warning, .error,
    .attention,
  ]

  static let allOptions: [SoundOption] = [.none] + pickerCues.map(SoundOption.init(cue:))

  /// A short tap, so little of it reaches the recording that has just started.
  static let defaultRecordingStart = SoundOption(cue: .tap)
  /// Cuelume's cue for a result that has arrived.
  static let defaultTranscriptionComplete = SoundOption(cue: .ready)

  static func option(id: String) -> SoundOption? {
    allOptions.first { $0.id == id }
  }

  /// The stored id to keep, or `fallback`'s for ids this version doesn't offer, such as the
  /// `click01`–`click04` files earlier versions played.
  static func migratedID(_ storedID: String, fallback: SoundOption) -> String {
    option(id: storedID) == nil ? fallback.id : storedID
  }
}

/// Plays Echo's sound effects, synthesised by `CuelumeSynth` rather than read from files.
@MainActor
class SoundManager: ObservableObject {
  static let shared = SoundManager()

  private let unifiedEngine = UnifiedAudioEngine.shared
  private let settingsManager = SettingsManager.shared

  private enum Slot: String, CaseIterable {
    case recordingStart = "recording start"
    case transcriptionComplete = "transcription complete"
  }

  private struct Selection: Equatable {
    let cue: CuelumeCue
    let theme: CuelumeTheme
  }

  /// Each slot's next play, rendered ahead so it starts at once. Every play renders a fresh take
  /// for the next, so the per-play variation Cuelume builds in is heard.
  private var nextTakes: [Slot: (selection: Selection, buffer: AVAudioPCMBuffer)] = [:]
  private var renderTasks: [Slot: Task<Void, Never>] = [:]
  /// What each slot was last asked to render, so a settings change renders only what changed.
  private var preparedSelections: [Slot: Selection?] = [:]

  private var soundChangeObserver: NSObjectProtocol?

  private init() {
    migrateLegacySelections()
    for slot in Slot.allCases { prepare(slot) }
    setupSoundChangeObserver()
  }

  // MARK: - Public Interface

  /// Plays the recording start sound; returns its length, or nil when nothing plays.
  @discardableResult
  func playRecordingStartSound(completion: (() -> Void)? = nil) -> TimeInterval? {
    guard settingsManager.soundEnabled && settingsManager.soundOnRecordingStart else {
      completion?()
      return nil
    }
    return play(.recordingStart, completion: completion)
  }

  func playTranscriptionCompleteSound() {
    guard settingsManager.soundEnabled && settingsManager.soundOnTranscriptionComplete else {
      return
    }
    play(.transcriptionComplete)
  }

  func testRecordingStartSound() {
    play(.recordingStart)
  }

  func testTranscriptionCompleteSound() {
    play(.transcriptionComplete)
  }

  /// Plays `cue` in the current theme, for previewing a choice in Settings.
  func preview(_ cue: CuelumeCue) {
    let theme = currentTheme
    Task {
      let rendering = await Task.detached(priority: .userInitiated) {
        CuelumeSynth.render(cue, theme: theme)
      }.value
      guard let buffer = rendering.makeBuffer() else { return }
      unifiedEngine.playSound(buffer, label: "preview \(cue.rawValue)")
    }
  }

  // MARK: - Rendering

  private var currentTheme: CuelumeTheme {
    CuelumeTheme(rawValue: settingsManager.soundTheme) ?? .standard
  }

  private func selection(for slot: Slot) -> Selection? {
    let id: String
    switch slot {
    case .recordingStart: id = settingsManager.recordingStartSound
    case .transcriptionComplete: id = settingsManager.transcriptionCompleteSound
    }
    guard let cue = SoundOption.option(id: id)?.cue else { return nil }
    return Selection(cue: cue, theme: currentTheme)
  }

  /// Renders the slot's next take in the background.
  private func prepare(_ slot: Slot) {
    renderTasks[slot]?.cancel()
    let selection = selection(for: slot)
    preparedSelections.updateValue(selection, forKey: slot)
    guard let selection else {
      nextTakes[slot] = nil
      return
    }
    renderTasks[slot] = Task { [weak self] in
      let rendering = await Task.detached(priority: .userInitiated) {
        CuelumeSynth.render(selection.cue, theme: selection.theme)
      }.value
      guard let self, !Task.isCancelled, self.selection(for: slot) == selection,
        let buffer = rendering.makeBuffer()
      else { return }
      self.nextTakes[slot] = (selection, buffer)
    }
  }

  @discardableResult
  private func play(_ slot: Slot, completion: (() -> Void)? = nil) -> TimeInterval? {
    guard let selection = selection(for: slot) else {
      completion?()
      return nil
    }

    // A take is normally ready; render one here if a play comes before it, or after a change.
    let buffer: AVAudioPCMBuffer?
    if let take = nextTakes[slot], take.selection == selection {
      buffer = take.buffer
    } else {
      buffer = CuelumeSynth.render(selection.cue, theme: selection.theme).makeBuffer()
    }
    nextTakes[slot] = nil
    prepare(slot)

    guard let buffer else {
      completion?()
      return nil
    }
    unifiedEngine.playSound(buffer, label: slot.rawValue, completion: completion)
    return Double(buffer.frameLength) / buffer.format.sampleRate
  }

  // MARK: - Settings

  private func migrateLegacySelections() {
    let start = SoundOption.migratedID(
      settingsManager.recordingStartSound, fallback: .defaultRecordingStart)
    if start != settingsManager.recordingStartSound {
      settingsManager.recordingStartSound = start
    }
    let complete = SoundOption.migratedID(
      settingsManager.transcriptionCompleteSound, fallback: .defaultTranscriptionComplete)
    if complete != settingsManager.transcriptionCompleteSound {
      settingsManager.transcriptionCompleteSound = complete
    }
  }

  private func setupSoundChangeObserver() {
    soundChangeObserver = NotificationCenter.default.addObserver(
      forName: UserDefaults.didChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        for slot in Slot.allCases where self.preparedSelections[slot] != self.selection(for: slot) {
          self.prepare(slot)
        }
      }
    }
  }
}
