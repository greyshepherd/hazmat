import Foundation
import HazmatAppSupport
import XCTest

/// What the sequence that makes the helper answer does, with the system replaced
/// by a double that can refuse the way the system does: a registration that lands
/// while a removal is still finishing is refused, and the same call works a
/// moment later.
final class HelperRepairTests: XCTestCase {
    private final class RegistrationDouble: HelperRegistering, @unchecked Sendable {
        var state: HelperState = .enabled
        /// What the system reports once it accepts a registration.
        var stateAfterRegistering: HelperState? = .enabled
        var refusals: [RegistrationFailure] = []
        var removalFailure: RegistrationFailure?
        private(set) var registrations = 0
        private(set) var removals = 0

        func register() throws {
            registrations += 1
            if refusals.isEmpty == false {
                throw refusals.removeFirst()
            }
            if let stateAfterRegistering {
                state = stateAfterRegistering
            }
        }

        func unregister() throws {
            removals += 1
            if let removalFailure {
                throw removalFailure
            }
        }
    }

    private final class PresenceDouble: HelperPresence, @unchecked Sendable {
        private var answers: [HelperReachability]
        private(set) var checks = 0

        init(_ answer: HelperReachability) {
            answers = [answer]
        }

        init(_ answers: HelperReachability...) {
            self.answers = answers
        }

        func check() -> HelperReachability {
            checks += 1
            return answers.isEmpty ? .silent : answers.removeFirst()
        }
    }

    private func repair(
        _ registration: RegistrationDouble,
        _ presence: HelperPresence,
        passes: Int = 2,
        attempts: Int = 3
    ) -> HelperRepair {
        HelperRepair(
            registration: registration,
            presence: presence,
            passes: passes,
            attempts: attempts,
            pause: 0,
            passPause: 0
        )
    }

    // MARK: - The registration before the removal

    /// Removing the record leaves it disabled, and a registration that lands
    /// while it is disabled is refused in a way no retry clears, so a helper that
    /// answers is installed without anything being removed.
    func testAHelperThatAnswersIsNeverRemoved() {
        let registration = RegistrationDouble()
        let presence = PresenceDouble(.answering)

        let outcome = repair(registration, presence).run()

        XCTAssertEqual(registration.removals, 0)
        XCTAssertEqual(registration.registrations, 1)
        XCTAssertEqual(presence.checks, 1)
        XCTAssertEqual(outcome.answer, .answering)
        XCTAssertNil(outcome.failure)
    }

    func testTheSystemAlreadyHavingTheHelperIsNotAFailureOfTheFirstPass() {
        let registration = RegistrationDouble()
        registration.refusals = [.alreadyRegistered]
        let presence = PresenceDouble(.answering)

        let outcome = repair(registration, presence).run()

        XCTAssertNil(outcome.failure, "a helper the system already has still needs to be asked")
        XCTAssertEqual(registration.registrations, 1)
        XCTAssertEqual(registration.removals, 0)
        XCTAssertEqual(outcome.answer, .answering)
    }

    // MARK: - The pass that replaces the job

    /// Refusing to launch a helper whose record is stale is what makes the system
    /// replace that record, so the pass after the refusal is the one that can
    /// succeed - and it is the pass that removes the job naming the old record.
    func testAPassThatDoesNotAnswerIsFollowedByOneThatReplacesTheJob() {
        let registration = RegistrationDouble()
        let presence = PresenceDouble(.silent)

        let outcome = repair(registration, presence).run()

        XCTAssertEqual(outcome.answer, .silent)
        XCTAssertEqual(registration.registrations, 2)
        XCTAssertEqual(registration.removals, 1, "only the pass after a check that did not answer removes")
        XCTAssertEqual(presence.checks, 2)
    }

    func testARepairStopsAtThePassThatAnswers() {
        let registration = RegistrationDouble()
        let presence = PresenceDouble(.silent, .answering)

        let outcome = repair(registration, presence).run()

        XCTAssertEqual(outcome.answer, .answering)
        XCTAssertEqual(presence.checks, 2)
        XCTAssertEqual(registration.registrations, 2)
    }

    // MARK: - The refusals the system makes

