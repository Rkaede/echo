
import AVFoundation
import Combine

// MARK: - Recording State

/// Represents the current state of the audio recorder
public enum RecordingState: Equatable {
    case idle
    case initiating  // Bluetooth connection setup, device preparation
    case recording   // Actually recording audio
    case paused
    case failed(Error)
    
    public static func == (lhs: RecordingState, rhs: RecordingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.initiating, .initiating),
             (.recording, .recording),
             (.paused, .paused):
            return true
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

// MARK: - Audio Recorder Error

public enum AudioRecorderUpdatedError: LocalizedError {
    case recordPermissionDenied
    case deviceNotAvailable
    case audioEngineFailure
    case fileCreationFailed
    case invalidConfiguration
    case recordingInProgress
    case noActiveRecording
    
    public var errorDescription: String? {
        switch self {
        case .recordPermissionDenied:
            return "Microphone permission denied"
        case .deviceNotAvailable:
            return "Audio device not available"
        case .audioEngineFailure:
            return "Audio engine failure"
        case .fileCreationFailed:
            return "Failed to create audio file"
        case .invalidConfiguration:
            return "Invalid audio configuration"
        case .recordingInProgress:
            return "Recording already in progress"
        case .noActiveRecording:
            return "No active recording"
        }
    }
}

// MARK: - Audio Recorder Delegate

public protocol AudioRecorderUpdatedDelegate: AnyObject {
    /// Called when recording state changes
    func AudioRecorderUpdated(_ recorder: AudioRecorderUpdated, didChangeState state: RecordingState)
    
    /// Called when audio levels are updated (for visualization)
    func AudioRecorderUpdated(_ recorder: AudioRecorderUpdated, didUpdateAudioLevel level: Float, peakLevel: Float)
    
    /// Called when recording is successfully completed
    func AudioRecorderUpdated(_ recorder: AudioRecorderUpdated, didFinishRecordingAt url: URL)
    
    /// Called when playback finishes
    func AudioRecorderUpdatedDidFinishPlayback(_ recorder: AudioRecorderUpdated)
}

// MARK: - Audio Recorder

public class AudioRecorderUpdated: NSObject {
    
    // MARK: - Properties
    
    public weak var delegate: AudioRecorderUpdatedDelegate?
    
    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?

    private var audioPlayer: AVAudioPlayer?
    private var startReadySound: AVAudioPlayer?

    @Published public private(set) var recordingState: RecordingState = .idle

    private var levelTimer: DispatchSourceTimer?
    private let levelUpdateInterval: TimeInterval = 0.05 // 20 Hz updates

    // Thread-safe level storage (accessed from audio thread and main thread)
    private var latestAudioLevel: Float = 0
    private var latestPeakLevel: Float = 0
    private let levelLock = NSLock()

    // Track whether a tap is currently installed
    private var isTapInstalled = false
    
    // Audio format: 16kHz mono
    private let targetSampleRate: Double = 16000.0
    private let targetChannelCount: AVAudioChannelCount = 1
    
    // For monitoring device changes
    private var deviceChangeObserver: NSObjectProtocol?
    
    // Cancellables for Combine
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    public override init() {
        super.init()
        setupStateObserver()
        setupDeviceChangeObserver()
        setupAudioSession()
        loadStartReadySound()
    }
    
