import AppKit
import Foundation
import HazmatAppSupport
import HazmatCore
import HazmatProtocol
import Observation

/// A name the window is asking for: creating, renaming or duplicating an item.
/// The scene shows a field; the model decides what the name is used for.
enum NameEntry: Equatable, Sendable {
    case newProfile
    case newFragment
    case renameProfile(ProfileID)
    case renameFragment(FragmentID)
    case duplicateProfile(ProfileID)
    case duplicateFragment(FragmentID)

    var title: String {
        switch self {
        case .newProfile: return "New Profile"
        case .newFragment: return "New Fragment"
        case .renameProfile: return "Rename Profile"
        case .renameFragment: return "Rename Fragment"
        case .duplicateProfile: return "Duplicate Profile"
        case .duplicateFragment: return "Duplicate Fragment"
        }
    }

    var confirmTitle: String {
        switch self {
        case .newProfile, .newFragment: return "Create"
        case .renameProfile, .renameFragment: return "Rename"
        case .duplicateProfile, .duplicateFragment: return "Duplicate"
        }
    }

    var placeholder: String {
        switch self {
        case .newProfile, .renameProfile, .duplicateProfile: return "Profile name"
        case .newFragment, .renameFragment, .duplicateFragment: return "Fragment name"
        }
    }

    var suggested: String {
        switch self {
        case .newProfile, .newFragment: return ""
        case .renameProfile(let profile), .duplicateProfile(let profile): return profile.rawValue
        case .renameFragment(let fragment), .duplicateFragment(let fragment): return fragment.rawValue
        }
    }
}

/// The shell's state: the helper, the store's reading for the menu, and the
/// editor's last read. Decisions live in app support; this holds what was read,
/// what the window is looking at, and forwards choices.
@MainActor
@Observable
final class ShellModel {
    private(set) var helper: HelperState = .notRegistered
    private(set) var notice = ""
    private(set) var busy = false
    private(set) var reading: ActiveProfileReading = .missingStore
    private(set) var editor: EditorPresentation
    /// The block the last apply replaced, kept for the session so it can be
    /// reverted. `nil` when the running application has applied nothing.
    private(set) var lastApply: ApplyRecord?

    /// The one selection the sidebar shows. A search that hides it leaves the
    /// selection here and clears the presentation's, so clearing the search
    /// brings the same item back.
    var selection: SidebarSelection?
    var searchText = ""
    var searchScope: SearchScope = .all

    /// The edited fragment text, so the menu's Save acts on the same draft the
    /// editor shows. The baseline is what the store held when the draft was
    /// adopted, so "dirty" survives a search that hides the selection.
    var fragmentDraft = ""
    private var draftFragment: FragmentID?
    private var draftBaseline = ""

    /// A write waiting for the window's confirmation.
    var confirmation: WriteRequest?
    /// A name the window is asking for.
    var nameEntry: NameEntry?
    var nameDraft = ""
    var showHelperSheet = false
    var sidebarVisible = true
    /// Whether the prominent action of a profile with no layers is choosing the
    /// fragment to add.
    var isAddingLayer = false
    /// Bumped when the search command asks for the field.
    private(set) var searchFocusRequests = 0

    private let environmentRoot: URL?
    private let preference: StoreLocationPreference
    private let fileURL: URL
    private let writer: PrivilegedWriter
    private var session: StoreSession
    private let registration: HelperRegistration

    init(
        fileURL: URL = DaemonTarget.hostsFile,
        writer: PrivilegedWriter? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        preference: StoreLocationPreference = DefaultsStoreLocationPreference()
    ) {
        let writer = writer ?? DaemonClient()
        self.fileURL = fileURL
        self.writer = writer
        self.preference = preference
        environmentRoot = StoreLocation.environmentRoot(environment)
        let session = StoreSession(
            root: StoreLocation.resolve(environment: environment, chosen: preference.chosenLocation()),
            fileURL: fileURL,
            writer: writer
        )
        self.session = session
        registration = HelperRegistration()
        editor = session.editor.read()
        reading = session.catalogue.activation(reading: session.liveFile)
        helper = registration.state
        selection = editor.selection
        adoptFragmentDraft(editor)
    }

    // MARK: - What the scene renders

