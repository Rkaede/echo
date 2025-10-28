import Foundation

/// Lightweight logger that wraps `print` while allowing callers to scope output by log level and category.
final class LoggingService {
  static let shared = LoggingService()

  enum LogLevel: String, CaseIterable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
  }

  struct Configuration {
    var isEnabled: Bool = true
    var categoryOverrides: [String: Bool] = [:]

    static let `default` = Configuration()
  }

  private let configurationQueue = DispatchQueue(label: "com.echo.LoggingService.configuration")
  private var configuration: Configuration
  private static let levelLabelLength: Int = {
    LogLevel.allCases.map { "[\($0.rawValue)]".count }.max() ?? 0
  }()

  init(configuration: Configuration = .default) {
    self.configuration = configuration
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
    let output: String
    if let category {
      output = "\(levelLabel) [\(category)] \(messageProvider())"
    } else {
      output = "\(levelLabel) \(messageProvider())"
    }

    print(output)
    return output
  }

  private func formattedLevel(_ level: LogLevel) -> String {
    let label = "[\(level.rawValue)]"
    return label.padding(toLength: Self.levelLabelLength, withPad: " ", startingAt: 0)
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
