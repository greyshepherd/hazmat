import Foundation
import XCTest
@testable import HazmatCore

func bytes(_ text: String) -> Data { Data(text.utf8) }

func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

func XCTAssertEqualBytes(_ actual: Data, _ expected: Data, _ label: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(Array(actual), Array(expected), label, file: file, line: line)
}

enum Fixture {
    static func url(_ name: String, ext: String, subdirectory: String = "Fixtures") throws -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: subdirectory) else {
            throw FixtureError.missing("\(subdirectory)/\(name).\(ext)")
        }
        return url
    }

    static func url(directory name: String, subdirectory: String = "Fixtures") throws -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: subdirectory) else {
            throw FixtureError.missing("\(subdirectory)/\(name)")
        }
        return url
    }

    static func data(_ name: String, ext: String, subdirectory: String = "Fixtures") throws -> Data {
        try Data(contentsOf: url(name, ext: ext, subdirectory: subdirectory))
    }
}

enum FixtureError: Error {
    case missing(String)
}

/// The fixture store: `base`, `project` and `blocklist` fragments and the `work`
/// profile that stacks them.
func fixtureStore() throws -> DirectoryStore {
    DirectoryStore(root: try Fixture.url(directory: "store"))
}

func workComposition() throws -> Composition {
    try HostsComposer(store: try fixtureStore()).compose(profile: ProfileID("work"))
}

/// A throwaway copy of the fixture store, so a test can change a fragment the
/// way an external editor would.
final class Workspace {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("hazmat-tests-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: try Fixture.url(directory: "store"), to: root)
    }

    var store: DirectoryStore { DirectoryStore(root: root) }

    func write(_ contents: String, to relativePath: String) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

func composition(fragments: [(String, String)], profile: String) throws -> Composition {
    let store = InMemoryStore(
        fragments: Dictionary(uniqueKeysWithValues: fragments.map { (FragmentID($0.0), $0.1) }),
        profiles: [ProfileID("work"): profile]
    )
    return try HostsComposer(store: store).compose(profile: ProfileID("work"))
}

/// Composes, expecting refusal, and returns every problem the refusal carried.
func compositionProblems(_ store: HostsStore, _ profile: ProfileID, file: StaticString = #filePath, line: UInt = #line) -> [CompositionProblem] {
    do {
        _ = try HostsComposer(store: store).compose(profile: profile)
        XCTFail("composition succeeded where it should have been refused", file: file, line: line)
        return []
    } catch let error as CompositionError {
        return error.problems
    } catch {
        XCTFail("unexpected error: \(error)", file: file, line: line)
        return []
    }
}

/// Counts what composition asked the store for, so a test can show that a report
/// needs no second pass.
final class CountingStore: HostsStore, @unchecked Sendable {
    private let base: InMemoryStore
    private(set) var fragmentReads: [FragmentID] = []
    private(set) var profileReads: [ProfileID] = []

    init(fragments: [FragmentID: String], profiles: [ProfileID: String]) {
        base = InMemoryStore(fragments: fragments, profiles: profiles)
    }

    func fragment(named id: FragmentID) throws -> String? {
        fragmentReads.append(id)
        return try base.fragment(named: id)
    }

    func profile(named id: ProfileID) throws -> String? {
        profileReads.append(id)
        return try base.profile(named: id)
    }
}

struct FileSnapshot: Equatable {
    let contents: Data
    let size: Int
    let modificationDate: Date
}

func snapshot(of url: URL) throws -> FileSnapshot {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return FileSnapshot(
        contents: try Data(contentsOf: url),
        size: (attributes[.size] as? NSNumber)?.intValue ?? -1,
        modificationDate: (attributes[.modificationDate] as? Date) ?? .distantPast
    )
}

extension Composition {
    func address(of name: String, _ family: AddressFamily) -> String? {
        resolved.first { $0.name == name && $0.family == family }?.address
    }

    var orderedNames: [String] { resolved.map(\.name) }

    var orderedSources: [SourceLocation] { resolved.map(\.source) }

    func familyCount(of name: String) -> Int {
        resolved.filter { $0.name == name }.count
    }
}