    func testARegistrationRefusedWhileTheRemovalFinishesIsAskedAgain() {
        let registration = RegistrationDouble()
        // The first pass answers nothing, so the second one removes and registers
        // - inside the window where the system refuses a registration.
        registration.refusals = [.notPermitted("the job is not allowed to bootstrap")]
        let presence = PresenceDouble(.silent, .answering)

        let outcome = repair(registration, presence).run()

        XCTAssertNil(outcome.failure)
        XCTAssertEqual(registration.removals, 1)
        XCTAssertEqual(registration.registrations, 3, "one registration, then a refusal the system makes while removing, then the same call again")
        XCTAssertEqual(outcome.answer, .answering)
    }

    func testARegistrationRefusedEveryTimeIsReportedWithoutAskingTheHelper() {
        let registration = RegistrationDouble()
        registration.refusals = Array(repeating: .notPermitted("the job is not allowed to bootstrap"), count: 10)
        let presence = PresenceDouble(.answering)

        let outcome = repair(registration, presence, passes: 1).run()

        XCTAssertEqual(outcome.failure, .notPermitted("the job is not allowed to bootstrap"))
        XCTAssertNil(outcome.answer)
        XCTAssertEqual(registration.registrations, 3, "bounded: the attempts are not a loop")
        XCTAssertEqual(presence.checks, 0, "nothing is registered to ask")
        XCTAssertEqual(registration.removals, 0, "a refusal that survives the attempts is not answered with a removal")
    }

    func testARefusalThatCannotBeRetriedIsReportedAtOnce() {
        let registration = RegistrationDouble()
        registration.refusals = [.invalidSignature]
        let presence = PresenceDouble(.answering)

        let outcome = repair(registration, presence, passes: 1).run()

        XCTAssertEqual(outcome.failure, .invalidSignature)
        XCTAssertEqual(registration.registrations, 1)
        XCTAssertEqual(presence.checks, 0)
    }

    func testAHelperThatWasNeverRegisteredIsStillRegistered() {
        let registration = RegistrationDouble()
        registration.removalFailure = .jobNotFound
        let presence = PresenceDouble(.silent, .answering)

        let outcome = repair(registration, presence).run()

        XCTAssertNil(outcome.failure, "a helper that was never registered is already in the state the removal wants")
        XCTAssertEqual(registration.removals, 1)
        XCTAssertEqual(registration.registrations, 2)
        XCTAssertEqual(outcome.answer, .answering)
    }

    func testARemovalThatFailsStopsThePassBeforeRegisteringAgain() {
        let registration = RegistrationDouble()
        registration.removalFailure = .deniedByUser
        let presence = PresenceDouble(.silent)

        let outcome = repair(registration, presence).run()

        XCTAssertEqual(outcome.failure, .deniedByUser)
        XCTAssertEqual(registration.registrations, 1, "the pass that removed did not register again")
        XCTAssertNil(outcome.answer)
    }

    // MARK: - What it reports

    func testTheReportIsWhatTheHelperSaidRatherThanWhatWasHoped() {
        for answer in [HelperReachability.silent, .refused(reason: "the helper is not running")] {
            let registration = RegistrationDouble()
            let outcome = repair(registration, PresenceDouble(answer), passes: 1).run()

            XCTAssertNil(outcome.failure)
            XCTAssertEqual(outcome.answer, answer)
        }
    }

    func testAHelperThatNeedsApprovalIsReportedByItsStateNotByAQuestion() {
        let registration = RegistrationDouble()
        registration.state = .awaitingApproval
        registration.stateAfterRegistering = .awaitingApproval
        let presence = PresenceDouble(.silent)

        let outcome = repair(registration, presence, passes: 1).run()

        XCTAssertNil(outcome.failure)
        XCTAssertNil(outcome.answer)
        XCTAssertEqual(presence.checks, 0, "an unapproved helper has nothing to answer with")
    }

    func testOnlyTheRefusalsTheSystemMakesWhileRemovingAreRetried() {
        XCTAssertTrue(RegistrationFailure.alreadyRegistered.isRetryable)
        XCTAssertTrue(RegistrationFailure.notPermitted("the job is not allowed to bootstrap").isRetryable)
        XCTAssertFalse(RegistrationFailure.deniedByUser.isRetryable)
        XCTAssertFalse(RegistrationFailure.invalidSignature.isRetryable)
        XCTAssertFalse(RegistrationFailure.jobNotFound.isRetryable)
    }
}
