import CryptoKit
import Foundation

/// The identity of some bytes: a SHA-256 of them. Two blocks with one digest
/// are one block for every purpose here — what an apply names as the block it
/// replaces, what a profile's rendering is compared against, what drift
/// carries — so the bytes themselves need not be kept to say which block they
/// were.
///
/// Built from any contiguous or sliced bytes, so a slice of the live file is
/// digested without being copied out first.
public struct ByteDigest: Hashable, Sendable {
    private let bytes: [UInt8]

    public init(_ data: some DataProtocol) {
        bytes = Array(SHA256.hash(data: data))
    }
}
