import SwiftUI

struct AudioControlsView: View {
    @StateObject private var audioPlayer = AudioPlayerManager.shared
    @StateObject private var audioStorage = AudioStorageManager.shared
    
    let transcription: TranscriptionHistory
    
    @State private var isLoadingAudio = false
    @State private var audioLoadError: String?
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack {
                if !hasAudioFile {
                    // No audio available - just show simple text message
                    Spacer()
                    Text("No audio file")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    HStack(spacing: 16) {
                        // Current time
                        Text(audioPlayer.formattedCurrentTime)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 35, alignment: .trailing)
                            .monospacedDigit()
                        
                        // Play/Pause button
                        Button(action: {
                            if audioPlayer.isLoaded {
                                audioPlayer.togglePlayback()
                            } else {
                                loadAndPlayAudio()
                            }
                        }) {
                            Image(systemName: buttonIconName)
                                .font(.title2)
                                .foregroundColor(.primary)
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoadingAudio)
                        .opacity(isLoadingAudio ? 0.5 : 1.0)
                        
                        // Progress bar
                        if audioPlayer.isLoaded || isLoadingAudio {
                            ProgressView(value: audioPlayer.playbackProgress, total: 1.0)
                                .progressViewStyle(AudioProgressStyle(
                                    isEnabled: audioPlayer.isLoaded && !isLoadingAudio,
                                    onSeek: { progress in
                                        audioPlayer.seek(toProgress: progress)
                                    }
                                ))
                                .frame(minWidth: 120)
                        } else {
                            // Show a placeholder progress bar when audio is available but not loaded
                            Rectangle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(height: 4)
                                .frame(minWidth: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                        }
                        
                        // Duration
                        Text(durationText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 35, alignment: .leading)
                            .monospacedDigit()
                        
                        Spacer()
                        
                        // Error message or loading indicator
                        if let error = audioLoadError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .lineLimit(1)
                        } else if isLoadingAudio {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .controlSize(.mini)
                                Text("Loading...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .onAppear {
            resetAudioPlayer()
        }
        .onChange(of: transcription.id) {
            resetAudioPlayer()
        }
    }
    
    private var hasAudioFile: Bool {
        transcription.audioFileReference != nil && !transcription.audioFileReference!.isEmpty
    }
    
    private var buttonIconName: String {
        if isLoadingAudio {
            return "hourglass"
        } else if !hasAudioFile {
            return "waveform.slash"
        } else if audioPlayer.isLoaded && audioPlayer.isPlaying {
            return "pause.fill"
        } else {
            return "play.fill"
        }
    }
    
    private var durationText: String {
        if audioPlayer.isLoaded {
            return audioPlayer.formattedDuration
        } else if hasAudioFile {
            return transcription.formattedDuration
        } else {
            return "--:--"
        }
    }
    
    private func loadAndPlayAudio() {
        guard let audioRef = transcription.audioFileReference,
              !audioRef.isEmpty else {
            audioLoadError = "No audio file available"
            return
        }
        
        guard let audioURL = audioStorage.getAudioFileURL(for: audioRef) else {
            audioLoadError = "Audio file not found"
            return
        }
        
        isLoadingAudio = true
        audioLoadError = nil
        
        // Load audio on background thread
        audioPlayer.loadAudioAsync(from: audioURL) { success, error in
            isLoadingAudio = false
            
            if success {
                audioPlayer.play()
            } else {
                audioLoadError = error ?? "Unknown error"
            }
        }
    }
    
    private func resetAudioPlayer() {
        // Completely unload audio when transcription changes
        audioPlayer.unloadAudio()
        audioLoadError = nil
        isLoadingAudio = false
    }
}

// Custom progress bar style that supports seeking
struct AudioProgressStyle: ProgressViewStyle {
    let isEnabled: Bool
    let onSeek: (Double) -> Void
    
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 4)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                
                // Progress track
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * (configuration.fractionCompleted ?? 0), height: 4)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                
                // Invisible overlay for click handling
                if isEnabled {
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            let progress = location.x / geometry.size.width
                            let clampedProgress = max(0, min(1, progress))
                            onSeek(clampedProgress)
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let progress = value.location.x / geometry.size.width
                                    let clampedProgress = max(0, min(1, progress))
                                    onSeek(clampedProgress)
                                }
                        )
                }
            }
        }
        .frame(height: 4)
    }
}

#Preview {
    VStack {
        // Preview with audio
        AudioControlsView(transcription: TranscriptionHistory(
            transcribedText: "This is a sample transcription with audio",
            duration: 15.5,
            audioFileReference: "sample_audio.wav",
            modelUsed: "whisper-large-v3"
        ))
        
        Divider().padding()
        
        // Preview without audio
        AudioControlsView(transcription: TranscriptionHistory(
            transcribedText: "This is a sample transcription without audio",
            duration: 8.2,
            modelUsed: "whisper-large-v3"
        ))
    }
    .frame(width: 400, height: 200)
}