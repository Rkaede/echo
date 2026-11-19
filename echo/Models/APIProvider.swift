import Foundation

/// The API service a transcription or post-processing model is called through.
///
/// Both services speak the OpenAI-compatible protocol, so the request shapes are shared;
/// only the base URL, the key and a few provider-specific fields differ.
enum APIProvider: String, Codable, CaseIterable {
  case groq
  case openRouter

  var displayName: String {
    switch self {
    case .groq: return "Groq"
    case .openRouter: return "OpenRouter"
    }
  }

  var transcriptionURL: URL {
    switch self {
    case .groq: return URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
    case .openRouter: return URL(string: "https://openrouter.ai/api/v1/audio/transcriptions")!
    }
  }

  var chatURL: URL {
    switch self {
    case .groq: return URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    case .openRouter: return URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    }
  }

  /// Extra headers OpenRouter uses to attribute requests to an app.
  var additionalHeaders: [String: String] {
    switch self {
    case .groq: return [:]
    case .openRouter: return ["X-Title": "Echo"]
    }
  }

  var missingKeyMessage: String {
    "Please add your \(displayName) API key in Settings"
  }
}
