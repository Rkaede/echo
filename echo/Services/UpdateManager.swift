import Foundation
import Sparkle
import SwiftUI

class UpdateManager: ObservableObject {
    private let updaterController: SPUStandardUpdaterController
    
    @Published var automaticChecksEnabled: Bool {
        didSet {
            updaterController.updater.automaticallyChecksForUpdates = automaticChecksEnabled
        }
    }
    
    @Published var canCheckForUpdates: Bool = false
    
    var updater: SPUUpdater {
        updaterController.updater
    }
    
    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        
        self.automaticChecksEnabled = updaterController.updater.automaticallyChecksForUpdates
        
        // Update canCheckForUpdates based on updater state
        Task { @MainActor in
            self.canCheckForUpdates = updaterController.updater.canCheckForUpdates
        }
    }
    
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
    
    func checkForUpdatesInBackground() {
        Task {
            updaterController.updater.checkForUpdatesInBackground()
        }
    }
    
    var lastUpdateCheckDate: Date? {
        updaterController.updater.lastUpdateCheckDate
    }
    
    var automaticUpdateInterval: TimeInterval {
        get {
            updaterController.updater.updateCheckInterval
        }
        set {
            updaterController.updater.updateCheckInterval = newValue
        }
    }
}
