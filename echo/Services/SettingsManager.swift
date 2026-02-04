import Foundation
import SwiftUI

enum AudioEngineIdlePolicy: String, CaseIterable {
  case stopWhenIdle
  case idleTimeout
  case alwaysOn
}

@MainActor
class SettingsManager: ObservableObject {
  static let shared = SettingsManager()
  
  private let keychainManager = KeychainManager.shared
  private var hasLoadedAPIKey = false
  private var hasMigrated = false
  private var cachedAPIKey: String = ""

  // All settings using @AppStorage for consistent storage
  @AppStorage("autoStart") var autoStart = false
  @AppStorage("showInDock") var showInDock = false
  @AppStorage("audioQuality") var audioQuality = "High"
  @AppStorage("autoTranscribe") var autoTranscribe = true
  @AppStorage("selectedModel") var selectedModel = Constants.API.whisperModel
  @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false
  @AppStorage("restoreClipboard") var restoreClipboard = true
  @AppStorage("enableHistory") var enableHistory = false
  @AppStorage("saveAudioWithHistory") var saveAudioWithHistory = false
  @AppStorage("audioStoragePath") var audioStoragePath = ""
  @AppStorage("audioStorageBookmark") var audioStorageBookmark = Data()
  @AppStorage("soundEnabled") var soundEnabled = true
  @AppStorage("soundOnRecordingStart") var soundOnRecordingStart = true
  @AppStorage("soundOnTranscriptionComplete") var soundOnTranscriptionComplete = true
  @AppStorage("recordingStartSound") var recordingStartSound = "click01"
  @AppStorage("transcriptionCompleteSound") var transcriptionCompleteSound = "click02"
  @AppStorage("audioEngineIdlePolicyRaw") var audioEngineIdlePolicyRaw = AudioEngineIdlePolicy.stopWhenIdle.rawValue
  @AppStorage("audioEngineIdleTimeoutSeconds") var audioEngineIdleTimeoutSeconds = 10

  var audioEngineIdlePolicy: AudioEngineIdlePolicy {
    get { AudioEngineIdlePolicy(rawValue: audioEngineIdlePolicyRaw) ?? .stopWhenIdle }
    set { audioEngineIdlePolicyRaw = newValue.rawValue }
  }
  
  // API key uses lazy loading to avoid immediate keychain access
  var apiKey: String {
    get {
      if !hasLoadedAPIKey {
        loadAPIKeyIfNeeded()
      }
      return cachedAPIKey
    }
    set {
      let oldValue = cachedAPIKey
      cachedAPIKey = newValue
      hasLoadedAPIKey = true
      
      if newValue != oldValue {
        if newValue.isEmpty {
          keychainManager.deleteAPIKey()
        } else {
          _ = keychainManager.saveAPIKey(newValue)
        }
        objectWillChange.send()
      }
    }
  }

  // Computed property for API key status - uses cached value to avoid keychain access
  var hasAPIKey: Bool {
    // If we haven't loaded the key yet, assume we don't have one
    // This prevents keychain access on app startup
    if !hasLoadedAPIKey {
      return false
    }
    return !cachedAPIKey.isEmpty
  }

  private init() {
    // Don't load anything on init - wait until needed
  }
  
  private func loadAPIKeyIfNeeded() {
    guard !hasLoadedAPIKey else { return }
    
    // Perform migration only once when first accessing the API key
    if !hasMigrated {
      keychainManager.migrateFromUserDefaults()
      hasMigrated = true
    }
    
    // Load API key from keychain
    if let storedKey = keychainManager.getAPIKey() {
      cachedAPIKey = storedKey
    }
    
    hasLoadedAPIKey = true
  }

  func clearAPIKey() {
    cachedAPIKey = ""
    hasLoadedAPIKey = true
    keychainManager.deleteAPIKey()
    objectWillChange.send()
  }
  
  // Force load the API key when user explicitly needs it (e.g., starting recording)
  func ensureAPIKeyLoaded() {
    if !hasLoadedAPIKey {
      loadAPIKeyIfNeeded()
    }
  }
  
  // MARK: - Security-Scoped Bookmark Management
  
  /// Sets a custom audio storage directory with security-scoped bookmark
  /// - Parameter url: The directory URL to set
  func setAudioStorageDirectory(_ url: URL) {
    // Store the path for display purposes
    audioStoragePath = url.path
    
    // Create and store security-scoped bookmark
    do {
      let bookmarkData = try url.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      audioStorageBookmark = bookmarkData
      print("SettingsManager: Saved security-scoped bookmark for \(url.path)")
    } catch {
      print("SettingsManager: Failed to create security-scoped bookmark: \(error)")
      // Clear bookmark on failure but keep path for display
      audioStorageBookmark = Data()
    }
  }
  
  /// Resolves the security-scoped bookmark to access the custom directory
  /// - Returns: The resolved URL if bookmark is valid, nil otherwise
  /// - Note: This method does NOT start security-scoped resource access. Use withSecurityScopedAccess() for file operations.
  func resolveAudioStorageDirectory() -> URL? {
    guard !audioStorageBookmark.isEmpty else {
      return nil
    }

    do {
      var isStale = false
      let resolvedURL = try URL(
        resolvingBookmarkData: audioStorageBookmark,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )

      if isStale {
        print("SettingsManager: Security-scoped bookmark is stale, clearing")
        audioStorageBookmark = Data()
        return nil
      }

      print("SettingsManager: Resolved security-scoped bookmark to \(resolvedURL.path)")
      return resolvedURL

    } catch {
      print("SettingsManager: Failed to resolve security-scoped bookmark: \(error)")
      audioStorageBookmark = Data()
      return nil
    }
  }

  /// Executes a closure with security-scoped access to the custom directory
  /// - Parameter operation: The closure to execute with the directory URL
  /// - Returns: The result of the operation, or nil if bookmark resolution fails
  /// - Note: Properly manages startAccessingSecurityScopedResource/stopAccessingSecurityScopedResource lifecycle
  func withSecurityScopedAccess<T>(_ operation: (URL) throws -> T) rethrows -> T? {
    guard let url = resolveAudioStorageDirectory() else {
      return nil
    }

    // Start accessing the security-scoped resource
    guard url.startAccessingSecurityScopedResource() else {
      print("SettingsManager: Failed to start accessing security-scoped resource")
      return nil
    }

    // Ensure we always stop accessing the resource when done
    defer {
      url.stopAccessingSecurityScopedResource()
    }

    return try operation(url)
  }
  
  /// Clears the custom audio storage directory and bookmark
  func clearAudioStorageDirectory() {
    audioStoragePath = ""
    audioStorageBookmark = Data()
  }
}
