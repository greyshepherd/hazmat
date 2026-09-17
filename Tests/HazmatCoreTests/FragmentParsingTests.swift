import XCTest
@testable import HazmatCore

final class FragmentParsingTests: XCTestCase {
    private let base = FragmentID("base")

    func testAddressHostNameAndAliases() throws {
        let outcome = FragmentParser.parse("127.0.0.1\tapi.example.com api api2\n", as: base)

        XCTAssertEqual(outcome.problems, [])
        let entry = try XCTUnwrap(outcome.fragment.entries.first)
        XCTAssertEqual(entry.address, "127.0.0.1")
        XCTAssertEqual(entry.family, .ipv4)
        XCTAssertEqual(entry.primaryName, "api.example.com")
        XCTAssertEqual(entry.aliases, ["api", "api2"])
        XCTAssertEqual(entry.source, SourceLocation(fragment: base, line: 1))
    }

    func testCommentsBlankLinesAndMixedWhitespaceContributeNoEntries() {
        let source = "# a comment with  trailing spaces   \n"
            + "\n"
            + "   \t \n"
            + "127.0.0.1\tlocalhost   localhost.localdomain\n"
            + "\t::1\tlocalhost\n"
            + "   # an indented comment\n"

        let outcome = FragmentParser.parse(source, as: base)

        XCTAssertEqual(outcome.problems, [])
        XCTAssertEqual(outcome.fragment.entries.count, 2)
        XCTAssertEqual(outcome.fragment.entries[0].names, ["localhost", "localhost.localdomain"])
        XCTAssertEqual(outcome.fragment.entries[0].source.line, 4)
        XCTAssertEqual(outcome.fragment.entries[1].address, "::1")
        XCTAssertEqual(outcome.fragment.entries[1].source.line, 5)
    }

    func testInlineCommentEndsTheEntry() throws {
        let outcome = FragmentParser.parse("127.0.0.1 localhost # the loopback interface\n", as: base)

        XCTAssertEqual(outcome.problems, [])
        let entry = try XCTUnwrap(outcome.fragment.entries.first)
        XCTAssertEqual(entry.names, ["localhost"])
    }

    func testIPv6FormsIncludingAZone() throws {
        let source = "::1 loopback\n"
            + "fe80::1%lo0 linklocal\n"
            + "::ffff:192.168.0.1 mapped\n"
            + "2001:0db8:85a3:0000:0000:8a2e:0370:7334 long.example\n"

        let outcome = FragmentParser.parse(source, as: base)

        XCTAssertEqual(outcome.problems, [])
        XCTAssertEqual(outcome.fragment.entries.map(\.family), [.ipv6, .ipv6, .ipv6, .ipv6])
        XCTAssertEqual(outcome.fragment.entries[1].address, "fe80::1%lo0")
    }

    func testInvalidAddressesAndNamesAreRefused() {
        let source = "010.0.0.1 host.example\n"
            + "1.2.3.4.5 host.example\n"
            + "1::2::3 host.example\n"
            + "127.0.0.1 bad*name\n"

        let outcome = FragmentParser.parse(source, as: base)

        XCTAssertEqual(outcome.fragment.items, [])
        XCTAssertEqual(outcome.problems.count, 4)
        XCTAssertEqual(outcome.problems[0], .malformedEntry(fragment: base, line: 1, text: "010.0.0.1 host.example", detail: .invalidAddress("010.0.0.1")))
        XCTAssertEqual(outcome.problems[1], .malformedEntry(fragment: base, line: 2, text: "1.2.3.4.5 host.example", detail: .invalidAddress("1.2.3.4.5")))
        XCTAssertEqual(outcome.problems[2], .malformedEntry(fragment: base, line: 3, text: "1::2::3 host.example", detail: .invalidAddress("1::2::3")))
        XCTAssertEqual(outcome.problems[3], .malformedEntry(fragment: base, line: 4, text: "127.0.0.1 bad*name", detail: .invalidHostName("bad*name")))
    }

    func testRemovalDirectiveYieldsARemovalAndNoEntry() {
        let source = "0.0.0.0 ads.example.com\n"
            + "# hazmat:remove ads.example.com\n"

        let outcome = FragmentParser.parse(source, as: base)

        XCTAssertEqual(outcome.problems, [])
        XCTAssertEqual(
            outcome.fragment.removals,
            [Removal(name: "ads.example.com", source: SourceLocation(fragment: base, line: 2))]
        )
        XCTAssertEqual(outcome.fragment.entries.map(\.primaryName), ["ads.example.com"])
        XCTAssertFalse(outcome.fragment.entries.contains { $0.source.line == 2 })
    }

    func testEveryMalformedLineIsReportedInOneResult() {
        let source = "127.0.0.1\n"
            + "not-an-address host.example\n"
            + "127.0.0.1 bad*name\n"
            + "# hazmat:remove\n"
            + "# hazmat:blocklist ads.example.com\n"
            + "127.0.0.1 dup.example dup.example\n"

        let outcome = FragmentParser.parse(source, as: base)

        XCTAssertEqual(outcome.fragment.items, [])
        XCTAssertEqual(outcome.problems, [
            .malformedEntry(fragment: base, line: 1, text: "127.0.0.1", detail: .missingName),
            .malformedEntry(fragment: base, line: 2, text: "not-an-address host.example", detail: .invalidAddress("not-an-address")),
            .malformedEntry(fragment: base, line: 3, text: "127.0.0.1 bad*name", detail: .invalidHostName("bad*name")),
            .malformedEntry(fragment: base, line: 4, text: "# hazmat:remove", detail: .malformedRemovalDirective("# hazmat:remove")),
            .malformedEntry(fragment: base, line: 5, text: "# hazmat:blocklist ads.example.com", detail: .unknownDirective("hazmat:blocklist")),
            .malformedEntry(fragment: base, line: 6, text: "127.0.0.1 dup.example dup.example", detail: .duplicateHostName("dup.example"))
        ])
    }

    func testCompositionReportsEveryMalformedLineOfAFragmentAtOnce() {
        let source = "127.0.0.1\n"
            + "127.0.0.1 bad*name\n"
            + "127.0.0.1 dup.example dup.example\n"
        let store = InMemoryStore(
            fragments: [base: source],
            profiles: [ProfileID("work"): "base\n"]
        )

        let problems = compositionProblems(store, ProfileID("work"))

        XCTAssertEqual(problems.count, 3)
        XCTAssertEqual(problems.map(\.message), [
            "fragment 'base' line 1: the line has an address but no host name",
            "fragment 'base' line 2: 'bad*name' is not a valid host name",
            "fragment 'base' line 3: 'dup.example' appears twice on the line"
        ])
    }

    func testTrailingCommentOnARemovalDirectiveIsRefusedRatherThanGuessed() {
        let outcome = FragmentParser.parse("# hazmat:remove ads.example.com # because\n", as: base)

        XCTAssertEqual(outcome.fragment.items, [])
        XCTAssertEqual(outcome.problems.count, 1)
        XCTAssertEqual(
            outcome.problems.first,
            .malformedEntry(
                fragment: base,
                line: 1,
                text: "# hazmat:remove ads.example.com # because",
                detail: .malformedRemovalDirective("# hazmat:remove ads.example.com # because")
            )
        )
    }
}
