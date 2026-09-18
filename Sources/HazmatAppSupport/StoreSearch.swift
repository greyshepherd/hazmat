import Foundation
import HazmatCore

/// The one thing the sidebar can have selected: a profile or a fragment.
public enum SidebarSelection: Hashable, Sendable {
    case profile(ProfileID)
    case fragment(FragmentID)
}

/// What a search covers.
public enum SearchScope: String, CaseIterable, Equatable, Sendable {
    case all
    case profiles
    case fragments

    public var title: String {
        switch self {
        case .all: return "All"
        case .profiles: return "Profiles"
        case .fragments: return "Fragments"
        }
    }
}

/// The sidebar's search: the text and the scope, and which of the store's names
/// match. The selection rule lives with it, so "the selection survives a search"
/// is a value a test can read.
public struct StoreSearch: Equatable, Sendable {
    public let text: String
    public let scope: SearchScope

    public static let none = StoreSearch()

    public init(text: String = "", scope: SearchScope = .all) {
        self.text = text
        self.scope = scope
    }

    /// Whether a search is narrowing the lists at all.
    public var isActive: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Case-insensitive, anywhere in the name, so a fragment found by a word in
    /// it does not need its first letters remembered.
    public func matches(_ name: String) -> Bool {
        guard isActive else { return true }
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    public func profiles(_ available: [ProfileID]) -> [ProfileID] {
        guard scope != .fragments else { return [] }
        return available.filter { matches($0.rawValue) }
    }

    public func fragments(_ available: [FragmentID]) -> [FragmentID] {
        guard scope != .profiles else { return [] }
        return available.filter { matches($0.rawValue) }
    }
}
