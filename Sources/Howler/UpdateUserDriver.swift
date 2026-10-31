import Foundation
import Sparkle

/// Defers ordinary scheduled offers to Howler's Update button. Sparkle still owns
/// downloading, validation, installation, progress, cancellation and error UI.
@MainActor
final class UpdateUserDriver: NSObject, SPUUserDriver {
    private let standard: SPUUserDriver
    var onAvailable: ((String?) -> Void)?
    private var pendingInstall: (() -> Void)?
    private var pendingPresentation: (() -> Void)?
    private var installOnReady = false

    init(standard: SPUUserDriver) {
        self.standard = standard
    }

    /// One explicit click authorizes this offer only, not future automatic updates.
    @discardableResult
    func installAvailableUpdate() -> Bool {
        guard let install = pendingInstall else { return false }
        pendingInstall = nil
        pendingPresentation = nil
        installOnReady = true
        onAvailable?(nil)
        install()
        return true
    }

    func offerUpdate(version: String, canInstall: Bool, userInitiated: Bool,
                     install: @escaping () -> Void, present: @escaping () -> Void) {
        reset()
        guard canInstall, !userInitiated else {
            present()
            return
        }
        pendingInstall = install
        pendingPresentation = present
        onAvailable?(version)
    }

    private func reset() {
        pendingInstall = nil
        pendingPresentation = nil
        installOnReady = false
        onAvailable?(nil)
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        offerUpdate(version: appcastItem.displayVersionString,
                    canInstall: !appcastItem.isInformationOnlyUpdate && !appcastItem.isMajorUpgrade,
                    userInitiated: state.userInitiated,
                    install: { reply(.install) },
                    present: { [weak self] in
            self?.standard.showUpdateFound(with: appcastItem, state: state, reply: reply)
        })
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        if installOnReady {
            reply(.install)
        } else {
            standard.showReady(toInstallAndRelaunch: reply)
        }
    }

    func showUpdateInFocus() {
        if let present = pendingPresentation {
            reset()
            present()
        }
        standard.showUpdateInFocus?()
    }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        standard.show(request, reply: reply)
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        reset()
        standard.showUserInitiatedUpdateCheck(cancellation: cancellation)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        standard.showUpdateReleaseNotes(with: downloadData)
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        standard.showUpdateReleaseNotesFailedToDownloadWithError(error)
    }

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        reset()
        standard.showUpdateNotFoundWithError(error, acknowledgement: acknowledgement)
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        reset()
        standard.showUpdaterError(error, acknowledgement: acknowledgement)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        standard.showDownloadInitiated { [weak self] in
            self?.reset()
            cancellation()
        }
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        standard.showDownloadDidReceiveExpectedContentLength(expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        standard.showDownloadDidReceiveData(ofLength: length)
    }

    func showDownloadDidStartExtractingUpdate() {
        standard.showDownloadDidStartExtractingUpdate()
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        standard.showExtractionReceivedProgress(progress)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {
        standard.showInstallingUpdate(withApplicationTerminated: applicationTerminated,
                                       retryTerminatingApplication: retryTerminatingApplication)
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        reset()
        standard.showUpdateInstalledAndRelaunched(relaunched, acknowledgement: acknowledgement)
    }

    func dismissUpdateInstallation() {
        reset()
        standard.dismissUpdateInstallation()
    }
}
