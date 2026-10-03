import Foundation

/// Times physical transitions with the event's monotonic timestamp.
struct FnRecordingGesture {
  enum Action: Equatable { case start, latch, stop }
  private var pressedAt: UInt64?
  private var latched = false
  private var consumeRelease = false
  static let holdThreshold: UInt64 = 300_000_000

  mutating func press(at timestamp: UInt64) -> Action? {
    guard pressedAt == nil else { return nil }
    pressedAt = timestamp
    if latched {
      latched = false
      consumeRelease = true
      return .stop
    }
    return .start
  }

  mutating func release(at timestamp: UInt64) -> Action? {
    guard let start = pressedAt else { return nil }
    pressedAt = nil
    if consumeRelease {
      consumeRelease = false
      return nil
    }
    if timestamp >= start && timestamp - start < Self.holdThreshold {
      latched = true
      return .latch
    }
    return .stop
  }

  mutating func reset() { self = Self() }
}

/// Owns startup until it settles; no subsequent session can inherit pending intent.
@MainActor
final class FnRecordingCoordinator {
  private var starting = false
  private var stopping = false
  private var pendingLatch = false
  private var pendingStop = false
  private var pendingCancel = false
  private let start: () async -> Void
  private let stop: () async -> Void
  private let cancel: () async -> Void
  private let setToggleMode: () -> Void

  var canStart: Bool { !starting && !stopping }
  var hasPendingEndRequest: Bool { pendingStop || pendingCancel }

  init(start: @escaping () async -> Void, stop: @escaping () async -> Void,
       cancel: @escaping () async -> Void, setToggleMode: @escaping () -> Void) {
    self.start = start
    self.stop = stop
    self.cancel = cancel
    self.setToggleMode = setToggleMode
  }

  func handle(_ action: FnRecordingGesture.Action) {
    switch action {
    case .start:
      guard !starting && !stopping else { return }
      starting = true
      pendingLatch = false
      pendingStop = false
      pendingCancel = false
      Task {
        await start()
        if pendingLatch { setToggleMode() }
        if pendingCancel { await cancel() }
        else if pendingStop { await stop() }
        pendingStop = false
        pendingCancel = false
        starting = false
      }
    case .latch:
      if starting { pendingLatch = true }
      setToggleMode()
    case .stop:
      if starting { pendingStop = true }
      else {
        guard !stopping else { return }
        stopping = true
        Task {
          await stop()
          stopping = false
        }
      }
    }
  }

  /// Returns true when cancellation will be performed after startup completes.
  func cancelDuringStartup() -> Bool {
    guard starting else { return false }
    pendingCancel = true
    return true
  }
}
