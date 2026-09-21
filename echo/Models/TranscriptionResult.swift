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

        /// Whisper's per-segment confidence signals, used by `SpeechGate` to spot text the
        /// model invented over silence. Optional because not every model returns them —
        /// a missing value means "cannot judge", not "this is speech".
        let averageLogProbability: Double?
        let noSpeechProbability: Double?
        let compressionRatio: Double?

        // The response is snake_case and the decoder uses no key strategy, so every key
        // has to be spelled out here, not just the renamed ones.
        enum CodingKeys: String, CodingKey {
            case id
            case start
            case end
            case text
            case averageLogProbability = "avg_logprob"
            case noSpeechProbability = "no_speech_prob"
            case compressionRatio = "compression_ratio"
        }
    }
}
