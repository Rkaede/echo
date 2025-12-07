// Treat legacy AVFoundation types as @unchecked Sendable while the module awaits concurrency annotations.
@preconcurrency import AVFoundation
import Combine
import CoreGraphics
import Foundation

private let unifiedAudioEngineLogCategory = "UnifiedAudioEngine"

/// Unified audio engine that manages all audio operations (recording + playback) through a single AVAudioEngine instance.
/// This architecture provides:
/// - Single HAL client (eliminates race conditions)
/// - Minimal Bluetooth mode switching (A2DP ↔ HFP)
/// - Always-running engine (no create/destroy overhead)
/// - Unified metering and level monitoring
@MainActor
class UnifiedAudioEngine: ObservableObject {
  static let shared = UnifiedAudioEngine()

  // Core audio components
  private let engine = AVAudioEngine()
  private let playerNode = AVAudioPlayerNode()
  private var sinkNode: AVAudioSinkNode?

  // Thread-safe queue for audio processing (access to shared state)
  private let audioProcessingQueue = DispatchQueue(
    label: "com.echo.audio.processing", qos: .userInteractive)

  // Async write queue for non-blocking file I/O (serial to maintain order)
  private let asyncWriteQueue = DispatchQueue(
    label: "com.echo.audio.write", qos: .userInitiated)

  // Buffer pool for zero-allocation real-time callbacks
  private let bufferPool = BufferPool()

  // Recording state (thread-safe via audioProcessingQueue)
  // These are accessed from both MainActor and audio thread, so we protect them with the queue
  nonisolated(unsafe) private var outputFile: AVAudioFile?
  nonisolated(unsafe) private var converter: AVAudioConverter?
  private var isRecordingActive = false
  private var recordingURL: URL?

  // Counter for pending buffer writes (thread-safe via writeLock)
  nonisolated(unsafe) private var pendingWriteCount = 0
  private let writeLock = NSLock()

  // Metering
  @Published var currentInputLevel: CGFloat = 0
  @Published var waveformSamples: [Float] = []
  nonisolated(unsafe) private var lastLevelUpdate: TimeInterval = 0
  private let levelUpdateThrottle: TimeInterval = 0.05  // 20Hz max (50ms)
  private let waveformBarCount: Int = 12

  // Sound buffers (preloaded)
  private var recordingStartBuffer: AVAudioPCMBuffer?
  private var transcriptionCompleteBuffer: AVAudioPCMBuffer?

  // Track engine initialization state
  private var hasAttemptedStart = false
  private var audioSessionConfigured = false

  private init() {
    setupAudioEngine()
    // Don't start engine immediately - wait until first use
    // This avoids Core Audio HAL errors before permissions are granted
  }

  deinit {
    // Engine cleanup happens automatically when deallocated
    // Note: Can't call MainActor methods from deinit
    // The AVAudioEngine will stop itself when deallocated
  }

  // MARK: - Engine Lifecycle

  /// Configures the audio session for recording and playback
  private func setupAudioSession() {
    guard !audioSessionConfigured else { return }

    #if os(macOS)
      // macOS doesn't use AVAudioSession in the same way as iOS
      // Audio routing is handled automatically by Core Audio
      audioSessionConfigured = true
      log("Audio session configuration not required on macOS", category: unifiedAudioEngineLogCategory, level: .debug)
    #else
      do {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
          .playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        audioSessionConfigured = true
        log("Audio session configured successfully", category: unifiedAudioEngineLogCategory, level: .info)
      } catch {
        log("Failed to configure audio session: \(error)", category: unifiedAudioEngineLogCategory, level: .error)
      }
    #endif
  }

  private func setupAudioEngine() {
    log("Setting up audio engine", category: unifiedAudioEngineLogCategory, level: .debug)

    // Attach player node for sound playback
    engine.attach(playerNode)

    // Get the output format from the main mixer node
    // This is typically the hardware's default output format (e.g., 48kHz stereo)
    let mixerFormat = engine.mainMixerNode.outputFormat(forBus: 0)
    log(
      "Mixer format - sampleRate: \(mixerFormat.sampleRate), channels: \(mixerFormat.channelCount)",
      category: unifiedAudioEngineLogCategory,
      level: .debug
    )

    // Connect player node to mixer with explicit format
    engine.connect(playerNode, to: engine.mainMixerNode, format: mixerFormat)

    log("Audio engine setup complete", category: unifiedAudioEngineLogCategory, level: .debug)
  }

