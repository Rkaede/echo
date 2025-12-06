import Cocoa
import CoreGraphics

class GlobalShortcutMonitor: ObservableObject {
  static let shared = GlobalShortcutMonitor()
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private let loggerCategory = "GlobalShortcutMonitor"
  private var isFnKeyPressed = false
  private var isRecording = false
  private var isToggleHotkeySuspended = false
  private var profileShortcuts: [(profileId: String, parsed: ShortcutUtils.ParsedShortcut)] = []
  private var lastEventTimestamp: Date?
  private var eventTapCheckTimer: Timer?

  @Published var shouldStartPushToTalk = false
  @Published var shouldStopPushToTalk = false
  @Published var shouldCancelRecording = false
  @Published var shouldActivateNextProfile = false
  @Published var shouldActivatePreviousProfile = false
  @Published var shouldTriggerRecording = false
  @Published var triggeredProfileId: String? = nil

  init() {
    startMonitoring()
  }

  deinit {
    stopMonitoring()
  }

  func startMonitoring() {
    // Create event mask for the events we want to monitor
    let eventMask =
      (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
      | (1 << CGEventType.tapDisabledByTimeout.rawValue)

    // Create the event tap
    guard
      let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: CGEventMask(eventMask),
        callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
          // Get the GlobalKeyboardMonitor instance
          let monitor = Unmanaged<GlobalShortcutMonitor>.fromOpaque(refcon!).takeUnretainedValue()

          // Check if event tap was disabled by timeout
          if type == .tapDisabledByTimeout {
            log(
              "Event tap disabled by timeout; attempting to re-enable",
              category: monitor.loggerCategory,
              level: .error
            )
            if let tap = monitor.eventTap {
              CGEvent.tapEnable(tap: tap, enable: true)
              log(
                "Event tap re-enabled",
                category: monitor.loggerCategory,
                level: .info
              )
            }
            return nil
          }

          return monitor.handleEvent(event: event, type: type)
        },
        userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
      )
    else {
      log(
        "Failed to create event tap",
        category: loggerCategory,
        level: .error
      )
      return
    }

    self.eventTap = eventTap

