import Foundation

/// The two bounds a fetch obeys, each named once so the refusal a user reads and
/// the check that produced it cannot drift apart.
public enum FetchBounds {
    /// The largest body a fetch will store: the same bound the applied block
    /// already obeys, because text that could not be applied is not worth
    /// keeping.
    public static let bodySizeBound = PlannedBytes.sizeBound

    /// How long one exchange may take before it is refused.
    public static let exchangeTime: TimeInterval = 60

    /// How many redirects one exchange may follow. A redirect is followed only
    /// while it stays on HTTPS, and only this many times, so a chain cannot run
    /// away with an exchange.
    public static let redirectLimit = 5

    /// Why a body was refused, naming the number so the report says what would
    /// have been acceptable.
    public static func oversizedBody(_ actual: Int) -> String {
        "the body is \(actual) bytes; a fetched body holds at most \(bodySizeBound) bytes"
    }

    /// Why an exchange was refused for taking too long.
    public static var exchangeTimedOut: String {
        "the exchange took longer than \(Int(exchangeTime)) seconds"
    }
}
