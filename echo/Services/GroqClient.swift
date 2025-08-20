import Foundation

class GroqAPIClient {
    static let shared = GroqAPIClient()

    private init() {}

    private let baseURL = "https://api.groq.com/openai/v1/audio/transcriptions"

    func transcribeAudio(fileURL: URL, apiKey: String) async throws -> TranscriptionResultWithTiming {
        let model = await SettingsManager.shared.selectedModel
        guard let url = URL(string: baseURL) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let builder = MultipartFormDataBuilder()
        request.setValue(builder.contentType, forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: fileURL)
        builder.addFileField(name: "file", filename: "recording.wav", contentType: "audio/wav", data: audioData)
        builder.addTextField(name: "model", value: model)
        builder.addTextField(name: "response_format", value: "verbose_json")

        request.httpBody = builder.build()

        // Create timing session delegate
        let timingDelegate = TimingSessionDelegate()

        // Create URLSession with timing delegate
        let session = URLSession(configuration: .default, delegate: timingDelegate, delegateQueue: nil)

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

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if uploadStartTime == nil {
            uploadStartTime = Date()
            requestStartTime = requestStartTime ?? Date()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        uploadEndTime = Date()
        downloadStartTime = Date()

        if let uploadStart = uploadStartTime {
            uploadTime = uploadEndTime!.timeIntervalSince(uploadStart)
        }

        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if downloadEndTime == nil {
            downloadEndTime = Date()
            if let downloadStart = downloadStartTime {
                downloadTime = downloadEndTime!.timeIntervalSince(downloadStart)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        downloadEndTime = downloadEndTime ?? Date()

        if let downloadStart = downloadStartTime {
            downloadTime = downloadEndTime!.timeIntervalSince(downloadStart)
        }

        if let requestStart = requestStartTime {
            totalNetworkTime = downloadEndTime!.timeIntervalSince(requestStart)
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