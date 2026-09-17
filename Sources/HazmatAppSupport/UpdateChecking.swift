import Foundation

/// What the menu can say about updates. Only a bundle that declares a feed can
/// check at all, so a development build reads as unavailable and is offered no
/// check.
public enum UpdateAvailability: Equatable, Sendable {
    /// This bundle declares no feed, or the framework could not be started.
    case unavailable
    /// A check can be started.
    case available
    /// The last check did not finish; the reason is what to show a person.
    case failed(String)
}

/// The update check, as the shell sees it: whether it can be made, and what
/// happened the last time it was. The app owns the implementation — and with it
/// the only dependency on an update framework — so nothing here or below it can
/// reach the feed.
@MainActor
public protocol UpdateChecking: AnyObject {
    var availability: UpdateAvailability { get }
    func checkForUpdates()
}
