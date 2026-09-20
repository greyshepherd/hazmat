import Darwin
import Foundation
import XCTest
@testable import HazmatCore

/// A throwaway store root that does not exist until something writes it.
private final class TemporaryRoot {
    let root: URL

    init() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("hazmat-store-\(UUID().uuidString)")
    }

    var layout: StoreLayout { StoreLayout(root: root) }
    var writer: StoreWriter { StoreWriter(layout: layout) }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func write(_ contents: String, to relativePath: String) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func text(_ relativePath: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// Every file under the root, relative to it, so a stray temporary file is
    /// visible. Directories are left out.
    func entries() -> [String] {
        let subpaths = (try? FileManager.default.subpathsOfDirectory(atPath: root.path)) ?? []
        return subpaths.filter { path in
            var isDirectory: ObjCBool = false
            let full = root.appendingPathComponent(path).path
            let exists = FileManager.default.fileExists(atPath: full, isDirectory: &isDirectory)
            return exists && !isDirectory.boolValue
        }
        .sorted()
    }
}

/// A flag and a count, readable from the reader thread.
private final class ReaderLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    private var incomplete: [String] = []
    private var complete = 0

    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
    }

    var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    func record(_ text: String, expected: [String]) {
        lock.lock()
        defer { lock.unlock() }
        if expected.contains(text) {
            complete += 1
        } else {
            incomplete.append(text)
        }
    }

    var summary: (complete: Int, incomplete: [String]) {
        lock.lock()
        defer { lock.unlock() }
        return (complete, incomplete)
    }
}

final class StoreAuthoringTests: XCTestCase {
    private func withoutOverride(_ body: () throws -> Void) rethrows {
        let previous = ProcessInfo.processInfo.environment[StoreLocation.environmentKey]
        unsetenv(StoreLocation.environmentKey)
        defer {
            if let previous {
                setenv(StoreLocation.environmentKey, previous, 1)
            } else {
                unsetenv(StoreLocation.environmentKey)
            }
        }
        try body()
    }

    // MARK: - 2.1 Location and layout

    func testTheDefaultRootIsTheApplicationSupportStoreAndTheLayoutNamesOneFilePerKind() {
        withoutOverride {
            let root = StoreLocation.defaultRoot
            XCTAssertTrue(root.path.hasSuffix("/Library/Application Support/Hazmat/store"), root.path)

            let layout = StoreLayout.current
            XCTAssertEqual(layout.root, root)
            XCTAssertEqual(layout.fragmentURL(FragmentID("base")).path, root.appendingPathComponent("fragments/base.hosts").path)
            XCTAssertEqual(layout.profileURL(ProfileID("work")).path, root.appendingPathComponent("profiles/work.profile").path)
            XCTAssertEqual(layout.fragmentsDirectory.lastPathComponent, "fragments")
            XCTAssertEqual(layout.profilesDirectory.lastPathComponent, "profiles")
            // Nothing here asserts that the default root is empty: running the app
            // creates it, and the acceptance walk runs the app. What `exists` means
            // is asserted against a root this suite chooses.
        }
    }

    func testAnOverriddenRootWinsAndLeavesTheDefaultAlone() {
        withoutOverride {
            let defaultRoot = StoreLocation.defaultRoot

            let probe = "/tmp/hazmat-store-probe-\(UUID().uuidString)"
            setenv(StoreLocation.environmentKey, probe, 1)
            let overridden = StoreLayout.current
            unsetenv(StoreLocation.environmentKey)

            XCTAssertEqual(overridden.root.path, probe)
            XCTAssertTrue(overridden.fragmentURL(FragmentID("base")).path.hasPrefix(probe), overridden.fragmentURL(FragmentID("base")).path)
            XCTAssertTrue(overridden.profileURL(ProfileID("work")).path.hasPrefix(probe))
            XCTAssertEqual(StoreLocation.defaultRoot.path, defaultRoot.path, "the override must not become the default")
            XCTAssertEqual(StoreLayout.current.root.path, defaultRoot.path)
        }
    }

