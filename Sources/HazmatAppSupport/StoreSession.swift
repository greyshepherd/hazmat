import Foundation
import HazmatCore

/// What an apply wrote, and what it replaced, so the change can be undone for
/// the session. `replaced` is `nil` when the apply installed a block where the
/// file held none, which a revert undoes by removing the block.
public struct ApplyRecord: Equatable, Sendable {
    public let profile: ProfileID
    /// The block the apply wrote.
    public let block: Data
    /// The block the apply replaced, byte for byte.
    public let replaced: Data?

    public init(profile: ProfileID, block: Data, replaced: Data?) {
        self.profile = profile
        self.block = block
        self.replaced = replaced
    }

    /// Whether the revert would remove the block rather than restore one.
    public var wasAnInstall: Bool { replaced == nil }
}

/// A store and the live file, held together and re-pointable: changing the
/// location moves the catalogue, the editor, the applier and the live file
/// reading as one, so nothing reads the previous location afterwards.
public struct StoreSession: Sendable {
    public private(set) var root: URL
    public let fileURL: URL
    public let writer: PrivilegedWriter
    /// What every read and derivation from this session reuses across reads. It
    /// survives re-pointing at the same store and is left behind when the store
    /// moves, so another store's bytes are never held.
    public let cache: StoreCache
    /// The moment a read is answered from, so a row's out-of-date state is
    /// decided by the same clock the schedule uses.
    public let now: @Sendable () -> Date

    public init(
        root: URL,
        fileURL: URL,
        writer: PrivilegedWriter,
        cache: StoreCache = StoreCache(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.root = root
        self.fileURL = fileURL
        self.writer = writer
        self.cache = cache
        self.now = now
    }

    public var layout: StoreLayout { StoreLayout(root: root) }

    public var catalogue: ProfileCatalogue { ProfileCatalogue(root: root, cache: cache) }

    public var editor: EditorModel {
        EditorModel(storeRoot: root, fileURL: fileURL, writer: writer, cache: cache, now: now)
    }

    public var applier: HostsFileApplier { HostsFileApplier(fileURL: fileURL, writer: writer) }

    /// The store's remote sources, read from `remote/` when it is asked.
    public var remoteSources: RemoteSourceCatalogue { RemoteSourceCatalogue(layout: layout) }

    public var liveFile: LiveHostsFile { LiveHostsFile(url: fileURL) }

    /// The same live file and writer, pointed at another store. Nothing in the
    /// previous location is read, written, or removed. The cache moves with the
    /// session only when the store is the same one.
    public func repointed(to root: URL) -> StoreSession {
        StoreSession(
            root: root,
            fileURL: fileURL,
            writer: writer,
            cache: root == self.root ? cache : StoreCache(),
            now: now
        )
    }
}

/// Where the location chosen in the window is remembered.
public protocol StoreLocationPreference: Sendable {
    func chosenLocation() -> URL?
    func remember(_ location: URL?)
}

/// The preference as the app stores it: a path in the defaults. A location is a
/// preference, not store content, so the store stays plain text.
public struct DefaultsStoreLocationPreference: StoreLocationPreference {
    public static let key = "storeRoot"

    private let suiteName: String?
    private let defaultsKey: String

    public init(suiteName: String? = nil, key: String = DefaultsStoreLocationPreference.key) {
        self.suiteName = suiteName
        defaultsKey = key
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func chosenLocation() -> URL? {
        guard let path = defaults.string(forKey: defaultsKey), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    public func remember(_ location: URL?) {
        guard let location else {
            defaults.removeObject(forKey: defaultsKey)
            return
        }
        defaults.set(location.path, forKey: defaultsKey)
    }
}
