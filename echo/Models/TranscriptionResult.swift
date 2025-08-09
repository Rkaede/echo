import Foundation

struct TranscriptionResult: Codable {
    let text: String
    let language: String?
    let duration: Double?
    let segments: [Segment]?
    
    struct Segment: Codable {
        let id: Int
        let start: Double
        let end: Double
        let text: String
    }
}