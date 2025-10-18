# Overlay Window Behavior

## Idle State
When idle, the overlay window is **hidden** (not visible).

## Recording Start Sequence
When recording starts, three things happen:

1. **Overlay window shows** — window appears at full size instantly with no delay or fade-in animation, status changes to `initiatingRecording`
2. **Bluetooth device wake-up** — Wait for the bluetooth device to wake up and be ready.
   - **Implemented Approach**: Hybrid method combining silent audio priming with adaptive delays
     - Step 1: Play 10ms of silent audio using AVAudioEngine to wake Bluetooth device
     - Step 2: **Critical 150ms stabilization delay** to let audio system release AVAudioEngine resources
     - Step 3: Device-type specific adaptive delays:
       - AirPods: 100ms additional delay (total ~260ms)
       - Generic Bluetooth: 50ms additional delay (total ~210ms)
       - Wired/Built-in: 20ms additional delay (total ~180ms)
   - **Why this works**:
     - Silent audio exercises the audio path, reliably waking Bluetooth devices
     - 150ms stabilization prevents "reconfig pending" errors and silent recordings
     - Adaptive delays account for remaining device-specific initialization times
     - No conflicts with AVAudioRecorder after proper cleanup
     - More reliable than fixed delays or polling alone
3. **Audio cue plays** — once the recording device is ready, the recording start sound plays, followed by actual recording

## Recording Stop Sequence
When recording stops and returns to idle, the overlay window **fades out and hides**.

## Key Design Decisions
- Do not do size transitions (expand/shrink) of the overlay window when starting to record. This was often janky because of other complexities with bluetooth devices and other audio cues.
- Overlay window maintains constant size when visible — only animate when hiding the window.
- Window shows immediately when recording starts — provides instant visual feedback