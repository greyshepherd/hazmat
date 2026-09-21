import Foundation
import XCTest
@testable import HazmatCore

/// A digest names bytes: the same bytes have one digest however they are held,
/// and bytes that differ anywhere have another.
final class ByteDigestTests: XCTestCase {
    func testEqualBytesHaveTheSameDigest() {
        XCTAssertEqual(ByteDigest(Data("127.0.0.1 localhost\n".utf8)), ByteDigest(Data("127.0.0.1 localhost\n".utf8)))
    }

    func testBytesOfTheSameLengthThatDifferHaveDifferentDigests() {
        XCTAssertNotEqual(ByteDigest(Data("127.0.0.1 localhost\n".utf8)), ByteDigest(Data("127.0.0.2 localhost\n".utf8)))
    }

    func testASliceDigestsAsTheBytesItHolds() {
        let whole = Data("prefix\n127.0.0.1 localhost\nsuffix\n".utf8)
        let range = 7..<(7 + "127.0.0.1 localhost\n".utf8.count)

        XCTAssertEqual(ByteDigest(whole[range]), ByteDigest(Data("127.0.0.1 localhost\n".utf8)))
    }

    func testTheEmptyBytesHaveADigest() {
        XCTAssertEqual(ByteDigest(Data()), ByteDigest(Data()))
        XCTAssertNotEqual(ByteDigest(Data()), ByteDigest(Data([0])))
    }
}
