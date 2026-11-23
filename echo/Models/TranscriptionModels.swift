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
  /// OpenRouter provider pin for Whisper models so requests stay on Groq's LPU deployment
  /// instead of routing to hosts whose output differs (e.g. phantom "Thank you." lines).
  static let openRouterGroqProviderField = #"{"order":["groq"],"allow_fallbacks":false}"#

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
      value: "openai/whisper-large-v3-turbo",
      label: "Whisper Large V3 Turbo",
      provider: .openRouter,
      supportedLanguages: "Multilingual",
      description:
        "Whisper Large V3 Turbo routed to Groq through OpenRouter. Fast, multilingual transcription using only an OpenRouter key.",
      costPerHour: 0.04,
      translationSupport: false,
      realTimeSpeedFactor: 414,
      wordErrorRate: "4.6%",
      extraFields: ["provider": openRouterGroqProviderField]
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
      value: "openai/whisper-large-v3",
      label: "Whisper Large V3",
      provider: .openRouter,
      supportedLanguages: "Multilingual",
      description:
        "Whisper Large V3 routed to Groq through OpenRouter. High-accuracy multilingual transcription using only an OpenRouter key.",
      costPerHour: 0.111,
      translationSupport: true,
      realTimeSpeedFactor: 189,
      wordErrorRate: "4.5%",
      extraFields: ["provider": openRouterGroqProviderField]
    ),
    ModelOption(
      value: "microsoft/mai-transcribe-2",
      label: "MAI-Transcribe-2",
      provider: .openRouter,
      supportedLanguages: "English",
      description:
        "Microsoft's transcription model, called through OpenRouter. About half the errors of Whisper, with cleaner punctuation, for roughly 0.5 s more latency. Falls back to Whisper Turbo if it is slow or fails.",
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

  /// Whisper model used when an OpenRouter transcription is slow or fails and a Groq key exists.
  static let fallbackModel = "whisper-large-v3-turbo"

  /// Whisper model on OpenRouter (pinned to Groq) used as a fallback when only an OpenRouter key exists.
  static let openRouterFallbackModel = "openai/whisper-large-v3-turbo"

  static func defaultModel(for provider: APIProvider) -> String {
    switch provider {
    case .groq: return fallbackModel
    case .openRouter: return openRouterFallbackModel
    }
  }

  /// The model a new or default profile starts with. With only an OpenRouter key it is
  /// OpenRouter's default. Otherwise it is the saved choice, unless that is an OpenRouter model
  /// (setup saves one) and the OpenRouter key has since been removed.
  static func newProfileModel(
    selected: String, hasGroqKey: Bool, hasOpenRouterKey: Bool
  ) -> String {
    if !hasGroqKey && hasOpenRouterKey {
      return defaultModel(for: .openRouter)
    }
    if provider(for: selected) == .openRouter && !hasOpenRouterKey {
      return defaultModel(for: .groq)
    }
    return selected
  }

  /// Picks a Whisper Turbo fallback for a slow or failing OpenRouter transcription.
  /// Prefers direct Groq when a Groq key is configured; otherwise falls back to Whisper Turbo
  /// on OpenRouter (unless that model is the one that already failed).
  static func fallbackOption(
    for failedModel: String,
    hasGroqKey: Bool,
    hasOpenRouterKey: Bool
  ) -> ModelOption? {
    guard provider(for: failedModel) == .openRouter else { return nil }
    if hasGroqKey {
      return option(for: fallbackModel)
    }
    if hasOpenRouterKey, failedModel != openRouterFallbackModel {
      return option(for: openRouterFallbackModel)
    }
    return nil
  }
}