    /// The menu bar item, derived from the last refresh. Presentation only: the
    /// items come from app support.
    var menu: MenuPresentation {
        MenuPresentation(reading: reading, helper: helper, notice: notice)
    }

    /// The phase the window is in: one value the scene switches on.
    var phase: WindowPhase {
        WindowPhase(editor: editor, helper: helper)
    }

    /// What a write would do now.
    var writeState: WriteState {
        editor.writeState(helper: helper)
    }

    /// The one prominent action the phase offers.
    var primaryAction: WindowAction? {
        phase.primaryAction(write: writeState, helper: helper)
    }

    /// Whether a revert is offered: only after an apply this session performed.
    var canRevert: Bool { lastApply != nil }

    var storeRoot: URL { session.root }

    var hostsFilePath: String { fileURL.path }

    /// Whether the environment names the store root, in which case the location
    /// chosen in the window cannot take effect.
    var locationIsOverridden: Bool { environmentRoot != nil }

    var helperSheet: HelperSheetPresentation { HelperSheetPresentation(current: helper) }

    /// The menu bar and the toolbar, from the same value.
    var commands: CommandPresentation {
        CommandPresentation.menuBar(
            editor: editor,
            helper: helper,
            canRevert: canRevert,
            hasUnsavedEdit: fragmentIsDirty
        )
    }

    /// Whether the draft differs from what the store holds.
    var fragmentIsDirty: Bool {
        draftFragment != nil && fragmentDraft != draftBaseline
    }

    // MARK: - Reading

    func refresh() {
        // The menu rebuilds for every observable change, so the writes are
        // guarded: an unchanged value must not notify observers and rebuild the
        // menu that is being read.
        let helperState = registration.state
        if helperState != helper { helper = helperState }

        let latest = session.catalogue.activation(reading: session.liveFile)
        if latest != reading { reading = latest }

        refreshEditor()
    }

    /// Re-reads the store and the live file for the window. Called when the
    /// selection or the search changes.
    func selectionChanged() {
        refreshEditor()
    }

    func searchChanged() {
        refreshEditor()
    }

    func focusSearch() {
        searchFocusRequests += 1
    }

    private func refreshEditor() {
        let latest = session.editor.read(
            selection: selection,
            search: StoreSearch(text: searchText, scope: searchScope)
        )
        if latest != editor { editor = latest }
        // A selection the store no longer holds moves to what the read chose; a
        // selection the search hid stays as the intent, so clearing the search
        // selects it again.
        if let effective = latest.selection, effective != selection { selection = effective }
        adoptFragmentDraft(latest)
    }

    /// Keeps the draft the user is editing, and adopts the store's text when
    /// another fragment is focused or when the file changed under an unedited
    /// draft. A search that hides the selection leaves the draft alone.
    private func adoptFragmentDraft(_ presentation: EditorPresentation) {
        switch presentation.selection {
        case .fragment(let fragment):
            if fragment != draftFragment {
                draftFragment = fragment
                fragmentDraft = presentation.fragmentText
                draftBaseline = presentation.fragmentText
                return
            }
            guard presentation.fragmentText != draftBaseline, fragmentDraft == draftBaseline else { return }
            fragmentDraft = presentation.fragmentText
            draftBaseline = presentation.fragmentText
        case .profile:
            draftFragment = nil
            fragmentDraft = ""
            draftBaseline = ""
        case nil:
            break
        }
    }

    // MARK: - The helper

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

    func createStore() {
        do {
            let outcome = try session.layout.create()
            notice = outcome == .created
                ? "The store was created at \(session.root.path)."
                : "The store is already there; nothing to do."
        } catch {
            notice = "\(error)"
        }
        refresh()
    }

    /// Points the shell at another store. The catalogue, the editor, the applier
    /// and the live file reading move together, so nothing reads the old
    /// location afterwards.
    func setStoreLocation(_ location: URL?) {
        preference.remember(location)
        session = session.repointed(to: StoreLocation.resolve(chosen: location))
        selection = nil
        searchText = ""
        lastApply = nil
        refresh()
        notice = "The store is now read from \(session.root.path)."
    }