  /// Ensures the engine is started (lazy initialization)
  /// Call this before any operation that requires the engine
  private func ensureEngineStarted() {
    // Configure audio session before starting engine
    setupAudioSession()

    // Check if engine is actually running, not just if we attempted to start it
    // This is important because the engine may be stopped/restarted during recording setup
    guard !engine.isRunning else {
      return
    }

    hasAttemptedStart = true
    startEngineWithRetry()
  }

  private func startEngineWithRetry(maxRetries: Int = 3) {
    for attempt in 1...maxRetries {
      do {
        if !engine.isRunning {
          try engine.start()
          log(
            "Engine started successfully on attempt \(attempt)",
            category: unifiedAudioEngineLogCategory,
            level: .info
          )
        }
        return
      } catch let error as NSError {
        log(
          "Start attempt \(attempt) failed: \(error)",
          category: unifiedAudioEngineLogCategory,
          level: .error
        )

        // EAGAIN (35) means device is reconfiguring - retry immediately without blocking
        if error.code == 35 && attempt < maxRetries {
          log(
            "Device reconfiguring, retrying immediately (attempt \(attempt + 1))...",
            category: unifiedAudioEngineLogCategory,
            level: .debug
          )
          continue
        }

        // Other errors or max retries reached
        log(
          "Failed to start engine after \(attempt) attempts: \(error)",
          category: unifiedAudioEngineLogCategory,
          level: .error
        )
        return
      }
    }
  }

  // Note: We keep the engine always running for optimal performance
  // No stopEngine() method - engine runs continuously

  // MARK: - Recording

  /// Starts recording audio to the specified URL using input tap
  func startRecording(to url: URL) throws {
    let startTime = Date()
    log(
      "[PERF] startRecording() started at \(startTime)",
      category: unifiedAudioEngineLogCategory,
      level: .debug
    )

    guard !isRecordingActive else {
      throw UnifiedAudioEngineError.alreadyRecording
    }

    // Ensure engine is started (lazy initialization)
    let engineStartTime = Date()
    ensureEngineStarted()
    let engineStartDuration = Date().timeIntervalSince(engineStartTime)
    log(
      "[PERF] ensureEngineStarted took \(engineStartDuration * 1000)ms",
      category: unifiedAudioEngineLogCategory,
      level: .debug
    )

    guard engine.isRunning else {
      throw UnifiedAudioEngineError.engineNotRunning
    }

    // Try to setup recording with retry logic for error 35 (EAGAIN)
    // This can happen when Bluetooth devices are reconfiguring
    let maxRetries = 3
    var lastError: Error?

    for attempt in 1...maxRetries {
      do {
        try setupRecordingTap(to: url)
        let totalDuration = Date().timeIntervalSince(startTime)
        log(
          "[PERF] startRecording() total duration: \(totalDuration * 1000)ms",
          category: unifiedAudioEngineLogCategory,
          level: .debug
        )
        log(
          "Recording started successfully on attempt \(attempt)",
          category: unifiedAudioEngineLogCategory,
          level: .info
        )
        return
      } catch let error as NSError {
        lastError = error
        log(
          "Recording setup attempt \(attempt) failed: \(error)",
          category: unifiedAudioEngineLogCategory,
          level: .error
        )

        // EAGAIN (35) or "already running" errors - retry immediately without blocking
        if (error.code == 35 || error.code == -10877) && attempt < maxRetries {
          log(
            "Device reconfiguring, retrying immediately (attempt \(attempt + 1))...",
            category: unifiedAudioEngineLogCategory,
            level: .warning
          )

          // Clean up any partial state
          if let sinkNode = sinkNode {
            engine.detach(sinkNode)
            self.sinkNode = nil
          }
          resetRecordingState()

          continue
        }

        // Other errors or max retries reached - clean up and throw
        resetRecordingState()
        throw error
      }
    }

    // If we get here, all retries failed
    if let error = lastError {
      throw error
    } else {
      throw UnifiedAudioEngineError.engineNotRunning
    }
  }

  private func setupRecordingTap(to url: URL) throws {
    let inputNode = engine.inputNode

    // CRITICAL: Query input format BEFORE stopping the engine
    // After stopping, the inputNode may return stale/incorrect format info
    // (e.g., 16000 Hz instead of the actual hardware format like 48000 Hz)
    let inputFormat = inputNode.outputFormat(forBus: 0)

    log(
      "Input format - sampleRate: \(inputFormat.sampleRate), channels: \(inputFormat.channelCount)",
      category: unifiedAudioEngineLogCategory,
      level: .debug
    )

    // CRITICAL: Stop the engine before modifying graph
    // According to Apple docs, you must configure nodes before starting the engine
    if engine.isRunning {
      log(
        "[DEBUG] Stopping engine to setup sink node",
        category: unifiedAudioEngineLogCategory,
        level: .debug
      )
      engine.stop()
    }

    // Create output format (16kHz mono 16-bit PCM)
    guard
      let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16000.0,
        channels: 1,
        interleaved: true  // 16-bit PCM must be interleaved for WAV on macOS
      )
    else {
      // Reset state on error
      resetRecordingState()
      throw UnifiedAudioEngineError.invalidFormat
    }

