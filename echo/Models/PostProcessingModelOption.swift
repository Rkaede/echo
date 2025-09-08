import Foundation
import SwiftUI

struct PostProcessingModelOption: Identifiable, Equatable {
  let id = UUID()
  let value: String
  let label: String
  let developer: String
  let tokensPerSecond: Int  // throughput in tokens per second
  let badge: String?
  let disabled: Bool

  // Additional properties from Groq API
  let attachment: Bool
  let reasoning: Bool
  let temperature: Bool
  let toolCall: Bool
  let knowledge: String?
  let releaseDate: String
  let lastUpdated: String
  let modalities: Modalities
  let openWeights: Bool
  let cost: Cost
  let limit: Limit

  struct Modalities: Equatable {
    let input: [String]
    let output: [String]
  }

  struct Cost: Equatable {
    let input: Double  // per 1M tokens
    let output: Double  // per 1M tokens
  }

  struct Limit: Equatable {
    let context: Int
    let output: Int
  }

  static func == (lhs: PostProcessingModelOption, rhs: PostProcessingModelOption) -> Bool {
    lhs.value == rhs.value
  }
}

extension PostProcessingModelOption {
  static let allOptions = PostProcessingData.modelOptions

  static var recommendedOption: PostProcessingModelOption? {
    allOptions.first(where: {
      ($0.badge?.caseInsensitiveCompare("Recommended") == .orderedSame) && !$0.disabled
    })
      ?? allOptions.first(where: { !$0.disabled })
      ?? allOptions.first
  }

  static var defaultOptionValue: String {
    recommendedOption?.value
      ?? allOptions.first?.value
      ?? "llama3-8b-8192"
  }
}
