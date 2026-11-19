import XCTest

@testable import Echo

final class ProviderRoutingXCTests: XCTestCase {
  // MARK: - Post-processing prompt

  func testPromptWithoutPlaceholderIsSentAsSystemMessage() {
    let messages = PostProcessingPrompt.messages(
      template: "  Clean this up.  ", transcript: "can you make the gap smaller")

    XCTAssertEqual(messages.map(\.role), ["system", "user"])
    XCTAssertEqual(messages[0].content, "Clean this up.")
    XCTAssertEqual(messages[1].content, "can you make the gap smaller")
  }

  func testPromptWithPlaceholderKeepsSingleUserMessage() {
    let messages = PostProcessingPrompt.messages(
      template: "Rewrite as an email:\n<t>{{TRANSCRIPTION}}</t>", transcript: "hi there")

    XCTAssertEqual(messages.map(\.role), ["user"])
    XCTAssertEqual(messages[0].content, "Rewrite as an email:\n<t>hi there</t>")
  }

  func testLegacyPlaceholderIsStillSubstituted() {
    let messages = PostProcessingPrompt.messages(
      template: "Fix: {{TRANSCRIBED_TEXT}}", transcript: "hello")

    XCTAssertEqual(messages.map(\.role), ["user"])
    XCTAssertEqual(messages[0].content, "Fix: hello")
  }

  func testEmptyPromptFallsBackToDefaultSystemPrompt() {
    let messages = PostProcessingPrompt.messages(template: " \n", transcript: "hello")

    XCTAssertEqual(messages.map(\.role), ["system", "user"])
    XCTAssertEqual(messages[0].content, PostProcessingData.defaultPrompt)
  }

  // MARK: - Post-processing models

  func testPostProcessingOptionsAreGptOssAndGeminiFlashLite() {
    let options = PostProcessingModelOption.allOptions
    XCTAssertEqual(options.map(\.value), ["openai/gpt-oss-20b", "google/gemini-3.5-flash-lite"])
    XCTAssertEqual(options.map(\.provider), [.groq, .openRouter])
  }

  func testDefaultPostProcessingModelOnlyNeedsGroqKey() {
    XCTAssertEqual(PostProcessingModelOption.defaultOptionValue, "openai/gpt-oss-20b")
    XCTAssertEqual(PostProcessingModelOption.recommendedOption?.provider, .groq)
  }

  func testUnknownPostProcessingModelResolvesToDefault() {
    XCTAssertEqual(
      PostProcessingModelOption.resolve("llama-3.3-70b-versatile").value, "openai/gpt-oss-20b")
    XCTAssertEqual(
      PostProcessingModelOption.resolve(" google/gemini-3.5-flash-lite ").provider, .openRouter)
  }

  func testChatRequestBodyMergesProviderOptions() {
    let gemini = PostProcessingModelOption.resolve("google/gemini-3.5-flash-lite")
    let body = APIClient.chatRequestBody(
      model: gemini.value,
      messages: [ChatMessage(role: "system", content: "s"), ChatMessage(role: "user", content: "u")],
      requestOptions: gemini.requestOptions)

    XCTAssertEqual(body["model"] as? String, "google/gemini-3.5-flash-lite")
    XCTAssertNil(body["temperature"], "Gemini 3.5 models have deprecated temperature")
    XCTAssertEqual((body["messages"] as? [[String: String]])?.map { $0["role"] }, ["system", "user"])
    XCTAssertEqual((body["reasoning"] as? [String: String])?["effort"], "minimal")
    XCTAssertNotNil(body["provider"])
    XCTAssertTrue(JSONSerialization.isValidJSONObject(body))
  }

  func testGptOssUsesLowReasoningEffortAndTemperatureZeroOnGroq() {
    let option = PostProcessingModelOption.resolve("openai/gpt-oss-20b")
    XCTAssertEqual(option.requestOptions["reasoning_effort"] as? String, "low")
    let body = APIClient.chatRequestBody(
      model: option.value, messages: [], requestOptions: option.requestOptions)
    XCTAssertEqual(body["temperature"] as? Int, 0)
  }

  // MARK: - Transcription models

  func testTranscriptionProviders() {
    XCTAssertEqual(TranscriptionData.provider(for: "whisper-large-v3-turbo"), .groq)
    XCTAssertEqual(TranscriptionData.provider(for: "microsoft/mai-transcribe-2"), .openRouter)
    // Older stored model IDs are Groq models.
    XCTAssertEqual(TranscriptionData.provider(for: "distil-whisper-large-v3-en"), .groq)
  }

  func testMaiTranscribeForcesEnglish() {
    let mai = TranscriptionData.option(for: "microsoft/mai-transcribe-2")
    XCTAssertEqual(mai?.extraFields["language"], "en")
  }

  func testGroqTranscriptionAsksForVerboseJSON() {
    let fields = APIClient.transcriptionFields(
      model: "whisper-large-v3-turbo", provider: .groq, extraFields: [:])
    XCTAssertEqual(fields.map(\.name), ["model", "response_format"])
    XCTAssertEqual(fields.last?.value, "verbose_json")
  }

  func testOpenRouterTranscriptionSendsOnlyModelAndExtraFields() {
    let mai = TranscriptionData.option(for: "microsoft/mai-transcribe-2")!
    let fields = APIClient.transcriptionFields(
      model: mai.value, provider: mai.provider, extraFields: mai.extraFields)
    XCTAssertEqual(fields.map(\.name), ["model", "language"])
    XCTAssertEqual(fields.map(\.value), ["microsoft/mai-transcribe-2", "en"])
  }

  func testFallbackModelRunsOnGroq() {
    XCTAssertEqual(TranscriptionData.provider(for: TranscriptionData.fallbackModel), .groq)
  }

  func testFallbackTimeoutGrowsWithRecordingLength() {
    XCTAssertEqual(TranscriptionService.fallbackTimeout(forRecordingDuration: 0), 4)
    XCTAssertEqual(TranscriptionService.fallbackTimeout(forRecordingDuration: 60), 6)
    XCTAssertEqual(TranscriptionService.fallbackTimeout(forRecordingDuration: -5), 4)
  }

  func testProviderEndpoints() {
    XCTAssertEqual(
      APIProvider.groq.transcriptionURL.absoluteString,
      "https://api.groq.com/openai/v1/audio/transcriptions")
    XCTAssertEqual(
      APIProvider.openRouter.chatURL.absoluteString,
      "https://openrouter.ai/api/v1/chat/completions")
  }
}
