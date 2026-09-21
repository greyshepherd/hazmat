import Foundation
import HazmatCore

/// What a reading reuses across reads: of each file whose bytes came back
/// identical, its summary and — while a window is composing over it — its
/// parse; and the compositions and renderings derived from them.
///
/// Nothing is presented from the cache: a read always reads the file. The cache
/// is consulted only about bytes that came back byte-identical, so a same-second,
/// same-length rewrite is seen for what it is rather than missed the way file
/// metadata would miss it.
///
/// One entry per file and one per derivation slot, so the cache is bounded by the
/// store rather than by how often the store was edited.
public final class StoreCache: StoreReadingCache, @unchecked Sendable {
    private struct FileEntry {
        let bytes: Data
        let generation: Int
        let summary: Any
        /// The whole parse, held while something asked for it and let go by a
        /// release.
        var parse: Any?
    }

    private let lock = NSLock()
    private var files: [URL: FileEntry] = [:]
    private var derivations: [DerivationKey.Slot: (key: DerivationKey, value: Any)] = [:]
    private var lastGeneration = 0

    public init() {}

    public func file<T, S>(
        _ url: URL,
        bytes: Data,
        derive: () -> T,
        summarise: (T) -> S,
        hold: Bool
    ) -> (generation: Int, summary: S) {
        lock.lock()
        if let entry = files[url], entry.bytes == bytes, let summary = entry.summary as? S {
            lock.unlock()
            return (entry.generation, summary)
        }
        lock.unlock()

        let value = derive()
        let summary = summarise(value)

        lock.lock()
        let generation = nextGeneration()
        files[url] = FileEntry(bytes: bytes, generation: generation, summary: summary, parse: hold ? value : nil)
        lock.unlock()
        return (generation, summary)
    }

    public func parse<T>(_ url: URL, derive: () -> T) -> T {
        lock.lock()
        if let held = files[url]?.parse as? T {
            lock.unlock()
            return held
        }
        lock.unlock()

        let value = derive()

        lock.lock()
        defer { lock.unlock() }
        if let held = files[url]?.parse as? T {
            return held
        }
        files[url]?.parse = value
        return value
    }

    public func derived<T>(_ key: DerivationKey, derive: () throws -> T) rethrows -> T {
        let slot = key.slot
        lock.lock()
        if let entry = derivations[slot], entry.key == key, let value = entry.value as? T {
            lock.unlock()
            return value
        }
        lock.unlock()

        let value = try derive()

        // Two readings can derive the same answer at once — the window's read
        // and the menu's, at launch. The first to store wins and the other
        // answers with it, so one composition is held rather than one each.
        lock.lock()
        defer { lock.unlock() }
        if let entry = derivations[slot], entry.key == key, let stored = entry.value as? T {
            return stored
        }
        derivations[slot] = (key, value)
        return value
    }

    public func retainFiles(_ urls: Set<URL>) {
        lock.lock()
        files = files.filter { urls.contains($0.key) }
        lock.unlock()
    }

    public func releaseParses() {
        lock.lock()
        for url in files.keys {
            files[url]?.parse = nil
        }
        derivations = derivations.filter { $0.key.kind != .composition }
        lock.unlock()
    }

    /// The files whose parse is held. Not part of its contract: the suite reads
    /// it to show what a release let go of.
    var heldParses: Set<URL> {
        lock.withLock { Set(files.filter { $0.value.parse != nil }.keys) }
    }

    /// The files the cache holds. Not part of its contract: the suite reads it
    /// to show that a file the store no longer lists was evicted.
    var heldFiles: Set<URL> {
        lock.withLock { Set(files.keys) }
    }

    /// The derivations the cache holds. Not part of its contract: the suite reads
    /// it to show exactly which profile's derivation a change replaced.
    var derivationKeys: [DerivationKey] {
        lock.withLock { derivations.values.map(\.key) }
    }

    private func nextGeneration() -> Int {
        lastGeneration += 1
        return lastGeneration
    }
}
