import Foundation
import HazmatCore
import XCTest
@testable import HazmatAppSupport

final class ProfileCatalogueTests: XCTestCase {
    func testListsTheStoresProfilesAndIgnoresEverythingElse() throws {
        let store = try TemporaryStore()
        defer { store.remove() }
        try store.write("base\n", to: "profiles/work.profile")
        try store.write("project\n", to: "profiles/alpha.profile")
        try store.write("notes\n", to: "profiles/notes.txt")
        try store.write("bad\n", to: "profiles/..secret.profile")

        let catalogue = ProfileCatalogue(root: store.root)

        XCTAssertTrue(catalogue.exists)
        XCTAssertEqual(catalogue.profiles().map(\.rawValue), ["alpha", "work"])
    }

    func testAMissingStoreHoldsNoProfiles() throws {
        let store = try TemporaryStore()
        let root = store.root
        store.remove()

        let catalogue = ProfileCatalogue(root: root)

        XCTAssertFalse(catalogue.exists)
        XCTAssertEqual(catalogue.profiles(), [])
    }

    func testRendersTheBlockTheStoreWouldApply() throws {
        let store = try TemporaryStore()
        defer { store.remove() }
        try store.write("127.0.0.1\tlocalhost hazmat.local\n::1\tapi.internal\n", to: "fragments/base.hosts")
        try store.write("0.0.0.0\tads.example.com\n", to: "fragments/project.hosts")
        try store.write("base\nproject\n", to: "profiles/work.profile")

        let catalogue = ProfileCatalogue(root: store.root)
        let rendered = try catalogue.renderedBlock(for: ProfileID("work"))

        let composition = try HostsComposer(store: DirectoryStore(root: store.root)).compose(profile: ProfileID("work"))
        XCTAssertEqual(rendered, BlockRenderer.render(composition))
        XCTAssertTrue(text(rendered).hasPrefix("# >>> hazmat:managed v1 >>>\n"))
        XCTAssertTrue(text(rendered).hasSuffix("# <<< hazmat:managed v1 <<<\n"))
        XCTAssertTrue(text(rendered).contains("127.0.0.1 localhost hazmat.local\n"))
        XCTAssertTrue(text(rendered).contains("0.0.0.0 ads.example.com\n"))
    }

    func testAProfileThatDoesNotComposeIsReportedRatherThanRendered() throws {
        let store = try TemporaryStore()
        defer { store.remove() }
        try store.write("missing\n", to: "profiles/work.profile")

        let catalogue = ProfileCatalogue(root: store.root)

        XCTAssertThrowsError(try catalogue.renderedBlock(for: ProfileID("work")))
        XCTAssertEqual(catalogue.profiles().map(\.rawValue), ["work"])
    }

    func testTheStoreRootCanBePointedAtADirectoryFromTheEnvironment() {
        let previous = ProcessInfo.processInfo.environment[StoreLocation.environmentKey]
        setenv(StoreLocation.environmentKey, "/tmp/hazmat-store-probe", 1)
        XCTAssertEqual(StoreLocation.defaultRoot.path, "/tmp/hazmat-store-probe")
        unsetenv(StoreLocation.environmentKey)

        if let previous {
            setenv(StoreLocation.environmentKey, previous, 1)
        } else {
            XCTAssertNotEqual(StoreLocation.defaultRoot.path, "/tmp/hazmat-store-probe")
        }
    }

    func testTheShellUsesTheProfilessRenderedBlockAndNeverTheResolvedNames() {
        let model = sourceFiles(in: "Sources/HazmatApp").first { $0.0 == "ShellModel.swift" }?.1 ?? ""

        XCTAssertTrue(model.contains("catalogue.renderedBlock(for: profile)"), model)
        XCTAssertFalse(model.contains(".resolved"), model)
    }
}
