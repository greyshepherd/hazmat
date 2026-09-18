import Foundation

/// What a status or state reads as, so a colour is never the only thing that
/// carries it.
public enum StatusTone: String, CaseIterable, Equatable, Sendable {
    case neutral
    case success
    case warning
    case danger
}
