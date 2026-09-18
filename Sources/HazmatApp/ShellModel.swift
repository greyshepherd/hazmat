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

/// A deletion the window is asking about. The store keeps no history, so a
/// deleted file is gone; the confirmation names what goes with it.
enum DeleteRequest: Equatable, Sendable {
    case profile(ProfileID)
    case fragment(FragmentID)

    var title: String {
        switch self {
        case .profile(let profile): return "Delete the profile '\(profile)'?"
        case .fragment(let fragment): return "Delete the fragment '\(fragment)'?"
        }
    }

    var message: String {
        switch self {
        case .profile:
            return "The profile is removed from the store. A block it wrote stays in the hosts file and is reported as drift until another profile is applied or the block is removed."
        case .fragment:
            return "The fragment is removed from the store. A profile that stacks it no longer resolves until the layer is removed from it."
        }
    }

    var confirmTitle: String { "Delete" }
}

/// The shell's state: the helper, the store's reading for the menu, and the
/// editor's last read. Decisions live in app support; this holds what was read,
/// what the window is looking at, and forwards choices.
@MainActor
@Observable
final class ShellModel {
    private(set) var helper: HelperState = .notRegistered
    private(set) var notice: MenuNotice = .quiet
    private(set) var busy = false
    private(set) var reading: ActiveProfileReading = .missingStore
    private(set) var editor: EditorPresentation
    /// The block the last apply replaced, kept for the session so it can be
    /// reverted. `nil` when the running application has applied nothing.
    private(set) var lastApply: ApplyRecord?
    /// What the menu can say about updates, read from the checker whenever the
    /// menu is rebuilt.
    private(set) var updateAvailability: UpdateAvailability = .unavailable

    /// The one selection the sidebar shows. A search that hides it leaves the
    /// selection here and clears the presentation's, so clearing the search
    /// brings the same item back.
    var selection: SidebarSelection?
    var searchText = ""

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
    /// A deletion waiting for the window's confirmation.
    var deletion: DeleteRequest?
    var nameDraft = ""
    var showHelperSheet = false
    var sidebarVisible = true
    /// Bumped when the search command asks for the field.
    private(set) var searchFocusRequests = 0

    private let environmentRoot: URL?
    private let preference: StoreLocationPreference
    private let fileURL: URL
    private let writer: PrivilegedWriter
    private var session: StoreSession
    private let registration: HelperRegistration
    private let presence: HelperPresence
    /// The update check, when the bundle declares a feed. A development bundle
    /// passes nothing and is offered no check.
    private let updates: (any UpdateChecking)?
    /// The last answer to a check for the helper, and when it arrived. Nothing
    /// is checked at launch, so this is empty until the first answer lands.
    private var lastAnswer: (answer: HelperReachability, at: Date)?
    private var checkInFlight = false
    private var repairInFlight = false
    /// Set once on the main actor and read only in `deinit`, which the actor
    /// isolation cannot see into.
    @ObservationIgnored private nonisolated(unsafe) var dockObserver: (any NSObjectProtocol)?
    /// Sees a window become key, which is when an action asked for while the
    /// window was closed has somewhere to present itself.
    @ObservationIgnored private nonisolated(unsafe) var keyWindowObserver: (any NSObjectProtocol)?
    /// An action asked for while the window was closed, kept until a window is
    /// there to present what it asks for.
    private var actionAwaitingTheWindow: WindowAction?
    /// The monitor that answers the window's own keystrokes, held for the same
    /// reason, so it can be removed when the model goes away.
    @ObservationIgnored private nonisolated(unsafe) var shortcutMonitor: Any?
    /// The window the shell is shown in. A keystroke the window answers without a
    /// menu bar item acts on the sidebar's selection, which only that window
    /// shows.
    @ObservationIgnored private weak var shellWindow: NSWindow?

    /// How long an answer is trusted while it says the helper is answering. A
    /// check costs a round trip that can take its whole bound when nothing
    /// answers, so a helper that answers is checked again at this interval,
    /// while a helper that did not answer is checked only when something asks.
    private static let answerFreshness: TimeInterval = 5

