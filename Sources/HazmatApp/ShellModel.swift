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
    private(set) var reading: ActiveProfileReading = .missingStore
    var selectedProfile: ProfileID?

    private let registration: HelperRegistration
    private let catalogue: ProfileCatalogue
    private let applier: HostsFileApplier
    private let liveFile: LiveHostsFile

    init(
        storeRoot: URL = StoreLocation.defaultRoot,
        fileURL: URL = DaemonTarget.hostsFile,
        writer: PrivilegedWriter? = nil
    ) {
        registration = HelperRegistration()
        catalogue = ProfileCatalogue(root: storeRoot)
        applier = HostsFileApplier(fileURL: fileURL, writer: writer ?? DaemonClient())
        liveFile = LiveHostsFile(url: fileURL)
        storePath = storeRoot.path
    }

    /// The menu bar item, derived from the last refresh. Presentation only: the
    /// items come from app support.
    var menu: MenuPresentation {
        MenuPresentation(reading: reading, helper: helper, notice: notice)
    }

    func refresh() {
        // The menu rebuilds for every observable change, so the writes are
        // guarded: an unchanged value must not notify observers and rebuild the
        // menu that is being read.
        let helperState = registration.state
        if helperState != helper { helper = helperState }

        let latest = catalogue.activation(reading: liveFile)
        if latest != reading { reading = latest }
        if latest.profiles != profiles { profiles = latest.profiles }

        if selectedProfile == nil || !profiles.contains(selectedProfile!) {
            let fallback = profiles.first
            if fallback != selectedProfile { selectedProfile = fallback }
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
        let updated: String
        if let profile = selectedProfile {
            do {
                updated = Self.describe(try applier.state(rendered: try catalogue.renderedBlock(for: profile)))
            } catch {
                updated = "The file could not be read: \(error)"
            }
        } else {
            updated = catalogue.exists ? "No profile selected." : "No store at \(catalogue.root.path)."
        }
        if updated != drift { drift = updated }
    }

    func apply(overwriteDrift: Bool) {
        guard let profile = selectedProfile else { return }
        activate(profile, overwriteDrift: overwriteDrift)
    }

    /// Activates a profile from the store. The live file is read again rather
    /// than trusting the menu's look: a block that changed since then must not be
    /// replaced unless it still belongs to a profile.
    func activate(_ profile: ProfileID) {
        let fresh = catalogue.activation(reading: liveFile)
        activate(profile, overwriteDrift: fresh.replacingIsASwitch)
    }

    /// Replaces a block no profile owns, which the menu offered as its own item.
    func overwriteDrift(with profile: ProfileID) {
        activate(profile, overwriteDrift: true)
    }

    private func activate(_ profile: ProfileID, overwriteDrift: Bool) {
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
        refresh()
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
