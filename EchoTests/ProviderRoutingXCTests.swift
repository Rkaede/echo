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

  func testPostProcessingOptionsAreGptOssDirectAndOpenRouterAndGeminiFlashLite() {
    let options = PostProcessingModelOption.allOptions
    XCTAssertEqual(
      options.map(\.value),
      ["openai/gpt-oss-20b", "openrouter/openai/gpt-oss-20b", "google/gemini-3.5-flash-lite"])
    XCTAssertEqual(options.map(\.provider), [.groq, .openRouter, .openRouter])
  }

  func testDefaultPostProcessingModelOnlyNeedsGroqKey() {
    XCTAssertEqual(PostProcessingModelOption.defaultOptionValue, "openai/gpt-oss-20b")
    XCTAssertEqual(PostProcessingModelOption.recommendedOption?.provider, .groq)
  }

  func testDefaultPostProcessingModelUsesOpenRouterWhenOnlyOpenRouterKeyExists() {
    let option = PostProcessingModelOption.defaultOption(hasGroqKey: false, hasOpenRouterKey: true)
    XCTAssertEqual(option.value, "openrouter/openai/gpt-oss-20b")
    XCTAssertEqual(option.apiModel, "openai/gpt-oss-20b")
    XCTAssertEqual(option.provider, .openRouter)
  }

  func testUnknownPostProcessingModelResolvesToDefault() {
    XCTAssertEqual(
      PostProcessingModelOption.resolve("llama-3.3-70b-versatile").value, "openai/gpt-oss-20b")
    XCTAssertEqual(
      PostProcessingModelOption.resolve(" google/gemini-3.5-flash-lite ").provider, .openRouter)
    XCTAssertEqual(
      PostProcessingModelOption.resolve("openrouter/openai/gpt-oss-20b").provider, .openRouter)
  }

  func testChatRequestBodyMergesProviderOptions() {
    let gemini = PostProcessingModelOption.resolve("google/gemini-3.5-flash-lite")
    let body = APIClient.chatRequestBody(
      model: gemini.apiModel,
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
    XCTAssertEqual(option.apiModel, "openai/gpt-oss-20b")
    XCTAssertEqual(option.requestOptions["reasoning_effort"] as? String, "low")
    let body = APIClient.chatRequestBody(
      model: option.apiModel, messages: [], requestOptions: option.requestOptions)
    XCTAssertEqual(body["temperature"] as? Int, 0)
  }

  func testGptOssOnOpenRouterSendsOpenRouterModelIDAndPinsGroq() {
    let option = PostProcessingModelOption.resolve("openrouter/openai/gpt-oss-20b")
    XCTAssertEqual(option.provider, .openRouter)
    XCTAssertEqual(option.apiModel, "openai/gpt-oss-20b")

    let body = APIClient.chatRequestBody(
      model: option.apiModel, messages: [], requestOptions: option.requestOptions)
    XCTAssertEqual(body["model"] as? String, "openai/gpt-oss-20b")
    XCTAssertEqual(body["temperature"] as? Int, 0)
    XCTAssertEqual((body["reasoning"] as? [String: String])?["effort"], "low")
    XCTAssertEqual((body["provider"] as? [String: Any])?["order"] as? [String], ["groq"])
    XCTAssertTrue(JSONSerialization.isValidJSONObject(body))
  }

  // MARK: - Transcription models

  func testTranscriptionProviders() {
    XCTAssertEqual(TranscriptionData.provider(for: "whisper-large-v3-turbo"), .groq)
    XCTAssertEqual(TranscriptionData.provider(for: "whisper-large-v3"), .groq)
    XCTAssertEqual(TranscriptionData.provider(for: "openai/whisper-large-v3-turbo"), .openRouter)
    XCTAssertEqual(TranscriptionData.provider(for: "openai/whisper-large-v3"), .openRouter)
    XCTAssertEqual(TranscriptionData.provider(for: "microsoft/mai-transcribe-2"), .openRouter)
    // Older stored model IDs are Groq models.
    XCTAssertEqual(TranscriptionData.provider(for: "distil-whisper-large-v3-en"), .groq)
  }

  func testOpenRouterWhisperModelsPinGroq() {
    for modelID in ["openai/whisper-large-v3-turbo", "openai/whisper-large-v3"] {
      let option = TranscriptionData.option(for: modelID)
      XCTAssertNotNil(option)
      XCTAssertEqual(option?.provider, .openRouter)
      XCTAssertEqual(option?.extraFields["provider"], TranscriptionData.openRouterGroqProviderField)

      let fields = APIClient.transcriptionFields(
        model: modelID, provider: .openRouter, extraFields: option?.extraFields ?? [:])
      XCTAssertEqual(fields.map(\.name), ["model", "provider"])
      XCTAssertEqual(fields.map(\.value), [modelID, TranscriptionData.openRouterGroqProviderField])
    }
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

  func testUnknownPostProcessingModelResolvesToAProviderWithAKey() {
    // A profile from an earlier version, on a model that has been removed.
    let removed = "llama-3.3-70b-versatile"
    XCTAssertEqual(
      PostProcessingModelOption.resolve(removed, hasGroqKey: true, hasOpenRouterKey: true).value,
      "openai/gpt-oss-20b")
    XCTAssertEqual(
      PostProcessingModelOption.resolve(removed, hasGroqKey: false, hasOpenRouterKey: true).value,
      "openrouter/openai/gpt-oss-20b")
    // A model that is still offered is kept, whatever keys are saved.
    XCTAssertEqual(
      PostProcessingModelOption.resolve(
        "google/gemini-3.5-flash-lite", hasGroqKey: true, hasOpenRouterKey: false
      ).value,
      "google/gemini-3.5-flash-lite")
  }

  func testFailedTranscriptionPointsToTheKeyOnlyWhenTheKeyWasRejected() {
    for status in [401, 403] {
      let guidance = TranscriptionService.failureGuidance(
        for: APIError.httpError(statusCode: status, message: "{}"))
      XCTAssertEqual(guidance.title, "API key rejected", "\(status)")
      XCTAssertEqual(guidance.hint, "Check Settings › Providers", "\(status)")
    }
    // Retrying can fix these, so they keep the retry hint.
    let retryable: [Error] = [
      APIError.httpError(statusCode: 429, message: "{}"),
      APIError.httpError(statusCode: 503, message: "{}"),
      URLError(.timedOut),
      URLError(.notConnectedToInternet),
    ]
    for error in retryable {
      let guidance = TranscriptionService.failureGuidance(for: error)
      XCTAssertEqual(guidance.title, "Transcription failed", "\(error)")
      XCTAssertEqual(guidance.hint, "Retry from the Echo menu", "\(error)")
    }
  }

  func testFallbackModelRunsOnGroq() {
    XCTAssertEqual(TranscriptionData.provider(for: TranscriptionData.fallbackModel), .groq)
    XCTAssertEqual(
      TranscriptionData.provider(for: TranscriptionData.openRouterFallbackModel), .openRouter)
  }

  func testFallbackSelectionForGroqAndOpenRouterOnlyKeys() {
    // Both keys: MAI-Transcribe-2 prefers direct Groq Whisper Turbo.
    XCTAssertEqual(
      TranscriptionData.fallbackOption(
        for: "microsoft/mai-transcribe-2", hasGroqKey: true, hasOpenRouterKey: true)?.value,
      "whisper-large-v3-turbo")

    // OpenRouter-only: MAI-Transcribe-2 falls back to Whisper Turbo on OpenRouter (pinned to Groq).
    let openRouterFallback = TranscriptionData.fallbackOption(
      for: "microsoft/mai-transcribe-2", hasGroqKey: false, hasOpenRouterKey: true)
    XCTAssertEqual(openRouterFallback?.value, "openai/whisper-large-v3-turbo")
    XCTAssertEqual(openRouterFallback?.provider, .openRouter)

    // OpenRouter-only already on Whisper Turbo: no self-fallback.
    XCTAssertNil(
      TranscriptionData.fallbackOption(
        for: "openai/whisper-large-v3-turbo", hasGroqKey: false, hasOpenRouterKey: true))

    // Both keys on OpenRouter Whisper Turbo: can still fall back to direct Groq.
    XCTAssertEqual(
      TranscriptionData.fallbackOption(
        for: "openai/whisper-large-v3-turbo", hasGroqKey: true, hasOpenRouterKey: true)?.value,
      "whisper-large-v3-turbo")

    // Direct Groq model: no fallback.
    XCTAssertNil(
      TranscriptionData.fallbackOption(
        for: "whisper-large-v3-turbo", hasGroqKey: true, hasOpenRouterKey: true))
  }

  func testProviderKeyFormatValidation() {
    let validGroqKey = String(repeating: "a", count: Constants.API.groqAPIKeyLength)
    XCTAssertTrue(APIProvider.groq.isValidKeyFormat(validGroqKey))
    XCTAssertTrue(APIProvider.groq.isValidKeyFormat(" \(validGroqKey)\n"))
    XCTAssertFalse(APIProvider.groq.isValidKeyFormat("short"))

    XCTAssertTrue(APIProvider.openRouter.isValidKeyFormat("sk-or-v1-0123456789abcdef0123456789"))
    XCTAssertTrue(APIProvider.openRouter.isValidKeyFormat(" sk-or-v1-0123456789abcdef0123456789\n"))
    XCTAssertFalse(APIProvider.openRouter.isValidKeyFormat("sk-or-short"))
    XCTAssertFalse(APIProvider.openRouter.isValidKeyFormat(validGroqKey))
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
