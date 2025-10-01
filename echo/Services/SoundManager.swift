@preconcurrency import AVFoundation
import Foundation
import AppKit

struct SoundOption {
    let id: String
    let label: String
    let fileName: String

    static let allOptions: [SoundOption] = [
        SoundOption(id: "none", label: "None", fileName: ""),
        SoundOption(id: "click01", label: "Click 1", fileName: "click01.mp3"),
        SoundOption(id: "click02", label: "Click 2", fileName: "click02.mp3"),
        SoundOption(id: "click03", label: "Click 3", fileName: "click03.mp3"),
        SoundOption(id: "click04", label: "Click 4", fileName: "click04.mp3")
    ]
}

@MainActor
class SoundManager: ObservableObject {
    static let shared = SoundManager()

    private var recordingStartPlayer: AVAudioPlayer?
    private var transcriptionCompletePlayer: AVAudioPlayer?
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
        loadSound(forSoundId: settingsManager.transcriptionCompleteSound, forPlayer: .transcriptionComplete)
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

        // Handle "none" option by clearing the player
        if soundId == "none" {
            switch playerType {
            case .recordingStart:
                recordingStartPlayer = nil
            case .transcriptionComplete:
                transcriptionCompletePlayer = nil
            }
            return
        }

        // Extract filename without extension
        let fileNameWithoutExtension = (soundOption.fileName as NSString).deletingPathExtension

        // Load the sound file from the main Resources folder
        guard let soundURL = Bundle.main.url(forResource: fileNameWithoutExtension, withExtension: "mp3") else {
            print("SoundManager: Could not find sound file \(soundOption.fileName) in bundle")
            return
        }

        print("SoundManager: Loading sound \(soundOption.label) for \(playerType == .recordingStart ? "recording start" : "transcription complete") from: \(soundURL)")
        loadPlayerFromURL(soundURL, forPlayer: playerType)

        // Update the currently loaded sound ID
        switch playerType {
        case .recordingStart:
            currentlyLoadedRecordingStartSoundId = soundId
        case .transcriptionComplete:
            currentlyLoadedTranscriptionCompleteSoundId = soundId
        }
    }
    
    
    // MARK: - Public Interface
    
    func playRecordingStartSound() {
        guard settingsManager.soundEnabled && settingsManager.soundOnRecordingStart else {
            return
        }

        guard let player = recordingStartPlayer else {
            print("SoundManager: Recording start player not available")
            return
        }

        // Play sound on background thread to avoid blocking animations
        DispatchQueue.global(qos: .userInitiated).async { [player] in
            nonisolated(unsafe) let unsafePlayer = player
            unsafePlayer.currentTime = 0
            unsafePlayer.play()
            print("SoundManager: Played recording start sound")
        }
    }
    
    func playTranscriptionCompleteSound() {
        guard settingsManager.soundEnabled && settingsManager.soundOnTranscriptionComplete else {
            return
        }

        guard let player = transcriptionCompletePlayer else {
            print("SoundManager: Transcription complete player not available")
            return
        }

        // Play sound on background thread to avoid blocking animations
        DispatchQueue.global(qos: .userInitiated).async { [player] in
            nonisolated(unsafe) let unsafePlayer = player
            unsafePlayer.currentTime = 0
            unsafePlayer.play()
            print("SoundManager: Played transcription complete sound")
        }
    }
    
    // MARK: - Volume Control

    func setVolume(_ volume: Float) {
        let clampedVolume = max(0.0, min(1.0, volume))
        recordingStartPlayer?.volume = clampedVolume
        transcriptionCompletePlayer?.volume = clampedVolume
    }

    func setRecordingStartVolume(_ volume: Float) {
        let clampedVolume = max(0.0, min(1.0, volume))
        recordingStartPlayer?.volume = clampedVolume
    }

    func setTranscriptionCompleteVolume(_ volume: Float) {
        let clampedVolume = max(0.0, min(1.0, volume))
        transcriptionCompletePlayer?.volume = clampedVolume
    }
    
    // MARK: - Testing
    
    func testRecordingStartSound() {
        let soundId = settingsManager.recordingStartSound

        // Don't test if set to "none"
        guard soundId != "none" else {
            print("SoundManager: Cannot test - recording start sound is set to 'none'")
            return
        }

        // If player is not loaded, load it temporarily for testing
        if recordingStartPlayer == nil {
            loadSound(forSoundId: soundId, forPlayer: .recordingStart)
        }

        guard let player = recordingStartPlayer else {
            print("SoundManager: Recording start player not available for testing")
            return
        }

        // Play sound on background thread to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async { [player] in
            nonisolated(unsafe) let unsafePlayer = player
            unsafePlayer.currentTime = 0
            unsafePlayer.play()
            print("SoundManager: Testing recording start sound")
        }
    }
    
    func testTranscriptionCompleteSound() {
        let soundId = settingsManager.transcriptionCompleteSound

        // Don't test if set to "none"
        guard soundId != "none" else {
            print("SoundManager: Cannot test - transcription complete sound is set to 'none'")
            return
        }

        // If player is not loaded, load it temporarily for testing
        if transcriptionCompletePlayer == nil {
            loadSound(forSoundId: soundId, forPlayer: .transcriptionComplete)
        }

        guard let player = transcriptionCompletePlayer else {
            print("SoundManager: Transcription complete player not available for testing")
            return
        }

        // Play sound on background thread to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async { [player] in
            nonisolated(unsafe) let unsafePlayer = player
            unsafePlayer.currentTime = 0
            unsafePlayer.play()
            print("SoundManager: Testing transcription complete sound")
        }
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
                    print("SoundManager: Transcription complete sound changed to \(currentTranscriptionCompleteSound)")
                    self.loadTranscriptionCompleteSound()
                }
            }
        }
    }

    // Load a specific player from URL
    private func loadPlayerFromURL(_ soundURL: URL, forPlayer playerType: PlayerType) {
        do {
            let player = try AVAudioPlayer(contentsOf: soundURL)
            player.prepareToPlay()
            player.volume = 0.6

            switch playerType {
            case .recordingStart:
                recordingStartPlayer = player
            case .transcriptionComplete:
                transcriptionCompletePlayer = player
            }

            print("SoundManager: Successfully loaded \(playerType == .recordingStart ? "recording start" : "transcription complete") sound from \(soundURL)")

        } catch {
            print("SoundManager: Failed to load \(playerType == .recordingStart ? "recording start" : "transcription complete") sound: \(error)")
        }
    }
}