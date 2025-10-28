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

