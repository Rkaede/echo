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
    @Published var currentInputLevel: CGFloat = 0
    @Published var showingProfileName: String? = nil
    @Published var showingProfileIconName: String? = nil
    @Published var showingProfileColorToken: String? = nil
    
    @Published var isHistoryWindowOpen: Bool = false
    @Published var historyCount: Int = 0
    @Published var recentTranscriptions: [TranscriptionHistory] = []
    
    private var confirmationTimeoutTask: Task<Void, Never>?
    private var _previousStatusBeforeConfirmation: RecordingStatus?
    private var profileDisplayTimeoutTask: Task<Void, Never>?
    
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
        
        print("AppState: Status changing from \(status) to \(newStatus)")
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
        
        print("AppState: Setting error: \(message)")
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
        profileDisplayTimeoutTask?.cancel()
        profileDisplayTimeoutTask = nil
        _previousStatusBeforeConfirmation = nil
        errorMessage = ""
        status = .idle
        recordingMode = nil
        showingProfileName = nil
        currentInputLevel = 0
        showingProfileIconName = nil
        showingProfileColorToken = nil
    }
    
    func updateHistoryState(count: Int, recent: [TranscriptionHistory]) {
        historyCount = count
        recentTranscriptions = recent
    }
    
    func toggleHistoryWindow() {
        isHistoryWindowOpen.toggle()
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
        print("AppState: Showing profile switch to: \(profile.title)")
        
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
                    print("AppState: Profile display timeout - returning to recording device")
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
