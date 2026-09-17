import Foundation

/// The fragment and profile text a composition reads from. Lookups are by name,
/// so no store hands composition an enumeration to depend on.
public protocol HostsStore: Sendable {
    /// The text of the fragment named `id`, or `nil` when the store holds none.
    func fragment(named id: FragmentID) throws -> String?

    /// The text of the profile named `id`, or `nil` when the store holds none.
    func profile(named id: ProfileID) throws -> String?
}

/// A store held in memory.
public struct InMemoryStore: HostsStore {
    private let fragments: [FragmentID: String]
    private let profiles: [ProfileID: String]

    public init(fragments: [FragmentID: String] = [:], profiles: [ProfileID: String] = [:]) {
        self.fragments = fragments
        self.profiles = profiles
    }

    public func fragment(named id: FragmentID) throws -> String? {
        fragments[id]
    }

    public func profile(named id: ProfileID) throws -> String? {
        profiles[id]
    }
}

/// A store backed by a directory: a fragment is
/// `<root>/fragments/<name>.hosts` and a profile is
/// `<root>/profiles/<name>.profile`, both plain text that any editor or version
/// control system can change.
public struct DirectoryStore: HostsStore {
    public let layout: StoreLayout

    public init(root: URL) {
        layout = StoreLayout(root: root)
    }

    public var root: URL { layout.root }

    public func fragment(named id: FragmentID) throws -> String? {
        try text(at: layout.fragmentURL(id))
    }

    public func profile(named id: ProfileID) throws -> String? {
        try text(at: layout.profileURL(id))
    }

    private func text(at url: URL) throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
