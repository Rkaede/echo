import Foundation
import SwiftUI
import CoreGraphics

enum RecordingStatus: String {
    case idle
    case initiatingRecording = "initiating recording"
    case recording
    case processing
    case postProcessing = "post-processing"
    case inserted
    case cancelled
    case noSpeechDetected = "no speech detected"
    case confirmingCancel = "confirming cancel"
    case error
}

enum ErrorCategory: String {
    case network = "Network"
    case apiKey = "API Key"
    case permission = "Permission"
    case audio = "Audio"
    case unknown = "Unknown"

    static func categorize(from errorMessage: String) -> ErrorCategory {
        let lowercased = errorMessage.lowercased()

        if lowercased.contains("network") || lowercased.contains("connection") ||
           lowercased.contains("timeout") || lowercased.contains("unreachable") {
            return .network
        } else if lowercased.contains("api key") || lowercased.contains("unauthorized") ||
                  lowercased.contains("authentication") || lowercased.contains("401") {
            return .apiKey
        } else if lowercased.contains("permission") || lowercased.contains("access denied") ||
                  lowercased.contains("microphone") || lowercased.contains("accessibility") {
            return .permission
        } else if lowercased.contains("audio") || lowercased.contains("recording") ||
                  lowercased.contains("microphone") {
            return .audio
        } else {
            return .unknown
        }
    }
}

enum RecordingMode {
    case toggle      // Fn tap (hands-free)
    case pushToTalk  // Fn key hold
}

@MainActor
class AppState: ObservableObject {
    private let loggerCategory = "AppState"

    @Published var status: RecordingStatus = .idle
    @Published var transcriptionText: String = ""
    @Published var errorMessage: String = ""
    @Published var errorCategory: ErrorCategory? = nil
    @Published var errorRecoveryHint: String? = nil
    @Published var currentInputDevice: String = ""
    @Published var recordingMode: RecordingMode? = nil
    // The live mic level is deliberately not published here: it changes ~33 times a second
    // and would re-render everything observing AppState. See AudioLevelMeter.
    @Published var showingProfileName: String? = nil
    @Published var showingProfileIconName: String? = nil
    @Published var showingProfileColorToken: String? = nil

    private var confirmationTimeoutTask: Task<Void, Never>?
    private var statusResetTask: Task<Void, Never>?
    private var _previousStatusBeforeConfirmation: RecordingStatus?
    private var profileDisplayTimeoutTask: Task<Void, Never>?

    init() {}
    
    func updateStatus(_ newStatus: RecordingStatus) {
        // Prevent stale async updates from overwriting cancelled state, but allow a new recording session.
        if status == .cancelled && newStatus != .idle && newStatus != .initiatingRecording {
            log("Ignoring state change from cancelled to \(newStatus)", category: loggerCategory, level: .debug)
            return
        }

        // Clear confirmation timeout if transitioning away from confirmation
        if status == .confirmingCancel && newStatus != .confirmingCancel {
            confirmationTimeoutTask?.cancel()
            confirmationTimeoutTask = nil
            _previousStatusBeforeConfirmation = nil
        }

        // Clear error message and category when transitioning away from error state
        if status == .error && newStatus != .error {
            errorMessage = ""
            errorCategory = nil
            errorRecoveryHint = nil
        }

        // Any non-transient transition should cancel pending auto-reset from a previous status.
        statusResetTask?.cancel()
        statusResetTask = nil

        log("Status changing from \(status) to \(newStatus)", category: loggerCategory, level: .info)
        status = newStatus

        // Auto-dismiss transient statuses only if they are still active when the delay ends.
        if newStatus == .inserted || newStatus == .cancelled || newStatus == .noSpeechDetected {
            scheduleStatusReset(for: newStatus, afterNanoseconds: 2_000_000_000)
        } else if newStatus == .error {
            // Auto-dismiss errors after 3.5 seconds (longer than success states)
            scheduleStatusReset(for: newStatus, afterNanoseconds: 3_500_000_000)
        }
    }

    private func scheduleStatusReset(for expectedStatus: RecordingStatus, afterNanoseconds delay: UInt64) {
        statusResetTask = Task {
            do {
                try await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                guard self.status == expectedStatus else { return }
                self.status = .idle
                self.recordingMode = nil
            } catch {
                // Task was cancelled, which is expected
            }
        }
    }
    
