# Bluetooth Audio Format Mismatch Fix

**Date:** December 2024
**Component:** `UnifiedAudioEngine.swift`
**Issue Type:** Audio Recording Crash

## Problem Description

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

## Solution (Round 1 - Incomplete)

The initial fix was to query the input format **after** stopping the engine. However, this only addressed half the problem - Bluetooth devices can switch modes **again** when the engine restarts.

## Solution (Round 2 - Complete Fix)

Insert an `AVAudioMixerNode` between `inputNode` and `AVAudioSinkNode`. Unlike `AVAudioSinkNode`, mixer nodes support automatic format conversion, isolating the sink from hardware format changes.

```swift
// Use a STABLE intermediate format (48kHz Float32 mono)
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

## Format Conversion Pipeline

The new architecture uses a two-stage conversion:

```
[Hardware Input]     [Mixer Node]      [Stable Format]     [Converter]        [Output File]
  Any Hz (dynamic)  →  Auto-convert  →    48000 Hz      →   Resample    →      16000 Hz
  Float32              (transparent)      Float32           + Format           Int16 PCM
  1 channel                               1 channel         Convert            Mono WAV
```

Stage 1: Mixer handles Bluetooth format switching automatically
Stage 2: AVAudioConverter resamples from stable 48kHz to 16kHz for Whisper API

## Testing Checklist

- [ ] Built-in MacBook microphone
- [ ] AirPods / AirPods Pro
- [ ] Other Bluetooth headphones
- [ ] USB microphone
- [ ] External audio interface
- [ ] Push-to-talk rapid start/stop
- [ ] Toggle recording mode

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

1. **Always query hardware format after audio graph changes** - Format can change when engine starts/stops
2. **Add format validation** - Check for valid sample rate and channel count
3. **Handle Bluetooth mode switching** - Be aware that mic access triggers A2DP → HFP switch
4. **Log format information** - Include sample rate in debug logs for troubleshooting

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
- Added `recordingMixerNode: AVAudioMixerNode?` property (~line 23)
- Rewrote `setupRecordingTap()` with new graph topology (lines 268-441)
- Updated `resetRecordingState()` to clean up mixer (lines 458-466)
- Updated `stopRecording()` to detach mixer (lines 489-492)

**Document Updates:**
- Added "Solution (Round 1 - Incomplete)" section
- Added "Solution (Round 2 - Complete Fix)" section with code example
- Updated "Format Conversion Pipeline" diagram to show two-stage conversion
- Added "Why This Works" explanation
