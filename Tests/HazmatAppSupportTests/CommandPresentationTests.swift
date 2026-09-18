import Foundation
import HazmatCore
import XCTest
@testable import HazmatAppSupport
import HazmatProtocol

/// The menu bar as a value: every action has an item, the shortcuts are the
/// ones the proposal names, and an item that cannot act in the current state is
/// listed but reported disabled.
final class CommandPresentationTests: XCTestCase {
    private let work = ProfileID("work")
    private let base = FragmentID("base")
    /// The file the app writes, without naming it: the suite must never touch it.
    private let hostsFile = DaemonTarget.hostsFile.path

    private func fixture(layers: String = "base\n") throws -> StoreFixture {
        try StoreFixture(
            store: [
                ("127.0.0.1\tlocalhost\n", "fragments/base.hosts"),
                ("127.0.0.1\tlocalhost\n", "fragments/full.hosts"),
                (layers, "profiles/work.profile")
            ],
            live: "127.0.0.1\tlocalhost\n"
        )
    }

    private func commands(
        _ fixture: StoreFixture,
        helper: HelperState = .enabled,
        canRevert: Bool = false,
        hasUnsavedEdit: Bool = false,
        selection: SidebarSelection? = .profile(ProfileID("work"))
    ) -> CommandPresentation {
        let editor = fixture.model(writer: UnregisteredHelper()).read(selection: selection)
        return CommandPresentation.menuBar(
            editor: editor,
            helper: helper,
            canRevert: canRevert,
            hasUnsavedEdit: hasUnsavedEdit
        )
    }

    // MARK: - 5.1 The menu bar

    func testTheMenuBarCarriesEveryMenuTheChangeNames() throws {
        let fixture = try fixture()
        defer { fixture.remove() }

        let menus = commands(fixture).menus

        XCTAssertEqual(menus.map(\.id), ["app", "file", "edit", "profiles", "fragments", "hosts", "window", "help"])
        XCTAssertEqual(
            menus.map(\.title),
            ["Hazmat", "File", "Edit", "Profiles", "Fragments", "Hosts", "Window", "Help"]
        )
        for menu in menus {
            XCTAssertFalse(menu.items.isEmpty, "\(menu.title) holds no items")
        }
    }

    func testEveryWindowActionHasAMenuItem() throws {
        let fixture = try fixture()
        defer { fixture.remove() }

        let actions = Set(commands(fixture).menus.flatMap(\.items).map(\.action))
        let expected: Set<WindowAction> = [
            .createStore, .chooseLocation, .newProfile, .newFragment, .apply, .revert, .overwriteDrift,
            .removeBlock, .reload, .rename, .duplicate, .delete, .save, .installHelper, .repairHelper,
            .revealHostsFile, .openSettings, .toggleSidebar, .search, .showHelp
        ]

        XCTAssertEqual(actions, expected)
    }

    func testTheShortcutsAreTheOnesTheProposalNames() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let commands = commands(fixture)

