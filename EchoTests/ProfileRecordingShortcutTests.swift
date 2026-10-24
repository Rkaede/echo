import CoreGraphics
import Foundation
import Testing
@testable import Echo

@Suite("Profile recording shortcuts")
struct ProfileRecordingShortcutTests {
  private func profile(_ id: String, shortcut: String?, enabled: Bool = true) -> Profile {
    Profile(
      id: id, title: id, isDefault: false, isEnabled: enabled, shortcut: shortcut,
      transcriptionModel: "whisper-large-v3", postProcessingEnabled: false,
      postProcessingPrompt: "{{TRANSCRIPTION}}",
      postProcessingModel: PostProcessingModelOption.defaultOptionValue,
      createdAt: Date(), updatedAt: Date()
    )
  }

  private func key(_ code: CGKeyCode, flags: CGEventFlags = [], repeatKey: Bool = false) -> CGEvent {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
    event.flags = flags
    event.setIntegerValueField(.keyboardEventAutorepeat, value: repeatKey ? 1 : 0)
    return event
  }

  @MainActor @Test func savedBindingsReloadReplaceAndRespectEnabledState() {
    let saved = profile("saved", shortcut: "option+space")
    // A fresh monitor loads existing persisted values without rewriting them.
    let monitor = GlobalShortcutMonitor(startMonitoring: false)
    var selected: [String] = []
    monitor.onProfileRecordingShortcut = { id, _ in selected.append(id) }
    monitor.loadProfileShortcuts([saved])
    #expect(monitor.handleEvent(event: key(49, flags: .maskAlternate), type: .keyDown) == nil)
    #expect(selected == ["saved"])
    #expect(monitor.handleEvent(event: key(49, flags: [.maskAlternate, .maskShift]), type: .keyDown) != nil)
    monitor.loadProfileShortcuts([profile("saved", shortcut: "ctrl+r")])
    #expect(monitor.handleEvent(event: key(49, flags: .maskAlternate), type: .keyDown) != nil)
    #expect(monitor.handleEvent(event: key(15, flags: .maskControl), type: .keyDown) == nil)
    #expect(selected == ["saved", "saved"])
    monitor.loadProfileShortcuts([profile("saved", shortcut: "ctrl+r", enabled: false)])
    #expect(monitor.handleEvent(event: key(15, flags: .maskControl), type: .keyDown) != nil)
    monitor.loadProfileShortcuts([])
    #expect(monitor.handleEvent(event: key(15, flags: .maskControl), type: .keyDown) != nil)
  }

  @MainActor @Test func captureSuspendsBindingsAndKeyRepeatDoesNotToggle() {
    let monitor = GlobalShortcutMonitor(startMonitoring: false)
    var presses = 0
    monitor.onProfileRecordingShortcut = { _, _ in presses += 1 }
    monitor.loadProfileShortcuts([profile("first", shortcut: "alt+space")])
    monitor.suspendToggleHotkey()
    #expect(monitor.handleEvent(event: key(49, flags: .maskAlternate), type: .keyDown) != nil)
    monitor.resumeToggleHotkey()
    #expect(monitor.handleEvent(event: key(49, flags: .maskAlternate), type: .keyDown) == nil)
    #expect(monitor.handleEvent(event: key(49, flags: .maskAlternate, repeatKey: true), type: .keyDown) == nil)
    #expect(presses == 1)
  }

