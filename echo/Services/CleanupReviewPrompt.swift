import Foundation

/// Instructions to paste into Claude Code or another coding agent. They ask the agent to review
/// a profile's dictation history, compare the raw transcripts with the cleaned text, and propose
/// a better clean-up prompt with a vocabulary list. This replaces hand-correcting a set of
/// dictations: the agent works out the corrections from patterns across the history.
enum CleanupReviewPrompt {
  /// The first version that saves the cleaned text and profile with each dictation.
  static let firstVersionWithCleanedText = "0.0.7"

  static func make(
    profileTitle: String,
    profileID: String,
    prompt: String,
    model: PostProcessingModelOption,
    databasePath: String
  ) -> String {
    let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    let currentPrompt = trimmedPrompt.isEmpty ? PostProcessingData.defaultPrompt : trimmedPrompt
    let usesPlaceholder = PostProcessingPrompt.placeholders.contains(where: currentPrompt.contains)
    let howPromptIsSent =
      usesPlaceholder
      ? "Echo puts the raw transcript where the prompt says {{TRANSCRIPTION}} and sends it all as one user message. A prompt without {{TRANSCRIPTION}} is sent as the system message with the transcript as a separate user message, which stops the model answering questions I dictate. Prefer that form."
      : "Echo sends the prompt below as the system message and each raw transcript as the user message."

    return """
      I dictate with Echo, a macOS speech-to-text app. Before pasting, Echo's "\(profileTitle)" profile sends each raw transcript to an LLM to clean it up. Please review my dictation history and write a better clean-up prompt for this profile.

      ## Where the data is

      Echo keeps its history in a SQLite database:

      \(databasePath)

      Open it read-only (`sqlite3 -readonly "\(databasePath)"`) and don't write to it. macOS may ask whether your terminal can access another app's data; that's expected.

      Each dictation is a row in `transcription_history`:

      - `transcribed_text`: the raw speech-to-text output
      - `post_processed_text`: the cleaned text Echo pasted (NULL when clean-up was off or failed)
      - `profile_id`: the profile used; this one is `\(profileID)`
      - `model_used`: the speech-to-text model; `post_processing_model`: the clean-up model
      - `application_context`: the app I was dictating into
      - `timestamp`: Unix seconds

      Start with this profile's cleaned dictations, newest first:

          SELECT timestamp, application_context, transcribed_text, post_processed_text
          FROM transcription_history
          WHERE profile_id = '\(profileID)' AND post_processed_text IS NOT NULL AND did_fail = 0
          ORDER BY timestamp DESC LIMIT 300;

      Dictations from before Echo \(firstVersionWithCleanedText) have no cleaned text or profile. If you find fewer than about 30 rows, also read recent raw transcripts from every profile to learn my vocabulary, and tell me you did.

      ## The current prompt

      Clean-up model: \(model.label) on \(model.provider.displayName). \(howPromptIsSent)

      <current_prompt>
      \(currentPrompt)
      </current_prompt>

      ## What to look for

      There is no audio, so judge what I meant from context, and look for patterns across many dictations rather than one-offs:

      1. Misheard names and terms: people, products, code identifiers, file names and acronyms that come out spelt several ways or as a sound-alike (for example "claw code" for "Claude Code"). Note which ones the clean-up fixed and which it missed.
      2. Punctuation and capitalisation: missing question marks, run-on sentences, names in the wrong case.
      3. Filler left in: um, uh, repeated words and false starts.
      4. Over-rewriting: the clean-up rephrasing, shortening or adding words, answering a question I dictated, following an instruction I dictated, or wrapping its output in quotes or a preamble.
      5. Errors the clean-up left in that it should have fixed.

      ## What I'd like back

      1. The recurring problems, each with two or three real examples: raw, cleaned, and what it should have been.
      2. The vocabulary you've inferred: each name or term spelt correctly, with the ways it gets misheard. Mark any you're unsure of, and ask me about them before relying on them.
      3. An improved prompt, ready to paste into Echo. Keep the current prompt's rules unless my history shows a reason to change one. Add the vocabulary as plain sentences: the names and terms I use, then known mishearings ("heard" → "meant"). Include only terms that appear in my history. Keep it short: smaller clean-up models rewrite more as a prompt grows, so add only the rules my history shows a need for. Don't add example dictations; in Echo's tests they made GPT OSS 20B rewrite far more.
      4. Each change you made to the prompt, and the dictations that justify it.
      5. Problems a prompt can't fix, such as a word the speech-to-text model never gets close to, with what to try instead.

      Don't edit any files, and don't copy my transcripts anywhere outside this conversation.
      """
  }
}
