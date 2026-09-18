import Foundation

/// Where the store lives. One location at a time, resolved as the root the
/// environment names, then the location chosen in the window, then the user's
/// application support directory. The override is authoritative so a
/// development bundle and a test store can be kept apart from the real one.
public enum StoreLocation {
    public static let environmentKey = "HAZMAT_STORE_ROOT"

    /// The root the environment names, when it names one.
    public static func environmentRoot(_ environment: [String: String]) -> URL? {
        guard let override = environment[environmentKey], !override.isEmpty else { return nil }
        return URL(fileURLWithPath: override)
    }

    /// The store the user gets when nothing else says otherwise.
    public static var applicationSupportRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Hazmat/store", isDirectory: true)
    }

    /// The environment's root, or the default one. Takes the environment as a
    /// value, so a test never has to mutate the process.
    public static func defaultRoot(environment: [String: String]) -> URL {
        environmentRoot(environment) ?? applicationSupportRoot
    }

    public static var defaultRoot: URL {
        defaultRoot(environment: ProcessInfo.processInfo.environment)
    }

    /// The one location in use: the environment's root, otherwise the location
    /// chosen in the window, otherwise the default. A chosen location that does
    /// not exist is still the location: resolution never falls back past it.
    public static func resolve(environment: [String: String], chosen: URL?) -> URL {
        environmentRoot(environment) ?? chosen ?? applicationSupportRoot
    }

    public static func resolve(chosen: URL?) -> URL {
        resolve(environment: ProcessInfo.processInfo.environment, chosen: chosen)
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
