import Foundation
import HazmatCore
import XCTest
@testable import HazmatAppSupport

/// The add-source and edit-source sheet: what it asks for, and why what has been
/// given cannot be used. The refusal is a value on the sheet while the fields
/// are still on screen, not a report after it closes.
final class SourceSheetPresentationTests: XCTestCase {
    func testANewSourceAsksForANameAURLAndAnInterval() {
        let sheet = SourceSheetPresentation(mode: .adding)

        XCTAssertTrue(sheet.asksForAName)
        XCTAssertEqual(sheet.name, "")
        XCTAssertEqual(sheet.url, "")
        XCTAssertEqual(sheet.hours, 24, "the default interval is a day")
        XCTAssertEqual(sheet.interval, RemoteInterval.standard)
        XCTAssertFalse(sheet.isManual)
        XCTAssertFalse(sheet.isUsable, "a source with no name and no URL is not usable")
    }

    func testAnUntouchedSheetSaysWhatIsMissingRatherThanWhatIsWrong() {
        let empty = SourceSheetPresentation(mode: .adding)
        XCTAssertNil(empty.problem, "opening the sheet reports nothing: nothing has been typed yet")
        XCTAssertEqual(empty.hint, "Enter a name and the URL the fragment is fetched from.")

        let named = SourceSheetPresentation(mode: .adding, name: "blocklist")
        XCTAssertNil(named.problem)
        XCTAssertEqual(named.hint, "Enter the URL the fragment is fetched from.")

        let addressed = SourceSheetPresentation(mode: .adding, url: "https://example.com/hosts.txt")
        XCTAssertNil(addressed.problem)
        XCTAssertEqual(addressed.hint, "Enter a name.")

        // A field holding something wrong is reported rather than hinted at.
        let wrong = SourceSheetPresentation(mode: .adding, name: "blocklist", url: "http://example.com/x")
        XCTAssertNil(wrong.hint)
        XCTAssertEqual(wrong.problem, "'http://example.com/x' is not an HTTPS URL. A source is fetched over HTTPS only.")

        // A complete sheet says nothing at all.
        let complete = SourceSheetPresentation(mode: .adding, name: "blocklist", url: "https://example.com/x", hours: 6)
        XCTAssertNil(complete.problem)
        XCTAssertNil(complete.hint)
        XCTAssertTrue(complete.isUsable)
    }

    func testSavingAnIncompleteSheetReportsWhatIsMissing() {
        let empty = SourceSheetPresentation(mode: .adding)
        XCTAssertEqual(empty.validation, "Enter a name.")
        XCTAssertFalse(empty.isUsable)

        let addressed = SourceSheetPresentation(mode: .adding, url: "https://example.com/hosts.txt")
        XCTAssertEqual(addressed.validation, "Enter a name.")

        let named = SourceSheetPresentation(mode: .adding, name: "blocklist")
        XCTAssertEqual(named.validation, "Enter the URL the fragment is fetched from.")
    }

    func testAValidSourceIsUsableAndReportsNoProblem() {
        let sheet = SourceSheetPresentation(
            mode: .adding,
            name: "blocklist",
            url: "https://example.com/hosts.txt?mirror=eu",
            hours: 6
        )

        XCTAssertNil(sheet.validation)
        XCTAssertNil(sheet.problem)
        XCTAssertTrue(sheet.isUsable)
        XCTAssertEqual(sheet.interval, 6 * 3600)
        XCTAssertEqual(sheet.fragment, FragmentID("blocklist"))
    }

    func testANonHTTPSURLIsReportedWithTheURLAndTheRule() {
        for url in ["http://example.com/hosts.txt", "ftp://example.com/hosts.txt", "example.com/hosts.txt"] {
            let sheet = SourceSheetPresentation(mode: .adding, name: "blocklist", url: url, hours: 6)

            XCTAssertFalse(sheet.isUsable, url)
            XCTAssertEqual(
                sheet.problem,
                "'\(url)' is not an HTTPS URL. A source is fetched over HTTPS only.",
                url
            )
        }
    }

    func testAURLThatIsNotAURLSaysWhatToPaste() {
        let sheet = SourceSheetPresentation(mode: .adding, name: "blocklist", url: "ht tp://example.com/x", hours: 6)

        XCTAssertFalse(sheet.isUsable)
        XCTAssertEqual(
            sheet.problem,
            "'ht tp://example.com/x' is not a URL. Paste the address you would open in a browser."
        )
    }

    func testARefusalQuotesWhatWasTypedRatherThanWhatFoundationMadeOfIt() {
        // Foundation percent-encodes a space and a non-ASCII host, so quoting its
        // version would report the field back in a form nobody typed.
        for typed in ["not a url at all", "example.com/a b", "http://例え.jp/x"] {
            let sheet = SourceSheetPresentation(mode: .adding, name: "blocklist", url: typed, hours: 6)
            XCTAssertTrue(sheet.problem?.contains(typed) ?? false, "\(typed): \(sheet.problem ?? "no problem")")
        }
    }

