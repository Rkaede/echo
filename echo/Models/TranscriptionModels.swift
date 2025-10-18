import Foundation
import SwiftUI

// MARK: - Transcription Model Option

struct ModelOption {
  let value: String
  let label: String
  let supportedLanguages: String
  let description: String
  let costPerHour: Double
  let translationSupport: Bool
  let realTimeSpeedFactor: Int
  let wordErrorRate: String
}

// MARK: - Transcription Data

struct TranscriptionData {
  static let modelOptions: [ModelOption] = [
    ModelOption(
      value: "whisper-large-v3",
      label: "Whisper Large V3",
      supportedLanguages: "Multilingual",
      description:
        "Provides state-of-the-art performance with high accuracy for multilingual transcription and translation tasks.",
      costPerHour: 0.111,
      translationSupport: true,
      realTimeSpeedFactor: 189,
      wordErrorRate: "10.3%"
    ),
    ModelOption(
      value: "whisper-large-v3-turbo",
      label: "Whisper Large V3 Turbo",
      supportedLanguages: "Multilingual",
      description:
        "A fine-tuned version of a pruned Whisper Large V3 designed for fast, multilingual transcription tasks.",
      costPerHour: 0.04,
      translationSupport: false,
      realTimeSpeedFactor: 216,
      wordErrorRate: "12%"
    ),
  ]
}
