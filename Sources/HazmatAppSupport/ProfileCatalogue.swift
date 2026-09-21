import Foundation
import HazmatCore

/// The profiles a store holds, and the block each one renders. The store itself
/// has no enumeration, so the shell lists the directory.
public struct ProfileCatalogue: Sendable {
    public let layout: StoreLayout
    /// What a derivation may reuse across reads. `nil` reads everything from
    /// scratch.
    public let cache: StoreCache?

    public init(root: URL, cache: StoreCache? = nil) {
        layout = StoreLayout(root: root)
        self.cache = cache
    }

    public var root: URL { layout.root }

    public var profilesDirectory: URL { layout.profilesDirectory }

    public var exists: Bool { layout.exists }

    public func profiles() -> [ProfileID] {
        layout.profiles()
    }

    public func renderedBlock(for profile: ProfileID) throws -> Data {
        let composition = try HostsComposer(store: DirectoryStore(root: layout.root)).compose(profile: profile)
        return BlockRenderer.render(composition)
    }

    /// The digest of the block the profile renders now, from a reading of the
    /// store: answered by the cache without a parse or a render while the
    /// profile's bytes and its layers' are unchanged, and holding no bytes
    /// either way.
    public func renderedDigest(for profile: ProfileID) throws -> ByteDigest {
        try StoreReading(layout: layout, cache: cache).summary(of: profile).digest
    }
}
