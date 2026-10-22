import AppKit
import SwiftUI

/// Manages notes mode: while active, each recording's transcription is appended to a
/// single note (with a screenshot taken when the recording stopped) instead of being
/// pasted. Dragging while recording draws over the screen; the drawing goes into
/// that recording's screenshot, which is cropped to the marked area. Stopping the mode
/// exports the note as an HTML file in the temp folder and opens it.
@MainActor
final class NotesModeService: ObservableObject {
  static let shared = NotesModeService()

  @Published private(set) var isActive = false
  @Published private(set) var screenshotsAvailable = true
  @Published private(set) var isDrawing = false

  private var entries: [NoteEntry] = []
  private var sessionDirectory: URL?
  private var imagesDirectory: URL?
  private var sessionStartDate: Date?
  private var pendingScreenshotFileName: String?
  private var screenshotCounter = 0
  private let annotationOverlay: ScreenAnnotationPresenting
  private let requestScreenshotPermission: () -> Bool
  private let sessionRootDirectory: URL
  private let captureScreenshot: (URL, ScreenAnnotation?) async -> Bool
  private var isRecording = false
  /// The drawing from the recording that just ended, waiting for its screenshot.
  private var pendingAnnotation: ScreenAnnotation?
  private let loggerCategory = "NotesModeService"

  private convenience init() {
    self.init(
      annotationOverlay: ScreenAnnotationOverlay(),
      requestScreenshotPermission: { ScreenshotService.requestPermissionIfNeeded() },
      sessionRootDirectory: FileManager.default.temporaryDirectory,
      captureScreenshot: { await ScreenshotService.capturePNG(to: $0, annotation: $1) }
    )
  }

  init(
    annotationOverlay: ScreenAnnotationPresenting,
    requestScreenshotPermission: @escaping () -> Bool,
    sessionRootDirectory: URL,
    captureScreenshot: @escaping (URL, ScreenAnnotation?) async -> Bool
  ) {
    self.annotationOverlay = annotationOverlay
    self.requestScreenshotPermission = requestScreenshotPermission
    self.sessionRootDirectory = sessionRootDirectory
    self.captureScreenshot = captureScreenshot
  }

  func toggle() {
    if isActive {
      stop()
    } else {
      start()
    }
  }

  func start() {
    guard !isActive else { return }

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd-HHmmss"
    let startDate = Date()

    let sessionDir = sessionRootDirectory
      .appendingPathComponent("echo", isDirectory: true)
      .appendingPathComponent("notes", isDirectory: true)
      .appendingPathComponent("note-\(formatter.string(from: startDate))", isDirectory: true)
    let imagesDir = sessionDir.appendingPathComponent("images", isDirectory: true)

    do {
      try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
    } catch {
      log(
        "Failed to create notes session directory: \(error)",
        category: loggerCategory,
        level: .error
      )
      return
    }

    sessionDirectory = sessionDir
    imagesDirectory = imagesDir
    sessionStartDate = startDate
    entries = []
    pendingScreenshotFileName = nil
    screenshotCounter = 0
    screenshotsAvailable = requestScreenshotPermission()
    isActive = true
    updateDrawing()

    log("Notes mode started, session at \(sessionDir.path)", category: loggerCategory, level: .info)
  }

  /// Ends the session and exports the note: a markdown file plus an HTML page with
  /// note/transcript/cleaned-up views, then opens the HTML. The cleaned-up version
  /// is produced by the LLM post-processing pipeline and is skipped on failure.
  /// Sessions with no entries are discarded.
  func stop() {
    guard isActive else { return }
    isActive = false
    isDrawing = false
    annotationOverlay.close()
    pendingAnnotation = nil
    discardPendingScreenshot()

    let exportEntries = entries
    let exportDirectory = sessionDirectory
    let exportStartDate = sessionStartDate ?? Date()

    sessionDirectory = nil
    imagesDirectory = nil
    sessionStartDate = nil
    entries = []

    guard let exportDirectory else { return }

    guard !exportEntries.isEmpty else {
      log("Notes mode stopped with no entries; discarding session", category: loggerCategory, level: .info)
      try? FileManager.default.removeItem(at: exportDirectory)
      return
    }

    Task {
      await self.exportNote(entries: exportEntries, startedAt: exportStartDate, to: exportDirectory)
    }
  }

