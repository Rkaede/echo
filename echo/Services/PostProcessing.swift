import Foundation

/// Builds the chat messages for a post-processing prompt.
enum PostProcessingPrompt {
    static let placeholders = ["{{TRANSCRIPTION}}", "{{TRANSCRIBED_TEXT}}"]  // second is legacy

    /// A prompt without a placeholder is sent as the system message, with the transcript as
    /// its own user message, so the model treats the dictation as text to clean rather than a
    /// request to answer. A prompt that contains `{{TRANSCRIPTION}}` keeps the original
    /// behaviour: the transcript is substituted in and everything is sent as one user message.
    static func messages(template: String, transcript: String) -> [ChatMessage] {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        if placeholders.contains(where: trimmed.contains) {
            let prompt = placeholders.reduce(trimmed) {
                $0.replacingOccurrences(of: $1, with: transcript)
            }
            return [ChatMessage(role: "user", content: prompt)]
        }
        let system = trimmed.isEmpty ? PostProcessingData.defaultPrompt : trimmed
        return [
            ChatMessage(role: "system", content: system),
            ChatMessage(role: "user", content: transcript),
        ]
    }

    /// Prompts earlier versions of Echo gave new profiles. A bare `{{TRANSCRIPTION}}` sends the
    /// dictation to the model on its own, so the model answers it instead of cleaning it.
    static let legacyDefaults = [
        "{{TRANSCRIPTION}}",
        "Cleanup the following text. Check for correct grammar and punctuation. Do not change the tone. Use as much of the original text as possible.\n\nHere is the transcription:\n\n<transcription>\n{{TRANSCRIPTION}}\n</transcription>",
    ]

    // MARK: Long transcripts

    /// Transcripts longer than this, about four minutes of speech, are cleaned up in sections.
    /// Each request then stays close to the dictation lengths Echo's benchmark measured, and
    /// its output fits well under the token cap.
    static let maxSectionWords = 600

    /// The transcript in sections of at most `maxWords`, cut at sentence ends. Short
    /// transcripts come back whole, and so does any transcript for a prompt that places it
    /// with {{TRANSCRIPTION}}: such prompts often reshape the whole text (into an email, say),
    /// which sections would break.
    static func sections(
        of transcript: String, template: String, maxWords: Int = maxSectionWords
    ) -> [String] {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let total = wordCount(trimmed)
        guard total > maxWords, !placeholders.contains(where: template.contains) else {
            return [transcript]
        }

        // Even sections: 700 words become two of 350, not 600 and 100.
        let sectionCount = (total + maxWords - 1) / maxWords
        let target = (total + sectionCount - 1) / sectionCount

        var sentences: [String] = []
        trimmed.enumerateSubstrings(in: trimmed.startIndex..., options: .bySentences) {
            sentence, _, _, _ in
            if let sentence { sentences.append(sentence) }
        }

        var sections: [String] = []
        var current: [String] = []
        var currentWords = 0
        func flush() {
            guard !current.isEmpty else { return }
            sections.append(current.joined(separator: " "))
            current = []
            currentWords = 0
        }
        for sentence in sentences {
            var words = sentence.split(whereSeparator: \.isWhitespace).map(String.init)
            guard !words.isEmpty else { continue }
            // Unpunctuated speech can run on for hundreds of words; cut it by word count.
            while words.count > maxWords {
                flush()
                sections.append(words.prefix(target).joined(separator: " "))
                words.removeFirst(min(target, words.count))
            }
            if currentWords + words.count > target { flush() }
            current.append(words.joined(separator: " "))
            currentWords += words.count
        }
        flush()
        return sections.isEmpty ? [transcript] : sections
    }

    /// Output cap for cleaning `text`: room for the text itself (about 1.3 tokens a word,
    /// rounded up) plus the model's reasoning, and never below the default.
    static func maxTokens(for text: String) -> Int {
        min(32_768, max(2_048, wordCount(text) * 2 + 1_024))
    }