    // Create a run loop source and add it to the current run loop
    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)

    // Enable the event tap
    CGEvent.tapEnable(tap: eventTap, enable: true)
    log(
      "Event tap created and enabled successfully",
      category: loggerCategory,
      level: .info
    )
  }

  func stopMonitoring() {
    if let eventTap = eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
      self.eventTap = nil
    }
    if let runLoopSource = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
      self.runLoopSource = nil
    }
  }

  private func handleEvent(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
    lastEventTimestamp = Date()

    // Log key events for debugging
    if type == .keyDown {
      let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
      if keyCode == 49 {  // Space key
        let timestamp = event.timestamp
        log(
          "handleEvent received keyDown for space (keyCode: 49) at timestamp: \(timestamp)",
          category: loggerCategory,
          level: .debug
        )
      }
    }

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
      log(
        "FN key pressed; starting push-to-talk",
        category: loggerCategory,
        level: .debug
      )
      isFnKeyPressed = true
      DispatchQueue.main.async {
        self.shouldStartPushToTalk.toggle()
      }
    } else if !fnKeyCurrentlyPressed && isFnKeyPressed {
      // FN key was just released
      log(
        "FN key released; stopping push-to-talk",
        category: loggerCategory,
        level: .debug
      )
      isFnKeyPressed = false
      DispatchQueue.main.async {
        self.shouldStopPushToTalk.toggle()
      }
    }
  }

  private func handleKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags

    // Log ALL keypresses for debugging (only log space + option for now)
    if keyCode == 49 && flags.contains(.maskAlternate) {
      log(
        "Option+Space keyDown detected - isRecording: \(isRecording), isToggleHotkeySuspended: \(isToggleHotkeySuspended), profileShortcuts count: \(profileShortcuts.count)",
        category: loggerCategory,
        level: .debug
      )
    }

    // Check for profile shortcuts first (only when not suspended)
    if !isToggleHotkeySuspended {
      for (profileId, parsed) in profileShortcuts {
        if keyCode == parsed.keyCode && flags.contains(parsed.modifiers) {
          // Check that we have exactly the modifiers specified (no extra modifiers)
          let relevantFlags: CGEventFlags = [
            .maskCommand, .maskControl, .maskAlternate, .maskShift,
          ]
          let currentModifiers = flags.intersection(relevantFlags)

          if currentModifiers == parsed.modifiers {
            log(
              "Profile shortcut matched for profile \(profileId) - isRecording: \(isRecording)",
              category: loggerCategory,
              level: .info
            )
            DispatchQueue.main.async {
              // Emit a nil first so repeated presses of the same shortcut still trigger observers
              self.triggeredProfileId = nil
              DispatchQueue.main.async {
                self.triggeredProfileId = profileId
              }
            }
            return nil  // Consume the event
          } else {
            log(
              "Modifier mismatch - expected: \(parsed.modifiers), got: \(currentModifiers)",
              category: loggerCategory,
              level: .debug
            )
          }
        }
      }
    } else {
      if keyCode == 49 && flags.contains(.maskAlternate) {
        log(
          "Toggle hotkey is suspended; skipping profile shortcut check",
          category: loggerCategory,
          level: .debug
        )
      }
    }

    switch keyCode {
    case 49:
      // Space key - check for Option modifier for toggle mode
      if flags.contains(.maskAlternate) && !isToggleHotkeySuspended {
        log(
          "Option+Space pressed; triggering toggle",
          category: loggerCategory,
          level: .info
        )
        DispatchQueue.main.async {
          self.shouldTriggerRecording.toggle()
        }
        return nil  // Consume the event
      }
    case 53:
      // Escape key - consume it if we're recording
      if isRecording {
        log(
          "Escape key pressed while recording; requesting cancellation",
          category: loggerCategory,
          level: .info
        )
        DispatchQueue.main.async {
          self.shouldCancelRecording.toggle()
        }
        return nil  // Consume the event - don't let it reach other apps
      } else {
        log(
          "Escape key pressed but not recording; letting event pass through",
          category: loggerCategory,
          level: .debug
        )
      }
    case 123:
      // Left arrow key
      if isRecording {
        log(
          "Left arrow key pressed while recording; requesting previous profile",
          category: loggerCategory,
          level: .info
        )
        DispatchQueue.main.async {
          self.shouldActivatePreviousProfile.toggle()
        }
      }
    case 124:
      // Right arrow key
      if isRecording {
        log(
          "Right arrow key pressed while recording; requesting next profile",
          category: loggerCategory,
          level: .info
        )
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
    log(
      "Recording state updated to: \(isRecording)",
      category: loggerCategory,
      level: .info
    )

    // Verify event tap is still active
    if let tap = eventTap {
      let isEnabled = CGEvent.tapIsEnabled(tap: tap)
      log(
        "Event tap enabled status: \(isEnabled)",
        category: loggerCategory,
        level: .debug
      )
    } else {
      log(
        "Event tap is nil",
        category: loggerCategory,
        level: .error
      )
    }
  }

  func suspendToggleHotkey() {
    guard !isToggleHotkeySuspended else { return }
    log(
      "Suspending toggle hotkey",
      category: loggerCategory,
      level: .info
    )
    isToggleHotkeySuspended = true
  }

  func resumeToggleHotkey() {
    guard isToggleHotkeySuspended else { return }
    log(
      "Resuming toggle hotkey",
      category: loggerCategory,
      level: .info
    )
    isToggleHotkeySuspended = false
  }

  func loadProfileShortcuts(from profiles: [Profile]) {
    var shortcuts: [(profileId: String, parsed: ShortcutUtils.ParsedShortcut)] = []

    for profile in profiles {
      guard profile.isEnabled,
        let shortcutString = profile.shortcut,
        !shortcutString.isEmpty,
        let parsed = ShortcutUtils.parse(shortcutString)
      else {
        continue
      }

      shortcuts.append((profileId: profile.id, parsed: parsed))
      log(
        "Loaded shortcut for profile '\(profile.title)': \(shortcutString)",
        category: loggerCategory,
        level: .debug
      )
    }

    profileShortcuts = shortcuts
    log(
      "Loaded \(shortcuts.count) profile shortcuts",
      category: loggerCategory,
      level: .info
    )
  }
}
