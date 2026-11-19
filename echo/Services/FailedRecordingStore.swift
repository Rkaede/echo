import Foundation

/// Keeps recordings whose transcription failed, so a long dictation is not lost to a network
/// error. The latest can be retried from the menu bar. Only the most recent few are kept,
/// as an hour of audio is over 100 MB.
@MainActor
final class FailedRecordingStore: ObservableObject {
  static let shared = FailedRecordingStore()
  static let keepCount = 3

  /// The most recent failed recording, if any.
  @Published private(set) var latest: URL?

  private let directory: URL

  init(directory: URL? = nil) {
    self.directory =
      directory
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Echo/failed-recordings", isDirectory: true)
    latest = recordings().first
  }

  /// Copies `recording` into the store. Returns the kept copy, or nil if it could not be saved.
  @discardableResult
  func save(_ recording: URL, at date: Date = Date()) -> URL? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let stamp = formatter.string(from: date)
    var destination = directory.appendingPathComponent("recording-\(stamp).wav")
    var suffix = 2
    while FileManager.default.fileExists(atPath: destination.path) {
      destination = directory.appendingPathComponent("recording-\(stamp)-\(suffix).wav")
      suffix += 1
    }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try FileManager.default.copyItem(at: recording, to: destination)
    } catch {
      log("Could not keep failed recording: \(error)", category: "FailedRecordingStore", level: .error)
      return nil
    }
    for old in recordings().dropFirst(Self.keepCount) {
      try? FileManager.default.removeItem(at: old)
    }
    latest = recordings().first
    return destination
  }

  func remove(_ recording: URL) {
    try? FileManager.default.removeItem(at: recording)
    latest = recordings().first
  }

  /// Newest first. File names start with a sortable timestamp.
  private func recordings() -> [URL] {
    let files =
      (try? FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil)) ?? []
    return files.filter { $0.pathExtension == "wav" }
      .sorted { $0.lastPathComponent > $1.lastPathComponent }
  }
}
