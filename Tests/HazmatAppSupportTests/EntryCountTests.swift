import Foundation
import XCTest
@testable import HazmatAppSupport

final class EntryCountTests: XCTestCase {
    func testACountIsSaidInTheRightNumber() {
        XCTAssertEqual(EntryCount.phrase(0), "0 entries")
        XCTAssertEqual(EntryCount.phrase(1), "1 entry")
        XCTAssertEqual(EntryCount.phrase(2), "2 entries")
        XCTAssertEqual(EntryCount.phrase(100), "100 entries")
    }

    func testASixFigureCountKeepsEveryDigitAndReadsAsANumber() {
        // A fetched blocklist runs to six figures, and an unbroken run of them is
        // not a number anyone reads. The separator is the locale's, so this
        // asserts the count is the locale's number rather than which character
        // separates it.
        let phrase = EntryCount.phrase(169_096)

        XCTAssertTrue(phrase.hasSuffix(" entries"), phrase)
        XCTAssertTrue(phrase.hasPrefix(169_096.formatted()), phrase)
        XCTAssertEqual(phrase.filter(\.isNumber), "169096", phrase)
    }
}
