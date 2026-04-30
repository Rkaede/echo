# Bluetooth Audio Issues

**Component:** `UnifiedAudioEngine.swift`
**Issue Types:** Audio Recording Crash, Silent Recording After Idle, HFP Lock-in After Recording
**History:** Dec 2024 (Rounds 1–2) → early 2026 (Round 3) → April 2026 (Round 4)

This document captures the evolving story of Echo's Bluetooth audio problems. Each "round"
addressed the issue that was visible at the time but left architectural choices that made
the next round's problem possible. Read top-to-bottom for the narrative.

## Problem 1: Format Mismatch Crash (December 2024)

When using Bluetooth audio devices (AirPods, headphones, etc.), the app would crash with a format mismatch error when attempting to start recording:

```
Format mismatch: input hw <AVAudioFormat: 1 ch, 24000 Hz, Float32>,
                 client format <AVAudioFormat: 1 ch, 48000 Hz, Float32>
```

### Error Trace

```
AVAudioIONodeImpl.mm:1334  Format mismatch: input hw format and tap format not matching
FAULT: com.apple.coreaudio.avfaudio: Input HW format and tap format not matching; {
    "-10868" = OSStatus;
}
```

The crash occurred in `setupRecordingTap()` when connecting the `AVAudioSinkNode` to the input node.

## Root Cause Analysis

### Bluetooth Audio Modes

Bluetooth audio devices operate in two distinct modes:

| Mode | Purpose | Sample Rate | Microphone |
|------|---------|-------------|------------|
| **A2DP** | High-quality playback | 44.1-48 kHz | No |
| **HFP/HSP** | Headset profile | 16-24 kHz | Yes |

When an app requests microphone access, macOS automatically switches the Bluetooth device from A2DP to HFP mode. This mode switch changes the hardware sample rate.

### The Bug

The original code in `UnifiedAudioEngine.swift` queried the input format **before** stopping the audio engine:

```swift
// WRONG: Querying format while in A2DP mode (48kHz)
let inputFormat = inputNode.outputFormat(forBus: 0)  // Returns 48000 Hz

// Engine stop triggers Bluetooth mode switch to HFP (24kHz)
engine.stop()

// ... setup code ...

// CRASH: Connecting with 48kHz format but hardware is now 24kHz
engine.connect(inputNode, to: sinkNode, format: inputFormat)
```

### Critical Constraint

