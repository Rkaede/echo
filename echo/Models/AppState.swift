import Foundation
import SwiftUI

enum RecordingStatus: String {
    case idle
    case initiatingRecording = "initiating recording"
    case recording
    case processing
    case inserted
    case cancelled
    case confirmingCancel = "confirming cancel"
    case error
}

enum RecordingMode {
    case toggle      // Option+Space
    case pushToTalk  // Fn key hold
}

@MainActor
class AppState: ObservableObject {
    
    @Published var status: RecordingStatus = .idle
    @Published var transcriptionText: String = ""
    @Published var errorMessage: String = ""
    @Published var currentInputDevice: String = ""
    @Published var recordingMode: RecordingMode? = nil
    
    private var confirmationTimeoutTask: Task<Void, Never>?
    private var _previousStatusBeforeConfirmation: RecordingStatus?
    
    init() {}
    
    func updateStatus(_ newStatus: RecordingStatus) {
        // Prevent overwriting cancelled state unless transitioning to idle
        if status == .cancelled && newStatus != .idle {
            print("AppState: Ignoring state change from cancelled to \(newStatus)")
            return
        }
        
        // Clear confirmation timeout if transitioning away from confirmation
        if status == .confirmingCancel && newStatus != .confirmingCancel {
            confirmationTimeoutTask?.cancel()
            confirmationTimeoutTask = nil
            _previousStatusBeforeConfirmation = nil
        }
        
        // Clear error message when transitioning away from error state
        if status == .error && newStatus != .error {
            errorMessage = ""
        }
        
        status = newStatus
        
        // If status is inserted or cancelled, automatically return to idle after 2 seconds
        if newStatus == .inserted || newStatus == .cancelled {
            Task {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                self.status = .idle
                self.recordingMode = nil
            }
        }
    }
    
    func setError(_ message: String) {
        // Prevent overwriting cancelled state with error
        if status == .cancelled {
            print("AppState: Ignoring error '\(message)' due to cancelled state")
            return
        }
        
        errorMessage = message
        status = .error
    }
    
    func clearError() {
        errorMessage = ""
        if status == .error {
            status = .idle
        }
    }
    
    func startConfirmingCancel() {
        // Only start confirmation if currently recording or processing in toggle mode
        guard recordingMode == .toggle && (status == .recording || status == .processing) else {
            print("AppState: Cannot start confirmation - not in toggle mode or invalid status: \(status)")
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
        
        print("AppState: Started cancellation confirmation (5 second timeout)")
    }
    
    func returnFromConfirmation() {
        guard status == .confirmingCancel else { return }
        
        confirmationTimeoutTask?.cancel()
        confirmationTimeoutTask = nil
        
        if let previousStatus = _previousStatusBeforeConfirmation {
            print("AppState: Confirmation timed out, returning to \(previousStatus)")
            status = previousStatus
        } else {
            print("AppState: Confirmation timed out, returning to recording")
            status = .recording
        }
        
        _previousStatusBeforeConfirmation = nil
    }
    
    func setRecordingMode(_ mode: RecordingMode) {
        recordingMode = mode
        print("AppState: Recording mode set to \(mode)")
    }
    
    var previousStatusBeforeConfirmation: RecordingStatus? {
        return _previousStatusBeforeConfirmation
    }
    
    func resetToIdle() {
        print("AppState: Force resetting to idle state")
        confirmationTimeoutTask?.cancel()
        confirmationTimeoutTask = nil
        _previousStatusBeforeConfirmation = nil
        errorMessage = ""
        status = .idle
        recordingMode = nil
    }
}
