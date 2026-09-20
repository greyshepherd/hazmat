import Foundation

/// One fragment as a reading holds it: the bytes that were read, and what they
/// parsed to. The text is decoded only when something asks for it, because only
/// the editor's draft needs the whole file as a string.
public struct FragmentReading: Equatable, Sendable {
    public let id: FragmentID
    public let bytes: Data
    public let outcome: FragmentParser.Outcome

    public var text: String { String(decoding: bytes, as: UTF8.self) }
}

/// One profile as a reading holds it.
public struct ProfileReading: Equatable, Sendable {
    public let id: ProfileID
    public let bytes: Data
    public let outcome: ProfileParser.Outcome

    public var text: String { String(decoding: bytes, as: UTF8.self) }
}

/// The store read once. It lists both directories, reads every file's bytes and
/// parses them, and answers every question the window and the menu ask from
/// that one reading: a fragment is parsed once per read rather than once per
/// row, per layer and per profile, and a profile is composed and rendered once
/// per reading rather than once per view.
///
/// With a cache, a derivation is reused across readings as well — but only when
/// the bytes read are byte-identical to the ones it was derived from. The files
/// themselves are read every time, because a store is read when it is asked.
///
/// A file the reading could not read is absent, the same answer as a store that
/// does not hold it.
public struct StoreReading: Sendable {
    /// The fragments the directory held when this reading was built, in name
    /// order.
    public let fragments: [FragmentID]
    /// The profiles the directory held when this reading was built.
    public let profiles: [ProfileID]

    private let box: Box

    public init(layout: StoreLayout, cache: (any StoreReadingCache)? = nil) {
        self.init(
            layout: layout,
            cache: cache,
            parseFragment: { FragmentParser.parse($0, as: $1) },
            parseProfile: { ProfileParser.parse($0, as: $1) }
        )
    }

    /// The seam a test counts parses through. The application parses with the
    /// real parsers.
    init(
        layout: StoreLayout,
        cache: (any StoreReadingCache)? = nil,
        parseFragment: (Data, FragmentID) -> FragmentParser.Outcome,
        parseProfile: (Data, ProfileID) -> ProfileParser.Outcome
    ) {
        let fragments = layout.fragments()
        let profiles = layout.profiles()

        var fragmentReadings: [FragmentID: FragmentReading] = [:]
        var fragmentGenerations: [FragmentID: Int] = [:]
        var profileReadings: [ProfileID: ProfileReading] = [:]
        var profileGenerations: [ProfileID: Int] = [:]
        var listed: Set<URL> = []

        for id in fragments {
            let url = layout.fragmentURL(id)
            listed.insert(url)
            guard let bytes = try? Data(contentsOf: url) else { continue }
            let cached = cache?.file(url, bytes: bytes) { parseFragment(bytes, id) }
            fragmentGenerations[id] = cached?.generation ?? 0
            fragmentReadings[id] = FragmentReading(id: id, bytes: bytes, outcome: cached?.value ?? parseFragment(bytes, id))
        }

        for id in profiles {
            let url = layout.profileURL(id)
            listed.insert(url)
            guard let bytes = try? Data(contentsOf: url) else { continue }
            let cached = cache?.file(url, bytes: bytes) { parseProfile(bytes, id) }
            profileGenerations[id] = cached?.generation ?? 0
            profileReadings[id] = ProfileReading(id: id, bytes: bytes, outcome: cached?.value ?? parseProfile(bytes, id))
        }

        cache?.retainFiles(listed)

        self.fragments = fragments
        self.profiles = profiles
        box = Box(
            fragments: fragmentReadings,
            profiles: profileReadings,
            fragmentGenerations: fragmentGenerations,
            profileGenerations: profileGenerations,
            cache: cache
        )
    }

    /// The fragment as it was read, or `nil` when the store held none.
    public func fragment(_ id: FragmentID) -> FragmentReading? { box.fragments[id] }

    /// The profile as it was read, or `nil` when the store held none.
    public func profile(_ id: ProfileID) -> ProfileReading? { box.profiles[id] }

