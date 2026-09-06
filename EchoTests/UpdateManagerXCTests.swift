import Combine
import XCTest

@testable import Echo

@MainActor
final class UpdateManagerXCTests: XCTestCase {
    func testStartsWithoutOpeningSettingsOrCreatingOverlay() async {
        await withAutomaticChecksDisabled {
            let manager = UpdateManager()
            XCTAssertTrue(manager.updater.canCheckForUpdates)
            await expectCheckButtonEnabled(manager)
        }
    }

    func testCheckButtonBecomesEnabledAfterDeferredStartup() async {
        await withAutomaticChecksDisabled {
            let manager = UpdateManager(startImmediately: false)
            XCTAssertFalse(manager.canCheckForUpdates)
            XCTAssertFalse(manager.updater.canCheckForUpdates)

            manager.startUpdater()
            await expectCheckButtonEnabled(manager)

            manager.startUpdater()
            XCTAssertTrue(manager.canCheckForUpdates)
        }
    }

    private func expectCheckButtonEnabled(_ manager: UpdateManager) async {
        let enabled = expectation(description: "Check for Updates becomes available")
        let observation = manager.$canCheckForUpdates
            .filter { $0 }
            .prefix(1)
            .sink { _ in enabled.fulfill() }
        defer { observation.cancel() }

        await fulfillment(of: [enabled], timeout: 2)
    }

    private func withAutomaticChecksDisabled(_ body: () async -> Void) async {
        let defaults = UserDefaults.standard
        let originalArguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = originalArguments
        arguments["SUEnableAutomaticChecks"] = false
        defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(originalArguments, forName: UserDefaults.argumentDomain) }

        await body()
    }
}
