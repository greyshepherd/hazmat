import Foundation
import HazmatCore

/// The add-source or edit-source sheet: what it asks for, and why what has been
/// given cannot be used.
///
/// Everything is validated as it is typed, so a URL that is not HTTPS or an
/// interval below the floor is corrected in the sheet rather than reported after
/// it closes. A field still empty is not reported: nothing is said about what has
/// not been typed yet, and the confirm action waits instead. The store's own
/// answer is kept here too, so a name the store refuses for a reason the sheet
/// cannot see is still shown where it was given.
public struct SourceSheetPresentation: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        /// A new source: the name is part of what is asked for.
        case adding
        /// An existing source: its URL and interval, with the name it is
        /// recorded under.
        case editing(FragmentID)
    }

    public let mode: Mode
    public var name: String
    public var url: String
    /// How many hours between refreshes. Ignored when `isManual`.
    public var hours: Double
    /// Whether the source is refreshed only when it is asked for.
    public var isManual: Bool
    /// Why the store refused the last attempt, when it did.
    public var refusal: String?

    public init(
        mode: Mode,
        name: String = "",
        url: String = "",
        hours: Double = SourceSheetPresentation.standardHours,
        isManual: Bool = false,
        refusal: String? = nil
    ) {
        self.mode = mode
        self.name = name
        self.url = url
        self.hours = hours
        self.isManual = isManual
        self.refusal = refusal
    }

    /// A day, as the field shows it.
    public static var standardHours: Double { RemoteInterval.standard / 3600 }

    /// The interval the sheet describes.
    public var interval: TimeInterval {
        isManual ? RemoteInterval.manual : hours * 3600
    }

    /// The fragment the sheet would record.
    public var fragment: FragmentID? {
        switch mode {
        case .adding: return FragmentID(name)
        case .editing(let name): return name
        }
    }

    /// Why what has been given cannot be used, or `nil` when it can. Every field
    /// is checked, including the ones still empty, so a caller that saves anyway
    /// gets a reason rather than a silent no-op.
    public var validation: String? {
        for check in checks {
            switch check {
            case .empty(let missing): return "Enter \(missing)."
            case .refused(let reason): return reason
            case .usable: continue
            }
        }
        return nil
    }

    /// What the sheet reports: the first refusal, or the store's own. A field
    /// still empty is left out, so opening the sheet says nothing about what has
    /// not been typed yet.
    public var problem: String? {
        for check in checks {
            if case .refused(let reason) = check { return reason }
        }
        return refusal
    }

    /// What the sheet is still waiting for, when nothing is wrong but something
    /// is missing. A hint, not a refusal: it is shown quietly, beside a confirm
    /// action that is waiting.
    public var hint: String? {
        let missing = checks.compactMap { check -> String? in
            guard case .empty(let field) = check else { return nil }
            return field
        }
        guard !missing.isEmpty else { return nil }
        return "Enter \(Self.listing(missing))."
    }

    /// Whether the sheet's confirm action can be used. A refusal the store gave
    /// disables it too, so the reason is read before the same attempt is made
    /// again; editing any field clears that refusal.
    public var isUsable: Bool {
        refusal == nil && checks.allSatisfy { $0 == .usable }
    }

    /// What each field comes to. One set of rules answers both questions the
    /// sheet asks — what to show, and whether it can be saved — so the message
    /// and the button can never disagree.
    private var checks: [Check] {
        [checkName(), checkURL(), checkInterval()]
    }

    private enum Check: Equatable {
        /// The field holds nothing yet, named as the missing thing: "a name".
        case empty(String)
        case refused(String)
        case usable
    }

    private func checkName() -> Check {
        guard asksForAName else { return .usable }
        guard !name.isEmpty else { return .empty("a name") }
        guard let reason = NameSyntax.refusal(name) else { return .usable }
        return .refused(reason)
    }

    private func checkURL() -> Check {
        guard !url.isEmpty else { return .empty("the URL the fragment is fetched from") }
        guard let reason = RemoteRefresher.urlRefusal(url) else { return .usable }
        return .refused(reason)
    }

    private func checkInterval() -> Check {
        guard let reason = RemoteInterval.refusal(for: interval) else { return .usable }
        return .refused(reason)
    }

    /// "a name", "a name and the URL", "a name, the URL and an interval".
    private static func listing(_ parts: [String]) -> String {
        guard let last = parts.last else { return "" }
        guard parts.count > 1 else { return last }
        return parts.dropLast().joined(separator: ", ") + " and \(last)"
    }

    /// Whether the name is editable here. An existing source is changed by URL
    /// and interval; renaming it is a rename of its fragment.
    public var asksForAName: Bool {
        if case .adding = mode { return true }
        return false
    }

    /// The sheet that opens for a source the store already holds.
    public static func editing(_ name: FragmentID, _ source: RemoteSource) -> SourceSheetPresentation {
        SourceSheetPresentation(
            mode: .editing(name),
            name: name.rawValue,
            url: source.url.absoluteString,
            hours: source.interval / 3600,
            isManual: source.interval == RemoteInterval.manual
        )
    }

    /// The sheet with a refusal from the store on it, keeping everything that
    /// was typed so it can be corrected in place.
    public func reporting(_ refusal: String) -> SourceSheetPresentation {
        var copy = self
        copy.refusal = refusal
        return copy
    }
}