        XCTAssertEqual(commands.item("new-profile")?.shortcut?.display, "⌘N")
        XCTAssertEqual(commands.item("new-fragment")?.shortcut?.display, "⇧⌘N")
        XCTAssertEqual(commands.item("reload")?.shortcut?.display, "⌘R")
        XCTAssertEqual(commands.item("apply")?.shortcut?.display, "⌘⏎")
        XCTAssertEqual(commands.item("duplicate-profile")?.shortcut?.display, "⌘D")
        XCTAssertEqual(commands.item("delete-profile")?.shortcut?.display, "⌘⌫")
        XCTAssertEqual(commands.item("search")?.shortcut?.display, "⌘F")
        XCTAssertEqual(commands.item("settings")?.shortcut?.display, "⌘,")
        XCTAssertEqual(commands.item("save")?.shortcut?.display, "⌘S")
        XCTAssertEqual(commands.item("toggle-sidebar")?.shortcut?.display, "⌃⌘S")
    }

    func testTheActionsThatActOnTheSelectionAreOffWithoutOne() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        // A search that hides the selection leaves the window with nothing
        // selected to act on.
        let editor = fixture.model(writer: UnregisteredHelper())
            .read(selection: .profile(work), search: StoreSearch(text: "no item matches this"))
        let commands = CommandPresentation.menuBar(
            editor: editor,
            helper: .enabled,
            canRevert: false,
            hasUnsavedEdit: false
        )

        XCTAssertTrue(commands.item("rename-profile")?.isEnabled == false)
        XCTAssertTrue(commands.item("duplicate-profile")?.isEnabled == false)
        XCTAssertTrue(commands.item("delete-profile")?.isEnabled == false)
    }

    func testTheWriteCommandsFollowTheWriteState() throws {
        let fixture = try fixture()
        defer { fixture.remove() }

        let pending = commands(fixture)
        XCTAssertTrue(pending.item("apply")?.isEnabled == true, "a pending write can be applied")
        XCTAssertTrue(pending.item("revert")?.isEnabled == false, "nothing has been applied this session")

        let blocked = commands(fixture, helper: .notRegistered)
        XCTAssertTrue(blocked.item("apply")?.isEnabled == false, "a blocked write is not offered")
        XCTAssertTrue(blocked.item("install-helper")?.isEnabled == true)
        XCTAssertFalse(
            blocked.item("repair-helper")?.isEnabled == true,
            "a helper that is not installed is installed, not repaired"
        )

        let notAnswering = commands(fixture, helper: .notAnswering)
        XCTAssertFalse(
            notAnswering.item("install-helper")?.isEnabled == true,
            "a registered helper is not installed again"
        )
        XCTAssertTrue(notAnswering.item("repair-helper")?.isEnabled == true)

        let reverted = commands(fixture, canRevert: true)
        XCTAssertTrue(reverted.item("revert")?.isEnabled == true)

        let helperReady = commands(fixture, helper: .enabled)
        XCTAssertTrue(helperReady.item("install-helper")?.isEnabled == false, "an enabled helper needs no install item")
        XCTAssertTrue(helperReady.item("repair-helper")?.isEnabled == false, "an enabled helper needs no repair")
    }

    func testSaveFollowsTheDraft() throws {
        let fixture = try fixture()
        defer { fixture.remove() }

        XCTAssertTrue(commands(fixture, hasUnsavedEdit: false).item("save")?.isEnabled == false)
        XCTAssertTrue(commands(fixture, hasUnsavedEdit: true).item("save")?.isEnabled == true)
    }

    func testTheStoreCommandsFollowWhatTheStoreHolds() throws {
        let fixture = try fixture()
        defer { fixture.remove() }

        let held = commands(fixture)
        XCTAssertTrue(held.item("create-store")?.isEnabled == false, "the store exists")
        XCTAssertTrue(held.item("remove-block")?.isEnabled == false, "the file holds no block")
        XCTAssertTrue(held.item("reveal")?.isEnabled == false)

        let store = try TemporaryStore()
        let root = store.root
        store.remove()
        let live = try LiveFile("127.0.0.1\tlocalhost\n")
        defer { live.remove() }
        let missing = EditorModel(storeRoot: root, fileURL: live.url, writer: UnregisteredHelper()).read()
        let commands = CommandPresentation.menuBar(editor: missing, helper: .enabled, canRevert: false, hasUnsavedEdit: false)

        XCTAssertTrue(commands.item("create-store")?.isEnabled == true)
        XCTAssertTrue(commands.item("new-profile")?.isEnabled == true, "a first profile is offered before a store exists")
    }

    func testAnAppliedBlockOffersRevealAndRemoval() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        try fixture.applyToLive(work)

        let commands = commands(fixture)

        XCTAssertTrue(commands.item("reveal")?.isEnabled == true)
        XCTAssertTrue(commands.item("remove-block")?.isEnabled == true)
        XCTAssertTrue(commands.item("apply")?.isEnabled == false, "an in-sync profile has nothing to apply")
    }

    // MARK: - 5.6 The toolbar's own actions

    func testTheToolbarActsOnlyThroughCommandsThatEveryPhaseCanPerform() throws {
        let fixture = try fixture()
        defer { fixture.remove() }

        let toolbar = ["toggle-sidebar", "new-profile", "new-fragment", "reload"]
        for id in toolbar {
            XCTAssertTrue(commands(fixture).item(id)?.isEnabled == true, "\(id) must work in this phase")
        }
    }

    func testTheWriteRequestConfirmationNamesTheFileAndTheEntries() {
        let request = WriteRequest.apply(profile: work, entries: 3, file: hostsFile)

        XCTAssertEqual(request.title, "Apply 3 entries to \(hostsFile)?")
        XCTAssertEqual(request.message.isEmpty, false)
        XCTAssertEqual(request.confirmTitle, "Apply")
        XCTAssertFalse(request.isDestructive, "an apply keeps what it replaces")
        XCTAssertEqual(request.file, hostsFile)
        XCTAssertEqual(request.entryCount, 3)
        XCTAssertEqual(request.profile, work)
    }

    func testOverwritingDriftAndRemovingTheBlockAreDestructive() {
        let overwrite = WriteRequest.overwriteDrift(profile: work, entries: 2, file: hostsFile)
        let remove = WriteRequest.removeBlock(file: hostsFile)
        let revert = WriteRequest.revert(profile: work, file: hostsFile, removesBlock: false)

        XCTAssertTrue(overwrite.isDestructive)
        XCTAssertTrue(remove.isDestructive)
        XCTAssertFalse(revert.isDestructive)
        XCTAssertTrue(overwrite.title.contains(hostsFile))
        XCTAssertEqual(overwrite.confirmTitle, "Replace the Block")
        XCTAssertTrue(remove.message.contains("markers"), remove.message)
    }

    func testRevertingAnInstallSaysThatItRemovesTheBlock() {
        let request = WriteRequest.revert(profile: work, file: hostsFile, removesBlock: true)

        XCTAssertEqual(request.confirmTitle, "Remove the Block")
        XCTAssertTrue(request.title.contains("Remove the managed block"), request.title)
        XCTAssertTrue(request.message.contains("removes it"), request.message)
    }
}