    deinit {
        stopRecording()
        if let observer = deviceChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Setup
    
    private func setupStateObserver() {
        $recordingState
            .sink { [weak self] state in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.delegate?.AudioRecorderUpdated(self, didChangeState: state)
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupDeviceChangeObserver() {
        deviceChangeObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.AVCaptureDeviceWasConnected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDeviceChange()
        }
    }
    
    private func setupAudioSession() {
        // macOS doesn't use AVAudioSession like iOS, but we configure the engine appropriately
    }
    
    private func loadStartReadySound() {
        // Load a system sound or custom sound to play when recording is ready
        // Using a simple system sound URL as an example
        if let soundURL = Bundle.main.url(forResource: "recording_start", withExtension: "aif") {
            do {
                startReadySound = try AVAudioPlayer(contentsOf: soundURL)
                startReadySound?.prepareToPlay()
            } catch {
                print("Failed to load start ready sound: \(error)")
            }
        }
    }
    
    // MARK: - Recording Control
    
    /// Start recording audio
    public func startRecording() async throws {
        guard recordingState == .idle else {
            throw AudioRecorderUpdatedError.recordingInProgress
        }
        
        // Check microphone permission
        guard await checkMicrophonePermission() else {
            recordingState = .failed(AudioRecorderUpdatedError.recordPermissionDenied)
            throw AudioRecorderUpdatedError.recordPermissionDenied
        }
        
        // Set state to initiating
        recordingState = .initiating
        
        do {
            // Setup audio file
            let fileURL = try createRecordingFile()
            recordingURL = fileURL

            // Configure audio engine (this may take time for Bluetooth devices)
            try await configureAudioEngine(outputURL: fileURL)

            // Start the engine
            try audioEngine.start()

            // Successfully started recording
            recordingState = .recording

            // Play ready sound
            playStartReadySound()

            // Start level monitoring
            startLevelMonitoring()

        } catch {
            // Clean up on error - remove tap if it was installed
            if isTapInstalled {
                audioEngine.inputNode.removeTap(onBus: 0)
                isTapInstalled = false
            }
            audioFile = nil
            recordingURL = nil
            recordingState = .failed(error)
            throw error
        }
    }
    
    /// Stop recording audio
    public func stopRecording() {
        guard recordingState == .recording || recordingState == .initiating else {
            return
        }

        stopLevelMonitoring()

        // Remove tap before stopping engine to prevent "required condition is false: nullptr == Tap()" crash
        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        audioEngine.stop()
        audioFile = nil

        if let url = recordingURL {
            delegate?.AudioRecorderUpdated(self, didFinishRecordingAt: url)
        }

        recordingURL = nil
        recordingState = .idle
    }
    
    /// Pause recording (stops engine but keeps file)
    public func pauseRecording() {
        guard recordingState == .recording else {
            return
        }
        
        stopLevelMonitoring()
        audioEngine.pause()
        recordingState = .paused
    }
    
    /// Resume recording from paused state
    public func resumeRecording() throws {
        guard recordingState == .paused else {
            throw AudioRecorderUpdatedError.noActiveRecording
        }
        
        try audioEngine.start()
        recordingState = .recording
        startLevelMonitoring()
    }
    
    // MARK: - Playback Control
    
    /// Play audio from URL
    public func playAudio(from url: URL) throws {
        stopPlayback() // Stop any existing playback
        
        audioPlayer = try AVAudioPlayer(contentsOf: url)
        audioPlayer?.delegate = self
        audioPlayer?.prepareToPlay()
        audioPlayer?.play()
    }
    
    /// Stop audio playback
    public func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
    }
    
    /// Play the recording start ready sound
    private func playStartReadySound() {
        startReadySound?.play()
    }
    
    // MARK: - Audio Engine Configuration
    
    private func configureAudioEngine(outputURL: URL) async throws {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Create output format: 16kHz mono
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: targetChannelCount,
            interleaved: true
        ) else {
            throw AudioRecorderUpdatedError.invalidConfiguration
        }
        
        // Create audio file
        audioFile = try AVAudioFile(
            forWriting: outputURL,
            settings: outputFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
        
        guard let audioFile = audioFile else {
            throw AudioRecorderUpdatedError.fileCreationFailed
        }
        
        // Create converter if needed
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioRecorderUpdatedError.invalidConfiguration
        }
        
        // Install tap on input node
        let bufferSize: AVAudioFrameCount = 4096

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self, self.recordingState == .recording else { return }

            // Convert buffer to target format
            self.convertAndWriteBuffer(buffer, converter: converter, to: audioFile)
        }

        // Mark that tap is now installed
        isTapInstalled = true
        
        // Prepare the audio engine (may trigger Bluetooth pairing)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.audioEngine.prepare()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func convertAndWriteBuffer(_ inputBuffer: AVAudioPCMBuffer, converter: AVAudioConverter, to file: AVAudioFile) {
        guard let outputFormat = file.processingFormat as? AVAudioFormat else { return }

