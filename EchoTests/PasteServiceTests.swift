import AppKit
import Testing

@testable import Echo

@MainActor
@Suite("Transcription paste delivery")
struct PasteServiceTests {
  @Test func eventCreationFailureKeepsTextForManualPaste() async {
    let fixture = Fixture()
    fixture.canPost = false
    let result = await fixture.makeService().pasteToFocusedApp("transcript", targetProcessIdentifier: 42)
    #expect(result == .failed(.eventCreationFailed, copiedToClipboard: true))
    #expect(fixture.clipboard.text == "transcript")
    #expect(fixture.clipboard.restoreCount == 0)
    #expect(fixture.restoreContinuation == nil)
  }

  @Test func deniedPermissionKeepsTextAndReportsRecovery() async {
    let fixture = Fixture()
    fixture.hasPermission = false
    let result = await fixture.makeService().pasteToFocusedApp("transcript", targetProcessIdentifier: 42)
    #expect(result == .failed(.accessibilityPermission, copiedToClipboard: true))
    #expect(fixture.posts.isEmpty)
    #expect(fixture.clipboard.text == "transcript")
    #expect(PasteService.Failure.accessibilityPermission.errorMessage(
      copiedToClipboard: true, historyEnabled: false).contains("Command+V"))
  }

  @Test func revokedPermissionDuringPreparationPreventsPosting() async {
    let fixture = Fixture()
    fixture.onSleep = { _ in fixture.hasPermission = false }
    let result = await fixture.makeService().pasteToFocusedApp("transcript", targetProcessIdentifier: 42)
    #expect(result == .failed(.accessibilityPermission, copiedToClipboard: true))
    #expect(fixture.posts.isEmpty)
  }

  @Test(arguments: [pid_t(7), nil])
  func changedOrMissingTargetDoesNotReceiveText(target: pid_t?) async {
    let fixture = Fixture()
    let result = await fixture.makeService().pasteToFocusedApp("transcript", targetProcessIdentifier: target)
    #expect(result == .failed(.targetChanged, copiedToClipboard: true))
    #expect(fixture.posts.isEmpty)
  }

  @Test func appSwitchDuringPreparationDoesNotRedirectText() async {
    let fixture = Fixture()
    fixture.onSleep = { _ in fixture.frontmostPID = 7 }
    let result = await fixture.makeService().pasteToFocusedApp("transcript", targetProcessIdentifier: 42)
    #expect(result == .failed(.targetChanged, copiedToClipboard: true))
    #expect(fixture.posts.isEmpty)
  }

  @Test(arguments: [
    CGEventFlags.maskSecondaryFn, .maskAlternate, .maskShift, .maskControl, .maskCommand,
  ])
  func heldModifiersPreventAlteredPasteShortcuts(flags: CGEventFlags) async {
    let fixture = Fixture()
    fixture.flags = flags
    let result = await fixture.makeService().pasteToFocusedApp("transcript", targetProcessIdentifier: 42)
    #expect(result == .failed(.modifiersHeld, copiedToClipboard: true))
    #expect(fixture.posts.isEmpty)
    #expect(fixture.delays.filter { $0 == 20_000_000 }.count == 75)
  }

  @Test func pasteWaitsForShortcutReleaseAndPostsOnceToTarget() async {
    let fixture = Fixture()
    fixture.flags = [.maskSecondaryFn, .maskAlternate]
    fixture.onSleep = { delay in
      if delay == 20_000_000 { fixture.flags = [] }
    }
    let result = await fixture.makeService().pasteToFocusedApp(
      "transcript", targetProcessIdentifier: 42, restoreClipboard: false)
    #expect(result == .posted)
    #expect(fixture.posts == [42])
    #expect(fixture.delays == [100_000_000, 20_000_000])
    #expect(fixture.clipboard.text == "transcript")
    #expect(fixture.restoreContinuation == nil)
  }

  @Test func capsLockDoesNotBlockPasting() async {
    let fixture = Fixture()
    fixture.flags = .maskAlphaShift
    let result = await fixture.makeService().pasteToFocusedApp(
      "transcript", targetProcessIdentifier: 42, restoreClipboard: false)
    #expect(result == .posted)
    #expect(fixture.posts == [42])
  }

  @Test func clipboardWriteFailureDoesNotPostOrLoseOriginalContents() async {
    let fixture = Fixture()
    let original = fixture.clipboard.items
    fixture.clipboard.canWriteText = false
    let result = await fixture.makeService().pasteToFocusedApp("transcript", targetProcessIdentifier: 42)
    #expect(result == .failed(.clipboardWriteFailed, copiedToClipboard: false))
    #expect(fixture.posts.isEmpty)
    #expect(fixture.clipboard.items == original)
  }

  @Test func aNewCopyDuringPreparationPreventsPasteAndIsPreserved() async {
    let fixture = Fixture()
    fixture.onSleep = { _ in _ = fixture.clipboard.writeText("new copy") }
    let result = await fixture.makeService().pasteToFocusedApp("transcript", targetProcessIdentifier: 42)
    #expect(result == .failed(.clipboardChanged, copiedToClipboard: false))
    #expect(fixture.posts.isEmpty)
    #expect(fixture.clipboard.text == "new copy")
    #expect(fixture.clipboard.restoreCount == 0)
    #expect(PasteService.Failure.clipboardChanged.errorMessage(
      copiedToClipboard: false, historyEnabled: true).contains("History"))
    #expect(!PasteService.Failure.clipboardChanged.errorMessage(
      copiedToClipboard: false, historyEnabled: false).contains("History"))
  }

  @Test func restoreWaitsForSlowReadersAndPreservesEveryRepresentation() async throws {
    let fixture = Fixture()
    fixture.clipboard.items = [
      [.string: Data("original".utf8), .rtf: Data([1, 2, 3])],
      [.png: Data([4, 5, 6])],
    ]
    let original = fixture.clipboard.items
    let service = fixture.makeService()
    #expect(await service.pasteToFocusedApp("transcript", targetProcessIdentifier: 42) == .posted)
    let restore = try await fixture.takeRestoreContinuation()
    // The recipient can still read the transcript throughout the full grace period.
    #expect(fixture.delays.last == 2_000_000_000)
    #expect(fixture.clipboard.text == "transcript")
    #expect(fixture.clipboard.restoreCount == 0)
    restore.resume()
    await fixture.waitForRestoreCount(1)
    #expect(fixture.clipboard.items == original)
  }

  @Test func delayedRestoreDoesNotOverwriteANewUserCopy() async throws {
    let fixture = Fixture()
    let service = fixture.makeService()
    #expect(await service.pasteToFocusedApp("transcript", targetProcessIdentifier: 42) == .posted)
    let restore = try await fixture.takeRestoreContinuation()
    _ = fixture.clipboard.writeText("new copy")
    restore.resume()
    for _ in 0..<100 { await Task.yield() }
    #expect(fixture.clipboard.text == "new copy")
    #expect(fixture.clipboard.restoreCount == 0)
  }

  @Test func anOriginallyEmptyClipboardIsRestoredToEmpty() async throws {
    let fixture = Fixture()
    fixture.clipboard.items = []
    let service = fixture.makeService()
    #expect(await service.pasteToFocusedApp("transcript", targetProcessIdentifier: 42) == .posted)
    let restore = try await fixture.takeRestoreContinuation()
    restore.resume()
    await fixture.waitForRestoreCount(1)
    #expect(fixture.clipboard.items.isEmpty)
  }

  @Test func consecutivePastesHonorTheFirstReadersGracePeriod() async throws {
    let fixture = Fixture()
    let original = fixture.clipboard.items
    let service = fixture.makeService()
    #expect(await service.pasteToFocusedApp("first", targetProcessIdentifier: 42) == .posted)
    let firstRestore = try await fixture.takeRestoreContinuation()
    let second = Task { await service.pasteToFocusedApp("second", targetProcessIdentifier: 42) }
    for _ in 0..<100 { await Task.yield() }
    #expect(fixture.posts == [42])
    #expect(fixture.clipboard.text == "first")
    #expect(fixture.clipboard.restoreCount == 0)
    firstRestore.resume()
    #expect(await second.value == .posted)
    #expect(fixture.posts == [42, 42])
    #expect(fixture.clipboard.text == "second")
    #expect(fixture.clipboard.restoreCount == 1)
    let secondRestore = try await fixture.takeRestoreContinuation()
    secondRestore.resume()
    await fixture.waitForRestoreCount(2)
    #expect(fixture.clipboard.items == original)
  }

  @Test func cancellationDuringPreparationDoesNotPost() async throws {
    let fixture = Fixture()
    let original = fixture.clipboard.items
    var preparation: CheckedContinuation<Void, Never>?
    fixture.onSleep = { _ in await withCheckedContinuation { preparation = $0 } }
    let service = fixture.makeService()
    let task = Task { await service.pasteToFocusedApp("transcript", targetProcessIdentifier: 42) }
    for _ in 0..<1000 where preparation == nil { await Task.yield() }
    let continuation = try #require(preparation)
    task.cancel()
    continuation.resume()
    #expect(await task.value == .cancelled)
    #expect(fixture.posts.isEmpty)
    #expect(fixture.clipboard.items == original)
  }

  @Test func cancellationBeforePreparationDoesNotTouchTheClipboard() async {
    let fixture = Fixture()
    let original = fixture.clipboard.items
    let service = fixture.makeService()
    let task = Task { await service.pasteToFocusedApp("transcript", targetProcessIdentifier: 42) }
    task.cancel()
    #expect(await task.value == .cancelled)
    #expect(fixture.posts.isEmpty)
    #expect(fixture.clipboard.items == original)
    #expect(fixture.clipboard.changeCount == 0)
  }

  @Test func cancellingAConsecutivePasteStillLetsThePreviousRecipientRead() async throws {
    let fixture = Fixture()
    let original = fixture.clipboard.items
    let service = fixture.makeService()
    #expect(await service.pasteToFocusedApp("first", targetProcessIdentifier: 42) == .posted)
    let restore = try await fixture.takeRestoreContinuation()
    let next = Task { await service.pasteToFocusedApp("second", targetProcessIdentifier: 42) }
    for _ in 0..<100 { await Task.yield() }
    next.cancel()
    #expect(fixture.clipboard.text == "first")
    #expect(fixture.posts == [42])
    restore.resume()
    #expect(await next.value == .cancelled)
    #expect(fixture.clipboard.items == original)
    #expect(fixture.posts == [42])
  }

  @Test func concurrentPasteCannotReplaceAnInFlightPaste() async throws {
    let fixture = Fixture()
    var preparation: CheckedContinuation<Void, Never>?
    fixture.onSleep = { _ in await withCheckedContinuation { preparation = $0 } }
    let service = fixture.makeService()
    let first = Task {
      await service.pasteToFocusedApp("first", targetProcessIdentifier: 42, restoreClipboard: false)
    }
    for _ in 0..<1000 where preparation == nil { await Task.yield() }
    let continuation = try #require(preparation)
    #expect(await service.pasteToFocusedApp("second", targetProcessIdentifier: 42) ==
      .failed(.busy, copiedToClipboard: false))
    #expect(fixture.clipboard.text == "first")
    continuation.resume()
    #expect(await first.value == .posted)
    #expect(fixture.posts == [42])
  }

  @Test(arguments: ["restart", "clear", "reset", "another error"])
  func pasteRecoveryHintClearsWhenTheErrorIsResolved(action: String) {
    let state = AppState()
    let failure = PasteService.Failure.eventCreationFailed
    state.setError(
      failure.errorMessage(copiedToClipboard: true, historyEnabled: true),
      recoveryHint: failure.recoveryHint(copiedToClipboard: true, historyEnabled: true))
    #expect(state.status == .error)
    #expect(state.errorRecoveryHint == "Press ⌘V to paste")
    switch action {
    case "restart": state.updateStatus(.initiatingRecording)
    case "clear": state.clearError()
    case "reset": state.resetToIdle()
    default: state.setError("A different error")
    }
    #expect(state.errorRecoveryHint == nil)
  }
}

