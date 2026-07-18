// Treat legacy AVFoundation types as @unchecked Sendable while the module awaits concurrency annotations.
@preconcurrency import AVFoundation
import AudioToolbox
import Combine
import CoreGraphics
import Foundation

private let unifiedAudioEngineLogCategory = "UnifiedAudioEngine"

/// Audio engine facade that uses two separate AVAudioEngine instances:
/// - `playbackEngine`: long-lived, output-only. Never touches `inputNode`, so Bluetooth
///   devices stay in A2DP while sound effects play.
/// - `recordingEngine`: created fresh for each recording and fully deallocated on stop.
///   Deallocating the engine releases the AUHAL input, letting Bluetooth devices return
///   to A2DP once recording ends.
@MainActor
class UnifiedAudioEngine: ObservableObject {
  static let shared = UnifiedAudioEngine()

  // MARK: - Playback (long-lived)
  private let playbackEngine = AVAudioEngine()
  private let playerNode = AVAudioPlayerNode()
  private var pendingPlaybackCount = 0
  private var lastKnownMixerSampleRate: Double?
  private var lastKnownMixerChannelCount: AVAudioChannelCount?
  private var configurationChangeObserver: NSObjectProtocol?
  private var idlePolicyObserver: NSObjectProtocol?
  private var idleStopTask: Task<Void, Never>?

  // MARK: - Recording (per-session)
  private var recordingEngine: AVAudioEngine?
  private var sinkNode: AVAudioSinkNode?
  private var recordingMixerNode: AVAudioMixerNode?

  // Thread-safe queue for audio processing (access to shared state)
  private let audioProcessingQueue = DispatchQueue(
    label: "com.echo.audio.processing", qos: .userInteractive)

  // Async write queue for non-blocking file I/O (serial to maintain order)
  private let asyncWriteQueue = DispatchQueue(
    label: "com.echo.audio.write", qos: .userInitiated)

  // Buffer pool for zero-allocation real-time callbacks
  private let bufferPool = BufferPool()

  // Recording state (accessed from MainActor and audio thread; protected by queue/lock)
  nonisolated(unsafe) private var outputFile: AVAudioFile?
  nonisolated(unsafe) private var converter: AVAudioConverter?
  private var isRecordingActive = false
  private var recordingURL: URL?

  nonisolated(unsafe) private var pendingWriteCount = 0
  private let writeLock = NSLock()

  // Frame counter used to detect silent HAL IO failure. AVAudioEngine.start() can return
  // success while the underlying AUHAL fails to start (CoreAudio logs
  // "StartAndWaitForState returned error 35"), leaving the sink node receiving no callbacks
  // and the recording file empty. We track frame deliveries and verify the first one arrived
  // before reporting the recording as started.
  nonisolated(unsafe) private var framesReceived: Int = 0
  private let frameCounterLock = NSLock()

  // Metering
  @Published var currentInputLevel: CGFloat = 0
  @Published var waveformSamples: [Float] = []
  nonisolated(unsafe) private var lastLevelUpdate: TimeInterval = 0
  private let levelUpdateThrottle: TimeInterval = 0.05  // 20Hz max (50ms)
  private let waveformBarCount: Int = 12
  nonisolated private static let normalizationTargetPeak: Float = 0.35
  nonisolated fileprivate static let normalizationMinPeak: Float = 0.02
  nonisolated private static let normalizationMinGain: Float = 0.75
  nonisolated private static let normalizationMaxGain: Float = 8.0
  nonisolated private static let normalizationDecayPerSecond: Float = 0.85
  nonisolated private static let normalizationSilenceGate: Float = 0.003
  nonisolated private static let normalizationGainSmoothing: Float = 0.2
  nonisolated(unsafe) private var normalizationState = WaveformNormalizationState()

  // Preloaded sound buffers
  private var recordingStartBuffer: AVAudioPCMBuffer?
  private var transcriptionCompleteBuffer: AVAudioPCMBuffer?

  private let settingsManager = SettingsManager.shared
  private let firstFrameTimeoutMs = 750

  private init() {
    setupPlaybackEngine()
    setupPlaybackConfigurationObserver()
    setupIdlePolicyObserver()
  }

