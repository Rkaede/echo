import Combine
import Foundation
import Sparkle
import SwiftUI

@MainActor
class UpdateManager: ObservableObject {
    private let updaterController: SPUStandardUpdaterController
    private var hasStarted = false

    @Published var automaticChecksEnabled: Bool {
        didSet {
            updaterController.updater.automaticallyChecksForUpdates = automaticChecksEnabled
        }
    }

    @Published private(set) var canCheckForUpdates: Bool = false

    var updater: SPUUpdater {
        updaterController.updater
    }

    init(startImmediately: Bool = true) {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        self.automaticChecksEnabled = updaterController.updater.automaticallyChecksForUpdates
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)

        if startImmediately {
            startUpdater()
        }
    }

    func startUpdater() {
        guard !hasStarted else { return }
        do {
            try updaterController.updater.start()
            hasStarted = true
            log("Updater started", category: "UpdateManager", level: .info)
        } catch {
            log("Failed to start updater: \(error)", category: "UpdateManager", level: .error)
        }
    }
    
    func checkForUpdates() {
        startUpdater()
        guard hasStarted else { return }
        updaterController.checkForUpdates(nil)
    }
    
    func checkForUpdatesInBackground() {
        startUpdater()
        guard hasStarted else { return }
        updaterController.updater.checkForUpdatesInBackground()
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
