import AVFoundation
import Foundation

@MainActor
class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = AudioPlayerManager()
    
    private var audioPlayer: AVAudioPlayer?
    private var playbackTimer: Timer?
    
    // Published properties for UI binding
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackProgress: Double = 0 // 0.0 to 1.0
    @Published var isLoaded = false
    @Published var loadingError: String?
    
    private override init() {
        super.init()
    }
    
    deinit {
        // Clean up synchronously - audioPlayer and timer cleanup
        audioPlayer?.stop()
        playbackTimer?.invalidate()
    }
    
    // MARK: - Audio Loading
    
    /// Loads an audio file for playback
    /// - Parameter url: The URL of the audio file to load
    func loadAudio(from url: URL) {
        // Stop and cleanup any existing playback
        stop()
        resetState()
        
        do {
            // Create audio player
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            
            // Prepare the player (loads audio into memory)
            guard audioPlayer?.prepareToPlay() == true else {
                throw AudioPlayerError.failedToPrepare
            }
            
            // Update duration
            duration = audioPlayer?.duration ?? 0
            isLoaded = true
            loadingError = nil
            
            print("AudioPlayerManager: Loaded audio file with duration \(duration)s")
            
        } catch {
            print("AudioPlayerManager: Failed to load audio file: \(error)")
            loadingError = "Failed to load audio file"
            isLoaded = false
            audioPlayer = nil
        }
    }
    
    /// Loads an audio file for playback on a background thread
    /// - Parameters:
    ///   - url: The URL of the audio file to load
    ///   - completion: Completion handler called on main thread with success/failure
    func loadAudioAsync(from url: URL, completion: @escaping (Bool, String?) -> Void) {
        // Stop current playback on main thread
        stop()
        resetState()
        
        Task.detached { [weak self] in
            do {
                // Create and prepare audio player on background thread
                let player = try AVAudioPlayer(contentsOf: url)
                guard player.prepareToPlay() else {
                    await MainActor.run {
                        completion(false, "Failed to prepare audio file")
                    }
                    return
                }
                
                // Update state on main thread
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.audioPlayer = player
                    self.audioPlayer?.delegate = self
                    self.duration = player.duration
                    self.isLoaded = true
                    self.loadingError = nil
                    
                    print("AudioPlayerManager: Loaded audio file with duration \(self.duration)s")
                    completion(true, nil)
                }
                
            } catch {
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    print("AudioPlayerManager: Failed to load audio file: \(error)")
                    let errorMessage = "Failed to load audio file"
                    self.loadingError = errorMessage
                    self.isLoaded = false
                    self.audioPlayer = nil
                    completion(false, errorMessage)
                }
            }
        }
    }
    
    // MARK: - Playback Controls
    
    /// Starts or resumes playback
    func play() {
        guard let player = audioPlayer, isLoaded else {
            print("AudioPlayerManager: Cannot play - no audio loaded")
            return
        }
        
        guard !isPlaying else {
            print("AudioPlayerManager: Already playing")
            return
        }
        
        if player.play() {
            isPlaying = true
            startPlaybackTimer()
            print("AudioPlayerManager: Started playback")
        } else {
            print("AudioPlayerManager: Failed to start playback")
        }
    }
    
    /// Pauses playback
    func pause() {
        guard let player = audioPlayer, isPlaying else {
            return
        }
        
        player.pause()
        isPlaying = false
        stopPlaybackTimer()
        print("AudioPlayerManager: Paused playback")
    }
    
    /// Stops playback and resets to beginning
    func stop() {
        guard let player = audioPlayer else {
            return
        }
        
        if isPlaying {
            player.stop()
            isPlaying = false
        }
        
        stopPlaybackTimer()
        
        // Reset to beginning
        player.currentTime = 0
        currentTime = 0
        playbackProgress = 0
        
        print("AudioPlayerManager: Stopped playback")
    }
    
    /// Toggles between play and pause
    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    /// Completely unloads the current audio file and resets all state
    func unloadAudio() {
        if isPlaying {
            audioPlayer?.stop()
            isPlaying = false
        }
        
        stopPlaybackTimer()
        audioPlayer = nil
        resetState()
        
        print("AudioPlayerManager: Unloaded audio")
    }
    
    // MARK: - Seeking
    
    /// Seeks to a specific time position
    /// - Parameter time: The time to seek to in seconds
    func seek(to time: TimeInterval) {
        guard let player = audioPlayer, isLoaded else {
            return
        }
        
        let clampedTime = max(0, min(time, duration))
        player.currentTime = clampedTime
        currentTime = clampedTime
        playbackProgress = duration > 0 ? clampedTime / duration : 0
        
        print("AudioPlayerManager: Seeked to \(clampedTime)s")
    }
    
    /// Seeks to a specific progress percentage
    /// - Parameter progress: Progress value from 0.0 to 1.0
    func seek(toProgress progress: Double) {
        let clampedProgress = max(0, min(progress, 1.0))
        let targetTime = duration * clampedProgress
        seek(to: targetTime)
    }
    
    // MARK: - State Management
    
    private func resetState() {
        isLoaded = false
        loadingError = nil
        currentTime = 0
        duration = 0
        playbackProgress = 0
        isPlaying = false
    }
    
    private func startPlaybackTimer() {
        stopPlaybackTimer()
        
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePlaybackProgress()
            }
        }
    }
    
    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
    
    private func updatePlaybackProgress() {
        guard let player = audioPlayer, isPlaying else {
            return
        }
        
        currentTime = player.currentTime
        playbackProgress = duration > 0 ? currentTime / duration : 0
        
        // Check if we've reached the end
        if currentTime >= duration {
            // Playback finished
            isPlaying = false
            stopPlaybackTimer()
            currentTime = duration
            playbackProgress = 1.0
        }
    }
    
    // MARK: - Utility Properties
    
    var formattedCurrentTime: String {
        formatTime(currentTime)
    }
    
    var formattedDuration: String {
        formatTime(duration)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // MARK: - AVAudioPlayerDelegate
    
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            print("AudioPlayerManager: Playback finished successfully: \(flag)")
            self.isPlaying = false
            self.stopPlaybackTimer()
            
            if flag {
                // Completed successfully - stay at end
                self.currentTime = self.duration
                self.playbackProgress = 1.0
            } else {
                // Error occurred - reset to beginning
                self.currentTime = 0
                self.playbackProgress = 0
            }
        }
    }
    
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            print("AudioPlayerManager: Decode error occurred: \(error?.localizedDescription ?? "Unknown")")
            self.isPlaying = false
            self.stopPlaybackTimer()
            self.loadingError = "Audio playback error: \(error?.localizedDescription ?? "Unknown error")"
        }
    }
}

// MARK: - Errors

enum AudioPlayerError: LocalizedError {
    case failedToPrepare
    case fileNotFound
    case unsupportedFormat
    
    var errorDescription: String? {
        switch self {
        case .failedToPrepare:
            return "Failed to prepare audio for playback"
        case .fileNotFound:
            return "Audio file not found"
        case .unsupportedFormat:
            return "Unsupported audio format"
        }
    }
}