        // Calculate audio levels from the input buffer (real-time calculation)
        let rmsLevel = calculateRMSLevel(from: inputBuffer)
        let peakLevel = calculatePeak(from: inputBuffer)

        // Store levels in thread-safe cache for the timer to read
        levelLock.lock()
        latestAudioLevel = rmsLevel
        latestPeakLevel = peakLevel
        levelLock.unlock()

        let capacity = AVAudioFrameCount(converter.outputFormat.sampleRate) * inputBuffer.frameLength / AVAudioFrameCount(inputBuffer.format.sampleRate)

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }

        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if error == nil {
            do {
                try file.write(from: outputBuffer)
            } catch {
                print("Error writing to audio file: \(error)")
            }
        }
    }
    
    // MARK: - Level Monitoring

    private func startLevelMonitoring() {
        stopLevelMonitoring()

        let timer = DispatchSource.makeTimerSource(queue: .main) // <-- main queue
        timer.schedule(deadline: .now(), repeating: levelUpdateInterval)
        timer.setEventHandler { [weak self] in
            self?.updateAudioLevels()
        }
        timer.resume()
        levelTimer = timer
    }

    private func stopLevelMonitoring() {
        levelTimer?.cancel()
        levelTimer = nil
    }
    
    private func updateAudioLevels() {
        // Read thread-safe cached values (calculated in audio tap)
        levelLock.lock()
        let level = latestAudioLevel
        let peak = latestPeakLevel
        levelLock.unlock()

        // Debug: Verify timer is firing (remove after testing)
        #if DEBUG
        print("[AudioRecorderUpdated] updateAudioLevels fired - level: \(String(format: "%.2f", level)), peak: \(String(format: "%.2f", peak))")
        #endif

        // We're already on main thread from DispatchSourceTimer, dispatch delegate call
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.AudioRecorderUpdated(self, didUpdateAudioLevel: level, peakLevel: peak)
        }
    }
    
    // MARK: - File Management
    
    private func createRecordingFile() throws -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let fileName = "recording_\(timestamp).wav"
        return documentsPath.appendingPathComponent(fileName)
    }
    
    // MARK: - Permissions
    
    private func checkMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
    
    // MARK: - Device Change Handling
    
    private func handleDeviceChange() {
        // Handle device connection/disconnection
        // You might want to restart the audio engine if needed
        print("Audio device changed")
    }
    
    // MARK: - Public Helpers
    
    /// Get current recording duration
    public var recordingDuration: TimeInterval? {
        guard recordingState == .recording, let audioFile = audioFile else {
            return nil
        }
        return Double(audioFile.length) / audioFile.processingFormat.sampleRate
    }
    
    /// Check if currently recording
    public var isRecording: Bool {
        return recordingState == .recording
    }
    
    /// Check if in initiating state (waiting for Bluetooth, etc.)
    public var isInitiating: Bool {
        return recordingState == .initiating
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioRecorderUpdated: AVAudioPlayerDelegate {
    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        delegate?.AudioRecorderUpdatedDidFinishPlayback(self)
    }
}

// MARK: - Audio Level Calculation Extension

extension AudioRecorderUpdated {
    /// Calculate RMS level from audio buffer (for actual implementation)
    func calculateRMSLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        
        let channelDataValue = channelData.pointee
        let channelDataValueArray = stride(
            from: 0,
            to: Int(buffer.frameLength),
            by: buffer.stride
        ).map { channelDataValue[$0] }
        
        let rms = sqrt(channelDataValueArray.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
        
        // Convert to dB scale (-160 to 0)
        let avgPower = 20 * log10(rms)
        let normalizedLevel = (avgPower + 160) / 160 // Normalize to 0-1
        
        return max(0, min(1, normalizedLevel))
    }
    
    /// Calculate peak level from audio buffer
    func calculatePeak(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        
        let channelDataValue = channelData.pointee
        let channelDataValueArray = stride(
            from: 0,
            to: Int(buffer.frameLength),
            by: buffer.stride
        ).map { abs(channelDataValue[$0]) }
        
        guard let peak = channelDataValueArray.max() else { return 0 }
        
        return min(1, peak)
    }
}
