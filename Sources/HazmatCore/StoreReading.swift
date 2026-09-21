import Foundation

/// One fragment as a reading holds it: the bytes that were read and how many
/// entries they hold. The parse is asked of the reading separately, because
/// only composing needs it. The text is decoded only when something asks for
/// it, because only the editor's draft needs the whole file as a string.
public struct FragmentReading: Equatable, Sendable {
    public let id: FragmentID
    public let bytes: Data
    /// How many entries the fragment holds, as its rows show it.
    public let entryCount: Int

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
        parseFragment: @escaping @Sendable (Data, FragmentID) -> FragmentParser.Outcome,
        parseProfile: (Data, ProfileID) -> ProfileParser.Outcome
    ) {
        let fragments = layout.fragments()
        let profiles = layout.profiles()

        var fragmentReadings: [FragmentID: FragmentReading] = [:]
        var fragmentGenerations: [FragmentID: Int] = [:]
        var fragmentBytes: [FragmentID: Data] = [:]
        var parses: [FragmentID: FragmentParser.Outcome] = [:]
        var profileReadings: [ProfileID: ProfileReading] = [:]
        var profileGenerations: [ProfileID: Int] = [:]
        var listed: Set<URL> = []

        // The profiles first: which fragments they stack decides whether a
        // fragment's parse is worth holding for composing, or its count is all
        // a read wants of it.
        for id in profiles {
            let url = layout.profileURL(id)
            listed.insert(url)
            guard let bytes = try? Data(contentsOf: url) else { continue }
            let cached = cache?.file(url, bytes: bytes, derive: { parseProfile(bytes, id) }, summarise: { $0 }, hold: false)
            profileGenerations[id] = cached?.generation ?? 0
            profileReadings[id] = ProfileReading(id: id, bytes: bytes, outcome: cached?.summary ?? parseProfile(bytes, id))
        }
        var stacked: Set<FragmentID> = []
        for profile in profileReadings.values {
            for reference in profile.outcome.profile.references {
                stacked.insert(reference.fragment)
            }
        }

        for id in fragments {
            let url = layout.fragmentURL(id)
            listed.insert(url)
            guard let bytes = try? Data(contentsOf: url) else { continue }
            fragmentBytes[id] = bytes
            let entryCount: Int
            if let cache {
                let cached = cache.file(
                    url,
                    bytes: bytes,
                    derive: { parseFragment(bytes, id) },
                    summarise: { $0.fragment.entryCount },
                    hold: stacked.contains(id)
                )
                fragmentGenerations[id] = cached.generation
                entryCount = cached.summary
            } else {
                // With nothing to hold it across reads, the parse is made now
                // and kept for this reading, so a count and a composition
                // still share it.
                let outcome = parseFragment(bytes, id)
                parses[id] = outcome
                fragmentGenerations[id] = 0
                entryCount = outcome.fragment.entryCount
            }
            fragmentReadings[id] = FragmentReading(id: id, bytes: bytes, entryCount: entryCount)
        }

        cache?.retainFiles(listed)

        self.fragments = fragments
        self.profiles = profiles
        box = Box(
            fragments: fragmentReadings,
            profiles: profileReadings,
            fragmentGenerations: fragmentGenerations,
            profileGenerations: profileGenerations,
            parses: parses,
            parseFragment: { id in
                guard let bytes = fragmentBytes[id] else { return nil }
                if let cache {
                    return cache.parse(layout.fragmentURL(id)) { parseFragment(bytes, id) }
                }
                return parseFragment(bytes, id)
            },
            cache: cache
        )
    }

    /// The fragment as it was read, or `nil` when the store held none.
    public func fragment(_ id: FragmentID) -> FragmentReading? { box.fragments[id] }

    /// The fragment parsed, or `nil` when the store held none. Parsed once per
    /// reading, and held across readings while the cache holds it.
    public func parse(_ id: FragmentID) -> FragmentParser.Outcome? { box.parse(id) }

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
    /// Parses the fragment's bytes as read, through the cache when there is one.
    private let parseFragment: (FragmentID) -> FragmentParser.Outcome?
    private let cache: (any StoreReadingCache)?

    private let lock = NSLock()
    private var parses: [FragmentID: FragmentParser.Outcome]
    private var compositions: [ProfileID: Composition] = [:]
    private var renderings: [ProfileID: Data] = [:]

    init(
        fragments: [FragmentID: FragmentReading],
        profiles: [ProfileID: ProfileReading],
        fragmentGenerations: [FragmentID: Int],
        profileGenerations: [ProfileID: Int],
        parses: [FragmentID: FragmentParser.Outcome],
        parseFragment: @escaping (FragmentID) -> FragmentParser.Outcome?,
        cache: (any StoreReadingCache)?
    ) {
        self.fragments = fragments
        self.profiles = profiles
        self.fragmentGenerations = fragmentGenerations
        self.profileGenerations = profileGenerations
        self.parses = parses
        self.parseFragment = parseFragment
        self.cache = cache
    }

    func parse(_ id: FragmentID) -> FragmentParser.Outcome? {
        lock.lock()
        let done = parses[id]
        lock.unlock()
        if let done { return done }

        guard let outcome = parseFragment(id) else { return nil }

        lock.lock()
        let stored = parses[id] ?? outcome
        parses[id] = stored
        lock.unlock()
        return stored
    }

    func composition(of profile: ProfileID) throws -> Composition {
        lock.lock()
        let done = compositions[profile]
        lock.unlock()
        if let done { return done }

        let derive = { try self.compose(profile: profile) }
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

    private func compose(profile id: ProfileID) throws -> Composition {
        guard let profile = profiles[id] else {
            throw CompositionError([.missingProfile(id)])
        }
        var problems = profile.outcome.problems
        var layers: [ParsedFragment] = []
        for reference in profile.outcome.profile.references {
            guard let outcome = parse(reference.fragment) else {
                problems.append(.missingFragment(profile: id, line: reference.line, fragment: reference.fragment))
                continue
            }
            problems.append(contentsOf: outcome.problems)
            layers.append(outcome.fragment)
        }
        return try HostsComposer.compose(profile: id, layers: layers, problems: problems)
    }
}
