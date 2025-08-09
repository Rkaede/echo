import Foundation

@MainActor
class TempFileManager: ObservableObject {
  static let shared = TempFileManager()
  
  private let tempDirectory: URL
  private let cleanupInterval: TimeInterval = 30 * 60 // 30 minutes
  private let maxFileAge: TimeInterval = 60 * 60 // 1 hour
  private var cleanupTimer: Timer?
  
  private init() {
    self.tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("echo")
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
  
  private func cleanupOrphanedFiles() {
    do {
      let contents = try FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: [.creationDateKey], options: [])
      
      let recordingFiles = contents.filter { url in
        url.lastPathComponent.hasPrefix("recording_") && url.pathExtension == "wav"
      }
      
      var cleanedCount = 0
      let currentTime = Date()
      
      for fileURL in recordingFiles {
        do {
          let resourceValues = try fileURL.resourceValues(forKeys: [.creationDateKey])
          
          if let creationDate = resourceValues.creationDate {
            let fileAge = currentTime.timeIntervalSince(creationDate)
            
            if fileAge > maxFileAge {
              try FileManager.default.removeItem(at: fileURL)
              cleanedCount += 1
              print("TempFileManager: Removed orphaned file: \(fileURL.lastPathComponent) (age: \(Int(fileAge/60)) minutes)")
            }
          } else {
            // If we can't get creation date, err on the side of caution and delete very old files
            try FileManager.default.removeItem(at: fileURL)
            cleanedCount += 1
            print("TempFileManager: Removed file with unknown creation date: \(fileURL.lastPathComponent)")
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
      let recordingFiles = contents.filter { url in
        url.lastPathComponent.hasPrefix("recording_") && url.pathExtension == "wav"
      }
      return (tempDirectory.path, recordingFiles.count)
    } catch {
      print("TempFileManager: Failed to get directory info: \(error)")
      return (tempDirectory.path, 0)
    }
  }
}