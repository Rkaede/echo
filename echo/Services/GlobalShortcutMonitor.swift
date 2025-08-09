import Cocoa
import CoreGraphics

class GlobalShortcutMonitor: ObservableObject {
    static let shared = GlobalShortcutMonitor()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isFnKeyPressed = false
    
    @Published var shouldStartPushToTalk = false
    @Published var shouldStopPushToTalk = false
    @Published var shouldCancelRecording = false

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
                monitor.handleEvent(event: event, type: type)
                return Unmanaged.passUnretained(event)
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
    
    private func handleEvent(event: CGEvent, type: CGEventType) {
        switch type {
        case .flagsChanged:
            handleFlagsChanged(event: event)
        case .keyDown:
            handleKeyDown(event: event)
        default:
            break
        }
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
    
    private func handleKeyDown(event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        
        // Check for Escape key (keyCode 53)
        if keyCode == 53 {
            print("GlobalShortcutMonitor: Escape key pressed - requesting recording cancellation")
            DispatchQueue.main.async {
                self.shouldCancelRecording.toggle()
            }
        }
    }
}