    /// The profile composed, or `CompositionError` carrying every problem found.
    /// Composed once per reading, and once across readings while its inputs are
    /// unchanged.
    public func composition(of profile: ProfileID) throws -> Composition {
        try box.composition(of: profile)
    }

    /// The block the profile renders. Rendered once per reading, and once across
    /// readings while its inputs are unchanged.
    public func rendering(of profile: ProfileID) throws -> Data {
        try box.rendering(of: profile)
    }
}

/// A reading's memo tables. A class, so a copy of a reading sees the same
/// parses and compositions: one read derives each answer once. A profile that
/// cannot be composed is not memoised, which costs a second derivation of a
/// failure and never a second parse.
private final class Box: @unchecked Sendable {
    let fragments: [FragmentID: FragmentReading]
    let profiles: [ProfileID: ProfileReading]

    private let fragmentGenerations: [FragmentID: Int]
    private let profileGenerations: [ProfileID: Int]
    private let cache: (any StoreReadingCache)?

    private let lock = NSLock()
    private var compositions: [ProfileID: Composition] = [:]
    private var renderings: [ProfileID: Data] = [:]

    init(
        fragments: [FragmentID: FragmentReading],
        profiles: [ProfileID: ProfileReading],
        fragmentGenerations: [FragmentID: Int],
        profileGenerations: [ProfileID: Int],
        cache: (any StoreReadingCache)?
    ) {
        self.fragments = fragments
        self.profiles = profiles
        self.fragmentGenerations = fragmentGenerations
        self.profileGenerations = profileGenerations
        self.cache = cache
    }

    func composition(of profile: ProfileID) throws -> Composition {
        lock.lock()
        let done = compositions[profile]
        lock.unlock()
        if let done { return done }

        let derive = { try Self.compose(profile: profile, fragments: self.fragments, profiles: self.profiles) }
        let composition: Composition
        if let cache, let key = derivationKey(for: profile, kind: .composition) {
            composition = try cache.derived(key, derive: derive)
        } else {
            composition = try derive()
        }

        lock.lock()
        let stored = compositions[profile] ?? composition
        compositions[profile] = stored
        lock.unlock()
        return stored
    }

    func rendering(of profile: ProfileID) throws -> Data {
        lock.lock()
        let done = renderings[profile]
        lock.unlock()
        if let done { return done }

        let derive = { BlockRenderer.render(try self.composition(of: profile)) }
        let rendering: Data
        if let cache, let key = derivationKey(for: profile, kind: .rendering) {
            rendering = try cache.derived(key, derive: derive)
        } else {
            rendering = try derive()
        }

        lock.lock()
        let stored = renderings[profile] ?? rendering
        renderings[profile] = stored
        lock.unlock()
        return stored
    }

    /// What a derivation of this profile is made from. `nil` when the reading
    /// never read the profile, in which case there is nothing to key on.
    private func derivationKey(for profile: ProfileID, kind: DerivationKey.Kind) -> DerivationKey? {
        guard let generation = profileGenerations[profile], let parsed = profiles[profile] else { return nil }
        var layers: [FragmentID: Int] = [:]
        for reference in parsed.outcome.profile.references {
            guard let layer = fragmentGenerations[reference.fragment] else { continue }
            layers[reference.fragment] = layer
        }
        return DerivationKey(profile: profile, kind: kind, generation: generation, layers: layers)
    }

    private static func compose(
        profile id: ProfileID,
        fragments: [FragmentID: FragmentReading],
        profiles: [ProfileID: ProfileReading]
    ) throws -> Composition {
        guard let profile = profiles[id] else {
            throw CompositionError([.missingProfile(id)])
        }
        var problems = profile.outcome.problems
        var layers: [ParsedFragment] = []
        for reference in profile.outcome.profile.references {
            guard let fragment = fragments[reference.fragment] else {
                problems.append(.missingFragment(profile: id, line: reference.line, fragment: reference.fragment))
                continue
            }
            problems.append(contentsOf: fragment.outcome.problems)
            layers.append(fragment.outcome.fragment)
        }
        return try HostsComposer.compose(profile: id, layers: layers, problems: problems)
    }
}
