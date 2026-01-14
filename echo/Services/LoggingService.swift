import AppKit
import Foundation

/// Lightweight logger that wraps `print` while allowing callers to scope output by log level and category.
/// Warnings and errors are also persisted to log files in ~/Library/Application Support/Echo/logs/
final class LoggingService {
  static let shared = LoggingService()

  enum LogLevel: String, CaseIterable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"

    /// Whether this log level should be persisted to file
    var shouldPersist: Bool {
      switch self {
      case .warning, .error:
        return true
      case .debug, .info:
        return false
      }
    }
  }

  struct Configuration {
    var isEnabled: Bool = true
    var categoryOverrides: [String: Bool] = [:]

    static let `default` = Configuration()
  }

  // MARK: - Properties

  private let configurationQueue = DispatchQueue(label: "com.echo.LoggingService.configuration")
  private let fileQueue = DispatchQueue(label: "com.echo.LoggingService.file")
  private var configuration: Configuration
  private static let levelLabelLength: Int = {
    LogLevel.allCases.map { "[\($0.rawValue)]".count }.max() ?? 0
  }()

  // File logging properties
  private let logDirectory: URL
  private let timestampFormatter: ISO8601DateFormatter
  private let fileDateFormatter: DateFormatter
  private var currentLogFileDate: String?
  private var fileHandle: FileHandle?
  private let maxLogAgeDays: Int = 30

  init(configuration: Configuration = .default) {
    self.configuration = configuration

    // Set up log directory
    let appSupportPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let echoDirectory = appSupportPath.appendingPathComponent("Echo")
    self.logDirectory = echoDirectory.appendingPathComponent("logs")

    // Set up timestamp formatter with millisecond precision
    self.timestampFormatter = ISO8601DateFormatter()
    self.timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    // Set up date formatter for file names
    self.fileDateFormatter = DateFormatter()
    self.fileDateFormatter.dateFormat = "yyyy-MM-dd"
    self.fileDateFormatter.timeZone = TimeZone.current

    // Create log directory if needed
    setupLogDirectory()
  }

  var currentConfiguration: Configuration {
    configurationQueue.sync { configuration }
  }

  func configure(_ configuration: Configuration) {
    configurationQueue.sync {
      self.configuration = configuration
    }
  }

  func setCategory(_ category: String, isEnabled: Bool) {
    configurationQueue.sync {
      configuration.categoryOverrides[category] = isEnabled
    }
  }

  func removeCategoryOverride(_ category: String) {
    configurationQueue.sync {
      configuration.categoryOverrides[category] = nil
    }
  }

  private func shouldLog(category: String?) -> Bool {
    configurationQueue.sync {
      if let category, let override = configuration.categoryOverrides[category] {
        return override
      }
      return configuration.isEnabled
    }
  }

  @discardableResult
  func log(
    _ message: @autoclosure () -> String,
    category: String? = nil,
    level: LogLevel = .info
  ) -> String? {
    log(messageProvider: message, category: category, level: level)
  }

  @discardableResult
  func log(
    messageProvider: () -> String,
    category: String? = nil,
    level: LogLevel = .info
  ) -> String? {
    guard shouldLog(category: category) else { return nil }

    let levelLabel = formattedLevel(level)
    let message = messageProvider()
    let output: String
    if let category {
      output = "\(levelLabel) [\(category)] \(message)"
    } else {
      output = "\(levelLabel) \(message)"
    }

    print(output)

    // Persist warnings and errors to file
    if level.shouldPersist {
      writeToFile(message, category: category, level: level)
    }

    return output
  }

  private func formattedLevel(_ level: LogLevel) -> String {
    let label = "[\(level.rawValue)]"
    return label.padding(toLength: Self.levelLabelLength, withPad: " ", startingAt: 0)
  }

  // MARK: - File Logging

  private func setupLogDirectory() {
    do {
      try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    } catch {
      print("LoggingService: Failed to create log directory: \(error)")
    }
  }

  private func getLogFileURL(for date: Date) -> URL {
    let dateString = fileDateFormatter.string(from: date)
    return logDirectory.appendingPathComponent("echo-\(dateString).log")
  }

  private func writeToFile(_ message: String, category: String?, level: LogLevel) {
    fileQueue.async { [weak self] in
      guard let self else { return }

      let now = Date()
      let dateString = self.fileDateFormatter.string(from: now)

      // Rotate file if date changed
      if dateString != self.currentLogFileDate {
        self.rotateLogFile(to: dateString)
      }

      // Format the log entry with timestamp
      let timestamp = self.timestampFormatter.string(from: now)
      let levelLabel = "[\(level.rawValue)]"
      let logEntry: String
      if let category {
        logEntry = "\(timestamp) \(levelLabel) [\(category)] \(message)\n"
      } else {
        logEntry = "\(timestamp) \(levelLabel) \(message)\n"
      }

      // Write to file
      if let data = logEntry.data(using: .utf8) {
        self.fileHandle?.write(data)
        try? self.fileHandle?.synchronize()
      }
    }
  }

  private func rotateLogFile(to dateString: String) {
    // Close existing file handle
    try? fileHandle?.close()
    fileHandle = nil

    // Open new file for the current date
    let fileURL = logDirectory.appendingPathComponent("echo-\(dateString).log")

    // Create file if it doesn't exist
    if !FileManager.default.fileExists(atPath: fileURL.path) {
      FileManager.default.createFile(atPath: fileURL.path, contents: nil)
    }

    do {
      fileHandle = try FileHandle(forWritingTo: fileURL)
      fileHandle?.seekToEndOfFile()
      currentLogFileDate = dateString
    } catch {
      print("LoggingService: Failed to open log file: \(error)")
    }
  }

  /// Removes log files older than the retention period (30 days)
  func cleanupOldLogs() {
    fileQueue.async { [weak self] in
      guard let self else { return }

      do {
        let contents = try FileManager.default.contentsOfDirectory(
          at: self.logDirectory,
          includingPropertiesForKeys: [.creationDateKey],
          options: []
        )

        let logFiles = contents.filter { $0.pathExtension == "log" }
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -self.maxLogAgeDays, to: Date())!
        var removedCount = 0

        for fileURL in logFiles {
          do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.creationDateKey])
            if let creationDate = resourceValues.creationDate, creationDate < cutoffDate {
              try FileManager.default.removeItem(at: fileURL)
              removedCount += 1
            }
          } catch {
            print("LoggingService: Failed to process log file \(fileURL.lastPathComponent): \(error)")
          }
        }

        if removedCount > 0 {
          print("LoggingService: Cleaned up \(removedCount) old log file(s)")
        }
      } catch {
        print("LoggingService: Failed to list log directory: \(error)")
      }
    }
  }

  /// Returns the URL to the logs directory
  func getLogDirectoryURL() -> URL {
    return logDirectory
  }

  /// Opens the logs folder in Finder
  func openLogsFolder() {
    // Ensure directory exists
    setupLogDirectory()
    NSWorkspace.shared.open(logDirectory)
  }
}

@discardableResult
func log(
  _ message: @autoclosure () -> String,
  category: String? = nil,
  level: LoggingService.LogLevel = .info
) -> String? {
  LoggingService.shared.log(messageProvider: message, category: category, level: level)
}