    func testTwoListingsOfTheSameDirectoryReturnTheSameOrder() throws {
        let store = TemporaryRoot()
        defer { store.remove() }
        try store.write("a\n", to: "fragments/zeta.hosts")
        try store.write("b\n", to: "fragments/alpha.hosts")
        try store.write("c\n", to: "profiles/work.profile")
        try store.write("d\n", to: "profiles/ads.profile")
        try store.write("ignored\n", to: "fragments/notes.txt")
        try store.write("ignored\n", to: "profiles/..hidden.profile")

        XCTAssertEqual(store.layout.fragments().map(\.rawValue), ["alpha", "zeta"])
        XCTAssertEqual(store.layout.profiles().map(\.rawValue), ["ads", "work"])
        XCTAssertEqual(store.layout.fragments(), store.layout.fragments())
        XCTAssertEqual(store.layout.profiles(), store.layout.profiles())
    }

    func testListingSeesAFileAnotherToolWrote() throws {
        let store = TemporaryRoot()
        defer { store.remove() }
        XCTAssertEqual(store.layout.fragments(), [])

        try store.write("127.0.0.1\tlocalhost\n", to: "fragments/base.hosts")

        XCTAssertEqual(store.layout.fragments(), [FragmentID("base")])
    }

    func testAStoreWhoseFirstFileWasAFragmentStillExists() throws {
        let store = TemporaryRoot()
        defer { store.remove() }
        let layout = store.layout

        XCTAssertFalse(layout.exists, "nothing has created the store here")

        XCTAssertEqual(try store.writer.save("127.0.0.1\tlocalhost\n", asFragment: FragmentID("base")), .wrote)

        XCTAssertTrue(layout.exists, "a store that holds a fragment is a store, even with no profiles directory yet")
        XCTAssertEqual(layout.fragments().map(\.rawValue), ["base"])
        XCTAssertEqual(layout.profiles(), [])
    }

    // MARK: - 2.2 Names are validated before anything is written

