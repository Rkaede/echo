import Testing
@testable import Echo

@Suite("Unified Fn recording")
struct FnRecordingGestureTests {
  @Test func tapLatchesAndNextPressConsumesRelease() {
    var gesture = FnRecordingGesture()
    #expect(gesture.press(at: 0) == .start)
    #expect(gesture.press(at: 1) == nil)
    #expect(gesture.release(at: 299_999_999) == .latch)
    #expect(gesture.release(at: 300_000_000) == nil)
    #expect(gesture.press(at: 400_000_000) == .stop)
    #expect(gesture.release(at: 410_000_000) == nil)
    #expect(gesture.press(at: 500_000_000) == .start)
  }

  @Test(arguments: [UInt64(300_000_000), UInt64(900_000_000)])
  func holdStopsAtThreshold(duration: UInt64) {
    var gesture = FnRecordingGesture()
    #expect(gesture.press(at: 0) == .start)
    #expect(gesture.release(at: duration) == .stop)
  }

  @Test func resetDiscardsPendingReleaseAndLatch() {
    var gesture = FnRecordingGesture()
    _ = gesture.press(at: 0)
    _ = gesture.release(at: 1)
    gesture.reset()
    #expect(gesture.release(at: 2) == nil)
    #expect(gesture.press(at: 3) == .start)
  }

  @MainActor @Test(arguments: [false, true])
  func delayedStartupRetainsStopOrCancel(cancelRequested: Bool) async {
    var resume: CheckedContinuation<Void, Never>?
    var events: [String] = []
    let coordinator = FnRecordingCoordinator(
      start: {
        events.append("start")
        await withCheckedContinuation { resume = $0 }
      },
      stop: { events.append("stop") },
      cancel: { events.append("cancel") },
      setToggleMode: { events.append("toggle") }
    )
    coordinator.handle(.start)
    while resume == nil { await Task.yield() }
    #expect(!coordinator.hasPendingEndRequest)
    coordinator.handle(.latch)
    #expect(!coordinator.hasPendingEndRequest)
    coordinator.handle(.stop)
    #expect(coordinator.hasPendingEndRequest)
    coordinator.handle(.start) // No overlapping startup.
    if cancelRequested { #expect(coordinator.cancelDuringStartup()) }
    #expect(events == ["start", "toggle"])
    resume?.resume()
    while events.count < 4 { await Task.yield() }
    #expect(events == ["start", "toggle", "toggle", cancelRequested ? "cancel" : "stop"])
    #expect(!coordinator.hasPendingEndRequest)
  }

  @MainActor @Test func stopWhileStartingWithoutLatchAndFreshSession() async {
    var resume: CheckedContinuation<Void, Never>?
    var starts = 0
    var stops = 0
    var toggles = 0
    let coordinator = FnRecordingCoordinator(
      start: {
        starts += 1
        await withCheckedContinuation { resume = $0 }
      },
      stop: { stops += 1 },
      cancel: {},
      setToggleMode: { toggles += 1 }
    )
    coordinator.handle(.start)
    while resume == nil { await Task.yield() }
    #expect(!coordinator.canStart)
    coordinator.handle(.stop)
    coordinator.handle(.stop)
    resume?.resume()
    while !coordinator.canStart { await Task.yield() }
    #expect(stops == 1)
    #expect(toggles == 0)

    resume = nil
    coordinator.handle(.start)
    while resume == nil { await Task.yield() }
    resume?.resume()
    while !coordinator.canStart { await Task.yield() }
    #expect(starts == 2)
    #expect(stops == 1) // The first session's pending stop was cleared.
  }

  @MainActor @Test func inFlightStopRejectsRestart() async {
    var resumeStop: CheckedContinuation<Void, Never>?
    var starts = 0
    let coordinator = FnRecordingCoordinator(
      start: { starts += 1 },
      stop: { await withCheckedContinuation { resumeStop = $0 } },
      cancel: {},
      setToggleMode: {}
    )
    coordinator.handle(.start)
    while !coordinator.canStart { await Task.yield() }
    coordinator.handle(.stop)
    while resumeStop == nil { await Task.yield() }
    coordinator.handle(.start)
    #expect(!coordinator.canStart)
    #expect(starts == 1)
    resumeStop?.resume()
    while !coordinator.canStart { await Task.yield() }
    #expect(!coordinator.cancelDuringStartup())
  }
}
