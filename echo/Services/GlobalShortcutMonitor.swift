import Cocoa
import CoreGraphics

class GlobalShortcutMonitor: ObservableObject {
    static let shared = GlobalShortcutMonitor()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isFnKeyPressed = false
    private var isRecording = false
    private var isToggleHotkeySuspended = false

    @Published var shouldStartPushToTalk = false
    @Published var shouldStopPushToTalk = false
    @Published var shouldCancelRecording = false
    @Published var shouldActivateNextProfile = false
    @Published var shouldActivatePreviousProfile = false
    @Published var shouldTriggerRecording = false

    init() {
        startMonitoring()
    }
    
    func startMonitoring() {
        // Create event mask for the events we want to monitor
        let eventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        
        // Create the event tap
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                // Get the GlobalKeyboardMonitor instance
                let monitor = Unmanaged<GlobalShortcutMonitor>.fromOpaque(refcon!).takeUnretainedValue()
                return monitor.handleEvent(event: event, type: type)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            print("Failed to create event tap")
            return
        }
        
        self.eventTap = eventTap
        
        // Create a run loop source and add it to the current run loop
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        
        // Enable the event tap
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }
    
    func stopMonitoring() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
    }
    
    private func handleEvent(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        switch type {
        case .flagsChanged:
            handleFlagsChanged(event: event)
        case .keyDown:
            return handleKeyDown(event: event)
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }
    
    private func handleFlagsChanged(event: CGEvent) {
        let flags = event.flags
        let fnKeyCurrentlyPressed = flags.contains(.maskSecondaryFn)
        
        // Check for FN key state change
        if fnKeyCurrentlyPressed && !isFnKeyPressed {
            // FN key was just pressed
            print("GlobalShortcutMonitor: FN key pressed - starting push-to-talk")
            isFnKeyPressed = true
            DispatchQueue.main.async {
                self.shouldStartPushToTalk.toggle()
            }
        } else if !fnKeyCurrentlyPressed && isFnKeyPressed {
            // FN key was just released
            print("GlobalShortcutMonitor: FN key released - stopping push-to-talk")
            isFnKeyPressed = false
            DispatchQueue.main.async {
                self.shouldStopPushToTalk.toggle()
            }
        }
    }
    
    private func handleKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        switch keyCode {
        case 49:
            // Space key - check for Option modifier for toggle mode
            if flags.contains(.maskAlternate) && !isToggleHotkeySuspended {
                print("GlobalShortcutMonitor: Option+Space pressed - triggering toggle")
                DispatchQueue.main.async {
                    self.shouldTriggerRecording.toggle()
                }
                return nil // Consume the event
            }
        case 53:
            // Escape key - consume it if we're recording
            if isRecording {
                print("GlobalShortcutMonitor: Escape key pressed while recording - consuming event and requesting cancellation")
                DispatchQueue.main.async {
                    self.shouldCancelRecording.toggle()
                }
                return nil // Consume the event - don't let it reach other apps
            } else {
                print("GlobalShortcutMonitor: Escape key pressed but not recording - letting event pass through")
            }
        case 123:
            // Left arrow key
            if isRecording {
                print("GlobalShortcutMonitor: Left arrow key pressed while recording - requesting previous profile")
                DispatchQueue.main.async {
                    self.shouldActivatePreviousProfile.toggle()
                }
            }
        case 124:
            // Right arrow key
            if isRecording {
                print("GlobalShortcutMonitor: Right arrow key pressed while recording - requesting next profile")
                DispatchQueue.main.async {
                    self.shouldActivateNextProfile.toggle()
                }
            }
        default:
            break
        }

        // Let all other events (or non-recording Escape) pass through
        return Unmanaged.passUnretained(event)
    }
    
    // Methods to update recording state
    func setRecording(_ isRecording: Bool) {
        self.isRecording = isRecording
        print("GlobalShortcutMonitor: Recording state updated to: \(isRecording)")
    }

    func suspendToggleHotkey() {
        guard !isToggleHotkeySuspended else { return }
        print("GlobalShortcutMonitor: Suspending toggle hotkey")
        isToggleHotkeySuspended = true
    }

    func resumeToggleHotkey() {
        guard isToggleHotkeySuspended else { return }
        print("GlobalShortcutMonitor: Resuming toggle hotkey")
        isToggleHotkeySuspended = false
    }
}
