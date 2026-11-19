import AppKit
import Testing

@testable import Echo

@MainActor
@Suite("Notes mode lifecycle and export")
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

  @Test func exportGeneratesTitleFromAllNotesAndKeepsMarkdownUnchanged() async throws {
    let fixture = try Fixture(title: "  \"Keep\tNotes Controls\nVisible\"  ")
    defer { fixture.cleanUp() }

    fixture.service.start()
    fixture.service.addTranscription("Keep the Notes button visible.")
    fixture.service.addTranscription("Restore normal clicks when recording stops.")
    let export = try #require(fixture.service.stop())
    await export.value

    let htmlURL = try #require(fixture.openedDocuments.first)
    let html = try String(contentsOf: htmlURL, encoding: .utf8)
    let markdown = try String(
      contentsOf: htmlURL.deletingLastPathComponent().appendingPathComponent("note.md"),
      encoding: .utf8
    )
    #expect(fixture.requests.count == 2)
    #expect(fixture.requests.allSatisfy {
      $0.text == "Keep the Notes button visible.\n\nRestore normal clicks when recording stops."
        && $0.model == PostProcessingModelOption.defaultOptionValue
    })
    #expect(html.contains("<div class=\"change-title\">Keep Notes Controls Visible</div>"))
    #expect(html.contains("Cleaned note"))
    #expect(markdown.hasPrefix("# Echo Note — "))
    #expect(markdown.contains("Keep the Notes button visible."))
    #expect(!markdown.contains("Keep Notes Controls Visible"))
  }

  @Test(arguments: ["", " \n\t ", "\" \"", String(repeating: "x", count: 121)])
  func invalidTitlesUseFallback(_ title: String) async throws {
    let fixture = try Fixture(title: title)
    defer { fixture.cleanUp() }
    fixture.service.start()
    fixture.service.addTranscription("Keep the Notes button visible.")
    await fixture.service.stop()?.value

    let htmlURL = try #require(fixture.openedDocuments.first)
    let html = try String(contentsOf: htmlURL, encoding: .utf8)
    #expect(html.contains("<div class=\"change-title\">Echo Note — "))
    #expect(html.contains("Cleaned note"))
  }

  @Test(arguments: [true, false])
  func titleAndCleanupFailuresAreIndependent(titleFails: Bool) async throws {
    let fixture = try Fixture(titleFails: titleFails, cleanupFails: !titleFails)
    defer { fixture.cleanUp() }
    fixture.service.start()
    fixture.service.addTranscription("Keep the Notes button visible.")
    await fixture.service.stop()?.value

    let htmlURL = try #require(fixture.openedDocuments.first)
    let html = try String(contentsOf: htmlURL, encoding: .utf8)
    #expect(html.contains("Keep the Notes button visible."))
    #expect(html.contains("<div class=\"change-title\">Echo Note — ") == titleFails)
    #expect(html.contains("<div class=\"change-title\">Keep Notes Controls Visible</div>") == !titleFails)
    #expect(html.contains("could not be generated") == !titleFails)
    #expect(html.contains("Cleaned note") == titleFails)
  }

  @Test func missingAPIKeyStillExportsTheNote() async throws {
    let fixture = try Fixture(titleFails: true, cleanupFails: true)
    defer { fixture.cleanUp() }
    fixture.service.start()
    fixture.service.addTranscription("Keep the Notes button visible.")
    await fixture.service.stop()?.value

    let htmlURL = try #require(fixture.openedDocuments.first)
    let html = try String(contentsOf: htmlURL, encoding: .utf8)
    #expect(html.contains("<div class=\"change-title\">Echo Note — "))
    #expect(html.contains("could not be generated"))
    #expect(FileManager.default.fileExists(
      atPath: htmlURL.deletingLastPathComponent().appendingPathComponent("note.md").path
    ))
  }

  @Test func emptySessionsDoNotGenerateOrOpenAnything() throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    fixture.service.start()
    #expect(fixture.service.stop() == nil)
    #expect(fixture.requests.isEmpty)
    #expect(fixture.openedDocuments.isEmpty)
  }

  @Test func exportEmbedsScreenshotsFromItsOwnSessionBeforeOpening() async throws {
    let image = try #require(Data(base64Encoded:
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC"
    ))
    let fixture = try Fixture(screenshotData: image)
    defer { fixture.cleanUp() }
    fixture.service.start()
    await fixture.service.captureScreenshotForNextEntry()
    fixture.service.addTranscription("First screenshot")
    await fixture.service.captureScreenshotForNextEntry()
    fixture.service.addTranscription("Second screenshot")
    let export = try #require(fixture.service.stop())
    fixture.service.start()
    await export.value

    let htmlURL = try #require(fixture.openedDocuments.first)
    // The copied fragment must remain usable after the export's images are removed.
    try FileManager.default.removeItem(
      at: htmlURL.deletingLastPathComponent().appendingPathComponent("images")
    )
    let html = try String(contentsOf: htmlURL, encoding: .utf8)
    let json = try #require(
      html.components(separatedBy: "id=\"copy-data\" type=\"application/json\">").last
    ).components(separatedBy: "</script>")[0]
    let payload = try #require(
      JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: String]
    )
    let noteHTML = try #require(payload["noteHTML"])
    #expect(noteHTML.components(separatedBy: "data:image/png;base64,\(image.base64EncodedString())").count - 1 == 2)
    #expect(!noteHTML.contains("images/"))
    #expect(!noteHTML.contains("Screenshot unavailable"))
    #expect(fixture.service.isActive)
  }

  @Test func exportRemainsIsolatedWhenAnotherSessionStarts() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    fixture.service.start()
    fixture.service.addTranscription("First session note.")
    let firstExport = try #require(fixture.service.stop())
    fixture.service.start()
    fixture.service.addTranscription("Second session note.")
    await firstExport.value
    #expect(fixture.service.isActive)

    let secondExport = try #require(fixture.service.stop())
    await secondExport.value
    #expect(fixture.openedDocuments.count == 2)
    let firstURL = fixture.openedDocuments[0]
    let secondURL = fixture.openedDocuments[1]
    #expect(firstURL != secondURL)
    let firstHTML = try String(contentsOf: firstURL, encoding: .utf8)
    let secondHTML = try String(contentsOf: secondURL, encoding: .utf8)
    #expect(firstHTML.contains("First session note."))
    #expect(!firstHTML.contains("Second session note."))
    #expect(secondHTML.contains("Second session note."))
    #expect(!secondHTML.contains("First session note."))
  }

  @MainActor
  private final class Fixture {
    let overlay = OverlayDouble()
    let directory: URL
    private(set) var service: NotesModeService!
    var captures: [ScreenAnnotation?] = []
    var requests: [(text: String, prompt: String, model: String)] = []
    var openedDocuments: [URL] = []

    init(
      screenshotsAvailable: Bool = true,
      title: String = "Keep Notes Controls Visible",
      titleFails: Bool = false,
      cleanupFails: Bool = false,
      screenshotData: Data? = nil
    ) throws {
      directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("notes-drawing-tests-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      service = NotesModeService(
        annotationOverlay: overlay,
        requestScreenshotPermission: { screenshotsAvailable },
        sessionRootDirectory: directory,
        captureScreenshot: { [unowned self] url, annotation in
          captures.append(annotation)
          if let screenshotData {
            do {
              try screenshotData.write(to: url)
              return true
            } catch {
              return false
            }
          }
          return false
        },
        processText: { [unowned self] text, prompt, model in
          requests.append((text, prompt, model))
          let isTitle = prompt.contains("change title")
          if isTitle ? titleFails : cleanupFails {
            throw PostProcessingError.missingAPIKey(.groq)
          }
          return isTitle ? title : "Cleaned note"
        },
        openDocument: { [unowned self] in openedDocuments.append($0) }
      )
    }

    func cleanUp() {
      service.stop() // Tests await any nonempty export before cleaning up.
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
