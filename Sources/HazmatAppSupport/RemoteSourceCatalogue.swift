import Foundation
import HazmatCore

/// One source as a reading holds it: the origin it records, or why that cannot
/// be read. A sidecar that cannot be read is a broken source — reported with its
/// reason and never fetched — rather than a source with guessed fields.
public struct RemoteSourceReading: Equatable, Sendable, Identifiable {
    public let fragment: FragmentID
    /// The origin, or `nil` when the sidecar cannot be read.
    public let source: RemoteSource?
    /// Why the sidecar cannot be read, when it cannot.
    public let problem: String?

    public init(fragment: FragmentID, source: RemoteSource?, problem: String? = nil) {
        self.fragment = fragment
        self.source = source
        self.problem = problem
    }

    public var id: FragmentID { fragment }

    public var url: URL? { source?.url }

    /// Whether the source records an origin that cannot be read.
    public var isBroken: Bool { source == nil }

    /// Why the source's text is not usable now: the sidecar's problem, or the
    /// failure the last refresh recorded.
    public var failure: String? { problem ?? source?.lastFailure }
}

/// The store's sources, read from `remote/` when it is asked. A store is plain
/// text that any editor may change, so nothing here is remembered between
/// questions.
public struct RemoteSourceCatalogue: Sendable {
    public let layout: StoreLayout

    public init(layout: StoreLayout) {
        self.layout = layout
    }

    public init(root: URL) {
        layout = StoreLayout(root: root)
    }

    /// Every source the store holds now, in name order, with a sidecar that
    /// cannot be read reported rather than passed over.
    public func readings() -> [RemoteSourceReading] {
        layout.remoteSources().compactMap { reading($0) }
    }

    /// The source recorded under `name`, or `nil` when the store holds no
    /// sidecar for it.
    public func reading(_ name: FragmentID) -> RemoteSourceReading? {
        let url = layout.remoteURL(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            let source = try RemoteSource.decode(data)
            return RemoteSourceReading(fragment: name, source: source)
        } catch {
            return RemoteSourceReading(fragment: name, source: nil, problem: "\(error)")
        }
    }

    /// The sources the schedule fetches now: the due ones whose fragment is
    /// there.
    ///
    /// A source whose text is not there yet is never fetched by the schedule.
    /// Its first text comes from the refresh the add-source step asks for, so a
    /// store that lost a fragment by hand is reported rather than silently
    /// refilled, and a first fetch that failed is retried when the user asks.
    public func scheduled(at now: Date) -> [RemoteSourceReading] {
        let present = Set(layout.fragments())
        return readings().filter { reading in
            guard present.contains(reading.fragment), let source = reading.source else { return false }
            return RemoteSchedule.isDue(source, at: now)
        }
    }

    /// The sources whose text should be shown as out of date now.
    public func outOfDate(at now: Date) -> [FragmentID] {
        readings().compactMap { reading in
            guard let source = reading.source else { return reading.fragment }
            return RemoteSchedule.isOutOfDate(source, at: now) ? reading.fragment : nil
        }
    }
}
