import Foundation
import HazmatAppSupport
import HazmatCore
import XCTest
@testable import HazmatApp

/// A store and a live file a shell model reads, with doubles for everything the
/// helper would answer.
struct ShellWorld {
    let root: URL
    let liveURL: URL
    let base = FragmentID("base")
    let project = FragmentID("project")
    let work = ProfileID("work")

    init() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hazmat-shell-\(UUID().uuidString)")
        let fragments = root.appendingPathComponent("fragments", isDirectory: true)
        let profiles = root.appendingPathComponent("profiles", isDirectory: true)
        try FileManager.default.createDirectory(at: fragments, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: profiles, withIntermediateDirectories: true)

        func write(_ contents: String, to relativePath: String) throws {
            try contents.write(to: root.appendingPathComponent(relativePath), atomically: true, encoding: .utf8)
        }
        try write("127.0.0.1\tlocalhost alpha.example\n", to: "fragments/base.hosts")
        try write("10.0.0.9\talpha.example\n", to: "fragments/project.hosts")
        try write("base\nproject\n", to: "profiles/work.profile")

        let liveURL = root.appendingPathComponent("hosts")
        try write("127.0.0.1\tlocalhost\n", to: "hosts")

        self.root = root
        self.liveURL = liveURL
    }

    var baseText: String { "127.0.0.1\tlocalhost alpha.example\n" }

    func write(_ contents: String, to relativePath: String) throws {
        try contents.write(to: root.appendingPathComponent(relativePath), atomically: true, encoding: .utf8)
    }

    @MainActor
    func model(read: StoreRead? = nil) -> ShellModel {
        ShellModel(
            fileURL: liveURL,
            writer: SilentWriter(),
            presence: SilentPresence(),
            environment: ["HAZMAT_STORE_ROOT": root.path],
            preference: ChosenLocation(nil),
            read: read
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

/// A helper that is not there: every request is refused with that reason.
final class SilentWriter: PrivilegedWriter, @unchecked Sendable {
    private(set) var requests = 0

    func write(bytes: Data, baseline: Data) -> PrivilegedWriteResult {
        requests += 1
        return .refused(reason: "the helper is not registered")
    }

    func removeBlock(baseline: Data) -> PrivilegedWriteResult {
        requests += 1
        return .refused(reason: "the helper is not registered")
    }
}

final class SilentPresence: HelperPresence, @unchecked Sendable {
    func check() -> HelperReachability { .silent }
}

/// The chosen location as a value a test can set.
final class ChosenLocation: StoreLocationPreference, @unchecked Sendable {
    private(set) var location: URL?

    init(_ location: URL?) {
        self.location = location
    }

    func chosenLocation() -> URL? { location }

    func remember(_ location: URL?) {
        self.location = location
    }
}

/// Counts the reads a model asked for, so a test can wait for one to land.
final class ReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int { lock.withLock { value } }

    func bump() { lock.withLock { value += 1 } }
}

/// Holds a read until the test lets it go.
actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }
}

/// Waits until `condition` holds, or gives up. A read lands on the main actor,
/// so a test that awaits lets it in.
@MainActor
func settle(within seconds: TimeInterval = 2, _ condition: @MainActor () -> Bool) async {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition(), Date() < deadline {
        try? await Task.sleep(for: .milliseconds(5))
    }
}
