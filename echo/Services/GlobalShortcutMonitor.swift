import Cocoa
import CoreGraphics

class GlobalShortcutMonitor {
  static let shared = GlobalShortcutMonitor()
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private let loggerCategory = "GlobalShortcutMonitor"
  private var isFnKeyPressed = false
  private var isDrawModifierPressed = false
  private var fnGesture = FnRecordingGesture()
  var onFnAction: (@MainActor (_ action: FnRecordingGesture.Action, _ keyTime: TimeInterval) -> Void)?
  var recordingStatus: (() -> RecordingStatus)?
  var canStartRecording: (() -> Bool)?
  private var isRecording = false
  private var isToggleHotkeySuspended = false
  private var notesModeShortcut: ShortcutUtils.ParsedShortcut?
  private var previousProfileShortcut: ShortcutUtils.ParsedShortcut?
  private var nextProfileShortcut: ShortcutUtils.ParsedShortcut?
  private var lastEventTimestamp: Date?
  private var eventTapCheckTimer: Timer?

  // Handlers run straight from the event tap on the main thread, without a SwiftUI
  // update pass. Fn actions also carry the uptime at which the tap saw the key.
  var onCancelRecording: (@MainActor () -> Void)?
  var onToggleNotesMode: (@MainActor () -> Void)?
  var onDrawModifierChanged: (@MainActor (_ isPressed: Bool) -> Void)?
  var onActivateNextProfile: (@MainActor () -> Void)?
  var onActivatePreviousProfile: (@MainActor () -> Void)?

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
          if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            monitor.interruptFnGesture()
            monitor.releaseDrawModifier()
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

  private func interruptFnGesture() {
    fnGesture.reset()
    let keyTime = ProcessInfo.processInfo.systemUptime
    deliver { self.onFnAction?(.stop, keyTime) }
  }

  func stopMonitoring() {
    interruptFnGesture()
    if let eventTap = eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
      self.eventTap = nil
    }
    if let runLoopSource = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
      self.runLoopSource = nil
    }
  }

  /// Runs a shortcut handler on the main thread. The tap's run loop source is added to the
  /// main run loop, so this normally runs it synchronously, right inside the tap callback.
  private func deliver(_ handler: @escaping @MainActor () -> Void) {
    guard Thread.isMainThread else {
      Task { @MainActor in handler() }
      return
    }
    MainActor.assumeIsolated { handler() }
  }

  private func handleEvent(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
    lastEventTimestamp = Date()

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
    updateDrawModifier(flags: flags)

    let fnKeyCurrentlyPressed = flags.contains(.maskSecondaryFn)

    guard fnKeyCurrentlyPressed != isFnKeyPressed else { return }
    isFnKeyPressed = fnKeyCurrentlyPressed
    guard !isToggleHotkeySuspended else { return }
    let status = recordingStatus?() ?? .idle
    switch status {
    case .processing, .postProcessing:
      fnGesture.reset()
      return
    default: break
    }
    // A previous stop may still be unwinding after cancellation. Reject the
    // whole gesture rather than latching a recording that never started.
    var nextGesture = fnGesture
    let action = fnKeyCurrentlyPressed
      ? nextGesture.press(at: event.timestamp)
      : nextGesture.release(at: event.timestamp)
    if action == .start, canStartRecording?() == false { return }
    fnGesture = nextGesture
    if let action {
      let keyTime = ProcessInfo.processInfo.systemUptime
      deliver { self.onFnAction?(action, keyTime) }
    }
  }

  /// Shift on its own arms notes-mode drawing while recording. Fn may be held too, so
  /// drawing works while holding Fn to record; other modifiers mean a shortcut like
  /// Cmd-Shift-4.
  private func updateDrawModifier(flags: CGEventFlags) {
    let isPressed =
      flags.contains(.maskShift)
      && flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty
    guard isPressed != isDrawModifierPressed else { return }
    isDrawModifierPressed = isPressed
    deliver { self.onDrawModifierChanged?(isPressed) }
  }

  /// A disabled tap can miss the Shift release, which would leave the drawing panel
  /// swallowing clicks.
  private func releaseDrawModifier() {
    guard isDrawModifierPressed else { return }
    isDrawModifierPressed = false
    deliver { self.onDrawModifierChanged?(false) }
  }

  func resetFnGesture() {
    // Keep the physical key state: a held key must be released before restarting.
    fnGesture.reset()
  }

  private func handleKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags

    // Check for the notes mode shortcut (only when not suspended, e.g. while
    // the shortcut recorder is capturing)
    if !isToggleHotkeySuspended, let notesShortcut = notesModeShortcut,
      shortcutMatches(notesShortcut, keyCode: keyCode, flags: flags)
    {
      log(
        "Notes mode shortcut matched",
        category: loggerCategory,
        level: .info
      )
      deliver { self.onToggleNotesMode?() }
      return nil  // Consume the event
    }

    if isRecording, !isToggleHotkeySuspended,
      let previousShortcut = previousProfileShortcut,
      shortcutMatches(previousShortcut, keyCode: keyCode, flags: flags)
    {
      log(
        "Previous profile shortcut matched",
        category: loggerCategory,
        level: .info
      )
      deliver { self.onActivatePreviousProfile?() }
      return nil
    }

    if isRecording, !isToggleHotkeySuspended,
      let nextShortcut = nextProfileShortcut,
      shortcutMatches(nextShortcut, keyCode: keyCode, flags: flags)
    {
      log(
        "Next profile shortcut matched",
        category: loggerCategory,
        level: .info
      )
      deliver { self.onActivateNextProfile?() }
      return nil
    }

    switch keyCode {
    case 53:
      // Escape key - consume it if we're recording
      if isRecording {
        log(
          "Escape key pressed while recording; requesting cancellation",
          category: loggerCategory,
          level: .info
        )
        deliver { self.onCancelRecording?() }
        return nil  // Consume the event - don't let it reach other apps
      } else {
        log(
          "Escape key pressed but not recording; letting event pass through",
          category: loggerCategory,
          level: .debug
        )
      }
    default:
      break
    }

    // Let all other events (or non-recording Escape) pass through
    return Unmanaged.passUnretained(event)
  }

  private func shortcutMatches(
    _ shortcut: ShortcutUtils.ParsedShortcut,
    keyCode: Int64,
    flags: CGEventFlags
  ) -> Bool {
    let relevantFlags: CGEventFlags = [
      .maskCommand, .maskControl, .maskAlternate, .maskShift,
    ]
    return keyCode == shortcut.keyCode
      && flags.intersection(relevantFlags) == shortcut.modifiers
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
    interruptFnGesture()
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

  func loadNotesModeShortcut(_ shortcut: String?) {
    guard let shortcut, !shortcut.isEmpty, let parsed = ShortcutUtils.parse(shortcut) else {
      notesModeShortcut = nil
      log("Notes mode shortcut cleared", category: loggerCategory, level: .info)
      return
    }
    notesModeShortcut = parsed
    log("Loaded notes mode shortcut: \(shortcut)", category: loggerCategory, level: .info)
  }

  func loadProfileNavigationShortcuts(previous: String?, next: String?) {
    previousProfileShortcut = previous.flatMap(ShortcutUtils.parse)
    nextProfileShortcut = next.flatMap(ShortcutUtils.parse)
    log(
      "Loaded profile navigation shortcuts",
      category: loggerCategory,
      level: .info
    )
  }

}
