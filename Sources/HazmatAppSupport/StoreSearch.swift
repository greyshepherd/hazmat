import Foundation
import HazmatCore

/// The one thing the sidebar can have selected: a profile or a fragment.
public enum SidebarSelection: Hashable, Sendable {
    case profile(ProfileID)
    case fragment(FragmentID)
}

/// The sidebar's search: the text and which of the store's names match. The
/// selection rule lives with it, so "the selection survives a search" is a
/// value a test can read.
public struct StoreSearch: Equatable, Sendable {
    public let text: String

    public static let none = StoreSearch()

    public init(text: String = "") {
        self.text = text
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
        available.filter { matches($0.rawValue) }
    }

    public func fragments(_ available: [FragmentID]) -> [FragmentID] {
        available.filter { matches($0.rawValue) }
    }
}
