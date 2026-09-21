import HazmatCore
import Foundation

/// What the last action came to, as the menu weighs it. The window reports
/// everything; the menu reports only what needs attention, so a quiet menu
/// means the file and the helper are as the marks and the items say.
public enum MenuNotice: Equatable, Sendable {
    /// Nothing was done, or what was done needs no words.
    case quiet
    /// A write is in flight.
    case progress(String)
    /// What was done.
    case success(String)
    /// What went wrong.
    case failure(String)

    public var text: String {
        switch self {
        case .quiet: return ""
        case .progress(let text), .success(let text), .failure(let text): return text
        }
    }

    public var isEmpty: Bool {
        if case .quiet = self { return true }
        return false
    }
}

extension MenuNotice {
    /// The applier's answer: a refusal or a failure needs attention; the rest
    /// is the success the marks already show.
    public init(_ outcome: ApplyOutcome) {
        switch outcome {
        case .applied, .nothingToDo: self = .success(outcome.description)
        case .refused, .failed: self = .failure(outcome.description)
        }
    }

    /// The editor's combined answer: any refusal or problem in it needs
    /// attention, and a refresh that found nothing changed needs no words at all.
    public init(_ outcome: EditorOutcome) {
        if outcome.needsAttention {
            self = .failure(outcome.description)
        } else if outcome.refresh?.wasUnchanged == true {
            // Nothing was done and nothing needs saying: the fragment's bytes are
            // untouched, and the source's row already names when it last
            // refreshed. A line here would only tell the reader what they can
            // already see.
            self = .quiet
        } else {
            self = .success(outcome.description)
        }
    }
}
