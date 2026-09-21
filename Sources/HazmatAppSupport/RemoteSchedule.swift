import Foundation
import HazmatCore

/// How often a source may be given: an interval in seconds, with a floor and a
/// default, and zero meaning only when the refresh is asked for.
public enum RemoteInterval {
    /// A day. A published hosts file changes at most daily in practice, so this
    /// is what a source gets when nothing else is configured.
    public static let standard: TimeInterval = 24 * 60 * 60

    /// A quarter of an hour. Below this a source is a load on someone else's
    /// server for no gain, so a shorter interval is refused rather than clamped.
    public static let floor: TimeInterval = 15 * 60

    /// Only when asked for: the schedule never fetches it.
    public static let manual: TimeInterval = 0

    /// Why an interval cannot be used, or `nil` when it can. Zero is usable: it
    /// is how a source is taken off the schedule.
    public static func refusal(for interval: TimeInterval) -> String? {
        if !interval.isFinite {
            return "An interval has to be a length of time."
        }
        if interval < 0 {
            return "An interval cannot be negative."
        }
        if interval > 0 && interval < floor {
            return "The shortest interval is \(describe(floor)), so \(describe(interval)) is too often."
        }
        return nil
    }

    /// Whether the interval can be used as configured.
    public static func isAcceptable(_ interval: TimeInterval) -> Bool {
        refusal(for: interval) == nil
    }

    /// The interval length a source is recorded with, from what the window
    /// offered: the value itself, or the default when nothing was offered.
    public static func length(from interval: TimeInterval?) -> TimeInterval {
        interval ?? standard
    }

    /// An interval as a phrase, so a refusal says "15 minutes" rather than "900".
    /// A length that is not a whole number of the largest unit that fits is
    /// rounded to the nearest one: this is read by a person, not parsed.
    public static func describe(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval > 0 else {
            return "\(Int(interval.rounded())) seconds"
        }
        let seconds = Int(interval.rounded())
        if seconds >= 3600, seconds % 3600 == 0 {
            let hours = seconds / 3600
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        }
        if seconds >= 60 {
            let minutes = Int((interval / 60).rounded())
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        }
        return "\(seconds) second\(seconds == 1 ? "" : "s")"
    }
}

/// When a source is fetched, and what the window says about it.
public enum RemoteSchedule {
    /// How often the shell asks which sources are due. At most the floor, so a
    /// source on the shortest usable interval is not left waiting long past it;
    /// the question is answered from the sidecars, which is cheap.
    public static let tick: TimeInterval = 60

    /// Whether the schedule should fetch the source now.
    ///
    /// A source set to manual is never due. A source that has never been talked
    /// to is due at once, whatever its interval: a source just added should not
    /// wait a day for its first text. Otherwise the interval must have elapsed
    /// since the last contact, whatever its outcome, so a source that is down is
    /// not hammered.
    public static func isDue(_ source: RemoteSource, at now: Date) -> Bool {
        guard source.interval > 0 else { return false }
        guard let contacted = lastContact(source) else { return true }
        return now.timeIntervalSince(contacted) >= source.interval
    }

    /// Whether the source's text is missing or older than its own interval says
    /// it should be. A manual source is out of date only while it has never been
    /// refreshed: nothing else says when it should be.
    public static func isOutOfDate(_ source: RemoteSource, at now: Date) -> Bool {
        guard let lastSuccess = source.lastSuccess else { return true }
        guard source.interval > 0 else { return false }
        return now.timeIntervalSince(lastSuccess) >= source.interval
    }

    /// When the source was last talked to, whatever the outcome. A failed
    /// attempt waits out the interval like a successful one.
    private static func lastContact(_ source: RemoteSource) -> Date? {
        [source.lastSuccess, source.lastAttempt].compactMap { $0 }.max()
    }
}