    func chooseStoreLocation() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose the folder that holds (or will hold) fragments/ and profiles/."
        panel.directoryURL = session.root
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setStoreLocation(url)
    }

    func createProfile(named name: String) {
        let created = ProfileID(name)
        let outcome = session.editor.createProfile(named: name)
        if created.isValid, outcome.didChangeTheStore {
            selection = .profile(created)
        }
        finish(outcome)
    }

    func createFragment(named name: String) {
        let created = FragmentID(name)
        let outcome = session.editor.createFragment(named: name)
        if created.isValid, outcome.didChangeTheStore {
            selection = .fragment(created)
        }
        finish(outcome)
    }

    func renameProfile(to name: String) {
        guard let profile = selectedProfile else { return }
        finish(session.editor.rename(profile: profile, to: name))
    }

    func renameFragment(to name: String) {
        guard let fragment = selectedFragment else { return }
        finish(session.editor.rename(fragment: fragment, to: name))
    }

    func duplicateProfile(as name: String) {
        guard let profile = selectedProfile else { return }
        finish(session.editor.duplicate(profile: profile, as: name))
    }

    func duplicateFragment(as name: String) {
        guard let fragment = selectedFragment else { return }
        finish(session.editor.duplicate(fragment: fragment, as: name))
    }

    func deleteProfile() {
        guard let profile = selectedProfile else { return }
        finish(session.editor.delete(profile: profile))
    }

    func deleteFragment() {
        guard let fragment = selectedFragment else { return }
        finish(session.editor.delete(fragment: fragment))
    }

    private var selectedProfile: ProfileID? { editor.selectedProfile }

    private var selectedFragment: FragmentID? { editor.selectedFragment }

    /// Saves the edited text, then re-applies the profile whose block is live
    /// when the block is still the one that profile rendered before the edit.
    func saveFragment(text: String) {
        guard let fragment = selectedFragment, let profile = selectedProfile else { return }
        finish(session.editor.save(fragment: fragment, text: text, editing: profile, previous: editor))
    }

    func saveFragmentDraft() {
        guard fragmentIsDirty else { return }
        saveFragment(text: fragmentDraft)
    }

    func addLayer(_ fragment: FragmentID) {
        guard let profile = selectedProfile else { return }
        finish(session.editor.addLayer(fragment, to: profile, previous: editor))
    }

    func removeLayer(at index: Int) {
        guard let profile = selectedProfile else { return }
        finish(session.editor.removeLayer(at: index, from: profile, previous: editor))
    }

    func moveLayer(from index: Int, to destination: Int) {
        guard let profile = selectedProfile else { return }
        finish(session.editor.moveLayer(from: index, to: destination, in: profile, previous: editor))
    }

    /// Reorders by the destination the list reports, which counts the row before
    /// it is removed.
    func moveLayer(from source: Int, beforeInsertionAt destination: Int) {
        moveLayer(from: source, to: destination > source ? destination - 1 : destination)
    }

    // MARK: - Names

    func beginNameEntry(_ entry: NameEntry) {
        nameEntry = entry
        nameDraft = entry.suggested
    }

    func beginRename() {
        switch editor.selection {
        case .profile(let profile): beginNameEntry(.renameProfile(profile))
        case .fragment(let fragment): beginNameEntry(.renameFragment(fragment))
        case nil: break
        }
    }

    func beginDuplicate() {
        switch editor.selection {
        case .profile(let profile): beginNameEntry(.duplicateProfile(profile))
        case .fragment(let fragment): beginNameEntry(.duplicateFragment(fragment))
        case nil: break
        }
    }

    func beginCreate(_ kind: NameEntry) {
        beginNameEntry(kind)
    }

    func commitNameEntry() {
        guard let entry = nameEntry else { return }
        let name = nameDraft
        nameEntry = nil
        nameDraft = ""
        switch entry {
        case .newProfile: createProfile(named: name)
        case .newFragment: createFragment(named: name)
        case .renameProfile: renameProfile(to: name)
        case .renameFragment: renameFragment(to: name)
        case .duplicateProfile: duplicateProfile(as: name)
        case .duplicateFragment: duplicateFragment(as: name)
        }
    }

    func cancelNameEntry() {
        nameEntry = nil
        nameDraft = ""
    }

    func deleteSelected() {
        switch editor.selection {
        case .profile: deleteProfile()
        case .fragment: deleteFragment()
        case nil: break
        }
    }

    // MARK: - The live file

    /// Asks for the confirmation that names the file and the entries before
    /// anything is written.
    func requestApply() {
        guard writeState.isPending, let profile = selectedProfile, let entries = writeState.entryCount else { return }
        confirmation = .apply(profile: profile, entries: entries, file: fileURL.path)
    }

    func requestOverwriteDrift() {
        guard let profile = selectedProfile, editor.live.liveBlock != nil else { return }
        confirmation = .overwriteDrift(profile: profile, entries: editor.entryCount, file: fileURL.path)
    }

    func requestRemoveBlock() {
        confirmation = .removeBlock(file: fileURL.path)
    }

    func requestRevert() {
        guard let change = lastApply else { return }
        confirmation = .revert(profile: change.profile, file: fileURL.path, removesBlock: change.wasAnInstall)
    }

    func cancelConfirmation() {
        confirmation = nil
    }

    /// Performs the confirmed write. Cancelling leaves the file untouched and
    /// the write state as it was.
    func confirm() {
        guard let request = confirmation else { return }
        confirmation = nil
        isAddingLayer = false
        switch request {
        case .apply(let profile, _, _):
            apply(profile, replacing: replacementForApply())
        case .overwriteDrift(let profile, _, _):
            guard let block = editor.live.liveBlock else { return }
            apply(profile, replacing: .block(block))
        case .revert:
            revert()
        case .removeBlock:
            removeBlock()
        }
    }

    private func replacementForApply() -> Replacement {
        if case .drifted(let block) = editor.live { return .block(block) }
        return .onlyIfAbsent
    }

    /// Activates a profile from the store. The live file is read again rather
    /// than trusting the menu's look: a block that changed since then must not be
    /// replaced unless it still holds the block the matched profile rendered.
    func activate(_ profile: ProfileID) {
        let fresh = session.catalogue.activation(reading: session.liveFile)
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

    /// The window's deliberate overwrite of the drifted block the editor's last
    /// read found, after the confirmation.
    func overwriteDrift() {
        requestOverwriteDrift()
    }

    private func namingTheMatchedProfile(_ matched: ProfileID) -> Replacement {
        do {
            return .block(try session.catalogue.renderedBlock(for: matched))
        } catch {
            return .onlyIfAbsent
        }
    }

    private func apply(_ profile: ProfileID, replacing replacement: Replacement) {
        let editorModel = session.editor
        busy = true
        notice = "Applying \(profile)…"
        Task.detached {
            let (outcome, change) = editorModel.apply(profile, replacing: replacement)
            await MainActor.run {
                if let change { self.lastApply = change }
                self.finish(outcome)
            }
        }
    }

    private func revert() {
        guard let change = lastApply else { return }
        let editorModel = session.editor
        busy = true
        notice = "Reverting…"
        Task.detached {
            let outcome = editorModel.revert(change)
            await MainActor.run {
                if outcome.isApplied { self.lastApply = nil }
                self.finish(outcome)
            }
        }
    }

    func removeBlock() {
        let applier = session.applier
        busy = true
        notice = "Removing the block…"
        Task.detached {
            let outcome = applier.removeBlock()
            await MainActor.run {
                self.lastApply = nil
                self.finish(outcome)
            }
        }
    }

    func revealHostsFile() {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    /// The chosen location as text, for the settings window to offer copying.
    func copyStorePath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(session.root.path, forType: .string)
        notice = "The store path is on the clipboard."
    }

    // MARK: - Commands

    /// One entry point for every menu item, so the menu bar and the window act
    /// on the same model.
    func perform(_ action: WindowAction) {
        switch action {
        case .createStore: createStore()
        case .chooseLocation: chooseStoreLocation()
        case .newProfile: beginNameEntry(.newProfile)
        case .newFragment: beginNameEntry(.newFragment)
        case .addFragment: isAddingLayer = true
        case .apply: requestApply()
        case .revert: requestRevert()
        case .overwriteDrift: requestOverwriteDrift()
        case .removeBlock: requestRemoveBlock()
        case .reload: refresh()
        case .rename: beginRename()
        case .duplicate: beginDuplicate()
        case .delete: deleteSelected()
        case .save: saveFragmentDraft()
        case .installHelper: showHelperSheet = true
        case .revealHostsFile: revealHostsFile()
        case .openSettings: break  // the Settings scene's own command opens it
        case .toggleSidebar: sidebarVisible.toggle()
        case .search: focusSearch()
        case .showHelp: showHelperSheet = true
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
