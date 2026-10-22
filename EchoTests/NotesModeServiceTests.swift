import AppKit
import Testing

@testable import Echo

@MainActor
@Suite("Notes drawing lifecycle")
struct NotesModeServiceTests {
  @Test func drawingFollowsRecordingWithoutAKeyboardEvent() throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }

    fixture.service.start()
    #expect(!fixture.service.isDrawing)
    fixture.service.setRecording(true)
    #expect(fixture.service.isDrawing)
    fixture.service.setRecording(true)
    #expect(fixture.overlay.events == ["enabled:true"])

    fixture.service.setRecording(false)
    fixture.service.setRecording(false)
    #expect(!fixture.service.isDrawing)
    #expect(fixture.overlay.events == ["enabled:true", "enabled:false", "take"])
  }

  @Test func notesCanStartAndRestartDuringTheSameRecording() throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }

    fixture.service.setRecording(true)
    #expect(!fixture.service.isDrawing)
    fixture.service.start()
    #expect(fixture.service.isDrawing)
    fixture.overlay.annotation = Fixture.annotation()
    fixture.service.stop()
    #expect(!fixture.service.isDrawing)
    #expect(fixture.overlay.annotation == nil)

    fixture.service.start()
    #expect(fixture.service.isDrawing)
    #expect(fixture.overlay.events == ["enabled:true", "close", "enabled:true"])
  }

  @Test func deniedScreenRecordingPermissionLeavesClicksAlone() throws {
    let fixture = try Fixture(screenshotsAvailable: false)
    defer { fixture.cleanUp() }

    fixture.service.setRecording(true)
    fixture.service.start()
    #expect(fixture.service.isActive)
    #expect(!fixture.service.screenshotsAvailable)
    #expect(!fixture.service.isDrawing)
    #expect(fixture.overlay.events.isEmpty)
  }

  @Test func completedDrawingIsPassedToOnlyOneScreenshot() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }

    fixture.service.start()
    fixture.service.setRecording(true)
    fixture.overlay.annotation = Fixture.annotation()
    fixture.service.setRecording(false)
    #expect(fixture.overlay.events.suffix(2) == ["enabled:false", "take"])
    #expect(fixture.overlay.annotation == nil)

    await fixture.service.captureScreenshotForNextEntry()
    await fixture.service.captureScreenshotForNextEntry()
    #expect(fixture.captures.count == 2)
    #expect(fixture.captures[0]?.strokes == Fixture.annotation().strokes)
    #expect(fixture.captures[1] == nil)
  }

  @Test func discardedRecordingCannotLeakMarksIntoNextRecording() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }

    fixture.service.start()
    fixture.service.setRecording(true)
    fixture.overlay.annotation = Fixture.annotation()
    fixture.service.setRecording(false)
    // Cancellation and no-speech paths discard the entry rather than capturing it.
    fixture.service.discardPendingScreenshot()
    fixture.service.setRecording(true)
    fixture.service.setRecording(false)
    await fixture.service.captureScreenshotForNextEntry()

    #expect(fixture.captures.count == 1)
    #expect(fixture.captures[0] == nil)
  }

  @Test func stoppingNotesDropsThePendingDrawing() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }

    fixture.service.start()
    fixture.service.setRecording(true)
    fixture.overlay.annotation = Fixture.annotation()
    fixture.service.setRecording(false)
    fixture.service.stop()
    fixture.service.start()
    await fixture.service.captureScreenshotForNextEntry()

    #expect(!fixture.service.isDrawing)
    #expect(fixture.captures.count == 1)
    #expect(fixture.captures[0] == nil)
  }

  @MainActor
  private final class Fixture {
    let overlay = OverlayDouble()
    let directory: URL
    private(set) var service: NotesModeService!
    var captures: [ScreenAnnotation?] = []

    init(screenshotsAvailable: Bool = true) throws {
      directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("notes-drawing-tests-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      service = NotesModeService(
        annotationOverlay: overlay,
        requestScreenshotPermission: { screenshotsAvailable },
        sessionRootDirectory: directory,
        captureScreenshot: { [unowned self] _, annotation in
          captures.append(annotation)
          return false
        }
      )
    }

    func cleanUp() {
      service.stop() // No entries, so this never exports or opens a document.
      try? FileManager.default.removeItem(at: directory)
    }

    static func annotation() -> ScreenAnnotation {
      ScreenAnnotation(screen: NSScreen(), strokes: [[CGPoint(x: 20, y: 30), CGPoint(x: 80, y: 90)]])
    }
  }

  private final class OverlayDouble: ScreenAnnotationPresenting {
    var events: [String] = []
    var annotation: ScreenAnnotation?

    func setDrawingEnabled(_ enabled: Bool) {
      events.append("enabled:\(enabled)")
    }

    func takeAnnotation() -> ScreenAnnotation? {
      events.append("take")
      defer { annotation = nil }
      return annotation
    }

    func close() {
      events.append("close")
      annotation = nil
    }
  }
}
