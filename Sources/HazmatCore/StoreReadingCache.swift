import Foundation

/// What a derivation was made from: which answer it is, the generation of the
/// profile's bytes, and the generation of every fragment the profile stacked.
/// Two derivations with the same key have the same inputs, so one may answer for
/// the other.
public struct DerivationKey: Hashable, Sendable {
    /// Which answer a derivation is. A composition and the rendering of it are
    /// different answers, derived from the same inputs.
    public enum Kind: Hashable, Sendable {
        case composition
        case rendering
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
/// asked about; this only answers about bytes that came back identical.
///
/// A generation identifies a file's bytes and changes whenever they do, so
/// anything keyed on generations is reused exactly while its inputs are
/// unchanged and never otherwise.
public protocol StoreReadingCache: Sendable {
    /// The generation of a file's bytes, and what `derive` made of them.
    /// `derive` runs only when the cached bytes differ from `bytes`.
    func file<T>(_ url: URL, bytes: Data, derive: () -> T) -> (generation: Int, value: T)

    /// What `derive` made of a derivation. `derive` runs only when `key` is not
    /// the key the stored value was derived from.
    func derived<T>(_ key: DerivationKey, derive: () throws -> T) rethrows -> T

    /// Keeps only the files named, so a file the store no longer lists stops
    /// being cached.
    func retainFiles(_ urls: Set<URL>)
}