    // Explicit settings to avoid Core Audio throwing kAudioUnitErr_FormatNotSupported (-10877)
    var fileSettings = outputFormat.settings
    fileSettings[AVFormatIDKey] = Int(kAudioFormatLinearPCM)
    fileSettings[AVLinearPCMBitDepthKey] = 16
    fileSettings[AVLinearPCMIsFloatKey] = false
    fileSettings[AVLinearPCMIsBigEndianKey] = false
    fileSettings[AVLinearPCMIsNonInterleaved] = false

    // Create output file with sanitized settings
    do {
      let file = try AVAudioFile(forWriting: url, settings: fileSettings)

      // Thread-safe assignment
      audioProcessingQueue.sync {
        self.outputFile = file
        self.recordingURL = url
      }
    } catch {
      resetRecordingState()
      throw error
    }

    // Use the concrete file format as converter target (Core Audio may adjust settings)
    var fileFormat: AVAudioFormat?
    audioProcessingQueue.sync {
      fileFormat = self.outputFile?.processingFormat
    }

    guard let fileFormat = fileFormat else {
      resetRecordingState()
      throw UnifiedAudioEngineError.invalidFormat
    }

    log(
      "Output file format - sampleRate: \(fileFormat.sampleRate), channels: \(fileFormat.channelCount), commonFormat: \(fileFormat.commonFormat)",
      category: unifiedAudioEngineLogCategory,
      level: .debug
    )

    // Create converter if formats differ
    if inputFormat.sampleRate != fileFormat.sampleRate
      || inputFormat.channelCount != fileFormat.channelCount
      || inputFormat.commonFormat != fileFormat.commonFormat
    {
      guard let conv = AVAudioConverter(from: inputFormat, to: fileFormat) else {
        resetRecordingState()
        throw UnifiedAudioEngineError.converterCreationFailed
      }

      // In live capture we cannot provide priming frames, so disable priming latency.
      conv.primeMethod = .none
      conv.primeInfo = AVAudioConverterPrimeInfo(leadingFrames: 0, trailingFrames: 0)

      // Thread-safe assignment
      audioProcessingQueue.sync {
        self.converter = conv
      }

      log(
        "Created format converter (\(inputFormat.sampleRate)Hz \(inputFormat.channelCount)ch -> \(fileFormat.sampleRate)Hz \(fileFormat.channelCount)ch)",
        category: unifiedAudioEngineLogCategory,
        level: .debug
      )
    } else {
      audioProcessingQueue.sync {
        self.converter = nil
      }
      log("No format conversion needed", category: unifiedAudioEngineLogCategory, level: .debug)
    }

    // Create sink node for real-time recording (replaces installTap for better performance)
    // AVAudioSinkNode provides lower latency than installTap (can receive 512-frame buffers)
    let sinkNode = AVAudioSinkNode { [weak self] timestamp, frameCount, audioBufferList in
      // CRITICAL: This callback runs on high-priority audio thread
      // Must return quickly (<1ms) to avoid audio glitches
      guard let self = self else { return 0 }

      // Process the audio buffer
      self.processRecordingBufferRealtime(
        timestamp: timestamp,
        frameCount: frameCount,
        bufferList: audioBufferList,
        format: inputFormat
      )

      return 0  // Return 0 to indicate success
    }

    // Attach and connect sink node to input
    log("Attaching sink node for real-time recording", category: unifiedAudioEngineLogCategory, level: .debug)
    engine.attach(sinkNode)
    engine.connect(inputNode, to: sinkNode, format: inputFormat)

    // Store sink node reference for cleanup
    self.sinkNode = sinkNode

    isRecordingActive = true

    // Start the engine after configuring the sink node
    do {
      try engine.start()
      log(
        "[DEBUG] Engine started successfully with sink node",
        category: unifiedAudioEngineLogCategory,
        level: .debug
      )
    } catch {
      log(
        "[ERROR] Failed to start engine: \(error)",
        category: unifiedAudioEngineLogCategory,
        level: .error
      )
      // Clean up on failure
      if let sinkNode = self.sinkNode {
        engine.detach(sinkNode)
        self.sinkNode = nil
      }
      resetRecordingState()
      throw UnifiedAudioEngineError.engineNotRunning
    }

