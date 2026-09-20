import Foundation
import HazmatCore

/// What a reading reuses across reads: the parse of each file whose bytes came
/// back identical, and the compositions and renderings derived from them.
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
        let value: Any
    }

    private let lock = NSLock()
    private var files: [URL: FileEntry] = [:]
    private var derivations: [DerivationKey.Slot: (key: DerivationKey, value: Any)] = [:]
    private var lastGeneration = 0

    public init() {}

    public func file<T>(_ url: URL, bytes: Data, derive: () -> T) -> (generation: Int, value: T) {
        lock.lock()
        if let entry = files[url], entry.bytes == bytes, let value = entry.value as? T {
            lock.unlock()
            return (entry.generation, value)
        }
        lock.unlock()

        let value = derive()

        lock.lock()
        let generation = nextGeneration()
        files[url] = FileEntry(bytes: bytes, generation: generation, value: value)
        lock.unlock()
        return (generation, value)
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

        lock.lock()
        derivations[slot] = (key, value)
        lock.unlock()
        return value
    }

    public func retainFiles(_ urls: Set<URL>) {
        lock.lock()
        files = files.filter { urls.contains($0.key) }
        lock.unlock()
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
