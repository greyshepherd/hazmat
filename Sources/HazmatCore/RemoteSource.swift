import Foundation

/// Why a sidecar could not be read. A source whose origin cannot be read is a
/// broken source: it is reported and never fetched, rather than fetched against
/// a guessed URL.
public enum RemoteSourceError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The sidecar's bytes are not a readable sidecar.
    case unreadable(reason: String)
    /// The sidecar was written by a version this one does not know.
    case unsupportedVersion(found: Int)

    public var description: String {
        switch self {
        case .unreadable(let reason):
            return "the source record cannot be read: \(reason)"
        case .unsupportedVersion(let found):
            return "the source record is version \(found), and version \(RemoteSource.currentVersion) is the one this version reads"
        }
    }
}

/// Where a fragment comes from, and how its last refresh went: the origin half of
/// a remote source, held beside the fragment in `remote/<name>.remote`.
///
/// The sidecar is JSON — plain text that survives version control and can be
/// read and corrected by hand — and carries a format version first, so a file
/// written by a later version is reported rather than guessed at. The format is
/// total: every field round trips, and an absent field means exactly what it
/// says (`nil`), never a defaulted value.
public struct RemoteSource: Equatable, Sendable, Codable {
    /// The sidecar format this version writes and reads.
    public static let currentVersion = 1

    /// The version the sidecar records. Read first, so an unknown one is a
    /// refusal rather than a misread.
    public var version: Int
    /// The URL the fragment is fetched from.
    public var url: URL
    /// How often the source is refreshed, in seconds. Zero means only when it is
    /// asked for.
    public var interval: TimeInterval
    /// When a refresh was last started, whatever its outcome. This is what keeps
    /// a source that is down from being asked again before its interval.
    public var lastAttempt: Date?
    /// When a refresh last succeeded, which is what the interval elapses from.
    public var lastSuccess: Date?
    /// The `ETag` the last answer carried, sent back as `If-None-Match`.
    public var etag: String?
    /// The `Last-Modified` the last answer carried, sent back as
    /// `If-Modified-Since`.
    public var lastModified: String?
    /// Why the last refresh failed, when it did.
    public var lastFailure: String?

    public init(
        url: URL,
        interval: TimeInterval,
        version: Int = RemoteSource.currentVersion,
        lastAttempt: Date? = nil,
        lastSuccess: Date? = nil,
        etag: String? = nil,
        lastModified: String? = nil,
        lastFailure: String? = nil
    ) {
        self.version = version
        self.url = url
        self.interval = interval
        self.lastAttempt = lastAttempt
        self.lastSuccess = lastSuccess
        self.etag = etag
        self.lastModified = lastModified
        self.lastFailure = lastFailure
    }

    /// A source that has just been created: nothing attempted, nothing
    /// succeeded, and therefore due.
    public init(newSourceAt url: URL, interval: TimeInterval) {
        self.init(url: url, interval: interval)
    }

    // MARK: - The sidecar as bytes

    /// The sidecar's bytes: JSON, pretty-printed and key-sorted, so a store under
    /// version control shows one line per field rather than one long line whose
    /// every change looks the same.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        do {
            return try encoder.encode(self)
        } catch {
            throw RemoteSourceError.unreadable(reason: "\(error)")
        }
    }

    /// Reads a sidecar's bytes. A body that is not a sidecar, or one written by
    /// a version this one does not read, is a typed refusal rather than a
    /// source with defaulted fields.
    public static func decode(_ data: Data) throws -> RemoteSource {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // The version is read on its own first, so an unknown one is reported as
        // an unknown version rather than as whatever else failed to decode.
        let version: Int
        do {
            version = try JSONDecoder().decode(VersionProbe.self, from: data).version
        } catch {
            throw RemoteSourceError.unreadable(reason: "\(error)")
        }
        guard version == currentVersion else {
            throw RemoteSourceError.unsupportedVersion(found: version)
        }

        do {
            return try decoder.decode(RemoteSource.self, from: data)
        } catch {
            throw RemoteSourceError.unreadable(reason: "\(error)")
        }
    }

    private struct VersionProbe: Decodable {
        let version: Int
    }
}