    log(
      "Recording sink node setup successfully, file ready at: \(url.path)",
      category: unifiedAudioEngineLogCategory,
      level: .info
    )
  }

  /// Resets recording state atomically (call on errors or cancellation)
  private func resetRecordingState() {
    isRecordingActive = false
    audioProcessingQueue.sync {
      self.outputFile = nil
      self.converter = nil
    }
    recordingURL = nil

    // Reset pending write counter
    writeLock.lock()
    pendingWriteCount = 0
    writeLock.unlock()

    // Clean up sink node if it exists
    if let sinkNode = sinkNode {
      engine.detach(sinkNode)
      self.sinkNode = nil
    }
  }

  /// Stops recording and returns the URL of the recorded file
  func stopRecording() async -> URL? {
    let startTime = Date()
    log(
      "[PERF] stopRecording() started at \(startTime)",
      category: unifiedAudioEngineLogCategory,
      level: .debug
    )

    guard isRecordingActive else {
      log("Not currently recording", category: unifiedAudioEngineLogCategory, level: .info)
      return nil
    }

    // Detach sink node first - no more data will be written
    let detachStart = Date()
    if let sinkNode = sinkNode {
      engine.detach(sinkNode)
      self.sinkNode = nil
    }
    let detachDuration = Date().timeIntervalSince(detachStart)
    log(
      "[PERF] detach sink node took \(detachDuration * 1000)ms",
      category: unifiedAudioEngineLogCategory,
      level: .debug
    )

    // Mark as inactive to prevent new operations
    isRecordingActive = false

    // Keep strong reference to the file and URL during finalization
    var fileToFinalize: AVAudioFile?
    var url: URL?
    audioProcessingQueue.sync {
      fileToFinalize = self.outputFile
      url = self.recordingURL
    }

    // CRITICAL: Wait for any pending audio buffers to be written
    // The tap callback runs on a separate audio thread, and even after removeTap(),
    // there may be buffers in flight. We need to give them time to complete.
    // Use counter-based waiting instead of fixed sleep duration
    log(
      "[PERF] Waiting for pending buffer writes to complete",
      category: unifiedAudioEngineLogCategory,
      level: .debug
    )
    let waitStart = Date()
    var iterations = 0

    // Helper to get count without async lock warnings
    let getCount = { [self] () -> Int in
      self.writeLock.lock()
      let count = self.pendingWriteCount
      self.writeLock.unlock()
      return count
    }

    while true {
      let count = getCount()

      if count == 0 {
        break
      }

      iterations += 1
      if iterations > 200 {  // Max 2 seconds wait (200 * 10ms) - increased for async writes
        log(
          "[WARN] Timeout waiting for buffers (still \(count) pending)",
          category: unifiedAudioEngineLogCategory,
          level: .warning
        )
        break
      }

      try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
    }
    let waitDuration = Date().timeIntervalSince(waitStart)
    log(
      "[PERF] Buffer wait took \(waitDuration * 1000)ms (\(iterations) iterations)",
      category: unifiedAudioEngineLogCategory,
      level: .debug
    )

    // Additional safety: Ensure async write queue is drained
    // This is a belt-and-suspenders approach - the counter should already be 0
    log(
      "[PERF] Ensuring async write queue is drained",
      category: unifiedAudioEngineLogCategory,
      level: .debug
    )
    let drainStart = Date()
    await withCheckedContinuation { continuation in
      asyncWriteQueue.async {
        continuation.resume()
      }
    }
    let drainDuration = Date().timeIntervalSince(drainStart)
    log(
      "[PERF] Queue drain took \(drainDuration * 1000)ms",
      category: unifiedAudioEngineLogCategory,
      level: .debug
    )

    // Now it's safe to finalize the file
    if let fileToFinalize = fileToFinalize {
      let finalizeStart = Date()
      let framePos = fileToFinalize.framePosition
      log(
        "Finalizing audio file (framePosition: \(framePos))",
        category: unifiedAudioEngineLogCategory,
        level: .debug
      )

      // Clean up file reference in thread-safe manner
      audioProcessingQueue.sync {
        self.outputFile = nil
        self.converter = nil
        self.recordingURL = nil
      }

      let finalizeDuration = Date().timeIntervalSince(finalizeStart)
      log(
        "[PERF] File finalization took \(finalizeDuration * 1000)ms",
        category: unifiedAudioEngineLogCategory,
        level: .debug
      )
    }

    let totalDuration = Date().timeIntervalSince(startTime)
    log(
      "[PERF] stopRecording() total duration: \(totalDuration * 1000)ms",
      category: unifiedAudioEngineLogCategory,
      level: .debug
    )
    log(
      "Recording stopped, file at: \(url?.path ?? "unknown")",
      category: unifiedAudioEngineLogCategory,
      level: .info
    )

    // Stop the engine to release input node connection
    engine.stop()

    // Reset the audio engine graph to fully release all audio resources
    // This ensures the input node is completely disconnected and the macOS
    // recording indicator (orange dot) is cleared
    engine.reset()

    hasAttemptedStart = false  // Reset flag to allow engine restart on next recording
    log(
      "Engine stopped and reset - recording indicator cleared",
      category: unifiedAudioEngineLogCategory,
      level: .debug
    )

    return url
  }

  /// Cancels recording and deletes the file
  func cancelRecording() async {
    log("Cancelling recording", category: unifiedAudioEngineLogCategory, level: .info)

    let url = await stopRecording()

    // Delete the recording file
    if let url = url {
      do {
        try FileManager.default.removeItem(at: url)
        log(
          "Deleted cancelled recording at: \(url.path)",
          category: unifiedAudioEngineLogCategory,
          level: .info
        )
      } catch {
        log(
          "Failed to delete cancelled recording: \(error)",
          category: unifiedAudioEngineLogCategory,
          level: .warning
        )
      }
    }

    // Ensure engine is stopped (stopRecording should have done this, but be explicit)
    engine.stop()
    engine.reset()
    hasAttemptedStart = false  // Reset flag to allow engine restart on next recording
    log(
      "Engine stopped and reset after cancellation",
      category: unifiedAudioEngineLogCategory,
      level: .debug
    )
  }

  // MARK: - Real-Time Audio Callback (C-Style for Performance)

  /// Real-time audio callback for AVAudioSinkNode (optimized C-style)
  /// CRITICAL: This runs on high-priority audio thread - must complete in <1ms
  nonisolated private func processRecordingBufferRealtime(
    timestamp: UnsafePointer<AudioTimeStamp>,
    frameCount: AVAudioFrameCount,
    bufferList: UnsafePointer<AudioBufferList>,
    format: AVAudioFormat
  ) {
    #if DEBUG
    let callbackStartTime = CFAbsoluteTimeGetCurrent()
    #endif

    // OPTIMIZATION: Direct access without queue sync (marked nonisolated unsafe)
    let localFile = self.outputFile
    let localConverter = self.converter

    guard localFile != nil else {
      // Not recording - exit immediately
      return
    }

    // Increment pending write counter (atomic via lock)
    let writeLockRef = self.writeLock
    writeLockRef.lock()
    self.pendingWriteCount += 1
    writeLockRef.unlock()

    // Get buffer from pool (reuse if available, allocate if needed)
    guard let copiedBuffer = bufferPool.getBuffer(format: format, frameCapacity: frameCount) else {
      writeLockRef.lock()
      self.pendingWriteCount -= 1
      writeLockRef.unlock()
      return
    }

    // CRITICAL: Fast C-style memcpy from AudioBufferList to AVAudioPCMBuffer
    copiedBuffer.frameLength = frameCount

    guard let destChannels = copiedBuffer.floatChannelData else {
      bufferPool.returnBuffer(copiedBuffer)
      writeLockRef.lock()
      self.pendingWriteCount -= 1
      writeLockRef.unlock()
      return
    }

    // Copy audio data using direct pointer arithmetic
    let bytesToCopy = Int(frameCount) * MemoryLayout<Float>.stride
    let abl = bufferList.pointee
    let numBuffers = Int(abl.mNumberBuffers)

    // Access the buffer array using withUnsafePointer
    withUnsafePointer(to: abl.mBuffers) { buffersPtr in
      let buffersPointer = UnsafeRawPointer(buffersPtr)
        .assumingMemoryBound(to: AudioBuffer.self)

      for channelIndex in 0..<min(numBuffers, Int(format.channelCount)) {
        let audioBuffer = buffersPointer[channelIndex]
        guard let sourceData = audioBuffer.mData?.assumingMemoryBound(to: Float.self) else {
          continue
        }
        memcpy(destChannels[channelIndex], sourceData, bytesToCopy)
      }
    }

    #if DEBUG
    // Measure callback execution time
    let callbackDuration = CFAbsoluteTimeGetCurrent() - callbackStartTime
    if callbackDuration > 0.001 {  // > 1ms
      // Log occasionally to avoid flooding
      if Int.random(in: 0..<100) == 0 {
        log(
          "[PERF WARN] Audio callback took \(callbackDuration * 1000)ms (should be < 1ms)",
          category: unifiedAudioEngineLogCategory,
          level: .warning
        )
      }
    }
    #endif

    // Dispatch file write ASYNCHRONOUSLY - don't wait for it to complete!
    // This is the key to avoiding stuttering
    let asyncWriteQueueRef = self.asyncWriteQueue
    let bufferPoolRef = self.bufferPool
    asyncWriteQueueRef.async {
      // Ensure we decrement counter and return buffer on all exit paths
      defer {
        writeLockRef.lock()
        self.pendingWriteCount -= 1
        writeLockRef.unlock()
        bufferPoolRef.returnBuffer(copiedBuffer)
      }

      // Unwrap file for use in this closure
      guard let file = localFile else { return }

      // Update level monitoring with throttling (moved OFF audio thread)
      let now = CFAbsoluteTimeGetCurrent()
      let timeSinceLastUpdate = now - self.lastLevelUpdate
      if timeSinceLastUpdate > self.levelUpdateThrottle {
        self.lastLevelUpdate = now

        // Calculate level from copied buffer and dispatch to main thread
        if let level = self.normalizedLevel(from: copiedBuffer) {
          // Also extract waveform samples for visualization
          let samples = self.extractWaveformSamples(from: copiedBuffer)

          Task { @MainActor [weak self] in
            self?.updateLevel(level)
            self?.updateWaveformSamples(samples)
          }
        }
      }

      // Perform conversion if needed (this is now OFF the audio thread)
      if let converter = localConverter {
        // Convert format using pull-based API
        let outputFrameCapacity =
          AVAudioFrameCount(
            Double(copiedBuffer.frameLength) * converter.outputFormat.sampleRate
              / converter.inputFormat.sampleRate
          ) + 1024  // Safety margin

        guard
          let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: converter.outputFormat,
            frameCapacity: outputFrameCapacity
          )
        else {
          log(
            "[ERROR] Failed to create output buffer",
            category: unifiedAudioEngineLogCategory,
            level: .error
          )
          return
        }

        // Convert
        var isBufferConsumed = false

        conversionLoop: while true {
          outputBuffer.frameLength = 0

          var providedInput = false
          var error: NSError?
          let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if isBufferConsumed {
              outStatus.pointee = .noDataNow
              return nil
            }

            isBufferConsumed = true
            providedInput = true
            outStatus.pointee = .haveData
            return copiedBuffer
          }

          if let error = error {
            log(
              "[ERROR] Conversion failed: \(error)",
              category: unifiedAudioEngineLogCategory,
              level: .error
            )
            break
          }

          let producedFrames = outputBuffer.frameLength

          if producedFrames > 0 {
            do {
              try file.write(from: outputBuffer)
            } catch {
              log(
                "[ERROR] Failed to write converted buffer: \(error)",
                category: unifiedAudioEngineLogCategory,
                level: .error
              )
              break
            }
          } else if !providedInput && status == .endOfStream {
            // No input provided and nothing output - nothing left to process.
            break
          }

          switch status {
          case .haveData:
            // Converter may still have residual data to emit.
            continue conversionLoop
          case .inputRanDry:
            // We've supplied all available input for now; exit until next buffer arrives.
            break conversionLoop
          case .endOfStream:
            break conversionLoop
          case .error:
            log(
              "[ERROR] Converter returned error status",
              category: unifiedAudioEngineLogCategory,
              level: .error
            )
            break conversionLoop
          @unknown default:
            break conversionLoop
          }
        }
      } else {
        // No conversion needed, write directly
        do {
          try file.write(from: copiedBuffer)
        } catch {
          log(
            "[ERROR] Failed to write buffer: \(error)",
            category: unifiedAudioEngineLogCategory,
            level: .error
          )
        }
      }
    }
  }

  /// Copies an audio buffer (fast operation for real-time thread safety)
  nonisolated private func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    guard
      let copy = AVAudioPCMBuffer(
        pcmFormat: buffer.format,
        frameCapacity: buffer.frameLength  // Only allocate what we need
      )
    else {
      return nil
    }

    copy.frameLength = buffer.frameLength

    // Fast copy using direct pointer access
    guard let sourceChannels = buffer.floatChannelData,
          let destChannels = copy.floatChannelData else {
      return nil
    }

    let channelCount = Int(buffer.format.channelCount)
    let bytesToCopy = Int(buffer.frameLength) * MemoryLayout<Float>.stride

    // Copy each channel's data
    for channel in 0..<channelCount {
      memcpy(destChannels[channel], sourceChannels[channel], bytesToCopy)
    }

    return copy
  }

  // MARK: - Level Monitoring

  /// Calculates a normalized audio level from the provided buffer
  nonisolated private func normalizedLevel(from buffer: AVAudioPCMBuffer) -> CGFloat? {
    guard let channelData = buffer.floatChannelData?[0] else { return nil }
    let frameLength = Int(buffer.frameLength)

    var sum: Float = 0
    for i in 0..<frameLength {
      let sample = channelData[i]
      sum += sample * sample
    }

    let rms = sqrt(sum / Float(frameLength))
    let db = 20 * log10(max(rms, 0.000001))  // Avoid log(0)

    // Normalize to 0-1 range
    let minDb: Float = -60
    let maxDb: Float = -10
    let normalized = (db - minDb) / (maxDb - minDb)
    let clamped = max(0, min(1, normalized))

    return CGFloat(clamped)
  }

  /// Updates the published audio level on the main actor
  private func updateLevel(_ level: CGFloat) {
    print("[WAVEFORM DEBUG] UnifiedAudioEngine.updateLevel: \(level)")
    currentInputLevel = level
    // Note: lastLevelUpdate is updated in the audio callback for performance
  }

  /// Extracts peak samples from the buffer for waveform visualization
  nonisolated private func extractWaveformSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
    guard let channelData = buffer.floatChannelData?[0] else { return [] }
    let frameLength = Int(buffer.frameLength)
    let barCount = waveformBarCount

    guard frameLength > 0 && barCount > 0 else { return [] }

    let samplesPerBar = frameLength / barCount
    guard samplesPerBar > 0 else { return [] }

    var peaks: [Float] = []
    for i in 0..<barCount {
      let start = i * samplesPerBar
      let end = min(start + samplesPerBar, frameLength)
      var maxAbs: Float = 0
      for j in start..<end {
        maxAbs = max(maxAbs, abs(channelData[j]))
      }
      peaks.append(maxAbs)
    }
    return peaks
  }

  /// Updates the published waveform samples on the main actor
  private func updateWaveformSamples(_ samples: [Float]) {
    waveformSamples = samples
  }

  // MARK: - Sound Playback

  /// Preloads a sound file into memory for faster playback
  func preloadSound(from url: URL, for type: SoundType) {
    log(
      "Preloading \(type) sound from \(url)",
      category: unifiedAudioEngineLogCategory,
      level: .debug
    )

    do {
      let audioFile = try AVAudioFile(forReading: url)
      let frameCount = AVAudioFrameCount(audioFile.length)
      let sourceFormat = audioFile.processingFormat

      // Get the playerNode's output format (matches the mixer's format)
      let playerFormat = playerNode.outputFormat(forBus: 0)

      log(
        "Converting \(type) from \(sourceFormat.sampleRate)Hz \(sourceFormat.channelCount)ch to \(playerFormat.sampleRate)Hz \(playerFormat.channelCount)ch",
        category: unifiedAudioEngineLogCategory,
        level: .debug
      )

      // Read the source audio into a buffer
      guard
        let sourceBuffer = AVAudioPCMBuffer(
          pcmFormat: sourceFormat,
          frameCapacity: frameCount
        )
      else {
        log(
          "Failed to create source buffer for \(type)",
          category: unifiedAudioEngineLogCategory,
          level: .error
        )
        return
      }

      try audioFile.read(into: sourceBuffer)

      // Convert to player format if needed
      let finalBuffer: AVAudioPCMBuffer
      if sourceFormat.sampleRate == playerFormat.sampleRate
        && sourceFormat.channelCount == playerFormat.channelCount
      {
        // No conversion needed
        finalBuffer = sourceBuffer
        log("No conversion needed for \(type)", category: unifiedAudioEngineLogCategory, level: .debug)
      } else {
        // Create converter
        guard let converter = AVAudioConverter(from: sourceFormat, to: playerFormat) else {
          log(
            "Failed to create converter for \(type)",
            category: unifiedAudioEngineLogCategory,
            level: .error
          )
          return
        }

        // Calculate output frame count
        let outputFrameCount = AVAudioFrameCount(
          Double(frameCount) * playerFormat.sampleRate / sourceFormat.sampleRate
        )

        // Create output buffer
        guard
          let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: playerFormat,
            frameCapacity: outputFrameCount
          )
        else {
          log(
            "Failed to create output buffer for \(type)",
            category: unifiedAudioEngineLogCategory,
            level: .error
          )
          return
        }

        // Convert
        var error: NSError?
        converter.convert(
          to: outputBuffer, error: &error,
          withInputFrom: { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return sourceBuffer
          })

        if let error = error {
          log(
            "Conversion error for \(type): \(error)",
            category: unifiedAudioEngineLogCategory,
            level: .error
          )
          return
        }

        finalBuffer = outputBuffer
        log(
          "Successfully converted \(type) sound",
          category: unifiedAudioEngineLogCategory,
          level: .debug
        )
      }

      // Store the converted buffer
      switch type {
      case .recordingStart:
        recordingStartBuffer = finalBuffer
      case .transcriptionComplete:
        transcriptionCompleteBuffer = finalBuffer
      }

      log(
        "Successfully preloaded \(type) sound",
        category: unifiedAudioEngineLogCategory,
        level: .info
      )
    } catch {
      log(
        "Failed to preload \(type) sound: \(error)",
        category: unifiedAudioEngineLogCategory,
        level: .error
      )
    }
  }

  /// Plays a preloaded sound
  func playSound(type: SoundType, completion: (() -> Void)? = nil) {
    let buffer: AVAudioPCMBuffer?

    switch type {
    case .recordingStart:
      buffer = recordingStartBuffer
    case .transcriptionComplete:
      buffer = transcriptionCompleteBuffer
    }

    guard let buffer = buffer else {
      log(
        "Sound \(type) not loaded",
        category: unifiedAudioEngineLogCategory,
        level: .warning
      )
      completion?()
      return
    }

    log("Playing \(type) sound", category: unifiedAudioEngineLogCategory, level: .debug)

    // Ensure engine is started (lazy initialization)
    ensureEngineStarted()

    // Schedule buffer on player node
    playerNode.scheduleBuffer(buffer) {
      log(
        "Finished playing \(type) sound",
        category: unifiedAudioEngineLogCategory,
        level: .debug
      )
      completion?()
    }

    // Start player if not already playing
    if !playerNode.isPlaying {
      playerNode.play()
    }
  }

  /// Clears a preloaded sound from memory
  func clearSound(type: SoundType) {
    switch type {
    case .recordingStart:
      recordingStartBuffer = nil
    case .transcriptionComplete:
      transcriptionCompleteBuffer = nil
    }
    log("Cleared \(type) sound from memory", category: unifiedAudioEngineLogCategory, level: .debug)
  }
}

