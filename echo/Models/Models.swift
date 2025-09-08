import Foundation
import SwiftUI

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

struct PostProcessingData {
  static let defaultPrompt =
    "You are tasked with cleaning up a voice-to-text transcription. Here is the transcribed text:\n\n<transcribed_text>\n{{TRANSCRIBED_TEXT}}\n</transcribed_text>\n\nYour job is to clean up this text by doing the following:\n1. Fix grammar and punctuation errors\n2. Remove filler words such as \"um\", \"uh\", and \"like\" (when used as filler)\n3. Remove unnecessary repetitions of words or phrases\n4. Preserve contractions and casual language if present in the original text\n5. Maintain the original meaning and tone of the transcription\n\nImportant: Do not add any new information or change the intended message of the speaker.\n\nWhen you've finished cleaning up the text, provide only the cleaned version as your output. Do not include any explanations, introductions, or phrases like \"Here is the cleaned text.\" Your response should begin immediately with the first word of the cleaned transcription."

  static let modelOptions = [
    PostProcessingModelOption(
      value: "deepseek-r1-distill-llama-70b",
      label: "R1 Distill Llama 70B",
      developer: "DeepSeek",
      tokensPerSecond: 400,
      badge: nil,
      disabled: false,
      attachment: false,
      reasoning: true,
      temperature: true,
      toolCall: true,
      knowledge: "2024-07",
      releaseDate: "2025-01-20",
      lastUpdated: "2025-01-20",
      modalities: PostProcessingModelOption.Modalities(input: ["text"], output: ["text"]),
      openWeights: true,
      cost: PostProcessingModelOption.Cost(input: 0.75, output: 0.99),
      limit: PostProcessingModelOption.Limit(context: 131072, output: 8192)
    ),
    PostProcessingModelOption(
      value: "gemma2-9b-it",
      label: "Gemma 2 9B",
      developer: "Google",
      tokensPerSecond: 500,
      badge: nil,
      disabled: false,
      attachment: false,
      reasoning: false,
      temperature: true,
      toolCall: true,
      knowledge: "2024-06",
      releaseDate: "2024-06-27",
      lastUpdated: "2024-06-27",
      modalities: PostProcessingModelOption.Modalities(input: ["text"], output: ["text"]),
      openWeights: true,
      cost: PostProcessingModelOption.Cost(input: 0.2, output: 0.2),
      limit: PostProcessingModelOption.Limit(context: 8192, output: 8192)
    ),
    PostProcessingModelOption(
      value: "openai/gpt-oss-120b",
      label: "GPT OSS 120B",
      developer: "OpenAI",
      tokensPerSecond: 500,
      badge: nil,
      disabled: false,
      attachment: false,
      reasoning: true,
      temperature: true,
      toolCall: true,
      knowledge: nil,
      releaseDate: "2025-08-05",
      lastUpdated: "2025-08-05",
      modalities: PostProcessingModelOption.Modalities(input: ["text"], output: ["text"]),
      openWeights: true,
      cost: PostProcessingModelOption.Cost(input: 0.15, output: 0.75),
      limit: PostProcessingModelOption.Limit(context: 131072, output: 32768)
    ),
    PostProcessingModelOption(
      value: "openai/gpt-oss-20b",
      label: "GPT OSS 20B",
      developer: "OpenAI",
      tokensPerSecond: 1000,
      badge: "Recommended",
      disabled: false,
      attachment: false,
      reasoning: true,
      temperature: true,
      toolCall: true,
      knowledge: nil,
      releaseDate: "2025-08-05",
      lastUpdated: "2025-08-05",
      modalities: PostProcessingModelOption.Modalities(input: ["text"], output: ["text"]),
      openWeights: true,
      cost: PostProcessingModelOption.Cost(input: 0.1, output: 0.5),
      limit: PostProcessingModelOption.Limit(context: 131072, output: 32768)
    ),
    PostProcessingModelOption(
      value: "moonshotai/kimi-k2-instruct",
      label: "Kimi K2 Instruct",
      developer: "Moonshot AI",
      tokensPerSecond: 200,
      badge: nil,
      disabled: false,
      attachment: false,
      reasoning: false,
      temperature: true,
      toolCall: true,
      knowledge: "2024-10",
      releaseDate: "2025-07-14",
      lastUpdated: "2025-07-14",
      modalities: PostProcessingModelOption.Modalities(input: ["text"], output: ["text"]),
      openWeights: true,
      cost: PostProcessingModelOption.Cost(input: 1.0, output: 3.0),
      limit: PostProcessingModelOption.Limit(context: 131072, output: 16384)
    ),
    PostProcessingModelOption(
      value: "llama3-8b-8192",
      label: "Llama 3 8B",
      developer: "Meta",
      tokensPerSecond: 1345,
      badge: nil,
      disabled: true,
      attachment: false,
      reasoning: false,
      temperature: true,
      toolCall: true,
      knowledge: "2023-03",
      releaseDate: "2024-04-18",
      lastUpdated: "2024-04-18",
      modalities: PostProcessingModelOption.Modalities(input: ["text"], output: ["text"]),
      openWeights: true,
      cost: PostProcessingModelOption.Cost(input: 0.05, output: 0.08),
      limit: PostProcessingModelOption.Limit(context: 8192, output: 8192)
    ),
    PostProcessingModelOption(
      value: "llama-3.1-8b-instant",
      label: "Llama 3.1 8B Instant",
      developer: "Meta",
      tokensPerSecond: 840,
      badge: nil,
      disabled: true,
      attachment: false,
      reasoning: false,
      temperature: true,
      toolCall: true,
      knowledge: "2023-12",
      releaseDate: "2024-07-23",
      lastUpdated: "2024-07-23",
      modalities: PostProcessingModelOption.Modalities(input: ["text"], output: ["text"]),
      openWeights: true,
      cost: PostProcessingModelOption.Cost(input: 0.05, output: 0.08),
      limit: PostProcessingModelOption.Limit(context: 131072, output: 8192)
    ),
    PostProcessingModelOption(
      value: "llama-3.3-70b-versatile",
      label: "Llama 3.3 70B Versatile",
      developer: "Meta",
      tokensPerSecond: 394,
      badge: nil,
      disabled: true,
      attachment: false,
      reasoning: false,
      temperature: true,
      toolCall: true,
      knowledge: "2023-12",
      releaseDate: "2024-12-06",
      lastUpdated: "2024-12-06",
      modalities: PostProcessingModelOption.Modalities(input: ["text"], output: ["text"]),
      openWeights: true,
      cost: PostProcessingModelOption.Cost(input: 0.59, output: 0.79),
      limit: PostProcessingModelOption.Limit(context: 131072, output: 32768)
    ),
    PostProcessingModelOption(
      value: "llama3-70b-8192",
      label: "Llama 3 70B",
      developer: "Meta",
      tokensPerSecond: 330,
      badge: nil,
      disabled: true,
      attachment: false,
      reasoning: false,
      temperature: true,
      toolCall: true,
      knowledge: "2023-03",
      releaseDate: "2024-04-18",
      lastUpdated: "2024-04-18",
      modalities: PostProcessingModelOption.Modalities(input: ["text"], output: ["text"]),
      openWeights: true,
      cost: PostProcessingModelOption.Cost(input: 0.59, output: 0.79),
      limit: PostProcessingModelOption.Limit(context: 8192, output: 8192)
    ),
    PostProcessingModelOption(
      value: "meta-llama/llama-4-maverick-17b-128e-instruct",
      label: "Llama 4 Maverick 17B",
      developer: "Meta",
      tokensPerSecond: 562,
      badge: nil,
      disabled: false,
      attachment: false,
      reasoning: false,
      temperature: true,
      toolCall: true,
      knowledge: "2024-08",
      releaseDate: "2025-04-05",
      lastUpdated: "2025-04-05",
      modalities: PostProcessingModelOption.Modalities(input: ["text", "image"], output: ["text"]),
      openWeights: true,
      cost: PostProcessingModelOption.Cost(input: 0.2, output: 0.6),
      limit: PostProcessingModelOption.Limit(context: 131072, output: 8192)
    ),
    PostProcessingModelOption(
      value: "meta-llama/llama-4-scout-17b-16e-instruct",
      label: "Llama 4 Scout 17B",
      developer: "Meta",
      tokensPerSecond: 594,
      badge: nil,
      disabled: false,
      attachment: false,
      reasoning: false,
      temperature: true,
      toolCall: true,
      knowledge: "2024-08",
      releaseDate: "2025-04-05",
      lastUpdated: "2025-04-05",
      modalities: PostProcessingModelOption.Modalities(input: ["text", "image"], output: ["text"]),
      openWeights: true,
      cost: PostProcessingModelOption.Cost(input: 0.11, output: 0.34),
      limit: PostProcessingModelOption.Limit(context: 131072, output: 8192)
    ),
    PostProcessingModelOption(
      value: "qwen/qwen3-32b",
      label: "Qwen3 32B",
      developer: "Alibaba",
      tokensPerSecond: 662,
      badge: nil,
      disabled: false,
      attachment: false,
      reasoning: true,
      temperature: true,
      toolCall: true,
      knowledge: "2024-11-08",
      releaseDate: "2024-12-23",
      lastUpdated: "2024-12-23",
      modalities: PostProcessingModelOption.Modalities(input: ["text"], output: ["text"]),
      openWeights: true,
      cost: PostProcessingModelOption.Cost(input: 0.29, output: 0.59),
      limit: PostProcessingModelOption.Limit(context: 131072, output: 16384)
    ),
  ]
}

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
    ModelOption(
      value: "distil-whisper-large-v3-en",
      label: "Distil-Whisper English",
      supportedLanguages: "English-only",
      description:
        "A distilled, or compressed, version of OpenAI's Whisper model, designed to provide faster, lower cost English speech recognition while maintaining comparable accuracy.",
      costPerHour: 0.02,
      translationSupport: false,
      realTimeSpeedFactor: 250,
      wordErrorRate: "13%"
    ),
  ]
}