    func testANameOutsideTheGrammarIsRefusedAndLeavesNothingBehind() throws {
        let store = TemporaryRoot()
        defer { store.remove() }
        let refused: [FragmentID] = [
            FragmentID("../escape"),
            FragmentID("with/slash"),
            FragmentID("with/slash space"),
            FragmentID("a..b"),
            FragmentID(".."),
            FragmentID(".hidden"),
            FragmentID("-dash"),
            FragmentID(" leading space"),
            FragmentID("trailing space "),
            FragmentID("two spaces at the end  "),
            FragmentID("")
        ]

        for name in refused {
            XCTAssertThrowsError(try store.writer.save("127.0.0.1\tlocalhost\n", asFragment: name), name.rawValue) { error in
                XCTAssertEqual(error as? StoreWriteError, .invalidName(name.rawValue), name.rawValue)
                XCTAssertFalse((error as? StoreWriteError)?.description.isEmpty ?? true, name.rawValue)
            }
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.layout.fragmentsDirectory.path))
        XCTAssertEqual(store.entries(), [])
    }

    func testANameWithAnInteriorSpaceIsWrittenListedAndCarriedThroughARename() throws {
        let store = TemporaryRoot()
        defer { store.remove() }
        let local = FragmentID("Local Dev")

        XCTAssertEqual(try store.writer.save("127.0.0.1\tdev.local\n", asFragment: local), .wrote)
        XCTAssertEqual(store.layout.fragments(), [local])
        XCTAssertEqual(store.entries(), ["fragments/Local Dev.hosts"])

        XCTAssertEqual(try store.writer.save("Local Dev\n", asProfile: ProfileID("Local Work")), .wrote)
        XCTAssertEqual(store.layout.profiles(), [ProfileID("Local Work")])

        let renamed = FragmentID("Local Dev Two")
        XCTAssertEqual(try store.writer.rename(fragment: local, to: renamed), .wrote)
        XCTAssertEqual(store.layout.fragments(), [renamed])
        XCTAssertEqual(try store.text("fragments/Local Dev Two.hosts"), "127.0.0.1\tdev.local\n")
        XCTAssertEqual(try store.text("profiles/Local Work.profile"), "Local Dev Two\n")
    }

    func testARefusedRenameOrDuplicateTargetTouchesNothing() throws {
        let store = TemporaryRoot()
        defer { store.remove() }
        try store.write("127.0.0.1\tlocalhost\n", to: "fragments/base.hosts")
        try store.write("0.0.0.0\tads.example.com\n", to: "fragments/ads.hosts")
        try store.write("base\n", to: "profiles/work.profile")

        XCTAssertThrowsError(try store.writer.rename(fragment: FragmentID("base"), to: FragmentID("../base")))
        XCTAssertThrowsError(try store.writer.duplicate(profile: ProfileID("work"), as: ProfileID("work/copy")))
        XCTAssertThrowsError(try store.writer.save("x\n", asProfile: ProfileID(".hidden")))

        XCTAssertEqual(
            store.entries().sorted(),
            ["fragments/ads.hosts", "fragments/base.hosts", "profiles/work.profile"]
        )
    }

    // MARK: - 2.3 Create, replace, and duplicate

    func testACreateInAStoreWhoseDirectoriesDoNotExist() throws {
        let store = TemporaryRoot()
        defer { store.remove() }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.root.path))

        XCTAssertEqual(try store.writer.save("127.0.0.1\tlocalhost\n", asFragment: FragmentID("base")), .wrote)

        let written = try String(contentsOf: store.layout.fragmentURL(FragmentID("base")), encoding: .utf8)
        XCTAssertEqual(written, "127.0.0.1\tlocalhost\n")
    }

    func testCreateReplaceAndDuplicateWriteTheTextAndLeaveNoTemporaryFile() throws {
        let store = TemporaryRoot()
        defer { store.remove() }

        XCTAssertEqual(try store.writer.save("first\n", asProfile: ProfileID("work")), .wrote)
        XCTAssertEqual(try store.writer.save("first\nsecond\n", asProfile: ProfileID("work")), .wrote)
        XCTAssertEqual(
            try String(contentsOf: store.layout.profileURL(ProfileID("work")), encoding: .utf8),
            "first\nsecond\n"
        )

        XCTAssertEqual(try store.writer.duplicate(profile: ProfileID("work"), as: ProfileID("copy")), .wrote)
        XCTAssertEqual(
            try String(contentsOf: store.layout.profileURL(ProfileID("copy")), encoding: .utf8),
            "first\nsecond\n"
        )
        XCTAssertEqual(
            store.entries().filter { $0.contains(".hazmat-") },
            [],
            "an authoring operation must leave no temporary file behind"
        )
    }

    func testAnUnchangedSaveLeavesTheBytesAndTheModificationTimeAlone() throws {
        let store = TemporaryRoot()
        defer { store.remove() }
        try store.writer.save("127.0.0.1\tlocalhost\n", asFragment: FragmentID("base"))
        let target = store.layout.fragmentURL(FragmentID("base"))
        let before = try snapshot(of: target)

        XCTAssertEqual(try store.writer.save("127.0.0.1\tlocalhost\n", asFragment: FragmentID("base")), .unchanged)

        XCTAssertEqual(try snapshot(of: target), before)
        XCTAssertEqual(try store.writer.save("127.0.0.1\tlocalhost\n", asFragment: FragmentID("base")), .unchanged)
        XCTAssertEqual(try snapshot(of: target), before)
    }

    func testAFailedWriteLeavesThePreviousTextAndNoTemporaryFile() throws {
        let store = TemporaryRoot()
        defer { store.remove() }
        try store.writer.save("first\n", asFragment: FragmentID("base"))
        let target = store.layout.fragmentURL(FragmentID("base"))
        let before = try snapshot(of: target)

        let directory = store.layout.fragmentsDirectory
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }

        XCTAssertThrowsError(try store.writer.save("second\n", asFragment: FragmentID("base")))

        XCTAssertEqual(try snapshot(of: target), before)
        XCTAssertEqual(store.entries().sorted(), ["fragments/base.hosts"])
    }

    func testAReadDuringAWriteReturnsOneCompleteVersion() throws {
        let store = TemporaryRoot()
        defer { store.remove() }
        let target = store.layout.fragmentURL(FragmentID("base"))
        let first = String(repeating: "127.0.0.1\tfirst.example\n", count: 4000)
        let second = String(repeating: "0.0.0.0\tsecond.example\n", count: 4000)
        try store.writer.save(first, asFragment: FragmentID("base"))

        let log = ReaderLog()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue(label: "reader").async {
            while !log.isStopped {
                guard let held = try? String(contentsOf: target, encoding: .utf8) else {
                    log.record("<unreadable>", expected: [first, second])
                    continue
                }
                log.record(held, expected: [first, second])
            }
            done.signal()
        }

        let writer = store.writer
        for index in 0..<200 {
            try writer.save(index.isMultiple(of: 2) ? second : first, asFragment: FragmentID("base"))
        }
        log.stop()
        XCTAssertEqual(done.wait(timeout: .now() + 10), .success, "the reader did not finish")

        let summary = log.summary
        XCTAssertTrue(summary.incomplete.isEmpty, "a reader saw \(summary.incomplete.prefix(1))")
        XCTAssertGreaterThan(summary.complete, 0, "the reader never read the file")
    }

    // MARK: - 2.4 Rename and delete

    func testRenameKeepsTheTextAndLeavesTheOldNameGone() throws {
        let store = TemporaryRoot()
        defer { store.remove() }
        try store.writer.save("127.0.0.1\tlocalhost\n", asFragment: FragmentID("base"))

        XCTAssertEqual(try store.writer.rename(fragment: FragmentID("base"), to: FragmentID("renamed")), .wrote)

        XCTAssertEqual(
            try String(contentsOf: store.layout.fragmentURL(FragmentID("renamed")), encoding: .utf8),
            "127.0.0.1\tlocalhost\n"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.layout.fragmentURL(FragmentID("base")).path))
    }

    func testARenameOntoAnExistingNameIsRefusedAndBothTextsSurvive() throws {
        let store = TemporaryRoot()
        defer { store.remove() }
        try store.writer.save("127.0.0.1\tlocalhost\n", asFragment: FragmentID("base"))
        try store.writer.save("0.0.0.0\tads.example.com\n", asFragment: FragmentID("ads"))
        try store.write("base\n", to: "profiles/work.profile")

        XCTAssertThrowsError(try store.writer.rename(fragment: FragmentID("base"), to: FragmentID("ads"))) { error in
            XCTAssertEqual(error as? StoreWriteError, .nameTaken("ads"))
        }

        XCTAssertEqual(
            try String(contentsOf: store.layout.fragmentURL(FragmentID("base")), encoding: .utf8),
            "127.0.0.1\tlocalhost\n"
        )
        XCTAssertEqual(
            try String(contentsOf: store.layout.fragmentURL(FragmentID("ads")), encoding: .utf8),
            "0.0.0.0\tads.example.com\n"
        )
        XCTAssertEqual(try store.text("profiles/work.profile"), "base\n", "a refused rename carries nothing")
    }

    func testRenamingAReferencedFragmentCarriesTheReferenceInEveryProfile() throws {
        let store = TemporaryRoot()
        defer { store.remove() }
        try store.write("127.0.0.1\tlocalhost\n", to: "fragments/base.hosts")
        try store.write("10.0.0.9\talpha.example\n", to: "fragments/project.hosts")
        try store.write("base\nproject\n", to: "profiles/work.profile")
        try store.write("base\n", to: "profiles/other.profile")

        XCTAssertEqual(try store.writer.rename(fragment: FragmentID("base"), to: FragmentID("renamed")), .wrote)

        XCTAssertEqual(try store.text("profiles/work.profile"), "renamed\nproject\n")
        XCTAssertEqual(try store.text("profiles/other.profile"), "renamed\n")
        XCTAssertEqual(store.layout.profiles(), [ProfileID("other"), ProfileID("work")])

        // The profiles resolve as they did before: the same layers, in the same
        // order, under the name the fragment now has.
        let composition = try HostsComposer(store: DirectoryStore(root: store.root)).compose(profile: ProfileID("work"))
        XCTAssertEqual(composition.resolved.map(\.name), ["localhost", "alpha.example"])
        XCTAssertEqual(Set(composition.resolved.map(\.source.fragment)), [FragmentID("project"), FragmentID("renamed")])
    }

    func testARenamedReferenceKeepsTheLineItStandsOn() throws {
        let store = TemporaryRoot()
        defer { store.remove() }
        try store.write("127.0.0.1\tlocalhost\n", to: "fragments/base.hosts")
        try store.write(
            """
            # the office stack
              base   # published by IT

            project
            not a name
            base # named twice
            """,
            to: "profiles/work.profile"
        )

        try store.writer.rename(fragment: FragmentID("base"), to: FragmentID("renamed"))

        XCTAssertEqual(
            try store.text("profiles/work.profile"),
            """
            # the office stack
              renamed   # published by IT

            project
            not a name
            renamed # named twice
            """
        )
    }

    func testAProfileThatDoesNotNameTheRenamedFragmentIsLeftExactlyAsItWas() throws {
        let store = TemporaryRoot()
        defer { store.remove() }
        try store.write("127.0.0.1\tlocalhost\n", to: "fragments/base.hosts")
        try store.write("10.0.0.9\talpha.example\n", to: "fragments/project.hosts")
        try store.write("project\n", to: "profiles/work.profile")
        let profile = store.layout.profileURL(ProfileID("work"))
        let before = try snapshot(of: profile)

        try store.writer.rename(fragment: FragmentID("base"), to: FragmentID("renamed"))

        XCTAssertEqual(try snapshot(of: profile), before)
    }

    func testDeletingWhatTheStoreDoesNotHoldReportsNothingToDo() throws {
        let store = TemporaryRoot()
        defer { store.remove() }
        try store.writer.save("work\n", asProfile: ProfileID("work"))

        XCTAssertEqual(try store.writer.delete(profile: ProfileID("absent")), .nothingToDo)
        XCTAssertEqual(try store.writer.delete(profile: ProfileID("work")), .deleted)
        XCTAssertEqual(store.layout.profiles(), [], "the deleted profile is gone from a later listing")
        XCTAssertEqual(try store.writer.delete(profile: ProfileID("work")), .nothingToDo)
    }

    func testRenamingWhatTheStoreDoesNotHoldIsReportedRatherThanSilentlyIgnored() throws {
        let store = TemporaryRoot()
        defer { store.remove() }

        XCTAssertThrowsError(try store.writer.rename(fragment: FragmentID("absent"), to: FragmentID("other"))) { error in
            XCTAssertEqual(error as? StoreWriteError, .missing("absent"))
        }
        XCTAssertEqual(store.entries(), [])
    }

    // MARK: - 2.5 Authoring needs no privilege and stays inside the store

    func testAuthoringNeedsNoPrivilegeAndLeavesEveryOtherFileAlone() throws {
        XCTAssertNotEqual(getuid(), 0, "the suite must run as an ordinary user")
        let store = TemporaryRoot()
        defer { store.remove() }
        try store.write("do not touch\n", to: "elsewhere/bystander.txt")
        let bystander = store.root.appendingPathComponent("elsewhere/bystander.txt")
        let before = try snapshot(of: bystander)

        try store.writer.save("127.0.0.1\tlocalhost\n", asFragment: FragmentID("base"))
        try store.writer.rename(fragment: FragmentID("base"), to: FragmentID("renamed"))
        try store.writer.delete(fragment: FragmentID("renamed"))

        XCTAssertEqual(try snapshot(of: bystander), before)
        XCTAssertEqual(store.layout.fragments(), [])
    }

    // MARK: - 2.6 Deleting a referenced fragment or the applied profile

    func testDeletingAReferencedFragmentSucceedsAndCompositionThenReportsIt() throws {
        let store = TemporaryRoot()
        defer { store.remove() }
        try store.write("127.0.0.1\tlocalhost\n", to: "fragments/base.hosts")
        try store.write("base\nproject\n", to: "profiles/work.profile")

        XCTAssertEqual(try store.writer.delete(fragment: FragmentID("base")), .deleted)

        let problems = compositionProblems(DirectoryStore(root: store.root), ProfileID("work"))
        XCTAssertEqual(problems.count, 2)
        guard case .missingFragment(let profile, let line, let fragment) = problems[0] else {
            return XCTFail("expected a missing fragment first, got \(problems)")
        }
        XCTAssertEqual(profile, ProfileID("work"))
        XCTAssertEqual(line, 1)
        XCTAssertEqual(fragment, FragmentID("base"))
    }

    func testDeletingTheProfileMatchingTheLiveBlockLeavesTheLiveFileAlone() throws {
        let store = TemporaryRoot()
        defer { store.remove() }
        try store.write("127.0.0.1\tlocalhost\n", to: "fragments/base.hosts")
        try store.write("base\n", to: "profiles/work.profile")

        let composition = try HostsComposer(store: DirectoryStore(root: store.root)).compose(profile: ProfileID("work"))
        let rendered = BlockRenderer.render(composition)
        let live = try TemporaryHostsFile(try BlockSplice.splice(block: rendered, into: try shippedHosts()))
        defer { live.remove() }
        let before = try live.snapshot()
        XCTAssertEqual(
            Activation.match(live: live.bytes, renders: [ProfileRender(profile: ProfileID("work"), rendering: .block(rendered))]).state,
            .active([ProfileID("work")])
        )

        XCTAssertEqual(try store.writer.delete(profile: ProfileID("work")), .deleted)

        XCTAssertEqual(try live.snapshot(), before)
        XCTAssertEqual(
            Activation.match(live: try LiveHostsFile(url: live.url).read(), renders: []).state,
            .drifted(liveBlock: rendered),
            "the block the deleted profile left behind is drift"
        )
    }
}
