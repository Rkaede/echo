import Foundation

/// Client for the OpenAI-compatible endpoints on Groq and OpenRouter.
class APIClient {
  static let shared = APIClient()

  private init() {}

  func transcribeAudio(
    fileURL: URL,
    apiKey: String,
    model: String,
    provider: APIProvider = .groq,
    extraFields: [String: String] = [:],
    timeout: TimeInterval? = nil
  ) async throws -> TranscriptionResultWithTiming {
    var request = URLRequest(url: provider.transcriptionURL)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    for (header, value) in provider.additionalHeaders {
      request.setValue(value, forHTTPHeaderField: header)
    }
    if let timeout {
      request.timeoutInterval = timeout
    }

    let builder = MultipartFormDataBuilder()
    request.setValue(builder.contentType, forHTTPHeaderField: "Content-Type")

    let audioData = try Data(contentsOf: fileURL)
    builder.addFileField(
      name: "file", filename: "recording.wav", contentType: "audio/wav", data: audioData)
    for (name, value) in Self.transcriptionFields(
      model: model, provider: provider, extraFields: extraFields)
    {
      builder.addTextField(name: name, value: value)
    }

    request.httpBody = builder.build()

    // Create timing session delegate
    let timingDelegate = TimingSessionDelegate()

    // Create URLSession with timing delegate
    let session = URLSession(configuration: .default, delegate: timingDelegate, delegateQueue: nil)

    // Ensure session is invalidated after use to prevent memory leaks
    defer {
      session.finishTasksAndInvalidate()
    }

    let (data, response) = try await session.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw APIError.invalidResponse
    }

    guard httpResponse.statusCode == 200 else {
      let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
      throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
    }

    let result = try JSONDecoder().decode(TranscriptionResult.self, from: data)

    // Return result with timing data
    return TranscriptionResultWithTiming(
      result: result,
      uploadTime: timingDelegate.uploadTime,
      downloadTime: timingDelegate.downloadTime,
      totalNetworkTime: timingDelegate.totalNetworkTime
    )
  }

  func postProcessText(
    messages: [ChatMessage],
    apiKey: String,
    model: String,
    provider: APIProvider = .groq,
    requestOptions: [String: Any] = [:]
  ) async throws -> String {
    var request = URLRequest(url: provider.chatURL)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    for (header, value) in provider.additionalHeaders {
      request.setValue(value, forHTTPHeaderField: header)
    }
    request.httpBody = try JSONSerialization.data(
      withJSONObject: Self.chatRequestBody(
        model: model, messages: messages, requestOptions: requestOptions))

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw APIError.invalidResponse
    }

    guard httpResponse.statusCode == 200 else {
      let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
      throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
    }

    return try Self.chatContent(from: data)
  }

  /// The reply text from a chat completion response body.
  static func chatContent(from data: Data) throws -> String {
    let chatResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)

    guard let firstChoice = chatResponse.choices.first else {
      throw APIError.invalidResponse
    }

    // Hitting max_tokens returns the text so far. Pasting it would silently drop the end
    // of the dictation, so report it and let the caller use the raw transcript.
    if firstChoice.finishReason == "length" {
      throw PostProcessingError.truncated
    }
    return firstChoice.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Text fields for a transcription request, in the order they are sent. Groq's
  /// `verbose_json` adds the segment confidence `SpeechGate` uses. OpenRouter requests send
  /// only the fields Echo's benchmark used, and its plain JSON response carries the text.
  static func transcriptionFields(
    model: String, provider: APIProvider, extraFields: [String: String]
  ) -> [(name: String, value: String)] {
    var fields: [(name: String, value: String)] = [("model", model)]
    if provider == .groq {
      fields.append(("response_format", "verbose_json"))
    }
    fields += extraFields.sorted { $0.key < $1.key }.map { (name: $0.key, value: $0.value) }
    return fields
  }

  /// JSON body for a chat completion. Built as a dictionary so provider-specific fields
  /// (Groq's `reasoning_effort`, OpenRouter's `reasoning` and `provider`) can be merged in.
  static func chatRequestBody(
    model: String, messages: [ChatMessage], requestOptions: [String: Any]
  ) -> [String: Any] {
    var body: [String: Any] = [
      "model": model,
      "messages": messages.map { ["role": $0.role, "content": $0.content] },
      // A cap, not a target: reasoning models spend part of it before the text. Long
      // transcripts are cleaned up in chunks, so each request stays well under it.
      "max_tokens": 2048,
      "stream": false,
      // No temperature by default: Google has deprecated it for Gemini 3.5 models. Models
      // that need one set it in their request options.
    ]
    body.merge(requestOptions) { _, option in option }
    return body
  }
}

struct TranscriptionResultWithTiming {
  let result: TranscriptionResult
  let uploadTime: TimeInterval
  let downloadTime: TimeInterval
  let totalNetworkTime: TimeInterval
}

class TimingSessionDelegate: NSObject, URLSessionDataDelegate {
  private var requestStartTime: Date?
  private var uploadStartTime: Date?
  private var uploadEndTime: Date?
  private var downloadStartTime: Date?
  private var downloadEndTime: Date?

  var uploadTime: TimeInterval = 0
  var downloadTime: TimeInterval = 0
  var totalNetworkTime: TimeInterval = 0

  func urlSession(
    _ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
    totalBytesSent: Int64, totalBytesExpectedToSend: Int64
  ) {
    if uploadStartTime == nil {
      uploadStartTime = Date()
      requestStartTime = requestStartTime ?? Date()
    }
  }

  func urlSession(
    _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    uploadEndTime = Date()
    downloadStartTime = Date()

    if let uploadStart = uploadStartTime, let uploadEnd = uploadEndTime {
      uploadTime = uploadEnd.timeIntervalSince(uploadStart)
    }

    completionHandler(.allow)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    if downloadEndTime == nil {
      downloadEndTime = Date()
      if let downloadStart = downloadStartTime, let downloadEnd = downloadEndTime {
        downloadTime = downloadEnd.timeIntervalSince(downloadStart)
      }
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    downloadEndTime = downloadEndTime ?? Date()

    if let downloadStart = downloadStartTime, let downloadEnd = downloadEndTime {
      downloadTime = downloadEnd.timeIntervalSince(downloadStart)
    }

    if let requestStart = requestStartTime, let downloadEnd = downloadEndTime {
      totalNetworkTime = downloadEnd.timeIntervalSince(requestStart)
    }
  }
}

enum APIError: LocalizedError {
  case invalidURL
  case invalidResponse
  case httpError(statusCode: Int, message: String)

  var errorDescription: String? {
    switch self {
    case .invalidURL:
      return "Invalid API URL"
    case .invalidResponse:
      return "Invalid response from server"
    case .httpError(let statusCode, let message):
      return "HTTP Error \(statusCode): \(message)"
    }
  }
}
