import Foundation

struct TranscriptionHistory: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let transcribedText: String
    let duration: TimeInterval
    let audioFileReference: String?
    let languageDetected: String?
    let modelUsed: String
    let wordCount: Int
    let applicationContext: String?
    let uploadTime: TimeInterval          // Legacy field: total time from upload start to completion (upload + server + download)
    let pureUploadTime: TimeInterval      // New: actual upload time only
    let downloadTime: TimeInterval        // New: response download time
    let totalNetworkTime: TimeInterval    // New: upload + download time
    let groqProcessingTime: TimeInterval
    let totalTranscriptionTime: TimeInterval
    let confidence: Double?
    let searchSnippet: String?
    
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        transcribedText: String,
        duration: TimeInterval,
        audioFileReference: String? = nil,
        languageDetected: String? = nil,
        modelUsed: String,
        wordCount: Int? = nil,
        applicationContext: String? = nil,
        uploadTime: TimeInterval = 0,
        pureUploadTime: TimeInterval = 0,
        downloadTime: TimeInterval = 0,
        totalNetworkTime: TimeInterval = 0,
        groqProcessingTime: TimeInterval = 0,
        totalTranscriptionTime: TimeInterval = 0,
        confidence: Double? = nil,
        searchSnippet: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.transcribedText = transcribedText
        self.duration = duration
        self.audioFileReference = audioFileReference
        self.languageDetected = languageDetected
        self.modelUsed = modelUsed
        self.wordCount = wordCount ?? transcribedText.split(separator: " ").count
        self.applicationContext = applicationContext
        self.uploadTime = uploadTime
        self.pureUploadTime = pureUploadTime
        self.downloadTime = downloadTime
        self.totalNetworkTime = totalNetworkTime
        self.groqProcessingTime = groqProcessingTime
        self.totalTranscriptionTime = totalTranscriptionTime
        self.confidence = confidence
        self.searchSnippet = searchSnippet
    }
}

extension TranscriptionHistory {
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    var relativeTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
    
    var formattedDuration: String {
        let seconds = Int(duration)
        if seconds < 60 {
            return "\(seconds)s"
        } else {
            let minutes = seconds / 60
            let remainingSeconds = seconds % 60
            return "\(minutes)m \(remainingSeconds)s"
        }
    }
    
    var truncatedText: String {
        if transcribedText.count <= 50 {
            return transcribedText
        }
        return String(transcribedText.prefix(50)) + "..."
    }
    
    var displayText: AttributedString {
        if let snippet = searchSnippet {
            return snippet.htmlToAttributedString()
        } else {
            return AttributedString(truncatedText)
        }
    }
}

extension String {
    func htmlToAttributedString() -> AttributedString {
        let htmlString = self
            .replacingOccurrences(of: "<b>", with: "**")
            .replacingOccurrences(of: "</b>", with: "**")
        
        do {
            return try AttributedString(markdown: htmlString)
        } catch {
            // Fallback to plain text if markdown parsing fails
            return AttributedString(self.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
        }
    }
}