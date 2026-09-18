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
        hasUnsavedEdit: Bool = false,
        update: UpdateAvailability = .unavailable,
        selection: SidebarSelection? = .profile(ProfileID("work"))
    ) -> CommandPresentation {
        let editor = fixture.model(writer: UnregisteredHelper()).read(selection: selection)
        return CommandPresentation.menuBar(
            editor: editor,
            helper: helper,
            hasUnsavedEdit: hasUnsavedEdit,
            update: update
        )
    }

    // MARK: - 5.1 The menu bar

    func testTheMenuBarCarriesEveryMenuTheChangeNames() throws {
        let fixture = try fixture()
        defer { fixture.remove() }

        let menus = commands(fixture).menus

        XCTAssertEqual(menus.map(\.id), ["app", "file", "edit", "hosts", "window", "help"])
        XCTAssertEqual(
            menus.map(\.title),
            ["Hazmat", "File", "Edit", "Hosts", "Window", "Help"]
        )
        // The application menu holds the update check when the bundle declares a
        // feed, and the settings scene and the platform fill the rest of it.
        for menu in menus where menu.id != "app" {
            XCTAssertFalse(menu.items.isEmpty, "\(menu.title) holds no items")
        }
    }

    /// The menu bar carries the commands whose subject is the application, the
    /// store, or the live file. A command that acts on the selection is offered
    /// on the row that shows it, and one that acts on the live block where the
    /// block was read: a menu bar cannot name either.
    func testTheMenuBarCarriesNoCommandThatActsOnASelectionOrTheLiveBlock() throws {
        let fixture = try fixture()
        defer { fixture.remove() }

        // A bundle that declares a feed, so the one action a bundle without one is
        // not offered is part of the set being checked.
        let actions = Set(commands(fixture, update: .available).menus.flatMap(\.items).map(\.action))
        let expected: Set<WindowAction> = [
            .createStore, .chooseLocation, .newProfile, .newFragment, .apply,
            .removeBlock, .reload, .save, .installHelper, .repairHelper,
            .revealHostsFile, .toggleSidebar, .search, .showHelp, .checkForUpdates
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
        XCTAssertEqual(commands.item("search")?.shortcut?.display, "⌘F")
        XCTAssertEqual(commands.item("save")?.shortcut?.display, "⌘S")
        XCTAssertEqual(commands.item("toggle-sidebar")?.shortcut?.display, "⌃⌘S")
    }

    // MARK: - 4.5 The application menu's update check

    func testTheApplicationMenuOffersTheCheckWhenTheBundleHasAFeed() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let commands = commands(fixture, update: .available)

        XCTAssertEqual(
            commands.menu("app")?.items.map(\.id), ["check-for-updates"],
            "the application menu carries the check and nothing the settings scene owns"
        )
        XCTAssertEqual(commands.item("check-for-updates")?.action, .checkForUpdates)
        XCTAssertEqual(commands.item("check-for-updates")?.title, "Check for Updates…")
        XCTAssertTrue(commands.item("check-for-updates")?.isEnabled == true)
        XCTAssertFalse(
            commands.menus.flatMap(\.items).contains { $0.title.hasPrefix("Settings") },
            "the settings scene owns its own item, so a second one would be the same control twice"
        )
    }

    func testTheApplicationMenuOffersNoCheckWithoutAFeed() throws {
        let fixture = try fixture()
        defer { fixture.remove() }

        // A development bundle, and a release whose framework could not start.
        for availability in [UpdateAvailability.unavailable] {
            let commands = commands(fixture, update: availability)
            XCTAssertEqual(commands.menu("app")?.items.map(\.id), [], "the application menu is empty")
            XCTAssertNil(commands.item("check-for-updates"), "a bundle with no feed can only report that")
            XCTAssertFalse(
                commands.menus.flatMap(\.items).map(\.action).contains(.checkForUpdates),
                "no menu may offer a check the bundle cannot make"
            )
        }
    }

    /// A check that failed is still a check this bundle can make, so it stays
    /// offered: the failure is what the person needs to see and retry.
    func testTheApplicationMenuStillOffersACheckThatFailed() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let commands = commands(fixture, update: .failed("the feed could not be reached"))

        XCTAssertEqual(commands.item("check-for-updates")?.action, .checkForUpdates)
    }

    func testTheActionsThatActOnTheSelectionAreOfferedOnTheRowInstead() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        // A search that hides the selection leaves the window with nothing
        // selected to act on.
        let editor = fixture.model(writer: UnregisteredHelper())
            .read(selection: .profile(work), search: StoreSearch(text: "no item matches this"))
        let commands = CommandPresentation.menuBar(
            editor: editor,
            helper: .enabled,
            hasUnsavedEdit: false
        )

        for id in ["rename-profile", "duplicate-profile", "delete-profile", "rename-fragment",
                   "duplicate-fragment", "delete-fragment", "revert", "overwrite-drift"] {
            XCTAssertNil(commands.item(id), "\(id) acts on a row or on the block that was read")
        }
        XCTAssertTrue(
            commands.item("apply")?.isEnabled == false,
            "an apply acts on the selection, so no selection leaves it unusable and unoffered"
        )
    }

    func testTheWriteCommandsFollowTheWriteState() throws {
        let fixture = try fixture()
        defer { fixture.remove() }

        let pending = commands(fixture)
        XCTAssertTrue(pending.item("apply")?.isEnabled == true, "a pending write can be applied")

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
        let commands = CommandPresentation.menuBar(editor: missing, helper: .enabled, hasUnsavedEdit: false)

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
