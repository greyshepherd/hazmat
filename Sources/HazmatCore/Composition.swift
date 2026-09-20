/// An entry that lost a conflict, and the entry that won it.
public struct Displacement: Equatable, Sendable {
    public let name: String
    public let family: AddressFamily
    /// The address that did not survive.
    public let address: String
    /// The fragment and line that supplied the losing entry.
    public let source: SourceLocation
    /// The fragment and line that supplied the winning entry.
    public let displacedBy: SourceLocation
}

/// A name that survived composition, with the address it resolves to.
public struct ResolvedName: Equatable, Sendable {
    public let name: String
    public let address: String
    public let family: AddressFamily
    /// The fragment and line that supplied the winning entry.
    public let source: SourceLocation

    let layer: Int
    let nameIndex: Int
}

/// A profile composed in one pass: the surviving names, and the conflicts that
/// decided them. Nothing here needs a second read of the store.
public struct Composition: Equatable, Sendable {
    public let profile: ProfileID
    /// Surviving names in resolution order: winning layer, then line, then the
    /// name's position within its entry.
    public let resolved: [ResolvedName]
    /// Every entry a conflict displaced, in the order the conflicts occurred.
    public let displacements: [Displacement]

    public var isEmpty: Bool { resolved.isEmpty }
}

/// Composes a profile's fragments into one resolved set, reading only through
/// `store`. Errors the store itself throws are propagated.
public struct HostsComposer: Sendable {
    private let store: HostsStore

    public init(store: HostsStore) {
        self.store = store
    }

    /// Composes `profile`, or throws `CompositionError` carrying every problem
    /// found in the same pass. Nothing is applied when any problem exists.
    public func compose(profile: ProfileID) throws -> Composition {
        guard let profileText = try store.profile(named: profile) else {
            throw CompositionError([.missingProfile(profile)])
        }
        let parsedProfile = ProfileParser.parse(profileText, as: profile)
        var problems = parsedProfile.problems

        var layers: [ParsedFragment] = []
        for reference in parsedProfile.profile.references {
            guard let text = try store.fragment(named: reference.fragment) else {
                problems.append(.missingFragment(profile: profile, line: reference.line, fragment: reference.fragment))
                continue
            }
            let outcome = FragmentParser.parse(text, as: reference.fragment)
            problems.append(contentsOf: outcome.problems)
            layers.append(outcome.fragment)
        }
        return try Self.compose(profile: profile, layers: layers, problems: problems)
    }

    /// Composes a profile whose layers are already parsed, together with the
    /// problems gathering them found. A caller that has read the store once
    /// asks this rather than making the composer read it again; nothing is
    /// resolved when a problem exists.
    public static func compose(
        profile: ProfileID,
        layers: [ParsedFragment],
        problems: [CompositionProblem] = []
    ) throws -> Composition {
        guard problems.isEmpty else { throw CompositionError(problems) }
        return resolve(profile: profile, layers: layers)
    }

    private static func resolve(profile: ProfileID, layers: [ParsedFragment]) -> Composition {
        struct Key: Hashable {
            let name: String
            let family: AddressFamily
        }

        var displacements: [Displacement] = []
        // Every name an entry supplied, in resolution order: winning layer, then
        // line, then the name's position within its entry. A later entry that
        // wins a name marks the earlier one superseded rather than moving it, so
        // the survivors are already in the order `resolved` has to be in and no
        // sort is needed to say so.
        var supplied: [ResolvedName] = []
        var superseded: [Bool] = []
        var winner: [Key: Int] = [:]

        for (layerIndex, fragment) in layers.enumerated() {
            for item in fragment.items {
                switch item {
                case .entry(let entry):
                    // Keyed on every name, so an alias conflict is resolved the
                    // same way a host name conflict is.
                    for (nameIndex, name) in entry.names.enumerated() {
                        let key = Key(name: name, family: entry.family)
                        if let displaced = winner[key] {
                            displacements.append(
                                Displacement(
                                    name: name,
                                    family: entry.family,
                                    address: supplied[displaced].address,
                                    source: supplied[displaced].source,
                                    displacedBy: entry.source
                                )
                            )
                            superseded[displaced] = true
                        }
                        winner[key] = supplied.count
                        supplied.append(
                            ResolvedName(
                                name: name,
                                address: entry.address,
                                family: entry.family,
                                source: entry.source,
                                layer: layerIndex,
                                nameIndex: nameIndex
                            )
                        )
                        superseded.append(false)
                    }
                case .removal(let removal):
                    for family in AddressFamily.allCases {
                        guard let removed = winner.removeValue(forKey: Key(name: removal.name, family: family)) else { continue }
                        superseded[removed] = true
                    }
                }
            }
        }

        let resolved = supplied.indices.compactMap { superseded[$0] ? nil : supplied[$0] }
        return Composition(profile: profile, resolved: resolved, displacements: displacements)
    }
}
