import Foundation
import HazmatCore
import XCTest
@testable import HazmatAppSupport

private struct UnreadableFile: Error {}

final class ActiveProfileReadingTests: XCTestCase {
    private let work = ProfileID("work")

    private func makeStore(_ files: [(String, String)]) throws -> TemporaryStore {
        let store = try TemporaryStore()
        for (contents, path) in files {
            try store.write(contents, to: path)
        }
        return store
    }

    // MARK: - 2.1 One read, every profile rendered

    func testReadsTheFileOnceWithSeveralProfilesAndAttributesTheMatch() throws {
        let store = try makeStore([
            ("127.0.0.1\tlocalhost\n", "fragments/base.hosts"),
            ("0.0.0.0\tads.example.com\n", "fragments/ads.hosts"),
            ("base\n", "profiles/work.profile"),
            ("base\nads\n", "profiles/full.profile"),
            ("base\nads\n", "profiles/twin.profile")
        ])
        defer { store.remove() }
        let catalogue = ProfileCatalogue(root: store.root)
        let file = CountingFile(try catalogue.renderedBlock(for: ProfileID("full")))

        let reading = catalogue.activation(reading: file)

        XCTAssertEqual(file.reads, 1, "the live file must be read once, not once per profile")
        XCTAssertEqual(reading.profiles, [ProfileID("full"), ProfileID("twin"), work])
        XCTAssertEqual(reading.activation?.state, .active([ProfileID("full"), ProfileID("twin")]))
    }

    func testReportsDriftWhenTheLiveBlockMatchesNoProfile() throws {
        let store = try makeStore([
            ("127.0.0.1\tlocalhost\n", "fragments/base.hosts"),
            ("base\n", "profiles/work.profile")
        ])
        defer { store.remove() }
        let catalogue = ProfileCatalogue(root: store.root)
        let stranger = bytes("# >>> hazmat:managed v1 >>>\n10.1.2.3 stranger.example\n# <<< hazmat:managed v1 <<<\n")
        XCTAssertNotEqual(try catalogue.renderedBlock(for: work), stranger)

        let reading = catalogue.activation(reading: CountingFile(stranger))

        XCTAssertEqual(reading.activation?.state, .drifted(ByteDigest(stranger)))
    }

    // MARK: - 2.2 A missing or empty store is its own result

    func testAMissingStoreIsItsOwnResultAndReadsNothing() throws {
        let store = try TemporaryStore()
        let root = store.root
        store.remove()
        let file = CountingFile(Data())

        let reading = ProfileCatalogue(root: root).activation(reading: file)

        XCTAssertEqual(reading, .missingStore)
        XCTAssertEqual(reading.profiles, [])
        XCTAssertNil(reading.activation)
        XCTAssertEqual(file.reads, 0)
    }

    func testAStoreHoldingNoProfilesIsItsOwnResultAndReadsNothing() throws {
        let store = try makeStore([])
        defer { store.remove() }
        try FileManager.default.createDirectory(
            at: store.root.appendingPathComponent("profiles"),
            withIntermediateDirectories: true
        )
        let file = CountingFile(Data())

        let reading = ProfileCatalogue(root: store.root).activation(reading: file)

        XCTAssertEqual(reading, .emptyStore)
        XCTAssertEqual(reading.profiles, [])
        XCTAssertEqual(file.reads, 0)
    }

    func testAFileThatCannotBeReadIsReportedWithItsReason() throws {
        let store = try makeStore([("base\n", "profiles/work.profile")])
        defer { store.remove() }
        let catalogue = ProfileCatalogue(root: store.root)

        let reading = catalogue.activation(reading: CountingFile(failing: UnreadableFile()))

        guard case .unreadableFile(let profiles, let reason) = reading else {
            return XCTFail("expected the read failure to be reported, got \(reading)")
        }
        XCTAssertEqual(profiles, [work])
        XCTAssertFalse(reason.isEmpty)
    }

    // MARK: - 2.3 One broken profile does not fail the read

    func testAProfileThatFailsToRenderDoesNotFailTheRead() throws {
        let store = try makeStore([
            ("127.0.0.1\tlocalhost\n", "fragments/base.hosts"),
            ("base\n", "profiles/work.profile"),
            ("missing\n", "profiles/broken.profile")
        ])
        defer { store.remove() }
        let catalogue = ProfileCatalogue(root: store.root)
        let file = CountingFile(try catalogue.renderedBlock(for: work))

        let reading = catalogue.activation(reading: file)

        guard case .derived(let profiles, let activation) = reading else {
            return XCTFail("expected a derivation, got \(reading)")
        }
        XCTAssertEqual(profiles, [ProfileID("broken"), work])
        XCTAssertEqual(activation.state, .active([work]))
        XCTAssertEqual(activation.problems.map(\.profile), [ProfileID("broken")])
        XCTAssertTrue(activation.problems[0].reason.contains("missing"), activation.problems[0].reason)
        XCTAssertEqual(file.reads, 1)
    }

    // MARK: - Replacing the live block is a switch only when it belongs to a profile

    /// The menu's deliberate overwrite names the block the derivation found, so
    /// the apply that follows replaces exactly the bytes that were read.
    func testTheOverwriteTheMenuOffersCarriesTheBlockTheDerivationFound() throws {
        let store = try makeStore([
            ("127.0.0.1\tlocalhost\n", "fragments/base.hosts"),
            ("base\n", "profiles/work.profile")
        ])
        defer { store.remove() }
        let stranger = bytes("# >>> hazmat:managed v1 >>>\n10.1.2.3 stranger.example\n# <<< hazmat:managed v1 <<<\n")

        let reading = ProfileCatalogue(root: store.root).activation(reading: CountingFile(stranger))
        guard case .drifted(let found)? = reading.activation?.state else {
            return XCTFail("expected a drift, got \(reading)")
        }
        let menu = MenuPresentation(reading: reading, helper: .enabled, notice: .quiet)
        let item = menu.sections.flatMap(\.items).first { $0.title == "Overwrite drift with 'work'" }

        XCTAssertEqual(found, ByteDigest(stranger))
        XCTAssertEqual(item?.action, .overwriteDrift(work, block: found))
    }

    func testOnlyABlockThatBelongsToAProfileMayBeReplacedAsASwitch() {
        let work = ProfileID("work")

        XCTAssertTrue(derived([work], .active([work])).replacingIsASwitch)
        XCTAssertFalse(derived([work], .drifted(ByteDigest(Data("x".utf8)))).replacingIsASwitch)
        XCTAssertFalse(derived([work], .off).replacingIsASwitch)
        XCTAssertFalse(derived([work], .unreadable(.unterminatedBlock(line: 1))).replacingIsASwitch)
        XCTAssertFalse(ActiveProfileReading.missingStore.replacingIsASwitch)
        XCTAssertFalse(ActiveProfileReading.emptyStore.replacingIsASwitch)
        XCTAssertFalse(ActiveProfileReading.unreadableFile(profiles: [work], reason: "no such file").replacingIsASwitch)
    }

    private func derived(_ profiles: [ProfileID], _ state: ActiveProfileState) -> ActiveProfileReading {
        .derived(profiles: profiles, activation: ActiveProfile(state: state))
    }
}
