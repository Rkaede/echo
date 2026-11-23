import Foundation

@MainActor
class TempFileManager: ObservableObject {
  static let shared = TempFileManager()
  
  private let tempDirectory: URL
  private let cleanupInterval: TimeInterval = 30 * 60 // 30 minutes
  private let maxFileAge: TimeInterval = 60 * 60 // 1 hour
  private var cleanupTimer: Timer?
  
  /// Where recordings are written while they are recorded and transcribed.
  nonisolated static let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("echo")

  /// A recording (`recording_<time>.wav`) or one part of a long one. The parts of a retried
  /// failed recording are named after it (`recording-<date>-part1.wav`), so both spellings count.
  nonisolated static func isRecordingFile(_ url: URL) -> Bool {
    url.lastPathComponent.hasPrefix("recording") && url.pathExtension == "wav"
  }

  private init() {
    self.tempDirectory = Self.directory
    createTempDirectoryIfNeeded()
  }
  
  deinit {
    cleanupTimer?.invalidate()
    cleanupTimer = nil
  }
  
  // MARK: - Public Interface
  
  func startPeriodicCleanup() {
    print("TempFileManager: Starting periodic cleanup (every \(cleanupInterval/60) minutes)")
    
    // Perform initial cleanup
    cleanupOrphanedFiles()
    
    // Schedule periodic cleanup
    cleanupTimer = Timer.scheduledTimer(withTimeInterval: cleanupInterval, repeats: true) { _ in
      Task { @MainActor in
        self.cleanupOrphanedFiles()
      }
    }
  }
  
  func stopPeriodicCleanup() {
    cleanupTimer?.invalidate()
    cleanupTimer = nil
    print("TempFileManager: Stopped periodic cleanup")
  }
  
  func performStartupCleanup() {
    print("TempFileManager: Performing startup cleanup of orphaned files")
    cleanupOrphanedFiles()
  }
  
  // MARK: - Private Methods
  
  private func createTempDirectoryIfNeeded() {
    do {
      try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
      print("TempFileManager: Echo temp directory ready at \(tempDirectory.path)")
    } catch {
      print("TempFileManager: Failed to create temp directory: \(error)")
    }
  }
  
  /// How long ago a file was last written, or nil when neither date is known. A recording
  /// still in progress was created long ago but written a moment ago, so it is judged by
  /// its last write: a dictation of over an hour must not be removed while it is recorded.
  nonisolated static func age(creationDate: Date?, modificationDate: Date?, now: Date) -> TimeInterval? {
    guard let lastWritten = [creationDate, modificationDate].compactMap({ $0 }).max() else {
      return nil
    }
    return now.timeIntervalSince(lastWritten)
  }

  private func cleanupOrphanedFiles() {
    do {
      let dateKeys: Set<URLResourceKey> = [.creationDateKey, .contentModificationDateKey]
      let contents = try FileManager.default.contentsOfDirectory(
        at: tempDirectory, includingPropertiesForKeys: Array(dateKeys), options: [])

      let recordingFiles = contents.filter(Self.isRecordingFile)

      var cleanedCount = 0
      let currentTime = Date()

      for fileURL in recordingFiles {
        do {
          let resourceValues = try fileURL.resourceValues(forKeys: dateKeys)

          if let fileAge = Self.age(
            creationDate: resourceValues.creationDate,
            modificationDate: resourceValues.contentModificationDate,
            now: currentTime)
          {
            if fileAge > maxFileAge {
              try FileManager.default.removeItem(at: fileURL)
              cleanedCount += 1
              print("TempFileManager: Removed orphaned file: \(fileURL.lastPathComponent) (age: \(Int(fileAge/60)) minutes)")
            }
          } else {
            // If we can't get either date, err on the side of caution and delete the file
            try FileManager.default.removeItem(at: fileURL)
            cleanedCount += 1
            print("TempFileManager: Removed file with unknown dates: \(fileURL.lastPathComponent)")
          }
        } catch {
          print("TempFileManager: Failed to process file \(fileURL.lastPathComponent): \(error)")
        }
      }
      
      if cleanedCount > 0 {
        print("TempFileManager: Cleanup completed, removed \(cleanedCount) orphaned files")
      } else {
        print("TempFileManager: No orphaned files found to clean up")
      }
      
    } catch {
      print("TempFileManager: Failed to list temp directory contents: \(error)")
    }
  }
  
  // MARK: - Directory Info (for debugging)
  
  func getTempDirectoryInfo() -> (path: String, fileCount: Int) {
    do {
      let contents = try FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil, options: [])
      let recordingFiles = contents.filter(Self.isRecordingFile)
      return (tempDirectory.path, recordingFiles.count)
    } catch {
      print("TempFileManager: Failed to get directory info: \(error)")
      return (tempDirectory.path, 0)
    }
  }
}