  @Test func validationRejectsReservedUnsupportedAndDuplicateBindings() throws {
    for reserved in ["CMD+Q", "cmd+w", "cmd+h", "cmd+m", "fn", "esc"] {
      #expect(throws: ProfileValidationError.reservedShortcut) {
        try ShortcutUtils.validate(reserved, against: [])
      }
    }
    #expect(throws: ProfileValidationError.invalidShortcut) {
      try ShortcutUtils.validate("ctrl+unsupported", against: [])
    }
    // Used in both directions: profile saves check other profiles and actions;
    // action saves check all profile bindings, including disabled profiles.
    for existing in ["option+space", "alt+space", " ALT + SPACE "] {
      #expect(throws: ProfileValidationError.duplicateShortcut) {
        try ShortcutUtils.validate("alt+space", against: [nil, existing])
      }
    }
    try ShortcutUtils.validate("alt+shift+space", against: ["alt+space"])
    try ShortcutUtils.validate(nil, against: ["alt+space"])
  }

  @MainActor @Test func selectsProfileBeforeStartAndStopsWithoutChangingSelection() async {
    var events: [String] = []
    var status = RecordingStatus.idle
    let coordinator = FnRecordingCoordinator(
      start: { events.append("fn-start"); status = .recording },
      stop: { events.append("transcribe/paste"); status = .inserted },
      cancel: {}, setToggleMode: {}
    )
    #expect(coordinator.toggle(status: status, beforeStart: { events.append("select-coding") }, start: {
      events.append("profile-start"); status = .recording
    }) == .start)
    while !coordinator.canStart { await Task.yield() }
    #expect(events == ["select-coding", "profile-start"])
    #expect(coordinator.toggle(status: status, beforeStart: { events.append("select-other") }, start: {}) == .stop)
    while !coordinator.canStart { await Task.yield() }
    #expect(events == ["select-coding", "profile-start", "transcribe/paste"])
    for busy in [RecordingStatus.processing, .postProcessing, .initiatingRecording, .confirmingCancel] {
      #expect(coordinator.toggle(status: busy, beforeStart: { events.append("unexpected") }, start: {}) == nil)
    }
    #expect(events.count == 3)
  }

  @MainActor @Test func secondPressDuringProfileStartupDefersOneStopAndBlocksRestart() async {
    var resumeStart: CheckedContinuation<Void, Never>?
    var resumeStop: CheckedContinuation<Void, Never>?
    var selections = 0
    var stops = 0
    let coordinator = FnRecordingCoordinator(
      start: {}, stop: {
        stops += 1
        await withCheckedContinuation { resumeStop = $0 }
      }, cancel: {}, setToggleMode: {}
    )
    #expect(coordinator.toggle(status: .idle, beforeStart: { selections += 1 }, start: {
      await withCheckedContinuation { resumeStart = $0 }
    }) == .start)
    while resumeStart == nil { await Task.yield() }
    #expect(coordinator.toggle(status: .initiatingRecording, beforeStart: { selections += 1 }, start: {}) == .stop)
    coordinator.handle(.stop) // Fn release cannot schedule a second stop.
    #expect(stops == 0)
    resumeStart?.resume()
    while resumeStop == nil { await Task.yield() }
    #expect(coordinator.toggle(status: .processing, beforeStart: { selections += 1 }, start: {}) == .stop)
    #expect(selections == 1)
    #expect(stops == 1)
    resumeStop?.resume()
    while !coordinator.canStart { await Task.yield() }
    #expect(!coordinator.hasPendingEndRequest)
  }

  @MainActor @Test func profileShortcutStopsFnSessionAndFnStopsProfileSession() async {
    var starts = 0
    var stops = 0
    let coordinator = FnRecordingCoordinator(
      start: { starts += 1 }, stop: { stops += 1 }, cancel: {}, setToggleMode: {}
    )
    coordinator.handle(.start)
    while !coordinator.canStart { await Task.yield() }
    #expect(coordinator.toggle(status: .recording, beforeStart: {}, start: {}) == .stop)
    while !coordinator.canStart { await Task.yield() }
    #expect(starts == 1)
    #expect(stops == 1)

    let monitor = GlobalShortcutMonitor(startMonitoring: false)
    var status = RecordingStatus.idle
    monitor.recordingStatus = { status }
    monitor.canStartRecording = { coordinator.canStart }
    monitor.onFnAction = { action, _ in coordinator.handle(action) }
    monitor.onProfileRecordingShortcut = { [weak monitor] _, _ in
      let action = coordinator.toggle(status: status, beforeStart: {}, start: {
        starts += 1; status = .recording
      })
      if action == .start { monitor?.latchFnRecording() }
    }
    monitor.loadProfileShortcuts([profile("dictation", shortcut: "alt+space")])
    _ = monitor.handleEvent(event: key(49, flags: .maskAlternate), type: .keyDown)
    while !coordinator.canStart { await Task.yield() }
    let fnPress = CGEvent(source: nil)!
    fnPress.flags = .maskSecondaryFn
    fnPress.timestamp = 1_000_000_000
    _ = monitor.handleEvent(event: fnPress, type: .flagsChanged)
    let fnRelease = CGEvent(source: nil)!
    fnRelease.timestamp = 1_100_000_000
    _ = monitor.handleEvent(event: fnRelease, type: .flagsChanged)
    while !coordinator.canStart { await Task.yield() }
    #expect(starts == 2)
    #expect(stops == 2) // Fn's release is consumed after its stop press.
  }
}