    func testAnIntervalBelowTheFloorIsReportedInMinutesNotSeconds() {
        let sheet = SourceSheetPresentation(mode: .adding, name: "blocklist", url: "https://example.com/hosts.txt", hours: 0.25 / 2)

        XCTAssertFalse(sheet.isUsable)
        XCTAssertEqual(sheet.interval, 450)
        XCTAssertEqual(sheet.problem, "The shortest interval is 15 minutes, so 8 minutes is too often.")

        let negative = SourceSheetPresentation(mode: .adding, name: "blocklist", url: "https://example.com/hosts.txt", hours: -1)
        XCTAssertFalse(negative.isUsable)
        XCTAssertEqual(negative.problem, "An interval cannot be negative.")
    }

    func testManualOnlyAndTheFloorAreBothUsable() {
        let manual = SourceSheetPresentation(
            mode: .adding,
            name: "blocklist",
            url: "https://example.com/hosts.txt",
            isManual: true
        )
        XCTAssertTrue(manual.isUsable)
        XCTAssertEqual(manual.interval, RemoteInterval.manual)

        let floor = SourceSheetPresentation(mode: .adding, name: "blocklist", url: "https://example.com/hosts.txt", hours: 0.25)
        XCTAssertTrue(floor.isUsable)
        XCTAssertEqual(floor.interval, RemoteInterval.floor)
    }

    func testANameOutsideTheGrammarIsReportedWithWhatToChange() {
        let refused: [(name: String, expected: String)] = [
            ("../escape", "A name has to start with a letter or a digit."),
            ("/tmp/blocklist", "A name has to start with a letter or a digit."),
            (" leading", "A name has to start with a letter or a digit."),
            ("-dash", "A name has to start with a letter or a digit."),
            ("a/b", "A name cannot hold '/'. Letters, digits, spaces, '.', '_' and '-' are allowed."),
            ("a:b", "A name cannot hold ':'."),
            ("trackers*", "A name cannot hold '*'."),
            ("trailing ", "A name cannot end with a space."),
            ("a..b", "A name cannot hold '..'."),
            ("éclair", "A name cannot hold that character.")
        ]

        for (name, expected) in refused {
            let sheet = SourceSheetPresentation(mode: .adding, name: name, url: "https://example.com/hosts.txt", hours: 6)

            XCTAssertFalse(sheet.isUsable, name)
            XCTAssertTrue(sheet.problem?.contains(expected) ?? false, "\(name): \(sheet.problem ?? "no problem")")
        }
    }

    func testAnExistingSourceAsksForNoNameAndKeepsItsRefreshState() {
        let source = RemoteSource(
            url: URL(string: "https://example.com/hosts.txt")!,
            interval: 2 * 3600,
            lastAttempt: Date(timeIntervalSince1970: 1_760_000_000),
            lastSuccess: Date(timeIntervalSince1970: 1_760_000_000),
            etag: "\"v1\""
        )

        let sheet = SourceSheetPresentation.editing(FragmentID("blocklist"), source)

        XCTAssertFalse(sheet.asksForAName)
        XCTAssertEqual(sheet.name, "blocklist")
        XCTAssertEqual(sheet.url, "https://example.com/hosts.txt")
        XCTAssertEqual(sheet.hours, 2)
        XCTAssertFalse(sheet.isManual)
        XCTAssertTrue(sheet.isUsable)
        XCTAssertEqual(sheet.fragment, FragmentID("blocklist"))
    }

    func testAnExistingManualSourceOpensWithManualOnlyOn() {
        let source = RemoteSource(url: URL(string: "https://example.com/hosts.txt")!, interval: RemoteInterval.manual)

        let sheet = SourceSheetPresentation.editing(FragmentID("blocklist"), source)

        XCTAssertTrue(sheet.isManual)
        XCTAssertEqual(sheet.interval, RemoteInterval.manual)
        XCTAssertTrue(sheet.isUsable)
    }

    func testAStoresRefusalIsShownInTheSheetAndOutlivesNothingItWasAbout() {
        let base = SourceSheetPresentation(mode: .adding, name: "blocklist", url: "https://example.com/hosts.txt", hours: 6)
        XCTAssertNil(base.problem)

        let refused = base.reporting("the store already holds 'blocklist'")
        XCTAssertEqual(refused.problem, "the store already holds 'blocklist'")
        XCTAssertNil(refused.hint, "the fields are filled in; the refusal is what stands in the way")
        XCTAssertEqual(refused.name, "blocklist", "everything that was typed is kept")
        XCTAssertEqual(refused.url, "https://example.com/hosts.txt")
        XCTAssertFalse(refused.isUsable)

        // A refusal about the fields is the one the sheet shows, even when a
        // store refusal is on it too.
        var wrongURL = refused
        wrongURL.url = "http://example.com/hosts.txt"
        XCTAssertTrue(wrongURL.problem?.contains("HTTPS") ?? false, wrongURL.problem ?? "no problem")
    }
}
