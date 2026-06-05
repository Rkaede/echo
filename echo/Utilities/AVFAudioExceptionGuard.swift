import Foundation

enum AVFAudioExceptionGuard {
  static func run<T>(operation: String, _ body: () throws -> T) throws -> T {
    var result: Result<T, Error>?
    var exceptionError: NSError?

    var succeeded = true
    do {
      try ECHObjCExceptionCatcher.`try` {
        do {
          result = .success(try body())
        } catch {
          result = .failure(error)
        }
      }
    } catch let error as NSError {
      exceptionError = error
      succeeded = false
    }

    guard succeeded else {
      let reason =
        exceptionError?.userInfo[ECHObjCExceptionReasonErrorKey] as? String
        ?? exceptionError?.localizedDescription
        ?? "Unknown Objective-C exception"
      throw UnifiedAudioEngineError.avfaudioException(operation: operation, reason: reason)
    }

    switch result {
    case .success(let value):
      return value
    case .failure(let error):
      throw error
    case .none:
      throw UnifiedAudioEngineError.avfaudioException(
        operation: operation,
        reason: "Operation completed without a result"
      )
    }
  }
}