    init(
        fileURL: URL = DaemonTarget.hostsFile,
        writer: PrivilegedWriter? = nil,
        presence: HelperPresence? = nil,
        updates: (any UpdateChecking)? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        preference: StoreLocationPreference = DefaultsStoreLocationPreference()
    ) {
        // One client serves both, so the app opens no second path to the helper
        // when neither is given.
        let client = DaemonClient()
        let writer = writer ?? client
        self.fileURL = fileURL
        self.writer = writer
        self.presence = presence ?? client
        self.updates = updates
        updateAvailability = updates?.availability ?? .unavailable
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
        // The first check is asked for here, off the main actor: a helper that
        // answers does so in milliseconds, and one that cannot be started keeps
        // the registration's own word for the seconds its bound takes rather
        // than holding the first frame back for them.
        checkPresence(forced: true)
        dockObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { [weak self] note in
            let closing = (note.object as? NSWindow).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                self?.matchDockPresenceToTheWindows(ignoring: closing)
            }
        }
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // The window that became key is the key window; asking the
            // application keeps the notification's object on its own side.
            MainActor.assumeIsolated {
                guard NSApp.keyWindow?.level == .normal else { return }
                self?.performTheActionAwaitingTheWindow()
            }
        }
        // A local monitor sees a keystroke before it is dispatched, which is what
        // lets one the text system has a better use for be passed on rather than
        // taken from it. The handler runs outside the main actor, so it carries
        // the keystroke in as values and the answer back as a flag: the event
        // itself never crosses that boundary.
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keystroke = Self.keystroke(of: event)
            let answered = MainActor.assumeIsolated {
                self?.answer(keystroke) ?? false
            }
            return answered ? nil : event
        }
    }

    // MARK: - The window's own keystrokes

    /// The window the shell is shown in, told by the scene that renders it.
    func windowChanged(_ window: NSWindow?) {
        shellWindow = window
    }

    /// Performs an action that presents something, once there is a window to
    /// present it in. A window that is already showing gets it now; otherwise
    /// the caller opens the window and the action follows when it becomes key.
    func performOnceTheWindowShows(_ action: WindowAction) {
        if let shellWindow, shellWindow.isVisible {
            perform(action)
        } else {
            actionAwaitingTheWindow = action
        }
    }

    private func performTheActionAwaitingTheWindow() {
        guard let action = actionAwaitingTheWindow else { return }
        actionAwaitingTheWindow = nil
        perform(action)
    }

    /// Answers a keystroke the window binds without a menu bar item, and reports
    /// whether it took it. An answered keystroke is consumed, so nothing acts on
    /// it twice.
    private func answer(_ keystroke: (characters: String, modifiers: CommandPresentation.Modifiers)) -> Bool {
        guard acceptsWindowShortcuts else { return false }
        guard let action = WindowShortcut.action(
            characters: keystroke.characters,
            modifiers: keystroke.modifiers,
            textEditing: NSApp.keyWindow?.firstResponder is NSTextView
        ) else { return false }

        perform(action)
        return true
    }

    /// Whether the keystroke belongs to the window that shows the selection. A
    /// sheet, the settings window and the store chooser are each key at times,
    /// and a keystroke answered there would act on a row none of them shows.
    private var acceptsWindowShortcuts: Bool {
        guard let shellWindow, NSApp.keyWindow === shellWindow, shellWindow.isVisible else { return false }
        return NSApp.modalWindow == nil
    }

    /// The keystroke an event carries, as values that can cross out of the
    /// handler's own isolation.
    private nonisolated static func keystroke(
        of event: NSEvent
    ) -> (characters: String, modifiers: CommandPresentation.Modifiers) {
        var modifiers: CommandPresentation.Modifiers = []
        let flags = event.modifierFlags
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        return (event.charactersIgnoringModifiers ?? "", modifiers)
    }

    // MARK: - What the scene renders

    /// The menu bar item, derived from the last refresh. Presentation only: the
    /// items come from app support.
    var menu: MenuPresentation {
        MenuPresentation(
            reading: reading,
            helper: helper,
            notice: notice,
            update: updateAvailability
        )
    }

    /// The check the menu offers. The framework reports its own progress and
    /// outcome; this only asks for one.
    func checkForUpdates() {
        updates?.checkForUpdates()
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

    /// What fills the content pane: the selected item, or the phase when the
    /// store offers nothing to edit.
    var content: EditorPresentation.Content { editor.content(phase: phase) }

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
            hasUnsavedEdit: fragmentIsDirty,
            update: updateAvailability
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
        let helperState = helperState()
        if helperState != helper { helper = helperState }

        let latest = session.catalogue.activation(reading: session.liveFile)
        if latest != reading { reading = latest }

        let latestUpdate = updates?.availability ?? .unavailable
        if latestUpdate != updateAvailability { updateAvailability = latestUpdate }

        refreshEditor()
        checkPresence()
    }

    /// What the registration reports, refined by the last answer when there is
    /// one. A helper the app has not checked yet keeps the registration's own
    /// word for the moment it takes the check to land.
    private func helperState() -> HelperState {
        guard let lastAnswer else { return registration.state }
        return registration.state.refined(by: lastAnswer.answer)
    }

    /// Records what a check found, and reports whether it changed the state.
    /// Nothing is decided here: the state follows from the answer the same way it
    /// follows from the registration.
    @discardableResult
    private func record(_ answer: HelperReachability) -> Bool {
        let changed = lastAnswer?.answer != answer
        lastAnswer = (answer, Date())
        if changed { helper = helperState() }
        return changed
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
            search: StoreSearch(text: searchText)
        )
        if latest != editor { editor = latest }
        // A selection the store no longer holds moves to what the read chose; a
        // selection the search hid stays as the intent, so clearing the search
        // selects it again.
        if let effective = latest.selection, effective != selection { selection = effective }
        adoptFragmentDraft(latest)
    }

    /// Keeps the draft the user is editing, and adopts the store's text when
    /// another fragment is focused, when the file changed under an unedited
    /// draft, or when the file now holds the draft a save wrote. A search that
    /// hides the selection leaves the draft alone.
    private func adoptFragmentDraft(_ presentation: EditorPresentation) {
        switch presentation.selection {
        case .fragment(let fragment):
            if fragment != draftFragment {
                draftFragment = fragment
                fragmentDraft = presentation.fragmentText
                draftBaseline = presentation.fragmentText
                return
            }
            guard presentation.fragmentText != draftBaseline else { return }
            guard fragmentDraft == draftBaseline || fragmentDraft == presentation.fragmentText else { return }
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

    /// Asks whether the helper is there, unless a check is already out, the last
    /// answer is still fresh, or the last answer was that nothing answered and
    /// nothing has happened since to ask again.
    ///
    /// The answer arrives on the main actor, so the window is never held up by a
    /// helper that is not there.
    private func checkPresence(forced: Bool = false) {
        guard registration.state == .enabled else { return }
        guard !checkInFlight else { return }
        if !forced, let lastAnswer {
            guard lastAnswer.answer == .answering else { return }
            guard Date().timeIntervalSince(lastAnswer.at) >= Self.answerFreshness else { return }
        }
        checkInFlight = true
        let presence = presence
        Task.detached {
            let answer = presence.check()
            await MainActor.run {
                self.checkInFlight = false
                if self.record(answer) { self.refresh() }
            }
        }
    }

    /// Installs the helper: the system registers it, asks whether it answers, and
    /// replaces the job once when nothing does.
    func register() {
        makeHelperAnswer(working: "Installing the helper…")
    }

    /// Removes the registration, away from the main thread: the system takes its
    /// time over it, the same as it does over a registration.
    func unregister() {
        guard !repairInFlight else { return }
        repairInFlight = true
        notice = .progress("Unregistering the helper…")
        let registration = registration
        Task.detached {
            let failure: RegistrationFailure?
            do {
                try registration.unregister()
                failure = nil
            } catch let refusal as RegistrationFailure {
                failure = refusal
            } catch {
                failure = .other(domain: "\(type(of: error))", code: 0, message: "\(error)")
            }
            await MainActor.run {
                self.repairInFlight = false
                self.notice = failure.map { .failure("\($0)") } ?? .success("Unregistered.")
                self.refresh()
            }
        }
    }

    /// Repairs the helper: the same sequence, named for what the user sees, so
    /// the window reports what it did rather than what it hoped for.
    func repairHelper() {
        makeHelperAnswer(working: "Repairing the helper…")
    }

    /// Runs the sequence that makes the helper answer, away from the main thread:
    /// the system finishes a removal after the call returns and refuses a
    /// registration that lands inside that window, so it takes some seconds. The
    /// state stays what the last answer made it for the whole of it, and the
    /// report is the outcome of the last step rather than a hope.
    private func makeHelperAnswer(working: String) {
        guard !repairInFlight else { return }
        repairInFlight = true
        notice = .progress(working)
        let repair = HelperRepair(registration: registration, presence: presence)
        Task.detached {
            let outcome = repair.run()
            await MainActor.run { self.finishHelperWork(outcome) }
        }
    }

    private func finishHelperWork(_ outcome: HelperRepair.Outcome) {
        repairInFlight = false
        if let failure = outcome.failure {
            notice = .failure("The system did not register the helper: \(failure) "
                + "Allow it in System Settings > General > Login Items & Extensions, or remove it and install it again.")
        } else if let answer = outcome.answer {
            record(answer)
            notice = answer == .answering
                ? .success("The helper answers, so writes are ready.")
                : .failure("The helper was registered and still does not answer.")
        } else {
            notice = .success("Registered. Approve the helper in System Settings to enable writes.")
        }
        refresh()
    }

    // MARK: - The store

    func createStore() {
        do {
            let outcome = try session.layout.create()
            notice = outcome == .created
                ? .success("The store was created at \(session.root.path).")
                : .success("The store is already there; nothing to do.")
        } catch {
            notice = .failure("\(error)")
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
        notice = .success("The store is now read from \(session.root.path).")
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

    func deleteProfile(_ profile: ProfileID) {
        finish(session.editor.delete(profile: profile))
    }

    func deleteFragment(_ fragment: FragmentID) {
        finish(session.editor.delete(fragment: fragment))
    }

    private var selectedProfile: ProfileID? { editor.selectedProfile }

    private var selectedFragment: FragmentID? { editor.selectedFragment }

    /// Saves the edited text, then re-applies the profile whose block is live
    /// when the block is still the one that profile rendered before the edit. A
    /// store that holds no profile still saves the text: there is nothing to
    /// re-apply.
    func saveFragment(text: String) {
        guard let fragment = selectedFragment else { return }
        let profile = selectedProfile
        edit(working: "Saving \(fragment)…") { editor, previous in
            editor.save(fragment: fragment, text: text, editing: profile, previous: previous)
        }
    }

    func saveFragmentDraft() {
        guard fragmentIsDirty else { return }
        saveFragment(text: fragmentDraft)
    }

    func addLayer(_ fragment: FragmentID) {
        guard let profile = selectedProfile else { return }
        edit(working: "Adding \(fragment)…") { editor, previous in
            editor.addLayer(fragment, to: profile, previous: previous)
        }
    }

    func removeLayer(at index: Int) {
        guard let profile = selectedProfile else { return }
        edit(working: "Removing the layer…") { editor, previous in
            editor.removeLayer(at: index, from: profile, previous: previous)
        }
    }

    func moveLayer(from index: Int, to destination: Int) {
        guard let profile = selectedProfile else { return }
        edit(working: "Reordering the layers…") { editor, previous in
            editor.moveLayer(from: index, to: destination, in: profile, previous: previous)
        }
    }

    /// An edit that can reach the live file: when the edited profile's block is
    /// live, the store write is followed by a privileged write, which is a round
    /// trip to the helper and takes its whole bound when nothing answers. It
    /// runs away from the main thread, like an apply, and one at a time: a
    /// second edit asked for while one is in flight would plan from a
    /// presentation the first is about to change.
    private func edit(
        working: String,
        _ body: @escaping @Sendable (EditorModel, EditorPresentation) -> EditorOutcome
    ) {
        guard !busy else { return }
        let editorModel = session.editor
        let previous = editor
        busy = true
        notice = .progress(working)
        Task.detached {
            let outcome = body(editorModel, previous)
            await MainActor.run { self.finish(outcome) }
        }
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

    /// Renames the item the sidebar shows selected, or the one a row's own menu
    /// names: a row's menu opens without selecting the row, so it says which.
    func beginRename(_ item: SidebarSelection? = nil) {
        switch item ?? editor.selection {
        case .profile(let profile): beginNameEntry(.renameProfile(profile))
        case .fragment(let fragment): beginNameEntry(.renameFragment(fragment))
        case nil: break
        }
    }

    func beginDuplicate(_ item: SidebarSelection? = nil) {
        switch item ?? editor.selection {
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

    // MARK: - Deleting

    /// Asks before deleting: the store keeps no history, so this is the one
    /// step that cannot be undone. Names the row's own item when a row's menu
    /// asks, the selection otherwise.
    func requestDelete(_ item: SidebarSelection? = nil) {
        switch item ?? editor.selection {
        case .profile(let profile): deletion = .profile(profile)
        case .fragment(let fragment): deletion = .fragment(fragment)
        case nil: break
        }
    }

    func cancelDelete() {
        deletion = nil
    }

    /// Performs the confirmed deletion.
    func confirmDelete() {
        guard let request = deletion else { return }
        deletion = nil
        switch request {
        case .profile(let profile): deleteProfile(profile)
        case .fragment(let fragment): deleteFragment(fragment)
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
        // One write at a time: a second apply would plan from the bytes the
        // first is replacing, and the helper would refuse it as a stale baseline
        // at best.
        guard !busy else { return }
        let editorModel = session.editor
        busy = true
        notice = .progress("Applying \(profile)…")
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
        notice = .progress("Reverting…")
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
        notice = .progress("Removing the block…")
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
        notice = .success("The store path is on the clipboard.")
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
        case .apply: requestApply()
        case .revert: requestRevert()
        case .overwriteDrift: requestOverwriteDrift()
        case .removeBlock: requestRemoveBlock()
        case .reload: refresh()
        case .rename: beginRename()
        case .duplicate: beginDuplicate()
        case .delete: requestDelete()
        case .save: saveFragmentDraft()
        case .installHelper: showHelperSheet = true
        case .repairHelper: repairHelper()
        case .revealHostsFile: revealHostsFile()
        case .toggleSidebar: sidebarVisible.toggle()
        case .search: focusSearch()
        case .showHelp: showHelperSheet = true
        case .checkForUpdates: checkForUpdates()
        }
    }

    private func finish(_ outcome: ApplyOutcome) {
        busy = false
        notice = MenuNotice(outcome)
        followUp(on: outcome)
        refresh()
    }

    /// A write is the strongest check there is: the helper answers by writing.
    /// A write that did not go through is evidence it is not there, so the state
    /// follows what was just learned instead of waiting for the next interval.
    private func followUp(on outcome: ApplyOutcome) {
        switch outcome {
        case .applied: record(.answering)
        case .refused, .failed: checkPresence(forced: true)
        case .nothingToDo: break
        }
    }

    private func finish(_ outcome: EditorOutcome) {
        busy = false
        notice = MenuNotice(outcome)
        if let apply = outcome.apply { followUp(on: apply) }
        refresh()
    }

    // MARK: - Presence in the Dock

    /// A window is on screen: the application is a regular citizen again, in
    /// the Dock and the application switcher, and comes forward.
    func windowOpened() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    /// With no window on screen the application lives in the menu bar alone:
    /// out of the Dock and the switcher, the way menu-bar applications are.
    /// Decided synchronously, because the closing window is still on screen
    /// while its notification travels.
    private func matchDockPresenceToTheWindows(ignoring closing: ObjectIdentifier?) {
        let windowIsVisible = NSApp.windows.contains { window in
            ObjectIdentifier(window) != closing && window.level == .normal && window.isVisible
        }
        NSApp.setActivationPolicy(windowIsVisible ? .regular : .accessory)
    }

    deinit {
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
        }
        if let dockObserver {
            NotificationCenter.default.removeObserver(dockObserver)
        }
        if let keyWindowObserver {
            NotificationCenter.default.removeObserver(keyWindowObserver)
        }
    }
}