    func setError(_ message: String, recoveryHint: String? = nil) {
        // Prevent overwriting cancelled state with error
        if status == .cancelled {
            log("Ignoring error '\(message)' due to cancelled state", category: loggerCategory, level: .warning)
            return
        }

        log("Setting error: \(message)", category: loggerCategory, level: .error)
        errorMessage = message
        errorCategory = ErrorCategory.categorize(from: message)
        errorRecoveryHint = recoveryHint
        status = .error
        log("Error categorized as: \(errorCategory?.rawValue ?? "Unknown")", category: loggerCategory, level: .debug)
    }

    func clearError() {
        errorMessage = ""
        errorCategory = nil
        errorRecoveryHint = nil
        if status == .error {
            status = .idle
        }
    }
    
    func startConfirmingCancel() {
        // Only start confirmation if currently recording or processing in toggle mode
        guard recordingMode == .toggle && (status == .recording || status == .processing) else {
            log("Cannot start confirmation - not in toggle mode or invalid status: \(status)", category: loggerCategory, level: .debug)
            return
        }

        _previousStatusBeforeConfirmation = status
        status = .confirmingCancel

        // Start 5-second timeout
        confirmationTimeoutTask = Task {
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                returnFromConfirmation()
            } catch {
                // Task was cancelled, which is expected
            }
        }

        log("Started cancellation confirmation (5 second timeout)", category: loggerCategory, level: .info)
    }

    func returnFromConfirmation() {
        guard status == .confirmingCancel else { return }

        confirmationTimeoutTask?.cancel()
        confirmationTimeoutTask = nil

        if let previousStatus = _previousStatusBeforeConfirmation {
            log("Confirmation timed out, returning to \(previousStatus)", category: loggerCategory, level: .info)
            status = previousStatus
        } else {
            log("Confirmation timed out, returning to recording", category: loggerCategory, level: .info)
            status = .recording
        }

        _previousStatusBeforeConfirmation = nil
    }

    func setRecordingMode(_ mode: RecordingMode) {
        recordingMode = mode
        log("Recording mode set to \(mode)", category: loggerCategory, level: .info)
    }
    
    var previousStatusBeforeConfirmation: RecordingStatus? {
        return _previousStatusBeforeConfirmation
    }
    
    func resetToIdle() {
        log("Force resetting to idle state", category: loggerCategory, level: .info)
        confirmationTimeoutTask?.cancel()
        confirmationTimeoutTask = nil
        statusResetTask?.cancel()
        statusResetTask = nil
        profileDisplayTimeoutTask?.cancel()
        profileDisplayTimeoutTask = nil
        _previousStatusBeforeConfirmation = nil
        errorMessage = ""
        errorCategory = nil
        errorRecoveryHint = nil
        status = .idle
        recordingMode = nil
        showingProfileName = nil
        showingProfileIconName = nil
        showingProfileColorToken = nil
    }
    
    func showProfileSwitch(_ profile: Profile) {
        // Cancel any existing profile display timeout
        profileDisplayTimeoutTask?.cancel()

        // Show the profile name with a smooth transition
        withAnimation(.easeInOut(duration: 0.2)) {
            showingProfileName = profile.title
            showingProfileIconName = profile.iconName
            showingProfileColorToken = profile.iconColor
        }
        log("Showing profile switch to: \(profile.title)", category: loggerCategory, level: .info)

        // Set timeout to fade back to recording device after 2 seconds
        profileDisplayTimeoutTask = Task {
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.showingProfileName = nil
                        self.showingProfileIconName = nil
                        self.showingProfileColorToken = nil
                    }
                    log("Profile display timeout - returning to recording device", category: self.loggerCategory, level: .debug)
                }
            } catch {
                // Task was cancelled, which is expected
            }
        }
    }
    
    func clearProfileDisplay() {
        profileDisplayTimeoutTask?.cancel()
        profileDisplayTimeoutTask = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            showingProfileName = nil
            showingProfileIconName = nil
            showingProfileColorToken = nil
        }
    }
}