    /// Cleans sections a few at a time and joins them in order. A section whose clean-up
    /// fails or is cut off keeps its raw text, so nothing is lost. If every section fails,
    /// the first error is thrown.
    static func cleanUpSections(
        _ sections: [String],
        maxConcurrent: Int = 4,
        cleanUp: @escaping (String) async throws -> String
    ) async throws -> String {
        var cleaned = [String?](repeating: nil, count: sections.count)
        var firstError: Error?
        func record(_ index: Int, _ result: Result<String, Error>) {
            switch result {
            case .success(let text):
                cleaned[index] = text
            case .failure(let error):
                print("PostProcessingService: section \(index + 1) of \(sections.count) kept raw - \(error)")
                if firstError == nil { firstError = error }
            }
        }
        // A few sections at a time: each waits for a slot before starting.
        await withTaskGroup(of: (Int, Result<String, Error>).self) { group in
            for (index, section) in sections.enumerated() {
                if index >= maxConcurrent, let (done, result) = await group.next() {
                    record(done, result)
                }
                group.addTask {
                    do { return (index, .success(try await cleanUp(section))) }
                    catch { return (index, .failure(error)) }
                }
            }
            for await (done, result) in group {
                record(done, result)
            }
        }
        if let firstError, cleaned.allSatisfy({ $0 == nil }) { throw firstError }
        return zip(sections, cleaned).map { raw, clean in clean ?? raw }.joined(separator: " ")
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    // MARK: Old defaults

    /// The current default when `prompt` is one of the old defaults, unedited; otherwise nil,
    /// so prompts the user wrote are left alone.
    static func upgradedDefault(for prompt: String) -> String? {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return legacyDefaults.contains(trimmed) ? PostProcessingData.defaultPrompt : nil
    }
}

class PostProcessingService {
    static let shared = PostProcessingService()

    private init() {}

    private let client = APIClient.shared

    @MainActor
    func processText(_ text: String, promptTemplate: String, postProcessingModel: String) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PostProcessingError.emptyText
        }

        let option = PostProcessingModelOption.resolve(postProcessingModel)
        let settings = SettingsManager.shared
        settings.ensureAPIKeyLoaded()
        guard settings.hasAPIKey(for: option.provider) else {
            throw PostProcessingError.missingAPIKey(option.provider)
        }
        let apiKey = settings.apiKey(for: option.provider)

        let client = self.client
        let cleanUp: (String) async throws -> String = { section in
            let processedText = try await client.postProcessText(
                messages: PostProcessingPrompt.messages(template: promptTemplate, transcript: section),
                apiKey: apiKey,
                model: option.apiModel,
                provider: option.provider,
                requestOptions: option.requestOptions.merging(
                    ["max_tokens": PostProcessingPrompt.maxTokens(for: section)]
                ) { _, sized in sized }
            )
            guard !processedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PostProcessingError.emptyResponse
            }
            return processedText
        }

        do {
            let sections = PostProcessingPrompt.sections(of: text, template: promptTemplate)
            guard sections.count > 1 else { return try await cleanUp(text) }
            print("PostProcessingService: cleaning a long transcript in \(sections.count) sections")
            return try await PostProcessingPrompt.cleanUpSections(sections, cleanUp: cleanUp)
        } catch {
            print("PostProcessingService: Error processing text - \(error)")
            throw PostProcessingError.apiError(error)
        }
    }
}

enum PostProcessingError: LocalizedError {
    case emptyText
    case missingAPIKey(APIProvider)
    case emptyResponse
    case apiError(Error)
    case timeout
    case truncated

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "No text to process"
        case .missingAPIKey(let provider):
            return "\(provider.displayName) API key not found"
        case .emptyResponse:
            return "Empty response from API"
        case .apiError(let error):
            return "API error: \(error.localizedDescription)"
        case .timeout:
            return "Post-processing timed out"
        case .truncated:
            return "Post-processing output was cut off"
        }
    }
}
