import XCTest

@testable import Echo

final class CleanupReviewPromptXCTests: XCTestCase {
  private let gptOss = PostProcessingModelOption.resolve("openai/gpt-oss-20b")
  private let databasePath =
    "/Users/me/Library/Containers/io.littlecove.echo/Data/Library/Application Support/Echo/echo.sqlite"

  private func makePrompt(_ prompt: String) -> String {
    CleanupReviewPrompt.make(
      profileTitle: "Coding", profileID: "ABC-123", prompt: prompt, model: gptOss,
      databasePath: databasePath)
  }

  // MARK: - Old default prompts

  func testOldDefaultPromptsUpgradeToCurrentDefault() {
    for legacy in PostProcessingPrompt.legacyDefaults {
      XCTAssertEqual(
        PostProcessingPrompt.upgradedDefault(for: "\n \(legacy)  \n"),
        PostProcessingData.defaultPrompt)
    }
  }

  func testEditedPromptsAreLeftAlone() {
    XCTAssertNil(PostProcessingPrompt.upgradedDefault(for: "Fix punctuation: {{TRANSCRIPTION}}"))
    XCTAssertNil(PostProcessingPrompt.upgradedDefault(for: PostProcessingData.defaultPrompt))
    XCTAssertNil(PostProcessingPrompt.upgradedDefault(for: ""))
  }

  // MARK: - Agent prompt

  func testAgentPromptNamesTheDatabaseProfileAndModel() {
    let text = makePrompt("Clean this up.")

    XCTAssertTrue(text.contains("Echo's \"Coding\" profile"))
    XCTAssertTrue(text.contains("sqlite3 -readonly \"\(databasePath)\""))
    XCTAssertTrue(text.contains("WHERE profile_id = 'ABC-123'"))
    XCTAssertTrue(text.contains("Clean-up model: GPT OSS 20B on Groq."))
    XCTAssertTrue(text.contains("<current_prompt>\nClean this up.\n</current_prompt>"))
    XCTAssertTrue(text.contains("before Echo \(CleanupReviewPrompt.firstVersionWithCleanedText)"))
  }

  func testAgentPromptExplainsSystemMessagePrompts() {
    let text = makePrompt("Clean this up.")

    XCTAssertTrue(text.contains("as the system message and each raw transcript as the user message"))
    XCTAssertFalse(text.contains("Prefer that form."))
  }

  func testAgentPromptSuggestsSystemFormForPlaceholderPrompts() {
    let text = makePrompt("Fix this:\n{{TRANSCRIPTION}}")

    XCTAssertTrue(text.contains("where the prompt says {{TRANSCRIPTION}}"))
    XCTAssertTrue(text.contains("Prefer that form."))
  }

  func testAgentPromptShowsTheDefaultWhenThePromptIsEmpty() {
    let text = makePrompt("  \n")

    XCTAssertTrue(
      text.contains("<current_prompt>\n\(PostProcessingData.defaultPrompt)\n</current_prompt>"))
  }
}