  deinit {
    if let observer = configurationChangeObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    if let observer = idlePolicyObserver {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  // MARK: - Playback Engine Lifecycle

  private func setupPlaybackEngine() {
    log("Setting up playback engine", category: unifiedAudioEngineLogCategory, level: .debug)

    playbackEngine.attach(playerNode)

    let mixerFormat = playbackEngine.mainMixerNode.outputFormat(forBus: 0)
    log(
      "Playback mixer format - sampleRate: \(mixerFormat.sampleRate), channels: \(mixerFormat.channelCount)",
      category: unifiedAudioEngineLogCategory,
      level: .debug
    )

    playbackEngine.connect(playerNode, to: playbackEngine.mainMixerNode, format: mixerFormat)
    lastKnownMixerSampleRate = mixerFormat.sampleRate
    lastKnownMixerChannelCount = mixerFormat.channelCount

    log("Playback engine setup complete", category: unifiedAudioEngineLogCategory, level: .debug)
  }

  /// Ensures the playback engine is running (lazy start on first sound).
  /// Only connects output — never touches `inputNode`, so Bluetooth stays in A2DP.
  private func ensurePlaybackEngineStarted() {
    if !playbackEngine.isRunning {
      refreshPlayerConnectionIfNeeded()
    }

    guard !playbackEngine.isRunning else { return }

    startPlaybackEngineWithRetry()
  }

  private func startPlaybackEngineWithRetry(maxRetries: Int = 3) {
    for attempt in 1...maxRetries {
      do {
        if !playbackEngine.isRunning {
          try playbackEngine.start()
          log(
            "Playback engine started on attempt \(attempt)",
            category: unifiedAudioEngineLogCategory,
            level: .info
          )
        }
        return
      } catch let error as NSError {
        log(
          "Playback engine start attempt \(attempt) failed: \(error)",
          category: unifiedAudioEngineLogCategory,
          level: .error
        )

        // EAGAIN (35) means device is reconfiguring - retry immediately
        if error.code == 35 && attempt < maxRetries {
          continue
        }
        return
      }
    }
  }

  private func setupPlaybackConfigurationObserver() {
    configurationChangeObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange,
      object: playbackEngine,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      Task { @MainActor in
        log(
          "Playback engine configuration changed",
          category: unifiedAudioEngineLogCategory,
          level: .warning
        )
        self.resetPlaybackEngineForConfigurationChange()
      }
    }
  }

  private func resetPlaybackEngineForConfigurationChange() {
    // Only stop/reset if actually running — resetting an idle engine can churn the HAL
    // and contend with a concurrent recording engine start.
    if playbackEngine.isRunning {
      playbackEngine.stop()
      playbackEngine.reset()
    }
    refreshPlayerConnectionIfNeeded()
  }

  private func refreshPlayerConnectionIfNeeded() {
    let mixerFormat = playbackEngine.mainMixerNode.outputFormat(forBus: 0)
    let sampleRateChanged = lastKnownMixerSampleRate != mixerFormat.sampleRate
    let channelCountChanged = lastKnownMixerChannelCount != mixerFormat.channelCount

    guard sampleRateChanged || channelCountChanged else { return }

    log(
      "Mixer format changed - reconnecting player node (sampleRate: \(mixerFormat.sampleRate), channels: \(mixerFormat.channelCount))",
      category: unifiedAudioEngineLogCategory,
      level: .debug
    )

    playbackEngine.disconnectNodeOutput(playerNode)
    playbackEngine.connect(playerNode, to: playbackEngine.mainMixerNode, format: mixerFormat)
    lastKnownMixerSampleRate = mixerFormat.sampleRate
    lastKnownMixerChannelCount = mixerFormat.channelCount
  }

  // MARK: - Idle Policy (playback engine only)

  private func setupIdlePolicyObserver() {
    idlePolicyObserver = NotificationCenter.default.addObserver(
      forName: UserDefaults.didChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      Task { @MainActor in
        self.handleIdlePolicyChange()
      }
    }
  }

  private func handleIdlePolicyChange() {
    switch settingsManager.audioEngineIdlePolicy {
    case .stopWhenIdle:
      stopPlaybackEngineIfIdle()
    case .idleTimeout:
      if pendingPlaybackCount == 0 {
        schedulePlaybackEngineIdleStop()
      }
    case .alwaysOn:
      cancelIdleStop()
    }
  }

  private func cancelIdleStop() {
    idleStopTask?.cancel()
    idleStopTask = nil
  }

  private func schedulePlaybackEngineIdleStop() {
    cancelIdleStop()

    switch settingsManager.audioEngineIdlePolicy {
    case .stopWhenIdle:
      stopPlaybackEngineIfIdle()
    case .idleTimeout:
      let seconds = SettingsManager.clampedIdleTimeoutSeconds(
        settingsManager.audioEngineIdleTimeoutSeconds
      )
      idleStopTask = Task { [weak self] in
        try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
        await MainActor.run {
          self?.stopPlaybackEngineIfIdle()
        }
      }
    case .alwaysOn:
      break
    }
  }

  private func stopPlaybackEngineIfIdle() {
    guard pendingPlaybackCount == 0 else { return }

    if playbackEngine.isRunning {
      playbackEngine.stop()
    }
    playbackEngine.reset()
    log(
      "Playback engine stopped due to idle policy",
      category: unifiedAudioEngineLogCategory,
      level: .debug
    )
  }

  private func handlePlaybackCompletion() {
    pendingPlaybackCount = max(0, pendingPlaybackCount - 1)
    log(
      "Playback completed (pending: \(pendingPlaybackCount))",
      category: unifiedAudioEngineLogCategory,
      level: .debug
    )

    if pendingPlaybackCount == 0 {
      if playerNode.isPlaying {
        playerNode.stop()
      }
      schedulePlaybackEngineIdleStop()
    }
  }

  // MARK: - Recording

  /// Starts recording audio to the specified URL.
  /// Creates a fresh AVAudioEngine for this session. On stop, the engine is fully
  /// deallocated — that's what releases the AUHAL input and lets Bluetooth headsets
  /// switch back from HFP to A2DP.
  func startRecording(to url: URL) async throws {
    let startTime = Date()
    log(
      "[PERF] startRecording() started at \(startTime)",
      category: unifiedAudioEngineLogCategory,
      level: .debug
    )

    guard !isRecordingActive else {
      throw UnifiedAudioEngineError.alreadyRecording
    }

    normalizationState = WaveformNormalizationState()

    // Retry logic handles two classes of failure:
    //   1. Setup throws EAGAIN (35) / format-not-supported (-10877) during Bluetooth
    //      profile transitions.
    //   2. Setup succeeds but AUHAL silently fails to start IO — engine.start() returns
    //      success yet no sink callback ever fires. Detected by waitForFirstFrame().
    let maxRetries = 3
    var lastError: Error?
    var allowConfiguredInputDevice = !settingsManager.selectedInputDeviceUID.isEmpty

    for attempt in 1...maxRetries {
      do {
        try await setupRecordingEngine(
          to: url,
          allowConfiguredInputDevice: allowConfiguredInputDevice
        )
      } catch {
        lastError = error
        log(
          "Recording setup attempt \(attempt) failed: \(error)",
          category: unifiedAudioEngineLogCategory,
          level: .error
        )

        tearDownRecordingEngine()

        if allowConfiguredInputDevice,
          shouldFallbackFromConfiguredInputDeviceSetup(error),
          attempt < maxRetries
        {
          allowConfiguredInputDevice = false
          let settleDelay = retrySettleDelayNanoseconds(afterAttempt: attempt)
          log(
            "Configured input device setup failed; retrying with system default input after \(settleDelay / 1_000_000)ms settle delay (attempt \(attempt + 1))...",
            category: unifiedAudioEngineLogCategory,
            level: .warning
          )
          try? await Task.sleep(nanoseconds: settleDelay)
          continue
        }

        if isRecoverableRecordingSetupError(error), attempt < maxRetries {
          let settleDelay = retrySettleDelayNanoseconds(afterAttempt: attempt)
          log(
            "Device reconfiguring, retrying after \(settleDelay / 1_000_000)ms settle delay (attempt \(attempt + 1))...",
            category: unifiedAudioEngineLogCategory,
            level: .warning
          )
          try? await Task.sleep(nanoseconds: settleDelay)
          continue
        }

        throw error
      }

      // Setup succeeded — verify the HAL is actually delivering audio frames.
      if await waitForFirstFrame(timeoutMs: firstFrameTimeoutMs) {
        let totalDuration = Date().timeIntervalSince(startTime)
        log(
          "[PERF] startRecording() total duration: \(totalDuration * 1000)ms",
          category: unifiedAudioEngineLogCategory,
          level: .info
        )
        log(
          "Recording started successfully on attempt \(attempt)",
          category: unifiedAudioEngineLogCategory,
          level: .info
        )
        return
      }

      log(
        "Recording engine started but HAL delivered no frames — silent IO failure (attempt \(attempt) of \(maxRetries))",
        category: unifiedAudioEngineLogCategory,
        level: .warning
      )
      tearDownRecordingEngine()

      if attempt < maxRetries {
        // setupRecordingEngine already stops the playback engine on each attempt, so we
        // just need to wait for the device to settle before the next try.
        let settleDelay = retrySettleDelayNanoseconds(afterAttempt: attempt)
        log(
          "Retrying recording after \(settleDelay / 1_000_000)ms settle delay (attempt \(attempt + 1))...",
          category: unifiedAudioEngineLogCategory,
          level: .warning
        )
        try? await Task.sleep(nanoseconds: settleDelay)
        continue
      }
    }

    if let error = lastError {
      throw error
    }
    throw UnifiedAudioEngineError.deviceUnavailable
  }

  private func retrySettleDelayNanoseconds(afterAttempt attempt: Int) -> UInt64 {
    switch attempt {
    case 1:
      return 500_000_000
    case 2:
      return 1_000_000_000
    default:
      return 1_500_000_000
    }
  }

  nonisolated static func preInputNodeSettleDelayNanoseconds(
    playbackEngineWasRunning: Bool
  ) -> UInt64 {
    playbackEngineWasRunning ? 500_000_000 : 0
  }

  private func isRecoverableRecordingSetupError(_ error: Error) -> Bool {
    if let engineError = error as? UnifiedAudioEngineError {
      switch engineError {
      case .avfaudioException, .invalidInputHardwareFormat:
        return true
      case .alreadyRecording, .engineNotRunning, .invalidFormat, .converterCreationFailed,
        .deviceUnavailable:
        return false
      }
    }

    if let inputDeviceError = error as? AudioInputDeviceError {
      switch inputDeviceError {
      case .failedToApplyDevice(let status):
        return AudioInputDeviceManager.isRecoverableAudioSetupStatus(status)
      }
    }

    let nsError = error as NSError
    return AudioInputDeviceManager.isRecoverableAudioSetupStatus(OSStatus(nsError.code))
  }

  private func shouldFallbackFromConfiguredInputDeviceSetup(_ error: Error) -> Bool {
    if let inputDeviceError = error as? AudioInputDeviceError {
      switch inputDeviceError {
      case .failedToApplyDevice:
        return true
      }
    }

    return isRecoverableRecordingSetupError(error)
  }

  /// Polls the frame counter until either a frame arrives or the timeout elapses.
  /// Used to detect silent AUHAL IO failures after `engine.start()` returns success.
  private func waitForFirstFrame(timeoutMs: Int) async -> Bool {
    let deadline = Date().addingTimeInterval(TimeInterval(timeoutMs) / 1000.0)

    // Read the counter through a sync closure so the lock never spans an await point.
    let getCount = { [self] () -> Int in
      self.frameCounterLock.lock()
      let count = self.framesReceived
      self.frameCounterLock.unlock()
      return count
    }

    while Date() < deadline {
      if getCount() > 0 { return true }
      try? await Task.sleep(nanoseconds: 20_000_000)  // 20ms
    }

    return getCount() > 0
  }

  private func resetFrameCounter() {
    frameCounterLock.lock()
    framesReceived = 0
    frameCounterLock.unlock()
  }

  private func setupRecordingEngine(
    to url: URL,
    allowConfiguredInputDevice: Bool
  ) async throws {
    // Fully release the playback engine before allocating the recording engine. Even when
    // idle, a recently-used playback engine holds a HAL output stream that contends with
    // the recording engine's input stream on the same Bluetooth device. Symptom of skipping
    // this: first recording succeeds (playback engine was cold), second fails silently
    // (playback engine warm from the recording-start / transcription-complete sounds).
    // The playback engine restarts lazily when the next sound effect plays.
    let playbackEngineWasRunning = playbackEngine.isRunning
    if playbackEngineWasRunning {
      log(
        "Stopping playback engine to release device before recording setup",
        category: unifiedAudioEngineLogCategory,
        level: .debug
      )
      playbackEngine.stop()
      playbackEngine.reset()
    }

    let preInputNodeSettleDelay = Self.preInputNodeSettleDelayNanoseconds(
      playbackEngineWasRunning: playbackEngineWasRunning
    )
    if preInputNodeSettleDelay > 0 {
      log(
        "Waiting \(preInputNodeSettleDelay / 1_000_000)ms for CoreAudio to settle before accessing recording input node",
        category: unifiedAudioEngineLogCategory,
        level: .debug
      )
      try? await Task.sleep(nanoseconds: preInputNodeSettleDelay)
    }

    // Reset the frame counter here (not just in teardown) so any stale callbacks from the
    // previous session's audio thread can't spoof a "first frame received" reading on the
    // new engine.
    resetFrameCounter()

    // Fresh engine per session so teardown fully releases the AUHAL input.
    log("Creating fresh recording engine", category: unifiedAudioEngineLogCategory, level: .debug)
    let engine = AVAudioEngine()
    recordingEngine = engine

    logDefaultInputDeviceBreadcrumb()
    log("Accessing recording input node", category: unifiedAudioEngineLogCategory, level: .debug)
    let inputNode = try AVFAudioExceptionGuard.run(operation: "recording inputNode") {
      engine.inputNode
    }
    log("Recording input node acquired", category: unifiedAudioEngineLogCategory, level: .debug)

    if allowConfiguredInputDevice {
      try AVFAudioExceptionGuard.run(operation: "apply configured input device") {
        try applyConfiguredInputDevice(to: inputNode)
      }
    } else if !settingsManager.selectedInputDeviceUID.isEmpty {
      log(
        "Skipping configured input devices for this attempt; using system default input",
        category: unifiedAudioEngineLogCategory,
        level: .warning
      )
    }

    log("Reading recording input hardware format", category: unifiedAudioEngineLogCategory, level: .debug)
    let inputFormat = try AVFAudioExceptionGuard.run(operation: "read input hardware format") {
      inputNode.inputFormat(forBus: 0)
    }
    log(
      "Input format - sampleRate: \(inputFormat.sampleRate), channels: \(inputFormat.channelCount), commonFormat: \(inputFormat.commonFormat)",
      category: unifiedAudioEngineLogCategory,
      level: .debug
    )

    guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
      throw UnifiedAudioEngineError.invalidInputHardwareFormat(
        sampleRate: inputFormat.sampleRate,
        channelCount: inputFormat.channelCount
      )
    }

    // Use current input sample rate with mono as the stable intermediate format.
    // Avoids kAudioUnitErr_FormatNotSupported (-10877) during Bluetooth A2DP↔HFP transitions.
    guard let stableFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: inputFormat.sampleRate,
      channels: 1,
      interleaved: false
    ) else {
      throw UnifiedAudioEngineError.invalidFormat
    }

