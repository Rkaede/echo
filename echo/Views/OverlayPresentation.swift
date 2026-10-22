import Foundation

enum OverlayStatusTone: Equatable {
  case neutral
  case preparing
  case recording
  case processing
  case postProcessing
  case success
  case cancelled
  case confirming
  case error
}

struct OverlayPresentation {
  static func statusIconName(
    for status: RecordingStatus,
    recordingIconName: String
  ) -> String {
    switch status {
    case .idle:
      return "mic.circle"
    case .initiatingRecording:
      return "clock.circle.fill"
    case .recording:
      return recordingIconName
    case .processing:
      return "sparkles"
    case .postProcessing:
      return "wand.and.rays"
    case .inserted:
      return "checkmark.circle.fill"
    case .cancelled:
      return "xmark.circle.fill"
    case .noSpeechDetected:
      return "waveform.slash"
    case .confirmingCancel:
      return "questionmark.circle.fill"
    case .error:
      return "exclamationmark.circle.fill"
    }
  }

  static func statusTone(for status: RecordingStatus) -> OverlayStatusTone {
    switch status {
    case .idle:
      return .neutral
    case .initiatingRecording:
      return .preparing
    case .recording:
      return .recording
    case .processing:
      return .processing
    case .postProcessing:
      return .postProcessing
    case .inserted:
      return .success
    case .cancelled:
      return .cancelled
    case .noSpeechDetected:
      // Same muted tone as a cancellation: nothing went wrong, nothing was pasted.
      return .cancelled
    case .confirmingCancel:
      return .confirming
    case .error:
      return .error
    }
  }

  static func statusText(for status: RecordingStatus) -> String {
    switch status {
    case .initiatingRecording:
      return "Preparing mic..."
    case .recording:
      return "Speak now"
    case .inserted:
      return "Done"
    case .noSpeechDetected:
      return "No speech detected"
    case .confirmingCancel:
      return "Are you sure? (Esc)"
    default:
      return status.rawValue.capitalized
    }
  }

  static func displayText(
    status: RecordingStatus,
    showingProfileName: String? = nil,
    currentInputDevice _: String = ""
  ) -> String {
    if let profileName = showingProfileName {
      return profileName
    }

    return statusText(for: status)
  }

  static func shouldShowWaveform(for status: RecordingStatus) -> Bool {
    status == .recording
  }

  /// The line under "Notes mode" between recordings: what the note holds so far, and
  /// whether screenshots are off because Screen Recording isn't allowed.
  static func notesModeDetail(entryCount: Int, screenshotsAvailable: Bool) -> String {
    let entries = entryCount == 1 ? "1 entry" : "\(entryCount) entries"
    switch (entryCount, screenshotsAvailable) {
    case (0, true):
      return "Press Fn to add an entry"
    case (0, false):
      return "Screenshots off"
    case (_, true):
      return entries
    case (_, false):
      return "\(entries), no screenshots"
    }
  }
}
