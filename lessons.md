When recording starts, there are three things happen:

1. The overlay window shows
2. The audio device is initialized
3. The start sound is played

## Overlay Window Showing Over Fullscreen Apps

**Problem:** The overlay window would not appear over fullscreen applications, even with `.fullScreenAuxiliary` collection behavior set.

**Root Cause:** SwiftUI's `Window` scene in macOS 15 doesn't properly support `.fullScreenAuxiliary` collection behavior. The window level and collection behavior settings applied through SwiftUI modifiers don't reliably work for fullscreen compatibility.

**Solution:** Create the overlay window programmatically using AppKit's `NSPanel`:

1. **Use NSPanel, not NSWindow** - `NSPanel` with `.fullScreenAuxiliary` properly registers with macOS fullscreen spaces
2. **Create programmatically, not via SwiftUI** - Direct AppKit API calls bypass SwiftUI's window management limitations
3. **Set properties before showing** - Collection behavior and window level must be set during initialization, not after
4. **Use .screenSaverWindow level** - Level 1000 is high enough to appear above all normal app content including fullscreen apps
5. **SwiftUI content via NSHostingView** - Embed SwiftUI views using `NSHostingView` while maintaining full reactivity through `@EnvironmentObject`

**Key Implementation:**
```swift
class OverlayPanel: NSPanel {
  init() {
    super.init(styleMask: [.borderless, .nonactivatingPanel], ...)
    self.level = .screenSaver  // Must be set early
    self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    self.hidesOnDeactivate = false  // Critical for fullscreen
    self.contentView = NSHostingView(rootView: content())
  }
}
```

**References:**
- Stack Overflow: "Keeping SwiftUI window on top of all other apps (even in fullscreen)" (Nov 2024)
- Apple Forums: Multiple reports of `.fullScreenAuxiliary` not working with SwiftUI Window scenes in macOS 15
- Recommended approach: Manual `NSPanel` creation with `NSHostingView` for SwiftUI content

## Audio Level Waveform Not Updating

**Problem:** The audio waveform visualization in the overlay remained static during recording, showing no audio level updates even though recording was working correctly.

**Root Cause:** The audio level monitoring system had two critical flaws:
1. **Timer on wrong thread** - `Timer.scheduledTimer()` was created on a background thread that had no running runloop, so the timer never fired
2. **Placeholder calculations** - The level calculation methods returned random values instead of computing real audio levels from buffer data

**Solution:** Implement proper thread-safe audio level monitoring:

1. **Use DispatchSourceTimer on main queue** - Unlike `Timer.scheduledTimer()`, `DispatchSourceTimer` with `queue: .main` guarantees execution on main thread regardless of where it's created
2. **Thread-safe level caching** - Calculate levels on audio thread (in tap callback), store in thread-safe cache with `NSLock`, then read from cache on main thread
3. **Delegate callbacks on main thread** - Ensure all SwiftUI state updates happen on `DispatchQueue.main` to avoid race conditions
4. **Real audio calculations** - Calculate actual RMS and peak levels from audio buffer data in the tap callback

**Key Implementation:**
```swift
// Thread-safe storage (accessed from audio thread and main thread)
private var latestAudioLevel: Float = 0
private var latestPeakLevel: Float = 0
private let levelLock = NSLock()

// Timer on main queue
private func startLevelMonitoring() {
    let timer = DispatchSource.makeTimerSource(queue: .main) // <-- main queue
    timer.schedule(deadline: .now(), repeating: levelUpdateInterval)
    timer.setEventHandler { [weak self] in
        self?.updateAudioLevels()
    }
    timer.resume()
    levelTimer = timer
}

// Calculate in audio tap (high-priority thread)
private func convertAndWriteBuffer(_ inputBuffer: AVAudioPCMBuffer, ...) {
    let rmsLevel = calculateRMSLevel(from: inputBuffer)  // Real calculation
    let peakLevel = calculatePeak(from: inputBuffer)

    levelLock.lock()
    latestAudioLevel = rmsLevel
    latestPeakLevel = peakLevel
    levelLock.unlock()

    // ... write buffer to file
}

// Read on main thread and dispatch delegate calls
private func updateAudioLevels() {
    levelLock.lock()
    let level = latestAudioLevel
    let peak = latestPeakLevel
    levelLock.unlock()

    DispatchQueue.main.async { [weak self] in
        self?.delegate?.AudioRecorderUpdated(self, didUpdateAudioLevel: level, peakLevel: peak)
    }
}
```

**Why This Works:**
- **DispatchSourceTimer** doesn't depend on runloops - it's managed by GCD and will fire on the specified queue
- **Separation of concerns** - Audio calculations happen on fast audio thread, UI updates happen on main thread
- **Lock-based synchronization** - Simple and reliable for single-value reads/writes between threads
- **No blocking** - Audio thread never waits, main thread only locks briefly to read values

