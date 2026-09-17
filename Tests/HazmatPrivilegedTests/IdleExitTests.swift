import Dispatch
import XCTest
@testable import HazmatPrivileged

/// The daemon does not outlive its usefulness: with nothing to serve it stops, so
/// a build that has been replaced is not the one answering the next request.
final class IdleExitTests: XCTestCase {
    func testItStopsAfterTheIdlePeriodWithNothingOpen() {
        let stopped = expectation(description: "the daemon stops")
        let idle = IdleExit(after: .milliseconds(50)) { stopped.fulfill() }

        idle.connectionOpened()
        idle.connectionClosed()

        wait(for: [stopped], timeout: 2)
    }

    func testAnOpenConnectionKeepsItAlive() {
        let stopped = expectation(description: "the daemon stops")
        stopped.isInverted = true
        let idle = IdleExit(after: .milliseconds(50)) { stopped.fulfill() }

        idle.connectionOpened()

        wait(for: [stopped], timeout: 0.3)
    }

    func testANewConnectionCancelsTheCountdown() {
        let stopped = expectation(description: "the daemon stops")
        stopped.isInverted = true
        let idle = IdleExit(after: .milliseconds(150)) { stopped.fulfill() }

        idle.connectionOpened()
        idle.connectionClosed()
        idle.connectionOpened()

        wait(for: [stopped], timeout: 0.4)
    }

    func testItStartsCountingAgainAfterServingAnotherRequest() {
        let stopped = expectation(description: "the daemon stops")
        let idle = IdleExit(after: .milliseconds(50)) { stopped.fulfill() }

        idle.connectionOpened()
        idle.connectionClosed()
        idle.connectionOpened()
        idle.connectionClosed()

        wait(for: [stopped], timeout: 2)
    }
}