    log(
      "Using stable intermediate format - sampleRate: \(stableFormat.sampleRate), channels: \(stableFormat.channelCount)",
      category: unifiedAudioEngineLogCategory,
      level: .debug
    )

    // Output format: 16kHz mono 16-bit PCM for Whisper API
    guard let outputFormat = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: 16000.0,
      channels: 1,
      interleaved: true
    ) else {
      throw UnifiedAudioEngineError.invalidFormat
    }

    var fileSettings = outputFormat.settings
    fileSettings[AVFormatIDKey] = Int(kAudioFormatLinearPCM)
    fileSettings[AVLinearPCMBitDepthKey] = 16
    fileSettings[AVLinearPCMIsFloatKey] = false
    fileSettings[AVLinearPCMIsBigEndianKey] = false
    fileSettings[AVLinearPCMIsNonInterleaved] = false

    let file = try AVAudioFile(forWriting: url, settings: fileSettings)
    audioProcessingQueue.sync {
      self.outputFile = file
      self.recordingURL = url
    }

    var fileFormat: AVAudioFormat?
    audioProcessingQueue.sync {
      fileFormat = self.outputFile?.processingFormat
    }

    guard let fileFormat else {
      throw UnifiedAudioEngineError.invalidFormat
    }

    log(
      "Output file format - sampleRate: \(fileFormat.sampleRate), channels: \(fileFormat.channelCount), commonFormat: \(fileFormat.commonFormat)",
      category: unifiedAudioEngineLogCategory,
      level: .debug
    )

    guard let conv = AVAudioConverter(from: stableFormat, to: fileFormat) else {
      throw UnifiedAudioEngineError.converterCreationFailed
    }
    // Live capture can't provide priming frames.
    conv.primeMethod = .none
    conv.primeInfo = AVAudioConverterPrimeInfo(leadingFrames: 0, trailingFrames: 0)

    audioProcessingQueue.sync {
      self.converter = conv
    }

    let recordingMixer = AVAudioMixerNode()
    let sinkNode = AVAudioSinkNode { [weak self] timestamp, frameCount, audioBufferList in
      // Runs on high-priority audio thread; must return in <1ms.
      guard let self else { return 0 }
      self.processRecordingBufferRealtime(
        timestamp: timestamp,
        frameCount: frameCount,
        bufferList: audioBufferList,
        format: stableFormat
      )
      return 0
    }

    try AVFAudioExceptionGuard.run(operation: "attach recording nodes") {
      engine.attach(recordingMixer)
      engine.attach(sinkNode)
    }

    // inputNode → mixer (auto-converts HW format) → sinkNode (stable format)
    try AVFAudioExceptionGuard.run(operation: "connect recording input graph") {
      engine.connect(inputNode, to: recordingMixer, format: nil)
      engine.connect(recordingMixer, to: sinkNode, format: stableFormat)
    }

    self.recordingMixerNode = recordingMixer
    self.sinkNode = sinkNode

    isRecordingActive = true

    try AVFAudioExceptionGuard.run(operation: "start recording engine") {
      try engine.start()
    }
    log(
      "Recording engine started with mixer → sink graph",
      category: unifiedAudioEngineLogCategory,
      level: .debug
    )
    log(
      "Recording ready at: \(url.path)",
      category: unifiedAudioEngineLogCategory,
      level: .info
    )
  }

  private func applyConfiguredInputDevice(to inputNode: AVAudioInputNode) throws {
    let preferredUID = settingsManager.selectedInputDeviceUID
    let fallbackUID = settingsManager.fallbackInputDeviceUID
    guard !preferredUID.isEmpty else {
      log(
        "No preferred input device; using system default input",
        category: unifiedAudioEngineLogCategory,
        level: .debug
      )
      return
    }

    log(
      "Resolving configured input devices - preferred uid: \(preferredUID), fallback uid: \(fallbackUID)",
      category: unifiedAudioEngineLogCategory,
      level: .debug
    )

    let selection = AudioInputDeviceManager.shared.resolvedSelection(
      preferredUID: preferredUID,
      fallbackUID: fallbackUID
    )
    guard let selectedDevice = selection.device else {
      log(
        "Configured input devices are unavailable and no default input device could be resolved",
        category: unifiedAudioEngineLogCategory,
        level: .warning
      )
      return
    }

    log(
      "Resolved \(selection.source.rawValue) input device - name: \(selectedDevice.name), id: \(selectedDevice.deviceID)",
      category: unifiedAudioEngineLogCategory,
      level: .debug
    )

    if selection.source == .systemDefault {
      let preferredName = settingsManager.selectedInputDeviceName.isEmpty
        ? preferredUID
        : settingsManager.selectedInputDeviceName
      let unavailableDescription: String
      if fallbackUID.isEmpty {
        unavailableDescription = "Preferred input device '\(preferredName)' is unavailable"
      } else {
        let fallbackName = settingsManager.fallbackInputDeviceName.isEmpty
          ? fallbackUID
          : settingsManager.fallbackInputDeviceName
        unavailableDescription =
          "Preferred input device '\(preferredName)' and fallback input device '\(fallbackName)' are unavailable"
      }
      log(
        "\(unavailableDescription); using system default input '\(selectedDevice.name)'",
        category: unifiedAudioEngineLogCategory,
        level: .warning
      )
      return
    }

    if selection.source == .fallback {
      let preferredName = settingsManager.selectedInputDeviceName.isEmpty
        ? preferredUID
        : settingsManager.selectedInputDeviceName
      log(
        "Preferred input device '\(preferredName)' is unavailable; using fallback input '\(selectedDevice.name)'",
        category: unifiedAudioEngineLogCategory,
        level: .warning
      )
    }

    guard let audioUnit = inputNode.audioUnit else {
      log(
        "Unable to access input audio unit; using system default input device",
        category: unifiedAudioEngineLogCategory,
        level: .warning
      )
      return
    }

    do {
      try AudioInputDeviceManager.applyInputDevice(selectedDevice.deviceID, to: audioUnit)
      log(
        "Applied \(selection.source.rawValue) input device: \(selectedDevice.name)",
        category: unifiedAudioEngineLogCategory,
        level: .info
      )
    } catch {
      log(
        "Failed to apply \(selection.source.rawValue) input device '\(selectedDevice.name)': \(error.localizedDescription). Using system default input device.",
        category: unifiedAudioEngineLogCategory,
        level: .warning
      )
      throw error
    }
  }

  private func logDefaultInputDeviceBreadcrumb() {
    if let defaultDevice = AudioInputDeviceManager.shared.currentDefaultInputDevice() {
      log(
        "Default input device - name: \(defaultDevice.name), uid: \(defaultDevice.uid), id: \(defaultDevice.deviceID)",
        category: unifiedAudioEngineLogCategory,
        level: .debug
      )
    } else {
      log(
        "Default input device unavailable",
        category: unifiedAudioEngineLogCategory,
        level: .warning
      )
    }
  }

  /// Fully tears down the recording engine. Deallocating the engine releases the
  /// AUHAL input, which is what allows Bluetooth devices to return to A2DP.
  private func tearDownRecordingEngine() {
    isRecordingActive = false

    weak var releasedEngine = recordingEngine

    if let engine = recordingEngine {
      if engine.isRunning {
        engine.stop()
      }
      engine.reset()
    }
    sinkNode = nil
    recordingMixerNode = nil
    recordingEngine = nil  // Release HAL input

    audioProcessingQueue.sync {
      self.outputFile = nil
      self.converter = nil
    }
    recordingURL = nil

    writeLock.lock()
    pendingWriteCount = 0
    writeLock.unlock()

    resetFrameCounter()

    bufferPool.clear()

    if releasedEngine != nil {
      Task { @MainActor in
        try? await Task.sleep(nanoseconds: 100_000_000)
        if releasedEngine != nil {
          log(
            "Recording engine still alive 100ms after teardown",
            category: unifiedAudioEngineLogCategory,
            level: .warning
          )
        } else {
          log(
            "Recording engine released after teardown",
            category: unifiedAudioEngineLogCategory,
            level: .debug
          )
        }
      }
    }
  }

  /// Stops recording and returns the URL of the recorded file.
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

    // Stop the engine so no new sink callbacks fire. In-flight writes still drain below.
    if let engine = recordingEngine, engine.isRunning {
      engine.stop()
    }
    isRecordingActive = false

    var url: URL?
    audioProcessingQueue.sync {
      url = self.recordingURL
    }

    // Wait for pending buffer writes to complete (tap callbacks already dispatched to queue)
    let waitStart = Date()
    let getCount = { [self] () -> Int in
      self.writeLock.lock()
      let count = self.pendingWriteCount
      self.writeLock.unlock()
      return count
    }

    var iterations = 0
    while true {
      let count = getCount()
      if count == 0 { break }
      iterations += 1
      if iterations > 200 {  // ~2s max
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

    // Belt-and-suspenders: ensure the async write queue is drained before finalizing.
    await withCheckedContinuation { continuation in
      asyncWriteQueue.async { continuation.resume() }
    }

    // Finalize and tear down. Nilling the engine releases the HAL, freeing BT for A2DP.
    tearDownRecordingEngine()

    let totalDuration = Date().timeIntervalSince(startTime)
    log(
      "[PERF] stopRecording() total duration: \(totalDuration * 1000)ms",
      category: unifiedAudioEngineLogCategory,
      level: .info
    )
    log(
      "Recording stopped, file at: \(url?.path ?? "unknown")",
      category: unifiedAudioEngineLogCategory,
      level: .info
    )

    return url
  }

  /// Cancels recording and deletes the file.
  func cancelRecording() async {
    log("Cancelling recording", category: unifiedAudioEngineLogCategory, level: .info)

    let url = await stopRecording()

    if let url {
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
  }

  // MARK: - Real-Time Audio Callback

  /// Real-time sinkNode callback. Runs on the audio thread — must complete in <1ms.
  nonisolated private func processRecordingBufferRealtime(
    timestamp: UnsafePointer<AudioTimeStamp>,
    frameCount: AVAudioFrameCount,
    bufferList: UnsafePointer<AudioBufferList>,
    format: AVAudioFormat
  ) {
    #if DEBUG
    let callbackStartTime = CFAbsoluteTimeGetCurrent()
    #endif

    // Track HAL activity *before* any early return so startRecording() can tell that
    // frames are actually flowing even if outputFile has been cleared mid-teardown.
    let frameLockRef = self.frameCounterLock
    frameLockRef.lock()
    self.framesReceived += 1
    frameLockRef.unlock()

    let localFile = self.outputFile
    let localConverter = self.converter

    guard localFile != nil else {
      // Not recording - exit immediately
      return
    }

    let writeLockRef = self.writeLock
    writeLockRef.lock()
    self.pendingWriteCount += 1
    writeLockRef.unlock()

    guard let copiedBuffer = bufferPool.getBuffer(format: format, frameCapacity: frameCount) else {
      writeLockRef.lock()
      self.pendingWriteCount -= 1
      writeLockRef.unlock()
      return
    }

    copiedBuffer.frameLength = frameCount

    guard let destChannels = copiedBuffer.floatChannelData else {
      bufferPool.returnBuffer(copiedBuffer)
      writeLockRef.lock()
      self.pendingWriteCount -= 1
      writeLockRef.unlock()
      return
    }

    // Fast C-style copy from AudioBufferList to AVAudioPCMBuffer
    let bytesToCopy = Int(frameCount) * MemoryLayout<Float>.stride
    let abl = bufferList.pointee
    let numBuffers = Int(abl.mNumberBuffers)

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
    let callbackDuration = CFAbsoluteTimeGetCurrent() - callbackStartTime
    if callbackDuration > 0.001 {
      if Int.random(in: 0..<100) == 0 {
        log(
          "[PERF WARN] Audio callback took \(callbackDuration * 1000)ms (should be < 1ms)",
          category: unifiedAudioEngineLogCategory,
          level: .warning
        )
      }
    }
    #endif

    // Dispatch file write asynchronously; don't block audio thread.
    let asyncWriteQueueRef = self.asyncWriteQueue
    let bufferPoolRef = self.bufferPool
    asyncWriteQueueRef.async {
      defer {
        writeLockRef.lock()
        self.pendingWriteCount -= 1
        writeLockRef.unlock()
        bufferPoolRef.returnBuffer(copiedBuffer)
      }

      guard let file = localFile else { return }

      // Level monitoring (throttled)
      let now = CFAbsoluteTimeGetCurrent()
      let timeSinceLastUpdate = now - self.lastLevelUpdate
      if timeSinceLastUpdate > self.levelUpdateThrottle {
        self.lastLevelUpdate = now

        let rawSamples = self.extractWaveformSamples(from: copiedBuffer)
        let normalized = self.normalizeWaveformSamples(rawSamples, now: now)

        if let level = self.normalizedLevel(from: copiedBuffer, gain: normalized.gain, isSilent: normalized.isSilent) {
          Task { @MainActor [weak self] in
            self?.updateLevel(level)
            self?.updateWaveformSamples(normalized.samples)
          }
        }
      }

      // Convert and write (off the audio thread)
      if let converter = localConverter {
        let outputFrameCapacity =
          AVAudioFrameCount(
            Double(copiedBuffer.frameLength) * converter.outputFormat.sampleRate
              / converter.inputFormat.sampleRate
          ) + 1024  // safety margin

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

          if let error {
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
            break
          }

          switch status {
          case .haveData:
            continue conversionLoop
          case .inputRanDry:
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

  // MARK: - Level Monitoring

  /// Normalizes raw waveform samples so different input devices render similar visual ranges.
  nonisolated private func normalizeWaveformSamples(
    _ samples: [Float],
    now: TimeInterval
  ) -> (samples: [Float], gain: Float, isSilent: Bool) {
    guard !samples.isEmpty else {
      return ([], 1, true)
    }

    let peak = samples.max() ?? 0
    let isSilent = peak <= Self.normalizationSilenceGate

    var state = normalizationState
    let delta = max(0, now - state.lastUpdate)
    let decay = pow(Self.normalizationDecayPerSecond, Float(delta))

    if peak > state.referencePeak {
      state.referencePeak = peak
    } else {
      state.referencePeak = max(peak, state.referencePeak * decay)
    }

    state.lastUpdate = now

    let referencePeak = max(state.referencePeak, Self.normalizationMinPeak)
    var targetGain = Self.normalizationTargetPeak / referencePeak
    targetGain = min(Self.normalizationMaxGain, max(Self.normalizationMinGain, targetGain))
    state.gain = state.gain + (targetGain - state.gain) * Self.normalizationGainSmoothing

    normalizationState = state

    if isSilent {
      return (Array(repeating: 0, count: samples.count), state.gain, true)
    }

    var normalizedSamples = samples
    for i in 0..<normalizedSamples.count {
      normalizedSamples[i] = min(1, normalizedSamples[i] * state.gain)
    }

    return (normalizedSamples, state.gain, false)
  }

  nonisolated private func normalizedLevel(
    from buffer: AVAudioPCMBuffer,
    gain: Float,
    isSilent: Bool
  ) -> CGFloat? {
    if isSilent {
      return 0
    }
    guard let channelData = buffer.floatChannelData?[0] else { return nil }
    let frameLength = Int(buffer.frameLength)

    var sum: Float = 0
    for i in 0..<frameLength {
      let sample = channelData[i]
      sum += sample * sample
    }

    let rms = sqrt(sum / Float(frameLength))
    let adjustedRms = min(1, rms * gain)
    let db = 20 * log10(max(adjustedRms, 0.000001))

    let minDb: Float = -55
    let maxDb: Float = -10
    let normalized = (db - minDb) / (maxDb - minDb)
    let clamped = max(0, min(1, normalized))

    return CGFloat(clamped)
  }

  private func updateLevel(_ level: CGFloat) {
    print("[WAVEFORM DEBUG] UnifiedAudioEngine.updateLevel: \(level)")
    currentInputLevel = level
  }

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

  private func updateWaveformSamples(_ samples: [Float]) {
    waveformSamples = samples
  }

  // MARK: - Sound Playback

  /// Preloads a sound file into memory for faster playback.
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
      let playerFormat = playerNode.outputFormat(forBus: 0)

      log(
        "Converting \(type) from \(sourceFormat.sampleRate)Hz \(sourceFormat.channelCount)ch to \(playerFormat.sampleRate)Hz \(playerFormat.channelCount)ch",
        category: unifiedAudioEngineLogCategory,
        level: .debug
      )

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

      let finalBuffer: AVAudioPCMBuffer
      if sourceFormat.sampleRate == playerFormat.sampleRate
        && sourceFormat.channelCount == playerFormat.channelCount
      {
        finalBuffer = sourceBuffer
        log("No conversion needed for \(type)", category: unifiedAudioEngineLogCategory, level: .debug)
      } else {
        guard let converter = AVAudioConverter(from: sourceFormat, to: playerFormat) else {
          log(
            "Failed to create converter for \(type)",
            category: unifiedAudioEngineLogCategory,
            level: .error
          )
          return
        }

        let outputFrameCount = AVAudioFrameCount(
          Double(frameCount) * playerFormat.sampleRate / sourceFormat.sampleRate
        )

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

        var error: NSError?
        converter.convert(
          to: outputBuffer, error: &error,
          withInputFrom: { _, outStatus in
            outStatus.pointee = .haveData
            return sourceBuffer
          })

        if let error {
          log(
            "Conversion error for \(type): \(error)",
            category: unifiedAudioEngineLogCategory,
            level: .error
          )
          return
        }

        finalBuffer = outputBuffer
      }

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

  /// Plays a preloaded sound on the playback engine.
  func playSound(type: SoundType, completion: (() -> Void)? = nil) {
    let buffer: AVAudioPCMBuffer?

    switch type {
    case .recordingStart:
      buffer = recordingStartBuffer
    case .transcriptionComplete:
      buffer = transcriptionCompleteBuffer
    }

    guard let buffer else {
      log(
        "Sound \(type) not loaded",
        category: unifiedAudioEngineLogCategory,
        level: .warning
      )
      completion?()
      return
    }

    log("Playing \(type) sound", category: unifiedAudioEngineLogCategory, level: .debug)

    cancelIdleStop()
    ensurePlaybackEngineStarted()

    pendingPlaybackCount += 1
    log(
      "Scheduled playback (pending: \(pendingPlaybackCount))",
      category: unifiedAudioEngineLogCategory,
      level: .debug
    )

    playerNode.scheduleBuffer(buffer) {
      log(
        "Finished playing \(type) sound",
        category: unifiedAudioEngineLogCategory,
        level: .debug
      )
      Task { @MainActor in
        self.handlePlaybackCompletion()
      }
      completion?()
    }

    if !playerNode.isPlaying {
      playerNode.play()
    }
  }

  /// Clears a preloaded sound from memory.
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

// MARK: - Waveform Normalization

/// State for adaptive waveform normalization (accessed on async write queue only).
private struct WaveformNormalizationState {
  var referencePeak: Float = UnifiedAudioEngine.normalizationMinPeak
  var gain: Float = 1
  var lastUpdate: TimeInterval = 0
}

// MARK: - Buffer Pool

/// Thread-safe buffer pool for zero-allocation real-time audio callbacks.
final class BufferPool: @unchecked Sendable {
  private var availableBuffers: [AVAudioPCMBuffer] = []
  private let lock = NSLock()
  private let poolSize = 20

  nonisolated func getBuffer(format: AVAudioFormat, frameCapacity: AVAudioFrameCount) -> AVAudioPCMBuffer? {
    lock.lock()
    defer { lock.unlock() }

    if let index = availableBuffers.firstIndex(where: {
      $0.format == format && $0.frameCapacity >= frameCapacity
    }) {
      return availableBuffers.remove(at: index)
    }

    return AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity)
  }

  nonisolated func returnBuffer(_ buffer: AVAudioPCMBuffer) {
    lock.lock()
    defer { lock.unlock() }

    guard availableBuffers.count < poolSize else { return }

    buffer.frameLength = 0
    availableBuffers.append(buffer)
  }

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
  case invalidInputHardwareFormat(sampleRate: Double, channelCount: AVAudioChannelCount)
  case converterCreationFailed
  case deviceUnavailable
  case avfaudioException(operation: String, reason: String)

  var errorDescription: String? {
    switch self {
    case .alreadyRecording:
      return "Recording is already in progress"
    case .engineNotRunning:
      return "Audio engine is not running"
    case .invalidFormat:
      return "Invalid audio format"
    case .invalidInputHardwareFormat(let sampleRate, let channelCount):
      return
        "Audio input hardware reported an invalid format (sampleRate: \(sampleRate), channels: \(channelCount))"
    case .converterCreationFailed:
      return "Failed to create audio format converter"
    case .deviceUnavailable:
      return "Audio input is unavailable. If you're on Bluetooth, try disconnecting and reconnecting your headset."
    case .avfaudioException(let operation, let reason):
      return "AVFAudio failed during \(operation): \(reason)"
    }
  }
}
