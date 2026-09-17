import Foundation
import HazmatAppSupport
import HazmatCore
import HazmatProtocol
import Observation

/// The shell's state: the helper, the profiles a store holds, and the state of
/// the live file for the selected profile. Nothing here edits a profile or
/// resolves one.
@MainActor
@Observable
final class ShellModel {
    private(set) var helper: HelperState = .notRegistered
    private(set) var profiles: [ProfileID] = []
    private(set) var drift = ""
    private(set) var notice = ""
    private(set) var storePath = ""
    private(set) var busy = false
    var selectedProfile: ProfileID?

    private let registration: HelperRegistration
    private let catalogue: ProfileCatalogue
    private let applier: HostsFileApplier

    init(
        storeRoot: URL = StoreLocation.defaultRoot,
        fileURL: URL = DaemonTarget.hostsFile,
        writer: PrivilegedWriter? = nil
    ) {
        registration = HelperRegistration()
        catalogue = ProfileCatalogue(root: storeRoot)
        applier = HostsFileApplier(fileURL: fileURL, writer: writer ?? DaemonClient())
        storePath = storeRoot.path
    }

    func refresh() {
        helper = registration.state
        profiles = catalogue.profiles()
        if selectedProfile == nil || !profiles.contains(selectedProfile!) {
            selectedProfile = profiles.first
        }
        refreshDrift()
    }

    func register() {
        do {
            try registration.register()
            notice = "Registered. Approve the helper in System Settings to enable writes."
        } catch {
            notice = "\(error)"
        }
        refresh()
    }

    func unregister() {
        do {
            try registration.unregister()
            notice = "Unregistered."
        } catch {
            notice = "\(error)"
        }
        refresh()
    }

    func refreshDrift() {
        guard let profile = selectedProfile else {
            drift = catalogue.exists ? "No profile selected." : "No store at \(catalogue.root.path)."
            return
        }
        do {
            let state = try applier.state(rendered: try catalogue.renderedBlock(for: profile))
            drift = Self.describe(state)
        } catch {
            drift = "The file could not be read: \(error)"
        }
    }

    func apply(overwriteDrift: Bool) {
        guard let profile = selectedProfile else { return }
        let catalogue = self.catalogue
        let applier = self.applier
        busy = true
        notice = "Applying \(profile)…"
        Task.detached {
            let outcome: ApplyOutcome
            do {
                outcome = applier.apply(
                    block: try catalogue.renderedBlock(for: profile),
                    overwriteDrift: overwriteDrift
                )
            } catch {
                outcome = .failed(reason: "rendering \(profile): \(error)")
            }
            await MainActor.run { self.finish(outcome) }
        }
    }

    func removeBlock() {
        let applier = self.applier
        busy = true
        notice = "Removing the block…"
        Task.detached {
            let outcome = applier.removeBlock()
            await MainActor.run { self.finish(outcome) }
        }
    }

    private func finish(_ outcome: ApplyOutcome) {
        busy = false
        notice = outcome.description
        refreshDrift()
    }

    static func describe(_ state: BlockState) -> String {
        switch state {
        case .absent:
            return "No block is applied."
        case .unchanged:
            return "The applied block matches the rendered block."
        case .drifted:
            return "The applied block differs from the rendered block."
        case .refused(let error):
            return "The file's markers are refused: \(error)"
        }
    }
}
