import Foundation

/// A pairing of speech-to-text and clean-up models offered during setup. Both run on
/// OpenRouter, the only key setup asks for.
///
/// The error, latency and cost figures come from Echo's Nov 2026 benchmark (147 hand-corrected
/// clips, errors in the pasted text). OpenRouter adds about 0.3 s over calling Groq directly,
/// which is included in the Fast wait. Cost is the logged OpenRouter spend per clip for both
/// models together, scaled to an hour of speech (clips averaged 21 s): about $0.22 and $0.76
/// per 1,000 dictations.
struct ModelPreset: Identifiable, Equatable {
  let id: String
  let title: String
  let badge: String
  let transcriptionModel: String
  let postProcessingModel: String
  let languages: String
  let errorRate: String
  let typicalWait: String
  let cost: String

  var transcriptionLabel: String {
    TranscriptionData.option(for: transcriptionModel)?.label ?? transcriptionModel
  }

  var postProcessingLabel: String {
    PostProcessingModelOption.resolve(postProcessingModel).label
  }

  static let fast = ModelPreset(
    id: "fast",
    title: "Fast",
    badge: "Fastest",
    transcriptionModel: "openai/whisper-large-v3-turbo",
    postProcessingModel: "openrouter/openai/gpt-oss-20b",
    languages: "Many",
    errorRate: "6.95%",
    typicalWait: "~1.3–1.6 s",
    cost: "~4¢ per hour"
  )

  static let accurate = ModelPreset(
    id: "accurate",
    title: "Accurate",
    badge: "Best overall",
    transcriptionModel: "microsoft/mai-transcribe-2",
    postProcessingModel: "google/gemini-3.5-flash-lite",
    languages: "English only",
    errorRate: "4.63%",
    typicalWait: "~1.5–1.8 s",
    cost: "~13¢ per hour"
  )

  static let all = [fast, accurate]
  static let recommended = accurate
}
