import Foundation
import HazmatAppSupport
import HazmatCore
import HazmatProtocol
import Observation

/// The shell's state: the helper, the profiles a store holds, and the editor's
/// last read. Decisions live in app support; this holds what was read and
/// forwards choices.
@MainActor
@Observable
final class ShellModel {
    private(set) var helper: HelperState = .notRegistered
    private(set) var profiles: [ProfileID] = []
    private(set) var notice = ""
    private(set) var busy = false
    private(set) var reading: ActiveProfileReading = .missingStore
    private(set) var editor: EditorPresentation
    var selectedProfile: ProfileID?
    var selectedFragment: FragmentID?

    private let registration: HelperRegistration
    private let catalogue: ProfileCatalogue
    private let applier: HostsFileApplier
    private let liveFile: LiveHostsFile
    private let editorModel: EditorModel

    init(
        storeRoot: URL = StoreLocation.defaultRoot,
        fileURL: URL = DaemonTarget.hostsFile,
        writer: PrivilegedWriter? = nil
    ) {
        let editorModel = EditorModel(storeRoot: storeRoot, fileURL: fileURL, writer: writer ?? DaemonClient())
        registration = HelperRegistration()
        catalogue = ProfileCatalogue(root: storeRoot)
        applier = HostsFileApplier(fileURL: fileURL, writer: writer ?? DaemonClient())
        liveFile = LiveHostsFile(url: fileURL)
        self.editorModel = editorModel
        editor = editorModel.read()
    }

    /// The menu bar item, derived from the last refresh. Presentation only: the
    /// items come from app support.
    var menu: MenuPresentation {
        MenuPresentation(reading: reading, helper: helper, notice: notice)
    }

    /// What the live file holds, for the window to name alongside the editor.
    var liveDescription: String {
        switch reading {
        case .missingStore:
            return "No store at this location."
        case .emptyStore:
            return "The store holds no profiles."
        case .unreadableFile(_, let reason):
            return "The live file could not be read: \(reason)"
        case .derived(_, let activation):
            switch activation.state {
            case .off:
                return "No block is applied."
            case .unreadable(let error):
                return "The live file's markers cannot be read: \(error)"
            case .drifted:
                return "The live block matches no profile, so it is reported as drift."
            case .active(let profiles):
                return "Active: \(profiles.map(\.rawValue).joined(separator: ", "))"
            }
        }
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
        refreshEditor()
    }

    /// Re-reads the store and the live file for the window. Called when the
    /// selection changes, so the editor shows what is selected now.
    func selectionChanged() {
        refreshEditor()
    }

    private func refreshEditor() {
        let latest = editorModel.read(profile: selectedProfile, fragment: selectedFragment)
        if latest.selectedProfile != selectedProfile { selectedProfile = latest.selectedProfile }
        if latest.selectedFragment != selectedFragment { selectedFragment = latest.selectedFragment }
        if latest != editor { editor = latest }
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

    // MARK: - The store

    func createProfile(named name: String) {
        finish(editorModel.createProfile(named: name))
    }

    func createFragment(named name: String) {
        finish(editorModel.createFragment(named: name))
    }

    func renameProfile(to name: String) {
        guard let profile = selectedProfile else { return }
        finish(editorModel.rename(profile: profile, to: name))
    }

    func renameFragment(to name: String) {
        guard let fragment = selectedFragment else { return }
        finish(editorModel.rename(fragment: fragment, to: name))
    }

    func duplicateProfile(as name: String) {
        guard let profile = selectedProfile else { return }
        finish(editorModel.duplicate(profile: profile, as: name))
    }

    func duplicateFragment(as name: String) {
        guard let fragment = selectedFragment else { return }
        finish(editorModel.duplicate(fragment: fragment, as: name))
    }

    func deleteProfile() {
        guard let profile = selectedProfile else { return }
        finish(editorModel.delete(profile: profile))
    }

    func deleteFragment() {
        guard let fragment = selectedFragment else { return }
        finish(editorModel.delete(fragment: fragment))
    }

    /// Saves the edited text, then re-applies the profile whose block is live
    /// when the block is still the one that profile rendered before the edit.
    func saveFragment(text: String) {
        guard let fragment = selectedFragment, let profile = selectedProfile else { return }
        finish(editorModel.save(fragment: fragment, text: text, editing: profile, previous: editor))
    }

    func addLayer(_ fragment: FragmentID) {
        guard let profile = selectedProfile else { return }
        finish(editorModel.addLayer(fragment, to: profile, previous: editor))
    }

    func removeLayer(at index: Int) {
        guard let profile = selectedProfile else { return }
        finish(editorModel.removeLayer(at: index, from: profile, previous: editor))
    }

    func moveLayer(from index: Int, to destination: Int) {
        guard let profile = selectedProfile else { return }
        finish(editorModel.moveLayer(from: index, to: destination, in: profile, previous: editor))
    }

    // MARK: - The live file

    /// Applies the selected profile, naming the block it read when the live file
    /// already holds one.
    func apply() {
        guard let profile = selectedProfile else { return }
        switch reading.activation?.state {
        case .active(let profiles):
            guard let matched = profiles.first else { return }
            apply(profile, replacing: namingTheMatchedProfile(matched))
        default:
            apply(profile, replacing: .onlyIfAbsent)
        }
    }

    /// Activates a profile from the store. The live file is read again rather
    /// than trusting the menu's look: a block that changed since then must not be
    /// replaced unless it still holds the block the matched profile rendered.
    func activate(_ profile: ProfileID) {
        let fresh = catalogue.activation(reading: liveFile)
        guard let matched = fresh.activation?.activeProfiles.first else {
            apply(profile, replacing: .onlyIfAbsent)
            return
        }
        apply(profile, replacing: namingTheMatchedProfile(matched))
    }

    /// Replaces the block no profile owns, which the menu offered as its own
    /// item. The reading named the block, so the apply replaces exactly it.
    func overwriteDrift(with profile: ProfileID, liveBlock: Data) {
        apply(profile, replacing: .block(liveBlock))
    }

    /// The window's deliberate overwrite: the selected profile replaces the
    /// drifted block the editor's last read found.
    func overwriteDrift() {
        guard let profile = editor.selectedProfile, let block = editor.live.liveBlock else { return }
        apply(profile, replacing: .block(block))
    }

    private func namingTheMatchedProfile(_ matched: ProfileID) -> Replacement {
        do {
            return .block(try catalogue.renderedBlock(for: matched))
        } catch {
            return .onlyIfAbsent
        }
    }

    private func apply(_ profile: ProfileID, replacing replacement: Replacement) {
        let catalogue = self.catalogue
        let applier = self.applier
        busy = true
        notice = "Applying \(profile)…"
        Task.detached {
            let outcome: ApplyOutcome
            do {
                outcome = applier.apply(
                    block: try catalogue.renderedBlock(for: profile),
                    replacement: replacement
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

    private func finish(_ outcome: EditorOutcome) {
        notice = outcome.description
        refresh()
    }
}
