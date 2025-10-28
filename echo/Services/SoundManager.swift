@preconcurrency import AVFoundation
import AppKit
import Foundation

struct SoundOption {
  let id: String
  let label: String
  let fileName: String

  static let allOptions: [SoundOption] = [
    SoundOption(id: "none", label: "None", fileName: ""),
    SoundOption(id: "click01", label: "Click 1", fileName: "click01.mp3"),
    SoundOption(id: "click02", label: "Click 2", fileName: "click02.mp3"),
    SoundOption(id: "click03", label: "Click 3", fileName: "click03.mp3"),
    SoundOption(id: "click04", label: "Click 4", fileName: "click04.mp3"),
  ]
}

@MainActor
class SoundManager: ObservableObject {
  static let shared = SoundManager()

  private let unifiedEngine = UnifiedAudioEngine.shared
  private let settingsManager = SettingsManager.shared

  // Track currently loaded sounds
  private var currentlyLoadedRecordingStartSoundId: String = ""
  private var currentlyLoadedTranscriptionCompleteSoundId: String = ""

  // Observe changes to sound settings
  private var soundChangeObserver: NSObjectProtocol?

  private init() {
    currentlyLoadedRecordingStartSoundId = settingsManager.recordingStartSound
    currentlyLoadedTranscriptionCompleteSoundId = settingsManager.transcriptionCompleteSound
    preloadSounds()
    setupSoundChangeObserver()
  }

  private func preloadSounds() {
    loadRecordingStartSound()
    loadTranscriptionCompleteSound()
  }

  private func loadRecordingStartSound() {
    loadSound(forSoundId: settingsManager.recordingStartSound, forPlayer: .recordingStart)
  }

  private func loadTranscriptionCompleteSound() {
    loadSound(
      forSoundId: settingsManager.transcriptionCompleteSound, forPlayer: .transcriptionComplete)
  }

  private enum PlayerType {
    case recordingStart
    case transcriptionComplete
  }

  private func loadSound(forSoundId soundId: String, forPlayer playerType: PlayerType) {
    // Find the sound option for the given ID
    guard let soundOption = SoundOption.allOptions.first(where: { $0.id == soundId }) else {
      print("SoundManager: Unknown sound ID: \(soundId)")
      return
    }

    // Handle "none" option by clearing the sound
    if soundId == "none" {
      let engineType: SoundType
      switch playerType {
      case .recordingStart:
        engineType = .recordingStart
      case .transcriptionComplete:
        engineType = .transcriptionComplete
      }
      unifiedEngine.clearSound(type: engineType)
      return
    }

    // Extract filename without extension
    let fileNameWithoutExtension = (soundOption.fileName as NSString).deletingPathExtension

    // Load the sound file from the main Resources folder
    guard
      let soundURL = Bundle.main.url(forResource: fileNameWithoutExtension, withExtension: "mp3")
    else {
      print("SoundManager: Could not find sound file \(soundOption.fileName) in bundle")
      return
    }

    print(
      "SoundManager: Loading sound \(soundOption.label) for \(playerType == .recordingStart ? "recording start" : "transcription complete") from: \(soundURL)"
    )

    // Preload sound into unified engine
    let engineType: SoundType
    switch playerType {
    case .recordingStart:
      engineType = .recordingStart
    case .transcriptionComplete:
      engineType = .transcriptionComplete
    }
    unifiedEngine.preloadSound(from: soundURL, for: engineType)

    // Update the currently loaded sound ID
    switch playerType {
    case .recordingStart:
      currentlyLoadedRecordingStartSoundId = soundId
    case .transcriptionComplete:
      currentlyLoadedTranscriptionCompleteSoundId = soundId
    }
  }

  // MARK: - Public Interface

  @discardableResult
  func playRecordingStartSound(completion: (() -> Void)? = nil) -> TimeInterval? {
    guard settingsManager.soundEnabled && settingsManager.soundOnRecordingStart else {
      completion?()
      return nil
    }

    print("SoundManager: Playing recording start sound via UnifiedAudioEngine")

    // Play sound via unified engine
    unifiedEngine.playSound(type: .recordingStart) {
      completion?()
    }

    // Return approximate duration (we can't get exact duration from buffer easily)
    // For short notification sounds, this is typically 0.1-0.3 seconds
    return 0.2
  }

  func playTranscriptionCompleteSound() {
    guard settingsManager.soundEnabled && settingsManager.soundOnTranscriptionComplete else {
      return
    }

    print("SoundManager: Playing transcription complete sound via UnifiedAudioEngine")

    // Play sound via unified engine
    unifiedEngine.playSound(type: .transcriptionComplete)
  }

  // MARK: - Volume Control
  // Note: Volume control is currently not implemented for UnifiedAudioEngine
  // The AVAudioPlayerNode in the engine plays at the system volume level
  // Future enhancement: Use AVAudioUnitEQ or AVAudioMixerNode for volume control

  func setVolume(_ volume: Float) {
    // TODO: Implement volume control via AVAudioMixerNode or AVAudioUnitEQ
    print("SoundManager: Volume control not yet implemented for UnifiedAudioEngine")
  }

  func setRecordingStartVolume(_ volume: Float) {
    // TODO: Implement volume control
    print("SoundManager: Volume control not yet implemented for UnifiedAudioEngine")
  }

  func setTranscriptionCompleteVolume(_ volume: Float) {
    // TODO: Implement volume control
    print("SoundManager: Volume control not yet implemented for UnifiedAudioEngine")
  }

  // MARK: - Testing

  func testRecordingStartSound() {
    let soundId = settingsManager.recordingStartSound

    // Don't test if set to "none"
    guard soundId != "none" else {
      print("SoundManager: Cannot test - recording start sound is set to 'none'")
      return
    }

    print("SoundManager: Testing recording start sound via UnifiedAudioEngine")
    unifiedEngine.playSound(type: .recordingStart)
  }

  func testTranscriptionCompleteSound() {
    let soundId = settingsManager.transcriptionCompleteSound

    // Don't test if set to "none"
    guard soundId != "none" else {
      print("SoundManager: Cannot test - transcription complete sound is set to 'none'")
      return
    }

    print("SoundManager: Testing transcription complete sound via UnifiedAudioEngine")
    unifiedEngine.playSound(type: .transcriptionComplete)
  }

  // MARK: - Sound Selection Observer

  private func setupSoundChangeObserver() {
    soundChangeObserver = NotificationCenter.default.addObserver(
      forName: UserDefaults.didChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self = self else { return }

      MainActor.assumeIsolated {
        // Check if recording start sound changed
        let currentRecordingStartSound = self.settingsManager.recordingStartSound
        if currentRecordingStartSound != self.currentlyLoadedRecordingStartSoundId {
          print("SoundManager: Recording start sound changed to \(currentRecordingStartSound)")
          self.loadRecordingStartSound()
        }

        // Check if transcription complete sound changed
        let currentTranscriptionCompleteSound = self.settingsManager.transcriptionCompleteSound
        if currentTranscriptionCompleteSound != self.currentlyLoadedTranscriptionCompleteSoundId {
          print(
            "SoundManager: Transcription complete sound changed to \(currentTranscriptionCompleteSound)"
          )
          self.loadTranscriptionCompleteSound()
        }
      }
    }
  }

}
