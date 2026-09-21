import Foundation

/// What a derivation was made from: which answer it is, the generation of the
/// profile's bytes, and the generation of every fragment the profile stacked.
/// Two derivations with the same key have the same inputs, so one may answer for
/// the other.
public struct DerivationKey: Hashable, Sendable {
    /// Which answer a derivation is. A composition, the summary of the block it
    /// renders and that block's bytes are different answers, derived from the
    /// same inputs. The summary is kept across a release; the other two are
    /// the window's.
    public enum Kind: Hashable, Sendable {
        case composition
        /// The rendered block's digest and entry count.
        case rendering
        /// The rendered block's bytes.
        case block
    }

    /// Where a derivation lives: one entry per profile and kind, so a cache is
    /// bounded by the store rather than by how often the store was edited.
    public var slot: Slot { Slot(profile: profile, kind: kind) }

    public struct Slot: Hashable, Sendable {
        public let profile: ProfileID
        public let kind: Kind

        public init(profile: ProfileID, kind: Kind) {
            self.profile = profile
            self.kind = kind
        }
    }

    public let profile: ProfileID
    public let kind: Kind
    /// The generation of the profile's bytes.
    public let generation: Int
    /// The generation of every fragment the profile stacked, by fragment.
    public let layers: [FragmentID: Int]

    public init(profile: ProfileID, kind: Kind, generation: Int, layers: [FragmentID: Int]) {
        self.profile = profile
        self.kind = kind
        self.generation = generation
        self.layers = layers
    }
}

/// What a reading reuses across reads. A reading always reads the files it is
/// asked about; this only answers about bytes whose digest came back identical.
/// The digest is of the bytes, never of metadata, so a same-length rewrite in
/// the same second is seen; and it is the digest that is kept, never the bytes.
///
/// A generation identifies a file's bytes and changes whenever they do, so
/// anything keyed on generations is reused exactly while its inputs are
/// unchanged and never otherwise.
///
/// Of each file the cache keeps two things: a summary every read wants (a
/// fragment's entry count, a profile's parse), and — only while something has
/// asked for it — the whole of what the bytes derived to (a fragment's parse).
/// The parses, the compositions and the rendered blocks' bytes exist for a
/// window that is showing them; releasing them keeps the digests, the counts
/// and the block summaries, which is what the menu and the schedule read.
public protocol StoreReadingCache: Sendable {
    /// Records a file's bytes by their digest and answers with their generation
    /// and summary. `derive` runs only when the recorded digest differs from
    /// `digest`, and what it made is summarised by `summarise` and held whole
    /// for `parse` when `hold` says so.
    func file<T, S>(_ url: URL, digest: ByteDigest, derive: () -> T, summarise: (T) -> S, hold: Bool) -> (generation: Int, summary: S)

    /// The whole of what `derive` makes of the file's recorded bytes: held from
    /// an earlier derive, or derived now and held.
    func parse<T>(_ url: URL, derive: () -> T) -> T

    /// What `derive` made of a derivation. `derive` runs only when `key` is not
    /// the key the stored value was derived from.
    func derived<T>(_ key: DerivationKey, derive: () throws -> T) rethrows -> T

    /// Keeps only the files named, so a file the store no longer lists stops
    /// being cached.
    func retainFiles(_ urls: Set<URL>)

    /// Lets go of every parse, every composition and every rendered block's
    /// bytes, keeping the digests, the counts and the block summaries: what a
    /// read with no window showing needs.
    func releaseDetail()
}
