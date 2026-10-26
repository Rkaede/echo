import XCTest

@testable import Echo

final class NoteHTMLBuilderXCTests: XCTestCase {
  private func render(
    entries: [NoteEntry],
    cleanedText: String? = "Cleaned version",
    markdownFilePath: String = "/tmp/echo/notes/note-test/note.md",
    changeTitle: String? = "Keep Notes Controls Visible While Recording",
    screenshots: [String: Data] = [:]
  ) -> String {
    NoteHTMLBuilder.render(
      entries: entries,
      startedAt: Date(),
      cleanedText: cleanedText,
      markdownFilePath: markdownFilePath,
      changeTitle: changeTitle,
      screenshots: screenshots
    )
  }

  func testEscapeReplacesHTMLSpecialCharacters() {
    XCTAssertEqual(
      NoteHTMLBuilder.escape(#"a & b < c > "d""#),
      "a &amp; b &lt; c &gt; &quot;d&quot;"
    )
  }

  func testRenderIncludesEntriesAndScreenshots() {
    let entries = [
      NoteEntry(timestamp: Date(), text: "First <note>", screenshotFileName: "screenshot-1.png"),
      NoteEntry(timestamp: Date(), text: "Second note", screenshotFileName: nil),
    ]
    let html = render(entries: entries)

    XCTAssertTrue(html.contains("First &lt;note&gt;"))
    XCTAssertTrue(html.contains("Second note"))
    XCTAssertTrue(html.contains("images/screenshot-1.png"))
    XCTAssertTrue(html.contains("2 entries"))

    let noteView = html.components(separatedBy: "id=\"view-note\"")[1]
      .components(separatedBy: "id=\"view-transcript\"")[0]
    XCTAssertEqual(noteView.components(separatedBy: "<article class=\"entry\"").count - 1, 2)
    XCTAssertEqual(html.components(separatedBy: "<img").count - 1, 1)
  }

  func testRenderSingleEntryUsesSingularLabel() {
    let entries = [NoteEntry(timestamp: Date(), text: "Only one", screenshotFileName: nil)]
    let html = render(entries: entries)

    XCTAssertTrue(html.contains("1 entry"))
  }

  func testRenderIncludesFormatTabsAndCopyControls() {
    let entries = [NoteEntry(timestamp: Date(), text: "Hello", screenshotFileName: nil)]
    let html = render(entries: entries, markdownFilePath: "/tmp/note-abc/note.md")

    XCTAssertTrue(html.contains("data-view=\"note\""))
    XCTAssertTrue(html.contains("data-view=\"transcript\""))
    XCTAssertTrue(html.contains("data-view=\"cleaned\""))
    XCTAssertTrue(html.contains("id=\"copy-content\""))
    XCTAssertTrue(html.contains("id=\"copy-md-path\""))
    XCTAssertTrue(html.contains("id=\"copy-data\""))
    XCTAssertTrue(html.contains(#"\/tmp\/note-abc\/note.md"#))
  }

  func testRenderIncludesCleanedTextWhenAvailable() {
    let entries = [NoteEntry(timestamp: Date(), text: "Raw text", screenshotFileName: nil)]
    let html = render(entries: entries, cleanedText: "Polished text")

    XCTAssertTrue(html.contains("Polished text"))
    XCTAssertFalse(html.contains("could not be generated"))
  }

  func testRenderShowsFallbackWhenCleanedTextMissing() {
    let entries = [NoteEntry(timestamp: Date(), text: "Raw text", screenshotFileName: nil)]
    let html = render(entries: entries, cleanedText: nil)

    XCTAssertTrue(html.contains("could not be generated"))
    XCTAssertFalse(html.contains("\"cleaned\":"))
  }

  func testCopyDataEscapesScriptBreakout() throws {
    let entries = [
      NoteEntry(timestamp: Date(), text: "Sneaky </script> content", screenshotFileName: nil)
    ]
    let html = render(entries: entries)

    let copyData = html.components(separatedBy: "id=\"copy-data\" type=\"application/json\">")[1]
      .components(separatedBy: "</script>")[0]
    let escapedLessThan = #"\"# + "u003c"
    XCTAssertFalse(copyData.contains("<"))
    XCTAssertTrue(copyData.contains(escapedLessThan))

    let parsed = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(copyData.utf8)) as? [String: String]
    )
    XCTAssertEqual(parsed["transcript"], "Sneaky </script> content")
  }

  func testRenderIncludesCopyHTMLButtonAndRichPayload() throws {
    let entries = [
      NoteEntry(timestamp: Date(), text: "Line one\nLine <two>", screenshotFileName: "shot.png"),
      NoteEntry(timestamp: Date(), text: "Second", screenshotFileName: nil),
    ]
    let image = try XCTUnwrap(Data(base64Encoded:
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC"
    ))
    let html = render(
      entries: entries, cleanedText: "Para one\n\nPara two", screenshots: ["shot.png": image]
    )
    let payload = try copyPayload(html)

    XCTAssertTrue(html.contains("id=\"copy-html\""))
    XCTAssertTrue(html.contains(">Copy HTML</button>"))
    XCTAssertTrue(html.contains("ClipboardItem"))

    let noteHTML = try XCTUnwrap(payload["noteHTML"])
    XCTAssertTrue(noteHTML.contains("<h2>Keep Notes Controls Visible While Recording</h2>"))
    XCTAssertTrue(noteHTML.contains("<p>Line one<br>Line &lt;two&gt;</p>"))
    XCTAssertTrue(noteHTML.contains("<p>Second</p>"))
    XCTAssertTrue(noteHTML.contains("<img src=\"data:image/png;base64,\(image.base64EncodedString())\""))
    XCTAssertFalse(noteHTML.contains("images/"))
    XCTAssertFalse(noteHTML.contains("file:"))
    XCTAssertEqual(noteHTML.components(separatedBy: "<h3>").count - 1, 2)

    XCTAssertEqual(
      payload["transcriptHTML"],
      "<p>Line one<br>Line &lt;two&gt;</p>\n<p>Second</p>"
    )
    XCTAssertEqual(payload["cleanedHTML"], "<p>Para one</p>\n<p>Para two</p>")
  }

  func testClipboardScreenshotsKeepTheirBytesAndEntryOrder() throws {
    let first = try XCTUnwrap(Data(base64Encoded:
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC"
    ))
    let second = try XCTUnwrap(Data(base64Encoded:
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNgYPgPAAEDAQAIicLsAAAAAElFTkSuQmCC"
    ))
    let entries = [
      NoteEntry(timestamp: Date(), text: "First <entry>", screenshotFileName: "first & shot.png"),
      NoteEntry(timestamp: Date(), text: "Text only", screenshotFileName: nil),
      NoteEntry(timestamp: Date(), text: "Last entry", screenshotFileName: "last.png"),
    ]
    let payload = try copyPayload(render(
      entries: entries, screenshots: ["first & shot.png": first, "last.png": second]
    ))
    let html = try XCTUnwrap(payload["noteHTML"])
    let sections = html.components(separatedBy: "<h3>")
    XCTAssertEqual(sections.count, 4)
    XCTAssertTrue(sections[1].contains("First &lt;entry&gt;</p>\n<p><img"))
    XCTAssertFalse(sections[2].contains("<img"))
    XCTAssertTrue(sections[3].contains("Last entry</p>\n<p><img"))
    let images = html.components(separatedBy: "data:image/png;base64,").dropFirst()
      .map { String($0.prefix(while: { $0 != "\"" })) }
    XCTAssertEqual(images.compactMap { Data(base64Encoded: $0) }, [first, second])
    XCTAssertFalse(html.contains("first & shot.png"))
    XCTAssertFalse(html.contains("last.png"))
    XCTAssertFalse(html.contains("images/"))
    XCTAssertFalse(try XCTUnwrap(payload["transcriptHTML"]).contains("<img"))
    XCTAssertFalse(try XCTUnwrap(payload["cleanedHTML"]).contains("<img"))
  }

  func testUnavailableScreenshotIsExplicitWithoutDroppingEntries() throws {
    let entries = [
      NoteEntry(timestamp: Date(), text: "Missing image", screenshotFileName: "missing.png"),
      NoteEntry(timestamp: Date(), text: "Empty image", screenshotFileName: "empty.png"),
      NoteEntry(timestamp: Date(), text: "No screenshot", screenshotFileName: nil),
    ]
    let html = try XCTUnwrap(copyPayload(render(
      entries: entries, screenshots: ["empty.png": Data()]
    ))["noteHTML"])
    XCTAssertEqual(html.components(separatedBy: "Screenshot unavailable").count - 1, 2)
    XCTAssertEqual(html.components(separatedBy: "<h3>").count - 1, 3)
    XCTAssertTrue(html.contains("<p>No screenshot</p>"))
    XCTAssertFalse(html.contains("<img"))
    XCTAssertFalse(html.contains("images/"))
  }

  func testCopyHTMLPayloadOmitsCleanedWhenUnavailable() throws {
    let entries = [NoteEntry(timestamp: Date(), text: "Raw", screenshotFileName: nil)]
    let payload = try copyPayload(render(entries: entries, cleanedText: nil))

    XCTAssertNil(payload["cleanedHTML"])
    XCTAssertNotNil(payload["noteHTML"])
  }

  func testPlainTranscriptJoinsEntriesWithBlankLines() {
    let entries = [
      NoteEntry(timestamp: Date(), text: "First", screenshotFileName: "screenshot-1.png"),
      NoteEntry(timestamp: Date(), text: "Second", screenshotFileName: nil),
    ]

    XCTAssertEqual(NoteHTMLBuilder.plainTranscript(entries: entries), "First\n\nSecond")
  }

  func testTitleAndPathAreCopiedTogetherWithoutChangingViewContents() throws {
    let entries = [NoteEntry(timestamp: Date(), text: "Raw note", screenshotFileName: nil)]
    let title = "Improve \"Notes\" & 日本語 </script>"
    let path = "/tmp/notes with spaces/note.md"
    let html = render(entries: entries, markdownFilePath: path, changeTitle: title)
    let payload = try copyPayload(html)

    XCTAssertTrue(html.contains("<div class=\"change-title\">\(NoteHTMLBuilder.escape(title))</div>"))
    XCTAssertTrue(html.contains(">Copy Title + Path</button>"))
    XCTAssertTrue(html.contains("copyText(copyData.markdownReference, event.currentTarget)"))
    XCTAssertEqual(payload["markdownReference"], "\(title)\n\(path)")
    XCTAssertEqual(payload["transcript"], "Raw note")
    XCTAssertEqual(payload["cleaned"], "Cleaned version")
    XCTAssertTrue(try XCTUnwrap(payload["note"]).hasPrefix("# Echo Note — "))
    XCTAssertFalse(try XCTUnwrap(payload["note"]).contains(title))
  }

  func testMissingTitleUsesDatedFallbackInDisplayAndClipboard() throws {
    let html = render(entries: [], changeTitle: nil)
    let reference = try XCTUnwrap(copyPayload(html)["markdownReference"])
    let lines = reference.components(separatedBy: "\n")

    XCTAssertEqual(lines.count, 2)
    XCTAssertTrue(lines[0].hasPrefix("Echo Note — "))
    XCTAssertEqual(lines[1], "/tmp/echo/notes/note-test/note.md")
    XCTAssertTrue(html.contains("<div class=\"change-title\">\(NoteHTMLBuilder.escape(lines[0]))</div>"))
  }

  private func copyPayload(_ html: String) throws -> [String: String] {
    let json = html.components(separatedBy: "id=\"copy-data\" type=\"application/json\">")[1]
      .components(separatedBy: "</script>")[0]
    XCTAssertFalse(json.contains("<"))
    return try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: String]
    )
  }

  func testRenderMarkdownIncludesEntriesAndImages() {
    let entries = [
      NoteEntry(timestamp: Date(), text: "First note", screenshotFileName: "screenshot-1.png"),
      NoteEntry(timestamp: Date(), text: "Second note", screenshotFileName: nil),
    ]
    let markdown = NoteHTMLBuilder.renderMarkdown(entries: entries, startedAt: Date())

    XCTAssertTrue(markdown.hasPrefix("# Echo Note — "))
    XCTAssertTrue(markdown.contains("First note"))
    XCTAssertTrue(markdown.contains("Second note"))
    XCTAssertTrue(markdown.contains("![Screenshot](images/screenshot-1.png)"))
    XCTAssertEqual(markdown.components(separatedBy: "\n## ").count - 1, 2)
    XCTAssertEqual(markdown.components(separatedBy: "![Screenshot]").count - 1, 1)
  }
}
