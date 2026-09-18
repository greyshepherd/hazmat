import Foundation
import HazmatCore
import XCTest
@testable import HazmatAppSupport

/// One location at a time, resolved as the environment, then the choice, then
/// the default; and a store that can be created before it holds anything.
final class StoreLocationTests: XCTestCase {
    private let chosen = URL(fileURLWithPath: "/tmp/hazmat-chosen-store")
    private let environmentStore = "/tmp/hazmat-environment-store"

    // MARK: - 2.1 Resolution

    func testTheEnvironmentWins() {
        let resolved = StoreLocation.resolve(
            environment: [StoreLocation.environmentKey: environmentStore],
            chosen: chosen
        )

        XCTAssertEqual(resolved.path, environmentStore)
    }

    func testTheChoiceIsUsedWhenTheEnvironmentNamesNothing() {
        let resolved = StoreLocation.resolve(environment: [:], chosen: chosen)

        XCTAssertEqual(resolved, chosen)
    }

    func testTheDefaultIsUsedWhenNothingElseSays() {
        let resolved = StoreLocation.resolve(environment: [:], chosen: nil)

        XCTAssertEqual(resolved, StoreLocation.applicationSupportRoot)
        XCTAssertTrue(resolved.path.hasSuffix("/Library/Application Support/Hazmat/store"), resolved.path)
    }

    func testAnEmptyEnvironmentValueIsNotAnOverride() {
        let resolved = StoreLocation.resolve(environment: [StoreLocation.environmentKey: ""], chosen: chosen)

        XCTAssertEqual(resolved, chosen)
    }

    func testAChosenLocationThatIsNotThereReportsAsNoStoreRatherThanFallingBack() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("hazmat-missing-\(UUID().uuidString)")

        let resolved = StoreLocation.resolve(environment: [:], chosen: missing)
        let layout = StoreLayout(root: resolved)

        XCTAssertEqual(resolved, missing)
        XCTAssertFalse(layout.exists)
        XCTAssertEqual(layout.profiles(), [])
        XCTAssertEqual(layout.fragments(), [])
        XCTAssertNotEqual(resolved, StoreLocation.applicationSupportRoot, "resolution never falls back past a choice")
    }

    // MARK: - 2.2 Creating the store

    func testCreatingTheStoreMakesItsDirectoriesAndHoldsNothing() throws {
        let store = try TemporaryStore()
        let root = store.root
        store.remove()
        let layout = StoreLayout(root: root)

        XCTAssertEqual(try layout.create(), .created)

        XCTAssertTrue(layout.exists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.fragmentsDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.profilesDirectory.path))
        XCTAssertEqual(layout.profiles(), [])
        XCTAssertEqual(layout.fragments(), [])
    }

    func testCreatingItTwiceReportsNothingToDo() throws {
        let store = try TemporaryStore()
        defer { store.remove() }
        let layout = StoreLayout(root: store.root)

        XCTAssertEqual(try layout.create(), .created)
        let before = try FileManager.default.attributesOfItem(atPath: layout.profilesDirectory.path)

        XCTAssertEqual(try layout.create(), .nothingToDo)
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: layout.profilesDirectory.path)[.modificationDate] as? Date,
            before[.modificationDate] as? Date
        )
    }

    func testCreatingTheStoreNeedsNoPrivilegeAndLeavesTheLiveFileAlone() throws {
        let store = try TemporaryStore()
        let root = store.root
        store.remove()
        let live = try LiveFile("127.0.0.1\tlocalhost\n")
        defer { live.remove() }
        let unregistered = UnregisteredHelper()
        let model = EditorModel(storeRoot: root, fileURL: live.url, writer: unregistered)
        let liveBefore = try live.state()

        XCTAssertEqual(try StoreLayout(root: root).create(), .created)
        XCTAssertEqual(try live.state(), liveBefore, "creating a store touches no live file")
        XCTAssertEqual(unregistered.requests, 0, "creating a store asks the helper for nothing")
        XCTAssertEqual(model.read().storeExists, true)
    }

    func testCreatingAStoreAtAChosenLocationThatDoesNotExistWorks() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("hazmat-chosen-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: missing) }

        let layout = StoreLayout(root: StoreLocation.resolve(environment: [:], chosen: missing))

        XCTAssertFalse(layout.exists)
        XCTAssertEqual(try layout.create(), .created)
        XCTAssertTrue(layout.exists)
    }

    // MARK: - 2.4 The chosen location is remembered

    func testTheChosenLocationIsRememberedAndReadBack() throws {
        let preference = PreferenceDouble()

        XCTAssertNil(preference.chosenLocation())
        preference.remember(chosen)
        XCTAssertEqual(preference.chosenLocation(), chosen)

        preference.remember(nil)
        XCTAssertNil(preference.chosenLocation())
    }

    func testTheDefaultsPreferenceRoundTripsAPath() throws {
        let suite = "hazmat-tests-\(UUID().uuidString)"
        let preference = DefaultsStoreLocationPreference(suiteName: suite)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        XCTAssertNil(preference.chosenLocation())
        preference.remember(chosen)
        XCTAssertEqual(preference.chosenLocation()?.path, chosen.path)
        preference.remember(nil)
        XCTAssertNil(preference.chosenLocation())
    }
}
