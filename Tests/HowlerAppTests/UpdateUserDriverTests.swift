import Foundation
import Sparkle
import XCTest
@testable import Howler

/// Exercises Sparkle's reply contract with synthetic callbacks, never a real installer.
final class UpdateUserDriverTests: XCTestCase {
    @MainActor
    func testScheduledOfferWaitsForOneClickThenInstallsAndRelaunchesWithoutAnotherPrompt() async {
        let standard = FixtureUpdateUI()
        let driver = UpdateUserDriver(standard: standard)
        var available: String?
        driver.onAvailable = { available = $0 }
        var installs = 0
        var offers = 0
        driver.offerUpdate(version: "0.1.13", canInstall: true, userInitiated: false,
                           install: { installs += 1 }, present: { offers += 1 })
        XCTAssertEqual(available, "0.1.13")
        XCTAssertEqual(installs, 0)
        XCTAssertEqual(offers, 0)
        XCTAssertTrue(driver.installAvailableUpdate())
        XCTAssertNil(available)
        XCTAssertEqual(installs, 1)
        XCTAssertFalse(driver.installAvailableUpdate())
        XCTAssertEqual(installs, 1)
        var choice: SPUUserUpdateChoice?
        driver.showReady { choice = $0 }
        XCTAssertEqual(choice, .install)
        XCTAssertEqual(standard.readyPrompts, 0)
    }

    @MainActor
    func testManualChecksAndNonInstallableOffersKeepSparklesStandardUI() async {
        for (canInstall, userInitiated) in [(true, true), (false, false), (false, true)] {
            let standard = FixtureUpdateUI()
            let driver = UpdateUserDriver(standard: standard)
            var presented = 0
            var installed = 0
            driver.offerUpdate(version: "0.1.13", canInstall: canInstall, userInitiated: userInitiated,
                               install: { installed += 1 }, present: { presented += 1 })
            XCTAssertEqual(presented, 1)
            XCTAssertFalse(driver.installAvailableUpdate())
            XCTAssertEqual(installed, 0)
            driver.showReady { _ in XCTFail("No automatic reply without a click") }
            XCTAssertEqual(standard.readyPrompts, 1)
        }
    }

    @MainActor
    func testCancelledDownloadAndErrorsDoNotAuthorizeLaterInstallations() async {
        for error in [false, true] {
            let standard = FixtureUpdateUI()
            let driver = UpdateUserDriver(standard: standard)
            driver.offerUpdate(version: "0.1.13", canInstall: true, userInitiated: false, install: {}, present: {})
            XCTAssertTrue(driver.installAvailableUpdate())
            if error {
                var acknowledged = false
                driver.showUpdaterError(NSError(domain: "fixture.update", code: 1)) { acknowledged = true }
                XCTAssertTrue(acknowledged)
            } else {
                var cancelled = false
                driver.showDownloadInitiated { cancelled = true }
                standard.cancelDownload?()
                XCTAssertTrue(cancelled)
            }
            XCTAssertFalse(driver.installAvailableUpdate())
            driver.showReady { _ in XCTFail("Consent must expire on cancel/error") }
            XCTAssertEqual(standard.readyPrompts, 1)
        }
    }

    @MainActor
    func testReplacedAndDismissedOffersCannotInstallStaleVersions() async {
        let standard = FixtureUpdateUI()
        let driver = UpdateUserDriver(standard: standard)
        var old = 0
        var new = 0
        driver.offerUpdate(version: "0.1.13", canInstall: true, userInitiated: false,
                           install: { old += 1 }, present: {})
        driver.offerUpdate(version: "0.1.14", canInstall: true, userInitiated: false,
                           install: { new += 1 }, present: {})
        XCTAssertTrue(driver.installAvailableUpdate())
        XCTAssertEqual(old, 0)
        XCTAssertEqual(new, 1)
        driver.dismissUpdateInstallation()
        driver.showReady { _ in XCTFail("Dismissal ends one-click consent") }
        XCTAssertEqual(standard.readyPrompts, 1)

        var presented = false
        driver.offerUpdate(version: "0.1.15", canInstall: true, userInitiated: false,
                           install: { XCTFail("A manual look is not consent to install") }, present: { presented = true })
        driver.showUpdateInFocus()
        XCTAssertTrue(presented)
        XCTAssertFalse(driver.installAvailableUpdate())
        XCTAssertEqual(standard.focusCalls, 1)
    }

    @MainActor
    func testProgressAndInstallationRemainOwnedBySparkle() async {
        let standard = FixtureUpdateUI()
        let driver = UpdateUserDriver(standard: standard)
        driver.showDownloadDidReceiveExpectedContentLength(100)
        driver.showDownloadDidReceiveData(ofLength: 40)
        driver.showDownloadDidStartExtractingUpdate()
        driver.showExtractionReceivedProgress(0.5)
        driver.showInstallingUpdate(withApplicationTerminated: true, retryTerminatingApplication: {})
        var acknowledged = false
        driver.showUpdateInstalledAndRelaunched(true) { acknowledged = true }
        XCTAssertEqual(standard.events, ["expected:100", "received:40", "extract", "progress:0.5", "install:true", "finished:true"])
        XCTAssertTrue(acknowledged)
    }
}

@MainActor
private final class FixtureUpdateUI: NSObject, SPUUserDriver {
    var readyPrompts = 0
    var focusCalls = 0
    var events: [String] = []
    var cancelDownload: (() -> Void)?
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {}
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {}
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { cancelDownload = cancellation }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) { events.append("expected:\(expectedContentLength)") }
    func showDownloadDidReceiveData(ofLength length: UInt64) { events.append("received:\(length)") }
    func showDownloadDidStartExtractingUpdate() { events.append("extract") }
    func showExtractionReceivedProgress(_ progress: Double) { events.append("progress:\(progress)") }
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { readyPrompts += 1 }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) { events.append("install:\(applicationTerminated)") }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { events.append("finished:\(relaunched)"); acknowledgement() }
    func dismissUpdateInstallation() { cancelDownload = nil }
    func showUpdateInFocus() { focusCalls += 1 }
}
