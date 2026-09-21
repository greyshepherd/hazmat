import Foundation
import HazmatCore
import HazmatAppSupport

func bytes(_ text: String) -> Data { Data(text.utf8) }

func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

/// The repository root, from this file's own location.
func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

func sourceFiles(in relativePath: String) -> [(String, String)] {
    let root = repositoryRoot().appendingPathComponent(relativePath)
    let contents = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
    return contents
        .filter { $0.pathExtension == "swift" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .compactMap { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return (url.lastPathComponent, text)
        }
}

/// A throwaway store with the files a composition reads.
final class TemporaryStore {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("hazmat-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func write(_ contents: String, to relativePath: String) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func text(_ relativePath: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

/// A throwaway live file standing in for the real hosts file.
final class LiveFile {
    let url: URL

    init(_ text: String) throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("hazmat-live-\(UUID().uuidString)")
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    var data: Data { (try? Data(contentsOf: url)) ?? Data() }

    func write(_ data: Data) throws {
        try data.write(to: url, options: .atomic)
    }

    func state() throws -> FileState {
        try FileState(of: url)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
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

/// Performs the write the way the daemon would, in the test process.
final class LocalWriter: PrivilegedWriter, @unchecked Sendable {
    let target: URL
    private(set) var writes = 0
    private(set) var removals = 0

    init(target: URL) {
        self.target = target
    }

    func write(bytes: Data, baseline: Data) -> PrivilegedWriteResult {
        guard let live = try? Data(contentsOf: target), live == baseline else {
            return .refused(reason: "the file changed since it was read")
        }
        do {
            try bytes.write(to: target, options: .atomic)
            writes += 1
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
            removals += 1
            return .written
        } catch {
            return .failed(reason: "\(error)")
        }
    }
}

/// A helper that is not registered: every request is refused with that reason.
final class UnregisteredHelper: PrivilegedWriter, @unchecked Sendable {
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

/// The chosen location as a value a test can set.
final class PreferenceDouble: StoreLocationPreference, @unchecked Sendable {
    private(set) var location: URL?
    private(set) var writes = 0

    init(location: URL? = nil) {
        self.location = location
    }

    func chosenLocation() -> URL? { location }

    func remember(_ location: URL?) {
        self.location = location
        writes += 1
    }
}

/// A store and a live file a model reads.
final class StoreFixture {
    let store: TemporaryStore
    let live: LiveFile

    init(store files: [(String, String)], live liveText: String) throws {
        store = try TemporaryStore()
        for (contents, path) in files {
            try store.write(contents, to: path)
        }
        live = try LiveFile(liveText)
    }

    var shipped: Data { bytes("127.0.0.1\tlocalhost\n") }

    func model(
        writer: PrivilegedWriter,
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> EditorModel {
        EditorModel(storeRoot: store.root, fileURL: live.url, writer: writer, now: now)
    }

    /// Records a source beside a fragment, the way the window's add-source step
    /// does.
    func writeSource(
        _ name: FragmentID,
        url: String,
        interval: TimeInterval,
        lastAttempt: Date? = nil,
        lastSuccess: Date? = nil,
        lastFailure: String? = nil
    ) throws {
        let source = RemoteSource(
            url: URL(string: url)!,
            interval: interval,
            lastAttempt: lastAttempt,
            lastSuccess: lastSuccess,
            lastFailure: lastFailure
        )
        try store.write(String(decoding: try source.encoded(), as: UTF8.self), to: "remote/\(name.rawValue).remote")
    }

    /// The block the store's profile renders.
    func rendered(_ profile: ProfileID) throws -> Data {
        let composition = try HostsComposer(store: DirectoryStore(root: store.root)).compose(profile: profile)
        return BlockRenderer.render(composition)
    }

    /// Puts the profile's rendering into the live file, behind the shipped bytes.
    func applyToLive(_ profile: ProfileID) throws {
        try live.write(try BlockSplice.splice(block: try rendered(profile), into: shipped))
    }

    func text(_ relativePath: String) throws -> String {
        try store.text(relativePath)
    }

    func remove() {
        store.remove()
        live.remove()
    }
}

/// A live file standing in for the real one, counting what was asked of it.
final class CountingFile: LiveFileReading, @unchecked Sendable {
    private let contents: Data
    private let failure: Error?
    private let lock = NSLock()
    private var count = 0

    var reads: Int { lock.withLock { count } }

    init(_ contents: Data) {
        self.contents = contents
        failure = nil
    }

    init(failing error: Error) {
        contents = Data()
        failure = error
    }

    func read() throws -> Data {
        lock.withLock { count += 1 }
        if let failure { throw failure }
        return contents
    }
}