// MARK: - Buffer Pool

/// Thread-safe buffer pool for zero-allocation real-time audio callbacks
final class BufferPool: @unchecked Sendable {
  private var availableBuffers: [AVAudioPCMBuffer] = []
  private let lock = NSLock()
  private let poolSize = 20

  /// Get a buffer from the pool (creates one if pool is empty)
  nonisolated func getBuffer(format: AVAudioFormat, frameCapacity: AVAudioFrameCount) -> AVAudioPCMBuffer? {
    lock.lock()
    defer { lock.unlock() }

    // Try to reuse existing buffer with matching format
    if let index = availableBuffers.firstIndex(where: {
      $0.format == format && $0.frameCapacity >= frameCapacity
    }) {
      return availableBuffers.remove(at: index)
    }

    // Pool is empty or no matching buffer, create new one
    return AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity)
  }

  /// Return a buffer to the pool for reuse
  nonisolated func returnBuffer(_ buffer: AVAudioPCMBuffer) {
    lock.lock()
    defer { lock.unlock() }

    // Only keep up to poolSize buffers to avoid unbounded memory growth
    guard availableBuffers.count < poolSize else { return }

    // Reset buffer for reuse
    buffer.frameLength = 0
    availableBuffers.append(buffer)
  }

  /// Clear all buffers from pool
  nonisolated func clear() {
    lock.lock()
    defer { lock.unlock() }
    availableBuffers.removeAll()
  }
}

// MARK: - Supporting Types

enum SoundType: String {
  case recordingStart
  case transcriptionComplete
}

enum UnifiedAudioEngineError: LocalizedError {
  case alreadyRecording
  case engineNotRunning
  case invalidFormat
  case converterCreationFailed

  var errorDescription: String? {
    switch self {
    case .alreadyRecording:
      return "Recording is already in progress"
    case .engineNotRunning:
      return "Audio engine is not running"
    case .invalidFormat:
      return "Invalid audio format"
    case .converterCreationFailed:
      return "Failed to create audio format converter"
    }
  }
}
