import Foundation
import HazmatCore

/// Reads the live file's bytes. The seam exists so a test can count reads.
public protocol LiveFileReading: Sendable {
    func read() throws -> Data
}

extension LiveHostsFile: LiveFileReading {}

/// What reading the store and the live file produced. A store that does not
/// exist and a store that holds no profiles are distinct answers: the first is
/// a missing directory, the second an empty one.
public enum ActiveProfileReading: Equatable, Sendable {
    case missingStore
    case emptyStore
    case unreadableFile(profiles: [ProfileID], reason: String)
    case derived(profiles: [ProfileID], activation: ActiveProfile)

    /// The profiles the store held, whenever it could be listed at all.
    public var profiles: [ProfileID] {
        switch self {
        case .missingStore, .emptyStore:
            return []
        case .unreadableFile(let profiles, _), .derived(let profiles, _):
            return profiles
        }
    }

    /// The derivation, when the live file was read.
    public var activation: ActiveProfile? {
        guard case .derived(_, let activation) = self else { return nil }
        return activation
    }

    /// Whether choosing a profile may replace the live block. It may when the
    /// block belongs to a profile - the apply path calls any other block drift,
    /// so a switch has to ask for the replace. A block no profile owns is only
    /// replaced when the menu's overwrite item asks for it.
    public var replacingIsASwitch: Bool {
        activation?.matchesAProfile == true
    }
}

extension ProfileCatalogue {
    /// Reads the live file once, renders every profile the store holds, and
    /// derives which profile the file represents. A profile that fails to
    /// render is reported in the derivation instead of failing the read.
    public func activation(reading file: LiveFileReading) -> ActiveProfileReading {
        guard exists else { return .missingStore }
        let profiles = profiles()
        guard !profiles.isEmpty else { return .emptyStore }

        let live: Data
        do {
            live = try file.read()
        } catch {
            return .unreadableFile(profiles: profiles, reason: "\(error)")
        }

        let renders = profiles.map { profile -> ProfileRender in
            do {
                return ProfileRender(profile: profile, rendering: .block(try renderedBlock(for: profile)))
            } catch {
                return ProfileRender(profile: profile, rendering: .problem("\(error)"))
            }
        }
        return .derived(profiles: profiles, activation: Activation.match(live: live, renders: renders))
    }
}