@MainActor
private final class MemoryPasteboard: PasteboardAccess {
  var items: ClipboardContents = [[.string: Data("original".utf8)]]
  var changeCount = 0
  var restoreCount = 0
  var canWriteText = true
  var text: String? { items.first?[.string].flatMap { String(data: $0, encoding: .utf8) } }

  func contents() -> ClipboardContents { items }

  func writeText(_ text: String) -> Bool {
    changeCount += 1
    items = []
    guard canWriteText else { return false }
    items = [[.string: Data(text.utf8)]]
    return true
  }

  func restore(_ contents: ClipboardContents) -> Bool {
    changeCount += 1
    restoreCount += 1
    items = contents
    return true
  }
}

@MainActor
private final class Fixture {
  let clipboard = MemoryPasteboard()
  var hasPermission = true
  var frontmostPID: pid_t? = 42
  var flags: CGEventFlags = []
  var canPost = true
  var posts: [pid_t] = []
  var delays: [UInt64] = []
  var onSleep: (UInt64) async -> Void = { _ in }
  var restoreContinuation: CheckedContinuation<Void, Never>?

  func makeService() -> PasteService {
    PasteService(
      pasteboard: clipboard,
      environment: PasteService.Environment(
        hasAccessibilityPermission: { self.hasPermission },
        frontmostProcessIdentifier: { self.frontmostPID },
        modifierFlags: { self.flags },
        postPaste: { pid in
          guard self.canPost else { return false }
          self.posts.append(pid)
          return true
        },
        sleep: { delay in
          self.delays.append(delay)
          if delay == PasteService.clipboardRestoreDelayNanoseconds {
            await withCheckedContinuation { self.restoreContinuation = $0 }
          } else {
            await self.onSleep(delay)
          }
        }
      )
    )
  }

  func takeRestoreContinuation() async throws -> CheckedContinuation<Void, Never> {
    for _ in 0..<1000 where restoreContinuation == nil { await Task.yield() }
    let continuation = try #require(restoreContinuation)
    restoreContinuation = nil
    return continuation
  }

  func waitForRestoreCount(_ count: Int) async {
    for _ in 0..<1000 where clipboard.restoreCount < count { await Task.yield() }
    #expect(clipboard.restoreCount == count)
  }
}
