import Foundation

/// The block a profile renders now, named by its digest, or the problem that
/// stopped it rendering.
public enum ProfileRendering: Equatable, Sendable {
    case block(ByteDigest)
    case problem(String)
}

/// One profile handed to the derivation: what it renders, or why it does not.
public struct ProfileRender: Equatable, Sendable {
    public let profile: ProfileID
    public let rendering: ProfileRendering

    public init(profile: ProfileID, rendering: ProfileRendering) {
        self.profile = profile
        self.rendering = rendering
    }
}

/// A profile whose rendered block could not be produced.
public struct ProfileRenderProblem: Equatable, Sendable {
    public let profile: ProfileID
    public let reason: String

    public init(profile: ProfileID, reason: String) {
        self.profile = profile
        self.reason = reason
    }
}

/// What the live file represents, judged from its bytes alone.
public enum ActiveProfileState: Equatable, Sendable {
    /// The file holds no managed block.
    case off
    /// The markers cannot be read as one supported block.
    case unreadable(BlockError)
    /// The block is well-formed and matches no profile's rendering. It carries
    /// the live block's digest, so a deliberate overwrite names the block it
    /// replaces without holding its bytes.
    case drifted(ByteDigest)
    /// The profiles whose rendering is byte-identical to the live block.
    case active([ProfileID])
}

/// The live file's state, plus the profiles that could not be rendered. A
/// profile that fails to render cannot match, and is reported rather than
/// silently treated as one more profile that is not active.
public struct ActiveProfile: Equatable, Sendable {
    public let state: ActiveProfileState
    public let problems: [ProfileRenderProblem]
    /// The digest of the block the file holds, when it holds a readable one:
    /// the block the active profiles render, or the drifted one.
    public let liveBlock: ByteDigest?

    public init(state: ActiveProfileState, problems: [ProfileRenderProblem] = [], liveBlock: ByteDigest? = nil) {
        self.state = state
        self.problems = problems
        self.liveBlock = liveBlock
    }

    /// The profiles whose rendering matches the live block, empty for every
    /// other state.
    public var activeProfiles: [ProfileID] {
        guard case .active(let profiles) = state else { return [] }
        return profiles
    }

    /// The live block is byte-identical to a profile's rendering, so replacing
    /// it is a switch. A block no profile owns is drift.
    public var matchesAProfile: Bool {
        !activeProfiles.isEmpty
    }
}

/// Answers which profile the live file represents by comparing the block it
/// holds against the bytes each profile renders. Nothing is stored, so an edit
/// made outside the application is what the next answer is based on.
public enum Activation {
    /// Derives the state from `live` and the profiles' current renderings.
    /// Order-independent: the matched profiles and the problems are sorted.
    public static func match(live: Data, renders: [ProfileRender]) -> ActiveProfile {
        var problems = renders.compactMap { render -> ProfileRenderProblem? in
            guard case .problem(let reason) = render.rendering else { return nil }
            return ProfileRenderProblem(profile: render.profile, reason: reason)
        }
        problems.sort { $0.profile < $1.profile }

        let location: ManagedBlockLocation
        do {
            guard let found = try ManagedBlock.locate(in: live) else {
                return ActiveProfile(state: .off, problems: problems)
            }
            location = found
        } catch let error as BlockError {
            return ActiveProfile(state: .unreadable(error), problems: problems)
        } catch {
            return ActiveProfile(state: .unreadable(.invalidBlock("\(error)")), problems: problems)
        }
        guard location.version == ManagedBlock.version else {
            return ActiveProfile(
                state: .unreadable(.unsupportedVersion(found: location.version, expected: ManagedBlock.version)),
                problems: problems
            )
        }

        let block = ByteDigest(live[location.range])
        let matched = renders
            .filter { $0.rendering == .block(block) }
            .map(\.profile)
            .sorted()
        return ActiveProfile(state: matched.isEmpty ? .drifted(block) : .active(matched), problems: problems, liveBlock: block)
    }
}
