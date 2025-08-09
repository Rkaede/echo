import Foundation
import SwiftUI

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
}
