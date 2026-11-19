import Foundation
import SwiftUI

// MARK: - Transcription Model Option

struct ModelOption {
  let value: String
  let label: String
  let provider: APIProvider
  let supportedLanguages: String
  let description: String
  let costPerHour: Double
  let translationSupport: Bool
  let realTimeSpeedFactor: Int
  let wordErrorRate: String
  /// Extra multipart fields sent with every request for this model.
  var extraFields: [String: String] = [:]
}

// MARK: - Transcription Data

struct TranscriptionData {
  /// Word error rates are Artificial Analysis AA-WER figures, so the models are comparable.
  static let modelOptions: [ModelOption] = [
    ModelOption(
      value: "whisper-large-v3-turbo",
      label: "Whisper Large V3 Turbo",
      provider: .groq,
      supportedLanguages: "Multilingual",
      description:
        "A fine-tuned version of a pruned Whisper Large V3 designed for fast, multilingual transcription tasks.",
      costPerHour: 0.04,
      translationSupport: false,
      realTimeSpeedFactor: 414,
      wordErrorRate: "4.6%"
    ),
    ModelOption(
      value: "whisper-large-v3",
      label: "Whisper Large V3",
      provider: .groq,
      supportedLanguages: "Multilingual",
      description:
        "Provides state-of-the-art performance with high accuracy for multilingual transcription and translation tasks.",
      costPerHour: 0.111,
      translationSupport: true,
      realTimeSpeedFactor: 189,
      wordErrorRate: "4.5%"
    ),
    ModelOption(
      value: "microsoft/mai-transcribe-2",
      label: "MAI-Transcribe-2",
      provider: .openRouter,
      supportedLanguages: "English",
      description:
        "Microsoft's transcription model, called through OpenRouter. About half the errors of Whisper, with cleaner punctuation, for roughly 0.5 s more latency. Falls back to Whisper Turbo on Groq if it is slow or fails.",
      costPerHour: 0.10,
      translationSupport: false,
      realTimeSpeedFactor: 339,
      wordErrorRate: "2.0%",
      // Forcing English improved punctuation and removed filler words in Echo's benchmark.
      extraFields: ["language": "en"]
    ),
  ]

  static func option(for value: String) -> ModelOption? {
    modelOptions.first { $0.value == value }
  }

  /// Models not in the list (older settings) are Groq model IDs.
  static func provider(for value: String) -> APIProvider {
    option(for: value)?.provider ?? .groq
  }

  /// Whisper model used when an OpenRouter transcription is slow or fails.
  static let fallbackModel = "whisper-large-v3-turbo"
}
