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
    XCTAssertFalse(html.contains("2 entries"))
    XCTAssertFalse(html.contains("entry-time"))
    XCTAssertTrue(html.contains(".entry:last-child { border-bottom: 0; }"))

    let noteView = html.components(separatedBy: "id=\"view-note\"")[1]
      .components(separatedBy: "id=\"view-transcript\"")[0]
    XCTAssertEqual(noteView.components(separatedBy: "<article class=\"entry\"").count - 1, 2)
    XCTAssertEqual(html.components(separatedBy: "<img").count - 1, 1)
  }

  func testRenderOmitsEntryCount() {
    let entries = [NoteEntry(timestamp: Date(), text: "Only one", screenshotFileName: nil)]
    let html = render(entries: entries)

    XCTAssertFalse(html.contains("1 entry"))
    XCTAssertFalse(html.contains("entries</div>"))
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
    XCTAssertFalse(noteHTML.contains("<h3>"))
    XCTAssertEqual(noteHTML.components(separatedBy: "<h2>").count - 1, 1)

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
    XCTAssertFalse(html.contains("<h3>"))
    let sections = html.components(separatedBy: "Text only</p>")
    XCTAssertEqual(sections.count, 2)
    XCTAssertTrue(sections[0].contains("First &lt;entry&gt;</p>\n<p><img"))
    XCTAssertFalse(try XCTUnwrap(sections[1].components(separatedBy: "Last entry").first).contains("<img"))
    XCTAssertTrue(sections[1].contains("Last entry</p>\n<p><img"))
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
    XCTAssertFalse(html.contains("<h3>"))
    XCTAssertTrue(html.contains("<p>No screenshot</p>"))
    XCTAssertFalse(html.contains("<img"))
    XCTAssertFalse(html.contains("images/"))
  }

  func testCopySourceIsIsolatedFromThemedPageStyles() throws {
    let entries = [NoteEntry(timestamp: Date(), text: "Hi", screenshotFileName: "a.png")]
    let html = render(entries: entries)

    let rule = try XCTUnwrap(
      html.components(separatedBy: ".copy-source {")[1].components(separatedBy: "}")[0]
    )
    XCTAssertTrue(rule.contains("all: initial;"))
    XCTAssertTrue(rule.contains("color-scheme: light;"))
    XCTAssertTrue(rule.contains("background: transparent;"))
    XCTAssertFalse(rule.contains("var(--"))

    // Selection copying and the clipboard fallback share one neutral source builder.
    XCTAssertEqual(html.components(separatedBy: "function createCopySource(").count - 1, 1)
    XCTAssertTrue(html.contains("createCopySource(copyData.noteHTML)"))
    XCTAssertTrue(html.contains("imageSource || createCopySource(html)"))
    XCTAssertFalse(html.contains("holder.style.cssText"))

    // `inert` makes the source unselectable, so the copy silently succeeds with nothing.
    XCTAssertFalse(html.contains("inert"))
    XCTAssertTrue(html.contains("if (selection.isCollapsed) return false;"))
    XCTAssertFalse(html.contains("Created with Echo notes mode"))
  }

  func testClipboardHTMLCarriesNoThemeStyling() throws {
    let image = try XCTUnwrap(Data(base64Encoded:
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC"
    ))
    let entries = [NoteEntry(timestamp: Date(), text: "Hi", screenshotFileName: "a.png")]
    let payload = try copyPayload(render(entries: entries, screenshots: ["a.png": image]))

    for key in ["noteHTML", "transcriptHTML", "cleanedHTML"] {
      let html = try XCTUnwrap(payload[key])
      XCTAssertFalse(html.contains("background"), key)
      XCTAssertFalse(html.contains("color"), key)
      XCTAssertFalse(html.contains("class="), key)
      XCTAssertFalse(html.contains("<style"), key)
    }
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

  func testRenderMarkdownIncludesEntriesAndImages() throws {
    let entries = [
      NoteEntry(timestamp: Date(), text: "First note", screenshotFileName: "screenshot-1.png"),
      NoteEntry(timestamp: Date(), text: "Second note", screenshotFileName: nil),
    ]
    let markdown = NoteHTMLBuilder.renderMarkdown(entries: entries, startedAt: Date())

    XCTAssertTrue(markdown.hasPrefix("# Echo Note — "))
    XCTAssertTrue(markdown.contains("First note"))
    XCTAssertTrue(markdown.contains("Second note"))
    XCTAssertTrue(markdown.contains("![Screenshot](images/screenshot-1.png)"))
    XCTAssertFalse(markdown.contains("\n## "))
    let first = try XCTUnwrap(markdown.range(of: "First note"))
    let image = try XCTUnwrap(markdown.range(of: "![Screenshot]"))
    let second = try XCTUnwrap(markdown.range(of: "Second note"))
    XCTAssertTrue(first.upperBound <= image.lowerBound && image.upperBound <= second.lowerBound)
    XCTAssertEqual(markdown.components(separatedBy: "![Screenshot]").count - 1, 1)
  }
}
