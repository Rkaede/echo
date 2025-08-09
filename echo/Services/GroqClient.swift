import Foundation

class GroqAPIClient {
    static let shared = GroqAPIClient()
    
    private init() {}
    
    private let baseURL = "https://api.groq.com/openai/v1/audio/transcriptions"
    
    func transcribeAudio(fileURL: URL, apiKey: String) async throws -> TranscriptionResult {
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
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        let result = try JSONDecoder().decode(TranscriptionResult.self, from: data)
        return result
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