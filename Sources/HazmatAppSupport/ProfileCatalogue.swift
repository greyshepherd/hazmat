import Foundation
import HazmatCore

/// The profiles a store holds, and the block each one renders. The store itself
/// has no enumeration, so the shell lists the directory.
public struct ProfileCatalogue: Sendable {
    public let layout: StoreLayout

    public init(root: URL) {
        layout = StoreLayout(root: root)
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
}