  /// Prompt for the cleaned-up view; `{{TRANSCRIPTION}}` is replaced with the
  /// plain transcript by `PostProcessingService`.
  private static let cleanupPromptTemplate = """
    You are cleaning up a note that was dictated with speech-to-text. Fix \
    transcription and punctuation errors, remove filler words and false starts, \
    and organize the text into clear paragraphs. Preserve every piece of \
    information and the original meaning — do not add new content or commentary. \
    Return only the cleaned-up note.

    {{TRANSCRIPTION}}
    """

  private func exportNote(entries: [NoteEntry], startedAt: Date, to directory: URL) async {
    let transcript = NoteHTMLBuilder.plainTranscript(entries: entries)

    var cleanedText: String?
    do {
      cleanedText = try await PostProcessingService.shared.processText(
        transcript,
        promptTemplate: Self.cleanupPromptTemplate,
        postProcessingModel: PostProcessingModelOption.defaultOptionValue
      )
    } catch {
      log(
        "Note cleanup failed; exporting without cleaned-up version: \(error)",
        category: loggerCategory,
        level: .warning
      )
    }

    let markdownURL = directory.appendingPathComponent("note.md")
    let htmlURL = directory.appendingPathComponent("note.html")
    let markdown = NoteHTMLBuilder.renderMarkdown(entries: entries, startedAt: startedAt)
    let html = NoteHTMLBuilder.render(
      entries: entries,
      startedAt: startedAt,
      cleanedText: cleanedText,
      markdownFilePath: markdownURL.path
    )

    do {
      try markdown.write(to: markdownURL, atomically: true, encoding: .utf8)
      try html.write(to: htmlURL, atomically: true, encoding: .utf8)
      log(
        "Notes mode exported \(entries.count) entries to \(htmlURL.path)",
        category: loggerCategory,
        level: .info
      )
      NSWorkspace.shared.open(htmlURL)
    } catch {
      log("Failed to write note export: \(error)", category: loggerCategory, level: .error)
    }
  }

  /// Called when a recording stops while notes mode is active. Captures the screen
  /// immediately so it reflects what the user was looking at while dictating; the
  /// screenshot is paired with the transcription once it arrives.
  func captureScreenshotForNextEntry() async {
    guard isActive, screenshotsAvailable, let imagesDirectory else { return }

    // A leftover capture from a cancelled recording is superseded by this one
    discardPendingScreenshot()

    screenshotCounter += 1
    let fileName = "screenshot-\(screenshotCounter).png"
    let fileURL = imagesDirectory.appendingPathComponent(fileName)

    let annotation = pendingAnnotation
    pendingAnnotation = nil
    guard await captureScreenshot(fileURL, annotation) else { return }

    if isActive {
      pendingScreenshotFileName = fileName
    } else {
      // Session ended while the capture was in flight
      try? FileManager.default.removeItem(at: fileURL)
    }
  }

  /// Appends transcribed text to the note, paired with the pending screenshot.
  func addTranscription(_ text: String) {
    guard isActive else { return }
    let entry = NoteEntry(
      timestamp: Date(),
      text: text,
      screenshotFileName: pendingScreenshotFileName
    )
    pendingScreenshotFileName = nil
    entries.append(entry)
    log("Added entry #\(entries.count) to note", category: loggerCategory, level: .info)
  }

  /// Drops a screenshot that never got paired with a transcription (e.g. the
  /// recording was cancelled while processing).
  func discardPendingScreenshot() {
    guard let fileName = pendingScreenshotFileName else { return }
    pendingScreenshotFileName = nil
    if let imagesDirectory {
      try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(fileName))
    }
  }

  // MARK: - Drawing

  /// A drawing belongs to one recording. When the recording ends the drawing leaves the
  /// screen, held for the screenshot taken if the recording goes on to be transcribed.
  func setRecording(_ recording: Bool) {
    guard recording != isRecording else { return }
    isRecording = recording
    updateDrawing()
    pendingAnnotation = recording ? nil : annotationOverlay.takeAnnotation()
  }

  /// Drawing is pointless without screenshots, so it stays off when they are.
  private func updateDrawing() {
    let enabled = isRecording && isActive && screenshotsAvailable
    guard enabled != isDrawing else { return }
    isDrawing = enabled
    annotationOverlay.setDrawingEnabled(enabled)
  }
}
