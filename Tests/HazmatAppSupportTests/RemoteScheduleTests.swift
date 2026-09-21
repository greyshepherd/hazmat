import Foundation
import HazmatCore
import XCTest
@testable import HazmatAppSupport

final class RemoteScheduleTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    private func source(
        interval: TimeInterval,
        lastAttempt: Date? = nil,
        lastSuccess: Date? = nil
    ) -> RemoteSource {
        RemoteSource(
            url: URL(string: "https://example.com/hosts.txt")!,
            interval: interval,
            lastAttempt: lastAttempt,
            lastSuccess: lastSuccess
        )
    }

    private func at(_ offset: TimeInterval) -> Date {
        start.addingTimeInterval(offset)
    }

    private let hour: TimeInterval = 3600

    // MARK: - 3.1 When a source is due

    func testASourceThatHasNeverBeenContactedIsDueAtOnce() {
        XCTAssertTrue(RemoteSchedule.isDue(source(interval: 24 * hour), at: start))
        XCTAssertTrue(RemoteSchedule.isDue(source(interval: RemoteInterval.floor), at: start))
    }

    func testAnIntervalOfZeroIsNeverDue() {
        for interval in [RemoteInterval.manual] {
            XCTAssertFalse(RemoteSchedule.isDue(source(interval: interval), at: start))
            XCTAssertFalse(RemoteSchedule.isDue(source(interval: interval, lastSuccess: at(-100 * hour)), at: start))
            XCTAssertFalse(RemoteSchedule.isDue(source(interval: interval, lastAttempt: at(-100 * hour)), at: start))
        }
    }

    func testDueTurnsOnTheIntervalElapsingSinceTheLastSuccess() {
        let overdue = source(interval: 6 * hour, lastSuccess: at(-7 * hour))
        XCTAssertTrue(RemoteSchedule.isDue(overdue, at: start))

        let fresh = source(interval: 6 * hour, lastSuccess: at(-1 * hour))
        XCTAssertFalse(RemoteSchedule.isDue(fresh, at: start), "not yet")

        let exactly = source(interval: 6 * hour, lastSuccess: at(-6 * hour))
        XCTAssertTrue(RemoteSchedule.isDue(exactly, at: start), "the interval has elapsed at exactly its length")
    }

    func testAFailedAttemptWaitsOutTheIntervalLikeASuccessfulOne() {
        // A success long ago, and a failure a moment ago: the failure resets the
        // waiting, so a source that is down is not fetched again inside the
        // interval.
        let failed = source(interval: 6 * hour, lastAttempt: at(-60), lastSuccess: at(-100 * hour))
        XCTAssertFalse(RemoteSchedule.isDue(failed, at: start))

        XCTAssertTrue(RemoteSchedule.isDue(failed, at: at(6 * hour)))
    }

    func testAFailedFirstFetchStillWaitsOutTheInterval() {
        let failed = source(interval: 6 * hour, lastAttempt: at(-1 * hour))
        XCTAssertFalse(RemoteSchedule.isDue(failed, at: start))
        XCTAssertTrue(RemoteSchedule.isDue(failed, at: at(5 * hour)))
    }

    func testDueIsReadOverATableOfIntervalsAndContacts() {
        let table: [(interval: TimeInterval, attempt: Date?, success: Date?, elapsed: TimeInterval, due: Bool)] = [
            (24 * hour, nil, nil, 0, true),
            (24 * hour, nil, nil, 100 * hour, true),
            (24 * hour, nil, at(-1 * hour), 0, false),
            (24 * hour, nil, at(-23 * hour), 0, false),
            (24 * hour, nil, at(-25 * hour), 0, true),
            (24 * hour, at(-1 * hour), nil, 0, false),
            (24 * hour, at(-25 * hour), nil, 0, true),
            (24 * hour, at(-1 * hour), at(-100 * hour), 0, false),
            (24 * hour, at(-25 * hour), at(-100 * hour), 0, true),
            (RemoteInterval.floor, at(-10 * 60), nil, 0, false),
            (RemoteInterval.floor, at(-20 * 60), nil, 0, true),
            (RemoteInterval.manual, nil, at(-1000 * hour), 0, false),
            (RemoteInterval.manual, at(-1000 * hour), nil, 0, false)
        ]

        for row in table {
            let due = RemoteSchedule.isDue(
                source(interval: row.interval, lastAttempt: row.attempt, lastSuccess: row.success),
                at: at(row.elapsed)
            )
            XCTAssertEqual(
                due,
                row.due,
                "interval \(row.interval) attempt \(String(describing: row.attempt)) success \(String(describing: row.success))"
            )
        }
    }

    func testOutOfDateFollowsTheLastSuccessAndTheInterval() {
        XCTAssertTrue(RemoteSchedule.isOutOfDate(source(interval: 6 * hour), at: start), "never refreshed")
        XCTAssertFalse(RemoteSchedule.isOutOfDate(source(interval: 6 * hour, lastSuccess: at(-1 * hour)), at: start))
        XCTAssertTrue(RemoteSchedule.isOutOfDate(source(interval: 6 * hour, lastSuccess: at(-7 * hour)), at: start))
        XCTAssertFalse(
            RemoteSchedule.isOutOfDate(source(interval: RemoteInterval.manual, lastSuccess: at(-100 * hour)), at: start),
            "a manual source has nothing to be out of date against"
        )
        XCTAssertTrue(RemoteSchedule.isOutOfDate(source(interval: RemoteInterval.manual), at: start))
        XCTAssertTrue(
            RemoteSchedule.isOutOfDate(source(interval: 6 * hour, lastAttempt: at(-60)), at: start),
            "an attempt that failed is not a refresh"
        )
    }

    func testASourceThatIsNotDueMayStillBeOutOfDate() {
        let failed = source(interval: 6 * hour, lastAttempt: at(-60), lastSuccess: at(-100 * hour))
        XCTAssertFalse(RemoteSchedule.isDue(failed, at: start))
        XCTAssertTrue(RemoteSchedule.isOutOfDate(failed, at: start))
    }

    // MARK: - 3.2 The default, the floor, and manual

    func testTheDefaultIsADayTheFloorIsAQuarterOfAnHourAndZeroIsManual() {
        XCTAssertEqual(RemoteInterval.standard, 24 * 60 * 60)
        XCTAssertEqual(RemoteInterval.floor, 15 * 60)
        XCTAssertEqual(RemoteInterval.manual, 0)
        XCTAssertEqual(RemoteInterval.describe(RemoteInterval.standard), "24 hours")
        XCTAssertEqual(RemoteInterval.describe(RemoteInterval.floor), "15 minutes")
    }

    func testAnIntervalBelowTheFloorIsRefusedWithAReasonAndZeroIsAccepted() {
        let acceptedLengths: [TimeInterval] = [RemoteInterval.manual, RemoteInterval.floor, RemoteInterval.standard, 7 * 24 * 3600]
        for accepted in acceptedLengths {
            XCTAssertNil(RemoteInterval.refusal(for: accepted), "\(accepted) is usable")
            XCTAssertTrue(RemoteInterval.isAcceptable(accepted))
        }

        let refusedLengths: [TimeInterval] = [1, 60, RemoteInterval.floor - 1]
        for refused in refusedLengths {
            let reason = RemoteInterval.refusal(for: refused)
            XCTAssertNotNil(reason, "\(refused) is below the floor")
            XCTAssertTrue(reason?.contains("15 minutes") ?? false, reason ?? "no reason")
        }

        // A length is described in the unit a person would say it in, rounded
        // rather than truncated: 450 seconds is eight minutes, not "450 seconds".
        XCTAssertEqual(RemoteInterval.refusal(for: 6 * 60), "The shortest interval is 15 minutes, so 6 minutes is too often.")
        XCTAssertEqual(RemoteInterval.refusal(for: 450), "The shortest interval is 15 minutes, so 8 minutes is too often.")
        XCTAssertEqual(RemoteInterval.refusal(for: -60), "An interval cannot be negative.")
        XCTAssertEqual(RemoteInterval.refusal(for: .infinity), "An interval has to be a length of time.")
        XCTAssertEqual(RemoteInterval.describe(2 * 3600), "2 hours")
        XCTAssertEqual(RemoteInterval.describe(90 * 60), "90 minutes")
        XCTAssertEqual(RemoteInterval.describe(45), "45 seconds")
    }

    func testAnUnconfiguredIntervalTakesTheDefault() {
        XCTAssertEqual(RemoteInterval.length(from: nil), RemoteInterval.standard)
        XCTAssertEqual(RemoteInterval.length(from: RemoteInterval.manual), RemoteInterval.manual)
        XCTAssertEqual(RemoteInterval.length(from: 2 * 3600), 2 * 3600)
    }
}
