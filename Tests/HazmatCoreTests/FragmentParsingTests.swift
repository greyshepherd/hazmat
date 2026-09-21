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

    /// A fragment's entry count is shown on every row that names it, so it is
    /// counted in place rather than by building the entries to count them.
    func testTheEntryCountIsTheNumberOfEntriesAmongTheItems() {
        let outcome = FragmentParser.parse(
            "127.0.0.1\tlocalhost\n# hazmat:remove docs.internal\n::1\tapi.internal\nbad line\n",
            as: FragmentID("base")
        )

        XCTAssertEqual(outcome.fragment.entryCount, 2)
        XCTAssertEqual(outcome.fragment.entryCount, outcome.fragment.entries.count)
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

    // MARK: - The edge corpus

    /// What one line of the hosts grammar is. The table below is the grammar's
    /// edge corpus: it was written for the byte-level rewrite and kept as the
    /// regression net for it.
    private enum Expected {
        case entry(String, [String])
        case removal(String)
        case problem(String, MalformedEntryDetail)
        case nothing
    }

    func testEveryEdgeLineIsReadAsTheGrammarSays() {
        for (line, expected) in Self.edgeCorpus {
            let outcome = FragmentParser.parse(line, as: base)
            let label = Self.visible(line)
            switch expected {
            case .entry(let address, let names):
                XCTAssertEqual(outcome.problems, [], label)
                XCTAssertEqual(outcome.fragment.entries.map(\.address), [address], label)
                XCTAssertEqual(outcome.fragment.entries.first?.names, names, label)
                XCTAssertEqual(outcome.fragment.entries.first?.source.line, 1, label)
            case .removal(let name):
                XCTAssertEqual(outcome.problems, [], label)
                XCTAssertEqual(outcome.fragment.removals.map(\.name), [name], label)
                XCTAssertEqual(outcome.fragment.entries, [], label)
            case .problem(let text, let detail):
                XCTAssertEqual(outcome.fragment.items, [], label)
                XCTAssertEqual(outcome.problems.count, 1, label)
                guard case .malformedEntry(let fragment, let number, let problemText, let problemDetail)? = outcome.problems.first else {
                    return XCTFail("expected a malformed entry for \(label)")
                }
                XCTAssertEqual(fragment, base, label)
                XCTAssertEqual(number, 1, label)
                XCTAssertEqual(problemText, text, label)
                XCTAssertEqual(problemDetail, detail, label)
            case .nothing:
                XCTAssertEqual(outcome.fragment.items, [], label)
                XCTAssertEqual(outcome.problems, [], label)
            }
        }
        XCTAssertGreaterThan(Self.edgeCorpus.count, 80, "the edge corpus shrank")
    }

    /// The same corpus read as one fragment: every answer keeps the line number
    /// the line was written on. A line ending in a carriage return is left out,
    /// because joining it with `\n` would make the `\r\n` pair that the byte
    /// parser is written to split; `EdgeCaseTests` covers that separately.
    func testTheEdgeCorpusReadAsOneFragmentKeepsItsLineNumbers() {
        let corpus = Self.edgeCorpus.filter { !$0.0.hasSuffix("\r") }
        let outcome = FragmentParser.parse(corpus.map(\.0).joined(separator: "\n"), as: base)

        let expectedEntries = corpus.enumerated().compactMap { index, pair -> Int? in
            guard case .entry = pair.1 else { return nil }
            return index + 1
        }
        XCTAssertEqual(outcome.fragment.entries.map(\.source.line), expectedEntries)

        let expectedRemovals = corpus.enumerated().compactMap { index, pair -> Int? in
            guard case .removal = pair.1 else { return nil }
            return index + 1
        }
        XCTAssertEqual(outcome.fragment.removals.map(\.source.line), expectedRemovals)

        let expectedProblems = corpus.enumerated().compactMap { index, pair -> Int? in
            guard case .problem = pair.1 else { return nil }
            return index + 1
        }
        let problemLines = outcome.problems.compactMap { problem -> Int? in
            guard case .malformedEntry(_, let number, _, _) = problem else { return nil }
            return number
        }
        XCTAssertEqual(problemLines, expectedProblems)
    }

    private static func visible(_ line: String) -> String {
        "'\(line.replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\t", with: "\\t"))'"
    }

    private static let edgeCorpus: [(String, Expected)] = [
        ("", .nothing),
        (" ", .nothing),
        ("\t", .nothing),
        ("   \t   ", .nothing),
        ("#", .nothing),
        ("# a comment with  trailing spaces   ", .nothing),
        ("   # an indented comment", .nothing),
        ("\t# tabbed comment", .nothing),
        ("#hazmat:remove ads.example.com", .removal("ads.example.com")),
        ("# hazmat:remove ads.example.com", .removal("ads.example.com")),
        ("# hazmat:remove  ads.example.com", .removal("ads.example.com")),
        ("# hazmat:remove\tads.example.com", .removal("ads.example.com")),
        ("# hazmat:remove ads.example.com ", .removal("ads.example.com")),
        ("# hazmat:remove ads.example.com extra", .problem("# hazmat:remove ads.example.com extra", .malformedRemovalDirective("# hazmat:remove ads.example.com extra"))),
        ("# hazmat:remove", .problem("# hazmat:remove", .malformedRemovalDirective("# hazmat:remove"))),
        ("# hazmat:remove bad*name", .problem("# hazmat:remove bad*name", .invalidHostName("bad*name"))),
        ("# hazmat:remove ads.example.com # because", .problem("# hazmat:remove ads.example.com # because", .malformedRemovalDirective("# hazmat:remove ads.example.com # because"))),
        ("# hazmat:blocklist ads.example.com", .problem("# hazmat:blocklist ads.example.com", .unknownDirective("hazmat:blocklist"))),
        ("# hazmat:", .problem("# hazmat:", .unknownDirective("hazmat:"))),
        ("# >>> hazmat:managed v1 >>>", .nothing),
        ("# >>> hazmat:managed v1", .nothing),
        ("#hazmat:unknown directive", .problem("#hazmat:unknown directive", .unknownDirective("hazmat:unknown"))),

        ("0.0.0.0 zero.example", .entry("0.0.0.0", ["zero.example"])),
        ("255.255.255.255 broadcast.example", .entry("255.255.255.255", ["broadcast.example"])),
        ("256.0.0.1 bad.example", .problem("256.0.0.1 bad.example", .invalidAddress("256.0.0.1"))),
        ("1.2.3 bad.example", .problem("1.2.3 bad.example", .invalidAddress("1.2.3"))),
        ("1.2.3.4.5 bad.example", .problem("1.2.3.4.5 bad.example", .invalidAddress("1.2.3.4.5"))),
        ("1.2.3.4 bad.example", .entry("1.2.3.4", ["bad.example"])),
        ("010.0.0.1 leading-zero.example", .problem("010.0.0.1 leading-zero.example", .invalidAddress("010.0.0.1"))),
        ("0.0.00.1 leading-zero.example", .problem("0.0.00.1 leading-zero.example", .invalidAddress("0.0.00.1"))),
        ("0.0.0.01 leading-zero.example", .problem("0.0.0.01 leading-zero.example", .invalidAddress("0.0.0.01"))),
        ("1.2.3.4", .problem("1.2.3.4", .missingName)),
        ("not-an-address host.example", .problem("not-an-address host.example", .invalidAddress("not-an-address"))),
        ("1.2.3.4 5.6.7.8 host.example", .entry("1.2.3.4", ["5.6.7.8", "host.example"])),
        ("1.2.3.4\t\thost.example", .entry("1.2.3.4", ["host.example"])),
        ("  1.2.3.4   host.example   ", .entry("1.2.3.4", ["host.example"])),
        ("\t1.2.3.4\thost.example", .entry("1.2.3.4", ["host.example"])),
        ("1.2.3.-1 bad.example", .problem("1.2.3.-1 bad.example", .invalidAddress("1.2.3.-1"))),
        ("1.2.3.+1 bad.example", .problem("1.2.3.+1 bad.example", .invalidAddress("1.2.3.+1"))),
        ("1.2.3.4. bad.example", .problem("1.2.3.4. bad.example", .invalidAddress("1.2.3.4."))),
        ("1..3.4 bad.example", .problem("1..3.4 bad.example", .invalidAddress("1..3.4"))),
        ("1.2.3.4#inline.example", .problem("1.2.3.4#inline.example", .missingName)),

        (":: loopback", .entry("::", ["loopback"])),
        ("::1 loopback", .entry("::1", ["loopback"])),
        ("fe80::1%lo0 linklocal", .entry("fe80::1%lo0", ["linklocal"])),
        ("fe80::1% linklocal", .problem("fe80::1% linklocal", .invalidAddress("fe80::1%"))),
        ("fe80::1%lo0.eth zone.example", .entry("fe80::1%lo0.eth", ["zone.example"])),
        ("fe80::1%lo-0_1 zone.example", .entry("fe80::1%lo-0_1", ["zone.example"])),
        ("fe80::1%* zone.example", .problem("fe80::1%* zone.example", .invalidAddress("fe80::1%*"))),
        ("::ffff:192.168.0.1 mapped", .entry("::ffff:192.168.0.1", ["mapped"])),
        ("::ffff:999.168.0.1 mapped", .problem("::ffff:999.168.0.1 mapped", .invalidAddress("::ffff:999.168.0.1"))),
        ("::ffff:1.2.3.4.5 mapped", .problem("::ffff:1.2.3.4.5 mapped", .invalidAddress("::ffff:1.2.3.4.5"))),
        ("1::2::3 bad.example", .problem("1::2::3 bad.example", .invalidAddress("1::2::3"))),
        ("1::2:3:4:5:6:7:8 too-many.example", .problem("1::2:3:4:5:6:7:8 too-many.example", .invalidAddress("1::2:3:4:5:6:7:8"))),
        ("1:2:3:4:5:6:7:8 exact.example", .entry("1:2:3:4:5:6:7:8", ["exact.example"])),
        ("1:2:3:4:5:6:7 too-few.example", .problem("1:2:3:4:5:6:7 too-few.example", .invalidAddress("1:2:3:4:5:6:7"))),
        ("1:2:3:4:5:6:7:8:9 too-many.example", .problem("1:2:3:4:5:6:7:8:9 too-many.example", .invalidAddress("1:2:3:4:5:6:7:8:9"))),
        ("g::1 bad.example", .problem("g::1 bad.example", .invalidAddress("g::1"))),
        ("1:2:3:4:5:6:7:g bad.example", .problem("1:2:3:4:5:6:7:g bad.example", .invalidAddress("1:2:3:4:5:6:7:g"))),
        ("12345::1 long-group.example", .problem("12345::1 long-group.example", .invalidAddress("12345::1"))),
        ("2001:0db8:85a3:0000:0000:8a2e:0370:7334 long.example", .entry("2001:0db8:85a3:0000:0000:8a2e:0370:7334", ["long.example"])),
        ("::%en0 empty-head.example", .entry("::%en0", ["empty-head.example"])),
        (":::%en0 bad.example", .problem(":::%en0 bad.example", .invalidAddress(":::%en0"))),
        ("1:2:3:4:5:6:1.2.3.4 embedded.example", .entry("1:2:3:4:5:6:1.2.3.4", ["embedded.example"])),
        ("1:2:3:4:5:6:7:1.2.3.4 embedded-too-many.example", .problem("1:2:3:4:5:6:7:1.2.3.4 embedded-too-many.example", .invalidAddress("1:2:3:4:5:6:7:1.2.3.4"))),

        ("127.0.0.1 dup.example dup.example", .problem("127.0.0.1 dup.example dup.example", .duplicateHostName("dup.example"))),
        ("127.0.0.1 ok.example OK.example", .entry("127.0.0.1", ["ok.example", "OK.example"])),
        ("127.0.0.1 bad*name", .problem("127.0.0.1 bad*name", .invalidHostName("bad*name"))),
        ("127.0.0.1 ünicode.example", .problem("127.0.0.1 ünicode.example", .invalidHostName("ünicode.example"))),
        ("127.0.0.1 café.example", .problem("127.0.0.1 café.example", .invalidHostName("café.example"))),
        ("127.0.0.1 -leading.example", .entry("127.0.0.1", ["-leading.example"])),
        ("127.0.0.1 under_score.example", .entry("127.0.0.1", ["under_score.example"])),
        ("127.0.0.1 dot..dot.example", .entry("127.0.0.1", ["dot..dot.example"])),
        ("127.0.0.1 a b c", .entry("127.0.0.1", ["a", "b", "c"])),
        ("127.0.0.1 \tname.example", .entry("127.0.0.1", ["name.example"])),
        ("127.0.0.1  ", .problem("127.0.0.1  ", .missingName)),
        ("127.0.0.1", .problem("127.0.0.1", .missingName)),
        ("127.0.0.1 # only a comment", .problem("127.0.0.1 # only a comment", .missingName)),
        ("127.0.0.1#host.example", .problem("127.0.0.1#host.example", .missingName)),
        ("127.0.0.1\thost.example # c", .entry("127.0.0.1", ["host.example"])),
        ("127.0.0.1 host.example#c", .entry("127.0.0.1", ["host.example"])),

        ("127.0.0.1 host.example\r", .entry("127.0.0.1", ["host.example"])),
        ("127.0.0.1\rhost.example", .problem("127.0.0.1\rhost.example", .invalidAddress("127.0.0.1\rhost.example"))),
        ("\r", .nothing),
        ("\r127.0.0.1 host.example", .entry("127.0.0.1", ["host.example"]))
    ]
}
