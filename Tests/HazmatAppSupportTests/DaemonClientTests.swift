import Foundation
import HazmatCore
import XCTest
@testable import HazmatAppSupport

/// The retry around a request: the daemon stops when it has nothing to serve, so
/// the moment a request lands as it stops must not read as a failure.
final class DaemonClientTests: XCTestCase {
    func testARequestIsMadeAgainWhenTheConnectionDiedBeforeAnAnswer() {
        var attempts = 0
        let outcome = attemptedTwice {
            attempts += 1
            return attempts == 1 ? .noReply(reason: "the helper is not running") : .answer(.written)
        }

        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(outcome, .answer(.written))
    }

    func testARefusalIsAnAnswerAndIsNotRepeated() {
        var attempts = 0
        let outcome = attemptedTwice {
            attempts += 1
            return .answer(.refused(reason: "drift"))
        }

        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(outcome, .answer(.refused(reason: "drift")))
    }

    func testAFailureThatRepeatsReportsTheReasonItStartedWith() {
        var attempts = 0
        let outcome = attemptedTwice {
            attempts += 1
            return .noReply(reason: "the helper did not answer in time")
        }

        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(outcome.result, .failed(reason: "the helper did not answer in time"))
    }
}
