import Foundation

class PostProcessingService {
    static let shared = PostProcessingService()
    
    private init() {}
    
    private let client = GroqAPIClient.shared
    
    func processText(_ text: String, promptTemplate: String, postProcessingModel: String) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PostProcessingError.emptyText
        }

        guard let apiKey = KeychainManager.shared.getAPIKey() else {
            throw PostProcessingError.missingAPIKey
        }
        
        // Build final prompt by replacing supported placeholders
        let finalPrompt = promptTemplate
            .replacingOccurrences(of: "{{TRANSCRIPTION}}", with: text)
            .replacingOccurrences(of: "{{TRANSCRIBED_TEXT}}", with: text) // legacy support

        do {
            let processedText = try await client.postProcessText(fullPrompt: finalPrompt, apiKey: apiKey, model: postProcessingModel)
            
            guard !processedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PostProcessingError.emptyResponse
            }
            
            return processedText
        } catch {
            print("PostProcessingService: Error processing text - \(error)")
            throw PostProcessingError.apiError(error)
        }
    }
}

enum PostProcessingError: LocalizedError {
    case emptyText
    case missingAPIKey
    case emptyResponse
    case apiError(Error)
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "No text to process"
        case .missingAPIKey:
            return "API key not found"
        case .emptyResponse:
            return "Empty response from API"
        case .apiError(let error):
            return "API error: \(error.localizedDescription)"
        case .timeout:
            return "Post-processing timed out"
        }
    }
}
