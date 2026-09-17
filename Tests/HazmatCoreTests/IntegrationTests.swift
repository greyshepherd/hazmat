import XCTest
@testable import HazmatCore

final class IntegrationTests: XCTestCase {
    private let work = ProfileID("work")

    func testThreeFragmentsAndAProfileReachASplicedHostsFile() throws {
        let shipped = try Fixture.data("shipped-hosts", ext: "txt")
        let composition = try workComposition()

        let spliced = try BlockSplice.splice(block: BlockRenderer.render(composition), into: shipped)

        XCTAssertEqualBytes(spliced, try Fixture.data("expected-work-hosts", ext: "txt"))
        XCTAssertEqual(composition.displacements.count, 1)
        XCTAssertEqual(composition.address(of: "api.internal", .ipv4), "127.0.0.1")
        XCTAssertEqual(composition.address(of: "api.internal", .ipv6), "::1")
        XCTAssertEqual(composition.address(of: "legacy.example.com", .ipv4), nil)
        XCTAssertEqualBytes(try BlockSplice.strip(from: spliced), shipped)
    }

    func testTheWholePathReadsAndWritesOnlyInsideTheWorkspace() throws {
        let workspace = try Workspace()
        defer { workspace.remove() }

        let fragmentBefore = try Data(contentsOf: workspace.root.appendingPathComponent("fragments/base.hosts"))
        let composition = try HostsComposer(store: workspace.store).compose(profile: work)
        let original = bytes("127.0.0.1\tlocalhost\n")
        let spliced = try BlockSplice.splice(block: BlockRenderer.render(composition), into: original)

        XCTAssertEqualBytes(Data(spliced.prefix(original.count)), original)
        XCTAssertEqualBytes(try BlockSplice.strip(from: spliced), original)
        XCTAssertEqualBytes(try Data(contentsOf: workspace.root.appendingPathComponent("fragments/base.hosts")), fragmentBefore)

        let entries = try FileManager.default.contentsOfDirectory(atPath: workspace.root.path).sorted()
        XCTAssertEqual(entries, ["fragments", "profiles"])
    }

    func testTheSuiteLeavesEtcHostsUntouched() throws {
        let hosts = URL(fileURLWithPath: "/etc/hosts")
        let before = try snapshot(of: hosts)

        let workspace = try Workspace()
        defer { workspace.remove() }
        let composition = try HostsComposer(store: workspace.store).compose(profile: work)
        let shipped = try Fixture.data("shipped-hosts", ext: "txt")
        let spliced = try BlockSplice.splice(block: BlockRenderer.render(composition), into: shipped)
        _ = try BlockSplice.strip(from: spliced)
        _ = try Fixture.data("expected-work-hosts", ext: "txt")

        let after = try snapshot(of: hosts)
        XCTAssertEqual(before.contents, after.contents, "/etc/hosts bytes changed during the suite")
        XCTAssertEqual(before.modificationDate, after.modificationDate, "/etc/hosts modification date changed during the suite")
        XCTAssertEqual(before.size, after.size)
    }
}
