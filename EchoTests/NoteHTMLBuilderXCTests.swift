import XCTest

@testable import Echo

final class NoteHTMLBuilderXCTests: XCTestCase {
  private func render(
    entries: [NoteEntry],
    cleanedText: String? = "Cleaned version",
    markdownFilePath: String = "/tmp/echo/notes/note-test/note.md",
    changeTitle: String? = "Keep Notes Controls Visible While Recording"
  ) -> String {
    NoteHTMLBuilder.render(
      entries: entries,
      startedAt: Date(),
      cleanedText: cleanedText,
      markdownFilePath: markdownFilePath,
      changeTitle: changeTitle
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