**References:**
- Apple Documentation: "DispatchSourceTimer is preferred over Timer for non-runloop contexts"
- Common pattern in AVAudioEngine-based apps: Calculate in tap, cache values, read from timer

## AirPods After Idle -> Silent Recording

**Problem:** After the app sits idle and AirPods are connected/used, recording starts but captures silence (waveform stays at 0.0), often with CoreAudio errors like EAGAIN (35) and kAudioUnitErr_FormatNotSupported (-10877).

**Root Cause:** The AVAudioEngine graph was built with stale device formats and a fixed 48kHz "stable" format. When Bluetooth devices switch profiles (A2DP 48kHz -> HFP 16-24kHz), the engine emits configuration changes but the graph (player connection + sink format) was not rebuilt. That mismatch causes start errors and/or a running engine with a silent input path.

**Solution:** Make the engine resilient to configuration changes and align the recording graph to the current input format:

1. **Observe engine configuration changes** - Listen for `.AVAudioEngineConfigurationChange` and reset/rebuild the engine.
2. **Reconnect playback node on format change** - Reconnect `playerNode` to the main mixer using the *current* output format whenever sample rate or channel count changes.
3. **Use current input sample rate for recording** - Build the "stable" recording format from `inputNode.inputFormat(forBus: 0)` so the sink format matches the active device profile.

**Key Implementation (current — post split-engine refactor):**
```swift
// Observer scoped to the playback engine only. The recording engine is created fresh per
// session, so there's no stale graph to repair there. (Originally the observer watched a
// single shared engine and used a `needsConfigurationReset` flag to defer resets during
// active recordings — that flag was removed when the two engines were split apart.)
configurationChangeObserver = NotificationCenter.default.addObserver(
  forName: .AVAudioEngineConfigurationChange,
  object: playbackEngine,
  queue: .main
) { [weak self] _ in
  guard let self else { return }
  Task { @MainActor in
    self.resetPlaybackEngineForConfigurationChange()
  }
}

// Build the recording-side stable format from the current input sample rate.
let inputFormat = inputNode.inputFormat(forBus: 0)
let stableFormat = AVAudioFormat(
  commonFormat: .pcmFormatFloat32,
  sampleRate: inputFormat.sampleRate,
  channels: 1,
  interleaved: false
)
```

**Why This Works:**
- **Configuration change handling** prevents stale device IDs/formats from lingering after Bluetooth profile switches.
- **Input-aligned stable format** avoids -10877 format mismatches during HFP/A2DP transitions.
- **Playback reconnection** keeps the playback engine's graph valid when the output device changes.

## Bluetooth Stays in HFP After Recording Ends

**Problem:** On AirPods (and other Bluetooth headsets), after a recording ended, music and video from other apps played at reduced fidelity — "half volume, muffled, lower bitrate" — and stayed that way until Echo was quit. Restarting or force-quitting Echo instantly restored normal playback, which was the tell that Echo itself was holding the device in the degraded profile.

**Root Cause:** `AVAudioEngine.inputNode` is a lazy property. On first access it allocates an AUHAL I/O unit that is permanently bound to that `AVAudioEngine` instance. `engine.stop()` and `engine.reset()` pause the audio graph but do **not** release the underlying audio unit — only `deinit` does.

When a single `AVAudioEngine` is shared between recording (which touches `inputNode`) and sound-effect playback (which calls `engine.start()` after recording ends, e.g. for a "transcription complete" chime), every `start()` reopens the mic, because the input AU is still wired up from the last recording. macOS then keeps the BT device in HFP — which is bidirectional call mode, mono, 16 kHz — and every app's audio output is downgraded accordingly.

**Solution:** Split the single shared `AVAudioEngine` into two instances with different lifetimes:

1. **Long-lived playback engine** — only ever used for sound-effect output. Never touches `inputNode`, so no AUHAL input is ever allocated and BT is never forced into HFP by playback.
2. **Per-session recording engine** — an `AVAudioEngine?` created fresh inside `setupRecordingEngine(to:)` and set to `nil` inside `tearDownRecordingEngine()` at the end of `stopRecording()`. Dropping the last strong reference deterministically deallocates the engine, which releases the AUHAL input. macOS then returns the BT device to A2DP within ~1 second.

**Key Implementation:**
```swift
private let playbackEngine = AVAudioEngine()      // output-only, long-lived
private var recordingEngine: AVAudioEngine?       // per-session, nilled after stopRecording

private func setupRecordingEngine(to url: URL) throws {
  let engine = AVAudioEngine()
  recordingEngine = engine
  let inputNode = engine.inputNode   // AUHAL allocated; tied to THIS engine's lifetime
  // ... build inputNode → mixer → sinkNode graph, start engine
}

private func tearDownRecordingEngine() {
  if let engine = recordingEngine {
    if engine.isRunning { engine.stop() }
    engine.reset()
  }
  sinkNode = nil
  recordingMixerNode = nil
  recordingEngine = nil   // last strong ref dropped → dealloc → AUHAL released → BT → A2DP
}
```

