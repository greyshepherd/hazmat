import Foundation

/// Makes the helper answer.
///
/// A helper stops answering when the system's record of it no longer describes
/// the app bundle it was registered from, which is what replacing the bundle
/// does. One sequence fixes both conditions that follow from that:
///
/// 1. Register the helper. The system refreshes its record from the bundle it is
///    registering against, which is what a launch the system previously refused
///    needs - and a job the system no longer holds is submitted by this call.
/// 2. Ask the helper whether it answers.
/// 3. If it does not, remove the registration and register again, because a job
///    the system still holds is replaced only by removing it.
///
/// The second step is never taken lightly: removing the record leaves it
/// *disabled*, and a registration that lands while it is disabled can be refused
/// in a way no retry clears, so the removal is the last resort rather than the
/// first move. Both passes are bounded, and a helper that answers is never
/// repaired further.
///
/// Runs on the calling thread and takes as long as the system does; the caller
/// keeps it off the main thread and shows that it is working.
public struct HelperRepair: Sendable {
    public struct Outcome: Equatable, Sendable {
        /// Why registration failed, when it did. Nothing is asked then: there is
        /// no registered helper to ask.
        public let failure: RegistrationFailure?
        /// What the helper answered, when it was asked at all.
        public let answer: HelperReachability?
    }

    private let registration: HelperRegistering
    private let presence: HelperPresence
    private let passes: Int
    private let attempts: Int
    private let pause: TimeInterval
    private let passPause: TimeInterval

    public init(
        registration: HelperRegistering,
        presence: HelperPresence,
        passes: Int = 2,
        attempts: Int = 3,
        pause: TimeInterval = 0.4,
        passPause: TimeInterval = 0.5
    ) {
        self.registration = registration
        self.presence = presence
        self.passes = max(1, passes)
        self.attempts = attempts
        self.pause = pause
        self.passPause = passPause
    }

    public func run() -> Outcome {
        var outcome = pass(replacingTheJob: false)
        var remaining = passes - 1
        while remaining > 0, outcome.failure == nil, outcome.answer != .answering {
            remaining -= 1
            Thread.sleep(forTimeInterval: passPause)
            // The passes after the first replace the job: the registration the
            // system already holds is what the check just failed to start.
            outcome = pass(replacingTheJob: true)
        }
        return outcome
    }

    private func pass(replacingTheJob: Bool) -> Outcome {
        if replacingTheJob {
            // A helper that was never registered is already in the state the
            // removal wants, so a missing registration is not a failure.
            do {
                try registration.unregister()
            } catch RegistrationFailure.jobNotFound {
            } catch let failure as RegistrationFailure {
                return Outcome(failure: failure, answer: nil)
            } catch {
                return Outcome(failure: .other(domain: "\(type(of: error))", code: 0, message: "\(error)"), answer: nil)
            }
        }

        if let failure = register(toleratingTheSystemAlreadyHavingIt: !replacingTheJob) {
            return Outcome(failure: failure, answer: nil)
        }

        // Only an approved helper can be asked. One that needs approval is
        // reported by the registration, not by a question it cannot answer.
        guard registration.state == .enabled else {
            return Outcome(failure: nil, answer: nil)
        }
        return Outcome(failure: nil, answer: presence.check())
    }

    /// Registers, asking again while the system refuses because a removal has not
    /// finished. Where the registration was not preceded by a removal, the system
    /// having the helper already is the state the pass wants rather than a
    /// failure of it, so that refusal is taken as registered.
    private func register(toleratingTheSystemAlreadyHavingIt: Bool) -> RegistrationFailure? {
        for attempt in 1...max(1, attempts) {
            do {
                try registration.register()
                return nil
            } catch let failure as RegistrationFailure {
                if toleratingTheSystemAlreadyHavingIt, failure == .alreadyRegistered {
                    return nil
                }
                guard failure.isRetryable, attempt < attempts else { return failure }
                Thread.sleep(forTimeInterval: pause)
            } catch {
                return .other(domain: "\(type(of: error))", code: 0, message: "\(error)")
            }
        }
        return nil
    }
}
