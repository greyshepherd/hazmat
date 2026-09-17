import Foundation
import HazmatCore

/// Where the store lives when nothing says otherwise. The override exists so a
/// development bundle can be pointed at a test store.
public enum StoreLocation {
    public static let environmentKey = "HAZMAT_STORE_ROOT"

    public static var defaultRoot: URL {
        if let override = ProcessInfo.processInfo.environment[environmentKey], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Hazmat/store", isDirectory: true)
    }
}

/// The profiles a store holds, and the block each one renders. The store itself
/// has no enumeration, so the shell lists the directory.
public struct ProfileCatalogue: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var profilesDirectory: URL {
        root.appendingPathComponent("profiles", isDirectory: true)
    }

    public var exists: Bool {
        FileManager.default.fileExists(atPath: profilesDirectory.path)
    }

    public func profiles() -> [ProfileID] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: profilesDirectory.path)) ?? []
        return names
            .filter { $0.hasSuffix(".profile") }
            .map { ProfileID(String($0.dropLast(".profile".count))) }
            .filter(\.isValid)
            .sorted()
    }

    public func renderedBlock(for profile: ProfileID) throws -> Data {
        let composition = try HostsComposer(store: DirectoryStore(root: root)).compose(profile: profile)
        return BlockRenderer.render(composition)
    }
}