`AVAudioSinkNode` does **not** support automatic format conversions. It must receive audio in the exact hardware input format. This is documented in [WWDC 2019: What's New in AVAudioEngine](https://developer.apple.com/videos/play/wwdc2019/510/) (around 3:55).

## Solution (Round 1 — Incomplete)

The initial fix was to query the input format **after** stopping the engine. However, this only addressed half the problem — Bluetooth devices can switch modes **again** when the engine restarts.

## Solution (Round 2 — Mixer Node)

Insert an `AVAudioMixerNode` between `inputNode` and `AVAudioSinkNode`. Unlike `AVAudioSinkNode`, mixer nodes support automatic format conversion, isolating the sink from hardware format changes.

```swift
// Use a STABLE intermediate format (48kHz Float32 mono)
// Note: Round 3 later changed this to inputFormat.sampleRate (see below).
let stableFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: 48000.0,
    channels: 1,
    interleaved: false
)!

// Create mixer node to handle format conversion
let recordingMixer = AVAudioMixerNode()

// Create sink node that receives stable format
let sinkNode = AVAudioSinkNode { ... }

// Attach and connect
engine.attach(recordingMixer)
engine.attach(sinkNode)

// Connect: inputNode → mixer (auto-converts) → sinkNode (stable format)
engine.connect(inputNode, to: recordingMixer, format: nil)  // nil = auto-detect
engine.connect(recordingMixer, to: sinkNode, format: stableFormat)

try engine.start()
```

### Why This Works

1. **Mixer handles dynamic formats**: The mixer automatically converts from whatever format the hardware provides (24kHz HFP, 48kHz A2DP, etc.)
2. **Sink receives stable format**: The sink node always receives 48kHz Float32, regardless of Bluetooth state
3. **No timing race**: Format changes don't matter because the mixer adapts automatically

### Changes Made

**File:** `echo/Services/UnifiedAudioEngine.swift`

1. Added `recordingMixerNode: AVAudioMixerNode?` property
2. Rewrote `setupRecordingTap()` to use mixer → sink graph
3. Updated `resetRecordingState()` to detach mixer node
4. Updated `stopRecording()` to detach mixer node
5. Converter now converts from stable 48kHz format to 16kHz output (always)

### What Round 2 Left Unsolved

Round 2 fixed the crash, but it did so within a **single shared `AVAudioEngine`** used for
both recording and sound-effect playback. Two problems were still latent:

1. Once a Bluetooth device had been put through its first A2DP↔HFP transition, if the engine
   ever wrapped an older input device state (after going idle, etc.), recording could start
   but produce silence. Addressed in Round 3.
2. Accessing `engine.inputNode` permanently attaches an AUHAL input to the engine instance.
   Even after recording ends, any subsequent `engine.start()` (e.g., to play the transcription
   complete sound) reopens the mic, holding the BT device in HFP. Music from other apps stays
   muffled until the app quits. Addressed in Round 4.

## Format Conversion Pipeline (post-Round 3)

Two-stage conversion. Note: after Round 3 the "stable format" sample rate tracks the current
input device rather than being pinned at 48 kHz, so the pipeline adapts to whatever the
hardware currently reports.

```
[Hardware Input]     [Mixer Node]         [Stable Format]         [Converter]        [Output File]
  Any Hz (dynamic)  →  Auto-convert   →   inputFormat.sampleRate →  Resample     →    16000 Hz
  Float32              (transparent)       Float32                   + Format           Int16 PCM
  1+ channel                                1 channel                 Convert           Mono WAV
```

Stage 1: Mixer handles Bluetooth format switching automatically.
Stage 2: `AVAudioConverter` resamples from the stable format to 16 kHz for the Whisper API.

## Problem 2: Silent Recording After Idle on AirPods (Round 3)

**Symptom:** After the app sat idle and AirPods had been used by another app, starting a
recording would succeed but capture pure silence (waveform flat at 0). Logs often showed
EAGAIN (35) and `kAudioUnitErr_FormatNotSupported` (-10877).

**Root cause:** The AVAudioEngine graph was built with stale device formats and a pinned
48 kHz "stable" format. When Bluetooth devices switched profiles (A2DP 48 kHz ↔ HFP 16–24 kHz),
the engine emitted `.AVAudioEngineConfigurationChange` but nothing rebuilt the graph. Sink
format and player connection went stale → start errors or a silent input path.

### Solution (Round 3)

1. **Observe `AVAudioEngineConfigurationChange`** — rebuild the engine graph when idle; defer
   while recording to avoid disrupting in-progress audio.
2. **Reconnect `playerNode` on format change** — re-wire to the main mixer using the current
   output format whenever sample rate or channel count changed.
3. **Align stable format to current hardware** — build the intermediate format from
   `inputNode.inputFormat(forBus: 0).sampleRate` instead of pinning 48 kHz, so the sink format
   always matches the active profile.

### Changes Made (Round 3)

**File:** `echo/Services/UnifiedAudioEngine.swift`

1. Added configuration-change observer + `needsConfigurationReset` deferral flag.
2. Added `refreshPlaybackConnectionIfNeeded()` to re-wire the player node on format change.
3. Changed stable format construction to use `inputFormat.sampleRate`.

*(Round 3 remained on the single-shared-engine architecture introduced in Round 2. This set
the stage for Problem 3.)*

## Problem 3: Bluetooth Stuck in HFP After Recording (Round 4, April 2026)

**Symptom:** After recording with AirPods, audio from *other* apps (music, video) plays at
reduced fidelity — "half volume, lower-bitrate, mono-feeling" sound — and stays that way
until Echo is quit. Quitting the app restores normal playback immediately.

The first "recording start" click also tended to play crackly/muffled on Bluetooth, because
the A2DP→HFP profile transition was happening mid-playback of that short sound.

**Root cause:** macOS Bluetooth has two mutually exclusive profiles:
- **A2DP** — high-quality stereo output, no mic (48 kHz stereo music).
- **HFP/SCO** — bidirectional call mode (16 kHz mono, compressed). All output, including
  music from other apps, is downgraded while in this profile.

macOS keeps the BT device in HFP as long as *any* process holds an active input stream on
it. Echo's single shared `AVAudioEngine` was holding one open continuously:

1. `AVAudioEngine.inputNode` is a **lazy property that allocates an AUHAL I/O unit on first
   access**. That unit is bound to the `AVAudioEngine` instance for its entire lifetime.
2. `engine.stop()` and `engine.reset()` pause the graph but do **not** release the AUHAL
   unit. Only `deinit` (dropping the last strong reference) releases it.
3. After a recording ended, the `transcriptionComplete` sound effect called
   `ensureEngineStarted()` on the same shared engine. Because `inputNode` had been touched
   during recording, restarting the engine reopened the mic → the BT device stayed in HFP.
4. Only quitting the app deallocated the `AVAudioEngine` → only then did HFP release.

### Solution (Round 4)

Split the single shared engine into two:

- **`playbackEngine`** — long-lived `AVAudioEngine`, only ever used for sound-effect output.
  Never touches `inputNode`, so it never allocates an AUHAL input and never pins BT to HFP.
- **`recordingEngine`** — `AVAudioEngine?`, created fresh inside `setupRecordingEngine(to:)`
  and nilled out at the end of `stopRecording()`/`tearDownRecordingEngine()`. Setting the
  reference to `nil` deallocates the engine, which releases the AUHAL input; macOS then lets
  the BT device switch back to A2DP within ~1 second.

```swift
// Playback: long-lived, output-only
private let playbackEngine = AVAudioEngine()
private let playerNode = AVAudioPlayerNode()

// Recording: per-session, torn down after stop
private var recordingEngine: AVAudioEngine?

private func setupRecordingEngine(to url: URL) throws {
  let engine = AVAudioEngine()
  recordingEngine = engine
  let inputNode = engine.inputNode   // AUHAL allocated here — bound to THIS engine only
  // ... build mixer → sink graph, start engine
}

private func tearDownRecordingEngine() {
  isRecordingActive = false
  if let engine = recordingEngine {
    if engine.isRunning { engine.stop() }
    engine.reset()
  }
  sinkNode = nil
  recordingMixerNode = nil
  recordingEngine = nil   // deallocation releases AUHAL → BT returns to A2DP
  // ... clear outputFile / converter / buffer pool
}
```

### Why This Works

- Output-only engine never allocates an input AU → no HFP trigger from sound playback.
- Recording engine is ephemeral; its `deinit` runs synchronously when `recordingEngine = nil`
  is assigned (no other strong references), releasing the AUHAL input deterministically.
- Configuration-change deferral from Round 3 is no longer needed for recording — each
  recording engine is fresh, so there's no stale graph to reset. Observer now watches the
  playback engine only.

### Changes Made (Round 4)

**File:** `echo/Services/UnifiedAudioEngine.swift`

1. Split single `engine` into `playbackEngine` (long-lived) and `recordingEngine: AVAudioEngine?` (per-session).
2. Renamed/replaced: `setupRecordingTap` → `setupRecordingEngine`, `resetRecordingState` → `tearDownRecordingEngine`, `ensureEngineStarted` → `ensurePlaybackEngineStarted`, `stopEngineIfIdle` → `stopPlaybackEngineIfIdle`.
3. Configuration-change observer now scoped to the playback engine.
4. Removed `needsConfigurationReset` (no longer needed — recording engine is never reset, it's re-created).
5. Removed dead helpers: `setupAudioSession` / `audioSessionConfigured` (iOS-only no-op on a macOS-only target), `hasAttemptedStart`, unused `copyBuffer`.
6. Idle policy now applies only to the playback engine; recording engine is always torn down immediately on `stopRecording`.

### Behavioral Notes

- The "recording start" click may still sound slightly rough on AirPods. This is inherent —
  the A2DP→HFP switch happens when the mic opens, and any output played during that switch
  is subject to the transition. The 250 ms delay in `TranscriptionService.startRecording`
  mitigates it but can't eliminate it entirely.
- The "transcription complete" sound is now always high-quality on BT — by the time the API
  response arrives and the paste completes, the recording engine has been torn down and BT is
  back in A2DP.

### Round 4 Follow-up: Silent HAL Failure Detection (April 22, 2026)

**Symptom:** After Round 4 shipped, a user on AirPods reported recordings that appeared to
succeed but produced a cryptic "Audio" error in the overlay. The server-side response was:

```
Audio file is too short. Minimum audio length is 0.01 seconds.
```

Logs showed the recording engine "started successfully" and ran for ~2.86 seconds of real
wall-clock time, yet the `[PERF] Buffer wait took 0.00ms (0 iterations)` line at stop
revealed **zero frames had ever been delivered** to the sink node. The on-disk WAV was
effectively empty.

Surrounding the failed start, Core Audio printed:

```
HALC_ProxyIOContext.cpp:1074  HALC_ProxyIOContext::_StartIO(): Start failed -
  StartAndWaitForState returned error 35
HALB_IOThread.cpp:326  HALB_IOThread::_Start: there already is a thread
throwing -10877   (× several)
```

**Root cause:** `AVAudioEngine.start()` is not a reliable signal that audio IO is actually
running. On a Bluetooth device in the middle of a profile transition, the underlying AUHAL
can fail to start IO (error 35 / EAGAIN) while `engine.start()` still returns success and
`engine.isRunning` still returns `true`. No Swift-level exception is thrown. The sink node
simply never receives a callback, and we happily record "2.86 seconds of silence" that is
really 2.86 seconds of nothing.

This failure mode wasn't introduced by Round 4 — it existed before too. But pre-Round 4 it
was largely masked by the retry loop fighting format-mismatch crashes on the same code
paths. With the cleaner Round 4 architecture it surfaced as its own distinct bug.

**Solution:** Don't trust `engine.start()`; verify audio is actually flowing before
returning from `startRecording`:

1. **Frame counter on the audio thread.** Increment `framesReceived` at the top of
   `processRecordingBufferRealtime`, before any early-return logic, so it tracks HAL
   activity independent of file writes.
2. **Post-start verification poll.** After `engine.start()`, await `waitForFirstFrame(timeoutMs: 300)`.
   On a healthy device, the first frame arrives in <50 ms; the timeout only fires on HAL
   silent failure.
3. **Retry with settle delay.** On zero-frame outcome: tear down the recording engine, stop
   the playback engine too (release HAL contention), wait 250 ms, retry. Up to 3 attempts.
4. **Clear terminal error.** If all retries fail, throw
   `UnifiedAudioEngineError.deviceUnavailable` — which surfaces a user-facing message
   suggesting a BT reconnect — instead of letting a blank WAV propagate to the transcription
   API and produce a confusing 400.

```swift
nonisolated(unsafe) private var framesReceived: Int = 0
private let frameCounterLock = NSLock()

// In processRecordingBufferRealtime, before any early return:
frameCounterLock.lock()
framesReceived += 1
frameCounterLock.unlock()

// In startRecording (now async throws):
try setupRecordingEngine(to: url)

if await waitForFirstFrame(timeoutMs: 300) {
  return  // real success
}

// HAL silent failure — tear down and retry
tearDownRecordingEngine()
if attempt < maxRetries {
  if playbackEngine.isRunning {
    playbackEngine.stop()
    playbackEngine.reset()
  }
  try? await Task.sleep(nanoseconds: 250_000_000)
  continue
}
throw UnifiedAudioEngineError.deviceUnavailable
```

### Changes Made (Follow-up)

**File:** `echo/Services/UnifiedAudioEngine.swift`
1. Added `framesReceived` counter + `frameCounterLock`.
2. Incremented the counter at the top of `processRecordingBufferRealtime` (before the
   `guard localFile != nil` early return).
3. Made `startRecording(to:)` `async throws`; added `waitForFirstFrame(timeoutMs:)` helper.
4. Added `UnifiedAudioEngineError.deviceUnavailable` with a BT-reconnect-suggesting message.
5. Changed `resetPlaybackEngineForConfigurationChange` to skip `stop()`/`reset()` on an idle
   engine, avoiding HAL churn during BT profile transitions.

**File:** `echo/Models/AudioRecorder.swift`
1. `await`s the now-async `unifiedEngine.startRecording(to:)`.
2. Removed the 100 ms verification `Task.sleep` — the engine verifies HAL activity itself.

**File:** `EchoTests/UnifiedAudioEngineXCTests.swift`
1. Updated `testInvalidURLThrows` to `await` the async `startRecording`.

## Testing Checklist

- [ ] Built-in MacBook microphone
- [ ] AirPods / AirPods Pro
- [ ] Other Bluetooth headphones
- [ ] USB microphone
- [ ] External audio interface
- [ ] Push-to-talk rapid start/stop
- [ ] Toggle recording mode
- [ ] **Round 4 regression:** Play music in another app, record with AirPods, stop recording,
      confirm music returns to full fidelity within ~1–2 seconds (no app quit needed)
- [ ] **Round 4 regression:** Record → transcription complete sound plays cleanly on BT
- [ ] **Round 4 follow-up:** Trigger a recording while AirPods are mid-profile-switch
      (e.g., right after another app released them). Confirm either: (a) recording succeeds,
      or (b) a "device unavailable" error is shown — but **not** an empty WAV → "audio too short" 400

## References

### Apple Documentation
- [AVAudioSinkNode Documentation](https://developer.apple.com/documentation/avfaudio/avaudiosinknode)
- [WWDC 2019: What's New in AVAudioEngine](https://developer.apple.com/videos/play/wwdc2019/510/)

### Stack Overflow
- [AVAudioSinkNode sample rate convert](https://stackoverflow.com/questions/58781271/swift-avaudioengine-and-avaudiosinknode-samplerate-convert) - Confirms AVAudioSinkNode doesn't support format conversion
- [Error installing tap on input node](https://stackoverflow.com/questions/53779214/error-when-installing-a-tap-on-audio-engine-input-node) - Format mismatch solutions
- [How to specify AVAudioEngine mic input format](https://stackoverflow.com/questions/33484140/how-can-i-specify-the-format-of-avaudioengine-mic-input) - Mixer node workaround

### Related Issues
- [AudioKit Issue #1851](https://github.com/AudioKit/AudioKit/issues/1851) - Similar crash with `format.SampleRate == hwFormat.SampleRate`

## Error Codes Reference

| Code | Name | Description |
|------|------|-------------|
| -10868 | kAudioUnitErr_FormatNotSupported | Format mismatch between nodes |
| -10877 | kAudioUnitErr_InvalidElement | Invalid bus or element |
| 35 | EAGAIN | Device reconfiguring, retry |

## Prevention

To prevent similar issues in the future:

1. **Always query hardware format after audio graph changes** — format can change when the engine starts/stops.
2. **Add format validation** — check for valid sample rate and channel count.
3. **Handle Bluetooth mode switching** — be aware that mic access triggers A2DP → HFP, and that the switch takes ~500 ms–1.5 s to negotiate.
4. **Log format information** — include sample rate in debug logs for troubleshooting.
5. **`AVAudioEngine.inputNode` is permanent** — once touched, the AUHAL input it allocates persists for the engine's lifetime. `stop()`/`reset()` do not release it; only deallocation does. If the engine is also used for output, every `start()` reopens the mic. Keep output-only and input-using engines separate, and make the input-using engine per-session.
6. **Bluetooth profile state is process-scoped** — macOS keeps BT in HFP while any AUHAL input is open for that device. Releasing all input AUs lets the OS return to A2DP after a brief grace period.
7. **`AVAudioEngine.start()` can lie** — it returns success and `engine.isRunning` reports `true` even when the underlying AUHAL fails to start IO (error 35, HFP renegotiation in flight, etc.). Don't trust the return value alone; verify audio flow by counting sink callbacks before reporting "recording started."
8. **Don't reset idle engines on configuration change** — observer callbacks that unconditionally `stop()`/`reset()` an already-stopped engine churn the HAL and can contend with a concurrently-starting second engine. Guard reset on `isRunning`.

---

## Changelog

### December 9, 2024 - Round 2 Fix

**Problem Recurrence:** The original fix (querying format after engine stop) was incomplete. Users still experienced the format mismatch crash with Bluetooth devices.

**Root Cause Discovery:** Bluetooth devices switch modes **twice**:
1. When engine stops: A2DP (48kHz) → HFP (24kHz) - this was handled
2. When engine restarts: HFP (24kHz) → A2DP (48kHz) - this was NOT handled

The error log showed the reverse of the original issue:
```
input hw <AVAudioFormat: 1 ch, 48000 Hz, Float32>   ← Hardware switched back
client format <AVAudioFormat: 1 ch, 24000 Hz, Float32>  ← Format we queried
```

**Solution Implemented:** Inserted `AVAudioMixerNode` between `inputNode` and `AVAudioSinkNode`. The mixer handles format conversion automatically, making the system immune to Bluetooth mode switching.

**Code Changes:**
- Added `recordingMixerNode: AVAudioMixerNode?` property
- Rewrote `setupRecordingTap()` with new graph topology
- Updated `resetRecordingState()` to clean up mixer
- Updated `stopRecording()` to detach mixer

**Document Updates:**
- Added "Solution (Round 1 - Incomplete)" section
- Added "Solution (Round 2 - Complete Fix)" section with code example
- Updated "Format Conversion Pipeline" diagram to show two-stage conversion
- Added "Why This Works" explanation

### Early 2026 — Round 3 Fix

**Problem:** Post-idle AirPods recordings captured silence, often with EAGAIN / -10877 errors.

**Root Cause:** Bluetooth profile switches (A2DP↔HFP) while the engine was idle left the graph
referencing stale device formats. The pinned 48 kHz "stable" format also diverged from actual
hardware rates during HFP.

**Solution Implemented:**
- Observed `.AVAudioEngineConfigurationChange` and reset the engine (deferred while recording).
- Added `refreshPlaybackConnectionIfNeeded()` to re-wire `playerNode` on format change.
- Replaced pinned 48 kHz stable format with `inputFormat.sampleRate`.

**Code Changes:**
- Added `configurationChangeObserver`, `needsConfigurationReset` deferral flag.
- Added `refreshPlaybackConnectionIfNeeded()`.
- Changed stable format construction to use the current input node's sample rate.

*Note: this round also lived in `lessons.md` under "AirPods After Idle → Silent Recording".
Round 4 later removed `needsConfigurationReset`.*

### April 22, 2026 — Round 4 Fix (HFP Lock-in)

**Problem:** After recording with AirPods, music and video from other apps played at reduced
fidelity (muffled, half-volume, lower bitrate) until Echo was quit.

**Root Cause Discovery:** `AVAudioEngine.inputNode` is a lazy property that allocates an
AUHAL I/O unit bound to the engine's lifetime. `engine.stop()` and `engine.reset()` do not
release it. The shared engine architecture from Rounds 2–3 reopened the mic whenever
`ensureEngineStarted()` ran for a post-recording sound effect, pinning the BT device in HFP.
Quitting the app was the only thing that deallocated the engine and freed the AUHAL.

**Solution Implemented:** Split the single shared engine into two separate instances. The
playback engine is long-lived and output-only. The recording engine is an `AVAudioEngine?`
that's created fresh per session and nilled out in `tearDownRecordingEngine()`, which
deterministically releases the AUHAL input and lets BT return to A2DP.

**Code Changes:**
- Split `engine` → `playbackEngine` (let) + `recordingEngine` (`AVAudioEngine?`).
- Added `setupRecordingEngine(to:)` and `tearDownRecordingEngine()` (replacing `setupRecordingTap` and `resetRecordingState`).
- Renamed `ensureEngineStarted` → `ensurePlaybackEngineStarted`; `stopEngineIfIdle` → `stopPlaybackEngineIfIdle`.
- Scoped configuration-change observer to the playback engine only.
- Removed `needsConfigurationReset` (recording engine is fresh each time, never needs reset).
- Removed dead code: `setupAudioSession`/`audioSessionConfigured` (iOS-only no-op on this macOS-only target), `hasAttemptedStart`, unused `copyBuffer`.

**Document Updates:**
- Renamed top-level title to "Bluetooth Audio Issues" (scope expanded beyond format mismatch).
- Added "Problem 2: Silent Recording After Idle on AirPods (Round 3)" section.
- Added "Problem 3: Bluetooth Stuck in HFP After Recording (Round 4)" section.
- Updated Format Conversion Pipeline diagram to reflect `inputFormat.sampleRate` (not pinned 48 kHz).
- Extended Prevention list with AUHAL/inputNode permanence and BT profile scoping notes.
- Extended Testing Checklist with post-recording BT fidelity regressions.

### April 22, 2026 — Round 4 Follow-up (Silent HAL Failure Detection)

**Problem:** Post-Round-4 bug report: recording would appear to succeed but produce empty
audio files. User saw a generic "Audio" error in the overlay; the underlying response was
Groq's `400 "Audio file is too short. Minimum audio length is 0.01 seconds."` Logs showed
`HALC_ProxyIOContext::_StartIO(): Start failed - StartAndWaitForState returned error 35`
and `HALB_IOThread::_Start: there already is a thread` at start, and zero pending buffer
writes at stop — the sink node had never received a single callback.

**Root Cause Discovery:** `AVAudioEngine.start()` returns success and `engine.isRunning`
reports `true` even when the underlying AUHAL silently fails to start IO (typically during
Bluetooth profile transitions). No Swift exception is thrown. The existing retry loop only
caught failures that actually *threw* out of setup; silent start-but-no-IO failures slipped
through, and we recorded "2.86 seconds of nothing" that the API correctly rejected.

This bug pre-dated Round 4 but was partially masked by retries churning over the other
issues. After Round 4's cleaner architecture removed that churn, it surfaced on its own.

**Solution Implemented:**
- Frame counter (`framesReceived`) incremented at the top of `processRecordingBufferRealtime`
  before any early-return, tracking raw HAL activity.
- `startRecording` now `async throws`. After `setupRecordingEngine`, it awaits
  `waitForFirstFrame(timeoutMs: 300)`. On timeout, the attempt is treated as failed.
- On silent-failure retry: tear down recording engine, stop the playback engine (to release
  device contention), 250 ms settle sleep, retry. Max 3 attempts.
- New `UnifiedAudioEngineError.deviceUnavailable` surfaces an actionable "reconnect Bluetooth"
  message when retries are exhausted, instead of a confusing "audio too short" 400.
- `resetPlaybackEngineForConfigurationChange` now skips `stop()`/`reset()` on an idle
  playback engine — previously it churned the HAL during every BT profile transition.

**Code Changes:**
- Added `framesReceived: Int` and `frameCounterLock: NSLock`.
- Added frame-counter increment at top of `processRecordingBufferRealtime` (and reset in `tearDownRecordingEngine`).
- `startRecording(to:)` now `async throws`; added private `waitForFirstFrame(timeoutMs:)`.
- Added `UnifiedAudioEngineError.deviceUnavailable` with BT-reconnect-suggesting message.
- Guarded `playbackEngine.stop()`/`reset()` in `resetPlaybackEngineForConfigurationChange` behind `isRunning`.
- `AudioRecorder.startRecording()` now `await`s the engine and dropped its 100 ms post-start sleep.
- `EchoTests/UnifiedAudioEngineXCTests.testInvalidURLThrows` updated to `await` the async API.

**Document Updates:**
- Added "Round 4 Follow-up: Silent HAL Failure Detection" section.
- Extended Prevention list: items 7 (trust-but-verify on `engine.start()`) and 8 (don't reset idle engines on config change).
- Added testing-checklist item for the mid-profile-switch recording case.
