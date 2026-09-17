import Darwin
import Foundation
import XCTest
@testable import HazmatCore

/// The derivation is a function of bytes: it answers from the file as it is,
/// reports what it cannot render, and touches nothing.
final class ActivationTests: XCTestCase {
    private let work = ProfileID("work")

    private func rendered(_ entries: String) throws -> Data {
        let fragments: [(String, String)] = [("base", entries)]
        return BlockRenderer.render(try composition(fragments: fragments, profile: "base\n"))
    }

    private func renderedEmptyProfile() throws -> Data {
        BlockRenderer.render(try composition(fragments: [(String, String)](), profile: ""))
    }

    // MARK: - 1.1 Every state

    func testReportsOffWhenTheFileHoldsNoBlock() throws {
        let live = try shippedHosts()

        let result = Activation.match(live: live, renders: [ProfileRender(profile: work, rendering: .block(try rendered("127.0.0.1\tlocalhost\n")))])

        XCTAssertEqual(result.state, .off)
        XCTAssertEqual(result.problems, [])
    }

    func testReportsAnUnreadableBlockWithItsReasonRatherThanDriftOrOff() throws {
        let render = ProfileRender(profile: work, rendering: .block(try rendered("127.0.0.1\tlocalhost\n")))
        let cases: [(Data, BlockError)] = [
            (
                bytes("# >>> hazmat:managed v1 >>>\n# <<< hazmat:managed v1 <<<\n# >>> hazmat:managed v1 >>>\n# <<< hazmat:managed v1 <<<\n"),
                .multipleBlocks(firstLine: 1, secondLine: 3)
            ),
            (
                bytes("# >>> hazmat:managed v2 >>>\n127.0.0.1 localhost\n# <<< hazmat:managed v2 <<<\n"),
                .unsupportedVersion(found: 2, expected: 1)
            ),
            (
                bytes("# >>> hazmat:managed v1\n127.0.0.1 localhost\n"),
                .malformedMarker(line: 1, text: "# >>> hazmat:managed v1")
            ),
            (bytes("# >>> hazmat:managed v1 >>>\n127.0.0.1 localhost\n"), .unterminatedBlock(line: 1))
        ]

        for (live, error) in cases {
            let result = Activation.match(live: live, renders: [render])
            XCTAssertEqual(result.state, .unreadable(error), text(live))
        }
    }

    func testAProfileRenderingIdenticalBytesIsActive() throws {
        let block = try rendered("127.0.0.1\tlocalhost hazmat.local\n")

        let result = Activation.match(live: block, renders: [ProfileRender(profile: work, rendering: .block(block))])

        XCTAssertEqual(result.state, .active([work]))
    }

    func testTwoProfilesRenderingTheSameBytesBothMatch() throws {
        let block = try rendered("127.0.0.1\tlocalhost\n")
        let second = ProfileID("second")

        let result = Activation.match(
            live: block,
            renders: [
                ProfileRender(profile: work, rendering: .block(block)),
                ProfileRender(profile: second, rendering: .block(block))
            ]
        )

        XCTAssertEqual(result.state, .active([second, work]))
    }

    func testAProfileRenderingAnEmptyBlockIsActiveRatherThanOff() throws {
        let empty = try renderedEmptyProfile()
        let render = ProfileRender(profile: work, rendering: .block(empty))

        XCTAssertEqual(Activation.match(live: empty, renders: [render]).state, .active([work]))
        // The same bytes with nothing rendering them are a block no profile owns.
        XCTAssertEqual(Activation.match(live: empty, renders: []).state, .drifted)
    }

    func testABlockMatchingNoRenderingIsDriftedAndNamesNoProfile() throws {
        let block = try rendered("127.0.0.1\tlocalhost\n")
        let otherProfile = try rendered("10.0.0.9\tlocalhost\n")

        let result = Activation.match(live: block, renders: [ProfileRender(profile: work, rendering: .block(otherProfile))])

        XCTAssertEqual(result.state, .drifted)
    }

    // MARK: - 1.2 A profile that cannot render is reported

    func testABrokenProfileIsReportedAlongsideAMatchingOne() throws {
        let block = try rendered("127.0.0.1\tlocalhost\n")
        let broken = ProfileID("broken")
        let reason = "profile 'broken' line 1: fragment 'missing' is not in the store"

        let result = Activation.match(
            live: block,
            renders: [
                ProfileRender(profile: broken, rendering: .problem(reason)),
                ProfileRender(profile: work, rendering: .block(block))
            ]
        )

        XCTAssertEqual(result.state, .active([work]))
        XCTAssertEqual(result.problems, [ProfileRenderProblem(profile: broken, reason: reason)])
    }

    func testABrokenProfileIsUnmatchedRatherThanTheOnlyMatch() throws {
        let block = try rendered("127.0.0.1\tlocalhost\n")

        let result = Activation.match(
            live: block,
            renders: [ProfileRender(profile: work, rendering: .problem("the fragment is malformed"))]
        )

        XCTAssertEqual(result.state, .drifted)
        XCTAssertEqual(result.problems, [ProfileRenderProblem(profile: work, reason: "the fragment is malformed")])
    }

    // MARK: - 1.3 Reading only

    func testDerivingWritesNothingAndNeedsNoPrivilege() throws {
        XCTAssertNotEqual(getuid(), 0, "the derivation must be exercised by an ordinary user")

        let block = try rendered("127.0.0.1\tlocalhost\n")
        let target = try TemporaryHostsFile(block)
        defer { target.remove() }
        let before = try target.snapshot()

        let result = Activation.match(
            live: try LiveHostsFile(url: target.url).read(),
            renders: [ProfileRender(profile: work, rendering: .block(block))]
        )

        XCTAssertEqual(result.state, .active([work]))
        XCTAssertEqual(try target.snapshot(), before, "a derivation may not touch the file it read")
    }

    // MARK: - 1.4 Determinism

    func testDerivingTwiceAndInEitherOrderGivesTheSameAnswer() throws {
        let block = try rendered("127.0.0.1\tlocalhost\n")
        let second = ProfileID("second")
        let broken = ProfileID("broken")
        let renders = [
            ProfileRender(profile: work, rendering: .block(block)),
            ProfileRender(profile: second, rendering: .block(block)),
            ProfileRender(profile: broken, rendering: .problem("the fragment is malformed"))
        ]

        let first = Activation.match(live: block, renders: renders)
        let again = Activation.match(live: block, renders: renders)
        let reversed = Activation.match(live: block, renders: renders.reversed())

        XCTAssertEqual(first.state, .active([second, work]))
        XCTAssertEqual(first, again)
        XCTAssertEqual(first, reversed)
    }
}
