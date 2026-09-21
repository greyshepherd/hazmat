import Foundation
import HazmatAppSupport
import HazmatCore
import os
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
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    @MainActor
    func model(showing: Bool = true, read: StoreRead? = nil) -> ShellModel {
        build(
            writer: SilentWriter(),
            presence: SilentPresence(),
            fetcher: ScriptedFetcher(.refused("no exchange was scripted")),
            clock: { Date() },
            registrationState: { .notRegistered },
            read: read,
            showing: showing
        )
    }

    @MainActor
    func model(
        fetcher: any RemoteFetching,
        clock: @escaping @Sendable () -> Date = { Date() },
        read: StoreRead? = nil
    ) -> ShellModel {
        build(
            writer: SilentWriter(),
            presence: SilentPresence(),
            fetcher: fetcher,
            clock: clock,
            registrationState: { .notRegistered },
            read: read
        )
    }

    /// A model whose writes reach the live file, so an edit or an apply lands
    /// and can be counted. `approves:` reports the helper as installed and
    /// answering, which is what a path through an apply needs.
    @MainActor
    func model(
        writer: PrivilegedWriter,
        fetcher: any RemoteFetching,
        clock: @escaping @Sendable () -> Date = { Date() },
        approves: Bool = false
    ) -> ShellModel {
        let presence: HelperPresence
        let state: HelperRegistrationState
        if approves {
            presence = AnsweringPresence()
            state = { HelperState.enabled }
        } else {
            presence = SilentPresence()
            state = { HelperState.notRegistered }
        }
        return build(
            writer: writer,
            presence: presence,
            fetcher: fetcher,
            clock: clock,
            registrationState: state,
            read: nil
        )
    }

    /// A model as the tests of the window's behaviour start from: its window
    /// showing, so the first read is in full. `showing: false` is a model that
    /// launched into the menu bar with no window.
    @MainActor
    private func build(
        writer: PrivilegedWriter,
        presence: HelperPresence,
        fetcher: any RemoteFetching,
        clock: @escaping @Sendable () -> Date,
        registrationState: @escaping HelperRegistrationState,
        read: StoreRead?,
        showing: Bool = true
    ) -> ShellModel {
        ShellModel(
            fileURL: liveURL,
            writer: writer,
            presence: presence,
            environment: ["HAZMAT_STORE_ROOT": root.path],
            preference: ChosenLocation(nil),
            fetcher: fetcher,
            clock: clock,
            registrationState: registrationState,
            read: read,
            windowShowing: showing
        )
    }

    /// Records a source beside a fragment, the way the window's add-source step
    /// does, so the schedule finds one.
    func writeSource(
        _ name: FragmentID,
        url: String,
        interval: TimeInterval,
        lastAttempt: Date? = nil,
        lastSuccess: Date? = nil,
        lastFailure: String? = nil,
        etag: String? = nil
    ) throws {
        let source = RemoteSource(
            url: URL(string: url)!,
            interval: interval,
            lastAttempt: lastAttempt,
            lastSuccess: lastSuccess,
            etag: etag,
            lastFailure: lastFailure
        )
        try write(String(decoding: try source.encoded(), as: UTF8.self), to: "remote/\(name.rawValue).remote")
    }

    func fragmentState(_ name: FragmentID) throws -> FileState {
        try FileState(of: root.appendingPathComponent("fragments/\(name.rawValue).hosts"))
    }

    func fragmentText(_ name: FragmentID) throws -> String {
        try String(contentsOf: root.appendingPathComponent("fragments/\(name.rawValue).hosts"), encoding: .utf8)
    }

    /// The recorded source, or `nil` when nothing is recorded under that name.
    func sourceIfAny(_ name: FragmentID) -> RemoteSource? {
        let url = root.appendingPathComponent("remote/\(name.rawValue).remote")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? RemoteSource.decode(data)
    }

    func source(_ name: FragmentID) throws -> RemoteSource {
        try RemoteSource.decode(Data(contentsOf: root.appendingPathComponent("remote/\(name.rawValue).remote")))
    }

    /// Whether the store holds a fragment file at all.
    func hasFragment(_ name: FragmentID) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent("fragments/\(name.rawValue).hosts").path)
    }

    /// The block the store's profile renders, as an apply would write it.
    func rendered(_ profile: ProfileID) throws -> Data {
        let composition = try HostsComposer(store: DirectoryStore(root: root)).compose(profile: profile)
        return BlockRenderer.render(composition)
    }

    /// Every file under the store, relative to its root, so a stray temporary
    /// file is visible.
    func storeEntries() throws -> [String] {
        let subpaths = (try? FileManager.default.subpathsOfDirectory(atPath: root.path)) ?? []
        return subpaths.filter { path in
            var isDirectory: ObjCBool = false
            let full = root.appendingPathComponent(path).path
            let exists = FileManager.default.fileExists(atPath: full, isDirectory: &isDirectory)
            return exists && !isDirectory.boolValue
        }
        .sorted()
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

/// A writer that performs the write in the test process and counts what it did,
/// so a test can tell one write from two.
final class CountingWriter: PrivilegedWriter, @unchecked Sendable {
    private struct State {
        var writes = 0
        var removals = 0
    }

    let target: URL
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(target: URL) {
        self.target = target
    }

    var writes: Int { state.withLock { $0.writes } }

    var removals: Int { state.withLock { $0.removals } }

    func write(bytes: Data, baseline: Data) -> PrivilegedWriteResult {
        guard let live = try? Data(contentsOf: target), live == baseline else {
            return .refused(reason: "the file changed since it was read")
        }
        do {
            try bytes.write(to: target, options: .atomic)
            state.withLock { $0.writes += 1 }
            return .written
        } catch {
            return .failed(reason: "\(error)")
        }
    }

    func removeBlock(baseline: Data) -> PrivilegedWriteResult {
        guard let live = try? Data(contentsOf: target), live == baseline else {
            return .refused(reason: "the file changed since it was read")
        }
        do {
            try BlockSplice.strip(from: live).write(to: target, options: .atomic)
            state.withLock { $0.removals += 1 }
            return .written
        } catch {
            return .failed(reason: "\(error)")
        }
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

/// A helper that answers, so a path that needs one — an apply through the shell
/// — can run in the suite.
final class AnsweringPresence: HelperPresence, @unchecked Sendable {
    func check() -> HelperReachability { .answering }
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

/// A file's bytes and modification time, so "unchanged" is the whole answer.
struct FileState: Equatable {
    let bytes: Data
    let size: Int
    let modificationDate: Date

    init(of url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        bytes = try Data(contentsOf: url)
        size = (attributes[.size] as? NSNumber)?.intValue ?? -1
        modificationDate = (attributes[.modificationDate] as? Date) ?? .distantPast
    }
}

/// A clock a test moves by hand, so the schedule can be driven through its
/// intervals without waiting for them.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ start: Date) { value = start }

    var now: Date { lock.withLock { value } }

    func advance(_ interval: TimeInterval) {
        lock.withLock { value = value.addingTimeInterval(interval) }
    }
}

/// A fetcher that answers from a script and never reaches the network. The
/// scripts are counted from one, so a test can answer differently on the second
/// exchange, and each one may wait, so a test can hold an exchange in flight.
final class ScriptedFetcher: RemoteFetching, @unchecked Sendable {
    private struct State {
        var requests: [RemoteFetchRequest] = []
    }

    private let script: @Sendable (Int) async -> RemoteFetchAnswer
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(_ script: @escaping @Sendable (Int) async -> RemoteFetchAnswer) {
        self.script = script
    }

    init(_ answer: RemoteFetchAnswer) {
        script = { _ in answer }
    }

    func fetch(_ request: RemoteFetchRequest) async -> RemoteFetchAnswer {
        let n = state.withLock { current -> Int in
            current.requests.append(request)
            return current.requests.count
        }
        return await script(n)
    }

    var requests: [RemoteFetchRequest] { state.withLock { $0.requests } }

    var count: Int { state.withLock { $0.requests.count } }
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
