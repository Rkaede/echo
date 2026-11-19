import AVFoundation
import Foundation

/// Splits recordings too long for one transcription request. Groq and OpenRouter accept
/// uploads of up to 25 MB, and Echo records 16 kHz 16-bit mono WAV at about 1.9 MB a minute,
/// so anything over about 13 minutes has to be sent in parts. Each cut is made at the quietest
/// moment shortly before the limit, so words are not split between parts.
enum LongRecordingSplitter {
  /// Ten minutes, about 19 MB a part, which leaves room under the 25 MB limit.
  static let maxPartSeconds: TimeInterval = 600
  /// How far before the limit to look for a pause.
  static let searchSeconds: TimeInterval = 30
  /// Length of the windows compared when looking for the quietest moment.
  static let windowSeconds: TimeInterval = 0.1

  struct Part {
    let url: URL
    let duration: TimeInterval
  }

  /// Frame offsets where each part after the first begins. `quietestFrame` returns the
  /// quietest frame in the range it is given.
  static func cutFrames(
    totalFrames: Int,
    sampleRate: Double,
    maxPartSeconds: TimeInterval = maxPartSeconds,
    searchSeconds: TimeInterval = searchSeconds,
    quietestFrame: (Range<Int>) throws -> Int
  ) rethrows -> [Int] {
    let maxFrames = max(1, Int(maxPartSeconds * sampleRate))
    let searchFrames = min(Int(searchSeconds * sampleRate), maxFrames / 2)
    var cuts: [Int] = []
    var start = 0
    while totalFrames - start > maxFrames {
      let window = (start + maxFrames - searchFrames)..<(start + maxFrames)
      // Clamp, so a bad answer can never stall the loop or overrun the part.
      let cut = min(max(try quietestFrame(window), window.lowerBound), window.upperBound)
      cuts.append(cut)
      start = cut
    }
    return cuts
  }

  /// Writes the parts beside `fileURL` and returns them in order. A recording short enough
  /// for one request comes back as a single part: the original file.
  static func split(
    _ fileURL: URL,
    maxPartSeconds: TimeInterval = maxPartSeconds,
    searchSeconds: TimeInterval = searchSeconds
  ) throws -> [Part] {
    let source = try AVAudioFile(forReading: fileURL)
    let sampleRate = source.processingFormat.sampleRate
    let totalFrames = Int(source.length)
    let cuts = try cutFrames(
      totalFrames: totalFrames, sampleRate: sampleRate, maxPartSeconds: maxPartSeconds,
      searchSeconds: searchSeconds
    ) { range in
      try quietestFrame(in: source, range: range)
    }
    guard !cuts.isEmpty else {
      return [Part(url: fileURL, duration: Double(totalFrames) / sampleRate)]
    }

    let base = fileURL.deletingPathExtension().lastPathComponent
    let directory = fileURL.deletingLastPathComponent()
    var parts: [Part] = []
    do {
      for (index, bounds) in zip([0] + cuts, cuts + [totalFrames]).enumerated() {
        let url = directory.appendingPathComponent("\(base)-part\(index + 1).wav")
        try copyFrames(from: source, range: bounds.0..<bounds.1, to: url)
        parts.append(Part(url: url, duration: Double(bounds.1 - bounds.0) / sampleRate))
      }
    } catch {
      for part in parts { try? FileManager.default.removeItem(at: part.url) }
      throw error
    }
    return parts
  }

  private static func quietestFrame(in file: AVAudioFile, range: Range<Int>) throws -> Int {
    let format = file.processingFormat
    guard
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format, frameCapacity: AVAudioFrameCount(range.count))
    else { return range.upperBound }
    file.framePosition = AVAudioFramePosition(range.lowerBound)
    try file.read(into: buffer, frameCount: AVAudioFrameCount(range.count))
    guard let samples = buffer.floatChannelData?[0] else { return range.upperBound }

    let window = max(1, Int(windowSeconds * format.sampleRate))
    var quietest = (energy: Float.infinity, frame: range.upperBound)
    var offset = 0
    while offset + window <= Int(buffer.frameLength) {
      var energy: Float = 0
      for index in offset..<(offset + window) {
        energy += samples[index] * samples[index]
      }
      if energy < quietest.energy {
        quietest = (energy, range.lowerBound + offset + window / 2)
      }
      offset += window
    }
    return quietest.frame
  }

  private static func copyFrames(from source: AVAudioFile, range: Range<Int>, to url: URL) throws {
    try? FileManager.default.removeItem(at: url)
    let format = source.processingFormat
    let output = try AVAudioFile(
      forWriting: url, settings: source.fileFormat.settings,
      commonFormat: format.commonFormat, interleaved: format.isInterleaved)
    let blockFrames = 1 << 18  // about 16 s at 16 kHz
    guard
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(blockFrames))
    else { throw CocoaError(.fileWriteUnknown) }

    source.framePosition = AVAudioFramePosition(range.lowerBound)
    var remaining = range.count
    while remaining > 0 {
      try source.read(into: buffer, frameCount: AVAudioFrameCount(min(remaining, blockFrames)))
      guard buffer.frameLength > 0 else { break }
      try output.write(from: buffer)
      remaining -= Int(buffer.frameLength)
    }
  }
}
