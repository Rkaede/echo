import Foundation
import Sparkle
import SwiftUI

class UpdateManager: ObservableObject {
    private let updaterController: SPUStandardUpdaterController
    private var hasStarted = false

    @Published var automaticChecksEnabled: Bool {
        didSet {
            updaterController.updater.automaticallyChecksForUpdates = automaticChecksEnabled
        }
    }

    @Published var canCheckForUpdates: Bool = false

    var updater: SPUUpdater {
        updaterController.updater
    }

    init(startImmediately: Bool = false) {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: startImmediately,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        self.automaticChecksEnabled = updaterController.updater.automaticallyChecksForUpdates
        self.hasStarted = startImmediately

        // Update canCheckForUpdates based on updater state
        Task { @MainActor in
            self.canCheckForUpdates = updaterController.updater.canCheckForUpdates
        }
    }

    func startUpdater() {
        guard !hasStarted else { return }
        hasStarted = true
        do {
            try updaterController.updater.start()
        } catch {
            print("UpdateManager: Failed to start updater: \(error)")
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
