import Foundation

/// Where the store lives when nothing says otherwise. The override exists so a
/// development bundle and a test store can be kept apart from the real one.
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

/// The store's fixed location and layout: a root, `fragments/` and `profiles/`,
/// and one file per name. The store is plain text any editor or version control
/// system can change, so every listing reads the directory when it is asked.
public struct StoreLayout: Equatable, Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// The location the environment names, or the default one.
    public static var current: StoreLayout {
        StoreLayout(root: StoreLocation.defaultRoot)
    }

    public var fragmentsDirectory: URL {
        root.appendingPathComponent("fragments", isDirectory: true)
    }

    public var profilesDirectory: URL {
        root.appendingPathComponent("profiles", isDirectory: true)
    }

    /// Whether the store has been created at all.
    public var exists: Bool {
        FileManager.default.fileExists(atPath: profilesDirectory.path)
    }

    public func fragmentURL(_ name: FragmentID) -> URL {
        fragmentsDirectory
            .appendingPathComponent(name.rawValue)
            .appendingPathExtension("hosts")
    }

    public func profileURL(_ name: ProfileID) -> URL {
        profilesDirectory
            .appendingPathComponent(name.rawValue)
            .appendingPathExtension("profile")
    }

    /// The fragments the directory holds now, in name order.
    public func fragments() -> [FragmentID] {
        names(in: fragmentsDirectory, fileExtension: "hosts").map(FragmentID.init)
    }

    /// The profiles the directory holds now, in name order.
    public func profiles() -> [ProfileID] {
        names(in: profilesDirectory, fileExtension: "profile").map(ProfileID.init)
    }

    /// Every file of this kind whose name is a usable identifier, sorted, so two
    /// listings of the same directory answer the same way.
    private func names(in directory: URL, fileExtension: String) -> [String] {
        let suffix = ".\(fileExtension)"
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return contents
            .filter { $0.hasSuffix(suffix) }
            .map { String($0.dropLast(suffix.count)) }
            .filter { NameSyntax.isIdentifier($0) }
            .sorted()
    }
}