**Why This Works:**
- **AUHAL release is deterministic** — releasing the last reference to an `AVAudioEngine` runs its deinit synchronously, which tears down the audio unit. Nothing less will.
- **Output-only playback engine never allocates an input unit** — so sound effects after a recording don't pin the device in HFP.
- **Recording engine is ephemeral** — each recording gets a clean engine with fresh device state, so there's no stale graph to fight with. The configuration-observer deferral logic from the "AirPods After Idle" fix is no longer needed on the recording path.

**References:**
- Apple docs on `AVAudioEngine.inputNode`: "The first time a client calls this property, the engine allocates an audio I/O unit" — which is then bound to the engine.
- macOS audio routing: BT profile (A2DP vs HFP/SCO) is process-scoped to any active input AU targeting that device. Releasing all input AUs lets the OS return to A2DP.

## AVAudioEngine.start() Returns Success When the HAL Silently Fails

**Problem:** Recordings would appear to succeed — no thrown error, `engine.isRunning` reported `true` — but produce empty audio files. The user saw a confusing "Audio" error in the overlay that was really a `400 "Audio file is too short. Minimum audio length is 0.01 seconds."` from the transcription API. Logs showed Core Audio complaining internally:

```
HALC_ProxyIOContext::_StartIO(): Start failed - StartAndWaitForState returned error 35
HALB_IOThread::_Start: there already is a thread
throwing -10877   (repeated)
```

…but nothing propagated to Swift. At stop time, the "wait for pending buffers" loop showed `0 iterations` — the sink node callback had never fired once.

**Root Cause:** `AVAudioEngine.start()` is not a reliable signal that audio IO is actually flowing. On Bluetooth devices mid-profile-transition (or any device with HAL contention), the underlying AUHAL can fail its `StartIO` while AVAudioEngine still reports success. No frames reach the sink node. You end up recording "N seconds of nothing" and sending a zero-byte WAV to the downstream API.

**Solution:** Don't trust `engine.start()` — verify audio is actually flowing before you report success:

1. **Frame counter on the audio thread.** Increment a counter at the top of the sink node callback, before any early-return logic. This tracks raw HAL activity regardless of whether you're currently persisting audio.
2. **Poll the counter after `start()`.** Wait up to a few hundred ms for the counter to become non-zero. On a healthy device, first frames arrive in <50 ms; timeouts only fire on silent HAL failure.
3. **Retry on zero-frame outcome.** Tear down the recording engine, give the device time to settle (250 ms works well for BT), stop any other engines that might contend for the HAL, then rebuild and retry. Cap the retries.
4. **Terminate with an actionable error.** After N attempts, throw a specific error type that the UI can translate into guidance ("reconnect your Bluetooth headset") — don't let a blank WAV propagate and produce a cryptic 400 downstream.

**Key Implementation:**
```swift
nonisolated(unsafe) private var framesReceived: Int = 0
private let frameCounterLock = NSLock()

// In the sink callback, BEFORE any other logic or early return:
frameCounterLock.lock()
framesReceived += 1
frameCounterLock.unlock()

// In startRecording (now async throws):
try setupRecordingEngine(to: url)

if await waitForFirstFrame(timeoutMs: 300) {
  return  // verified success
}

// Silent HAL failure — retry
tearDownRecordingEngine()
if attempt < maxRetries {
  if playbackEngine.isRunning {
    playbackEngine.stop()   // release device contention
    playbackEngine.reset()
  }
  try? await Task.sleep(nanoseconds: 250_000_000)
  continue
}
throw UnifiedAudioEngineError.deviceUnavailable
```

**Why This Works:**
- **Audio-thread counter is the source of truth.** It definitively reports whether the HAL is delivering audio, independent of what `engine.start()` or `isRunning` say.
- **Counting before the "are we recording?" check** separates "HAL is alive" from "we're currently saving frames," which is also useful for diagnostic logging.
- **Stopping the playback engine between retries** removes a common contention source on shared-device scenarios (BT speakers that are also mics). The playback engine restarts lazily when the next sound plays; no user-visible cost.
- **The 250 ms settle delay** gives macOS time to complete BT profile negotiation, which is usually what triggered the initial HAL failure. Without it, retries just hammer the same broken state.

**Related gotchas:**
- Also audit any `AVAudioEngineConfigurationChange` observer: resetting an idle engine in response to the notification churns the HAL and can contend with a concurrently-starting second engine. Guard `stop()`/`reset()` behind `engine.isRunning`.

**References:**
- Core Audio error 35 is EAGAIN — device reconfiguring. `-10877` is `kAudioUnitErr_FormatNotSupported`. Both appear repeatedly during BT profile transitions.
- Apple Developer Forums: several reports over the years of AVAudioEngine appearing to start successfully while the HAL does nothing.
