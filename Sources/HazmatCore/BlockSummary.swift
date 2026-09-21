import Foundation

/// What is kept of a rendered block once its bytes are let go: the digest
/// that says which block it is, and how many entries it holds. It answers
/// everything asked of a block that is not shown or written — whether the
/// live block is this one, what an apply would count — in 40 bytes.
public struct BlockSummary: Hashable, Sendable {
    public let digest: ByteDigest
    public let entryCount: Int

    public init(digest: ByteDigest, entryCount: Int) {
        self.digest = digest
        self.entryCount = entryCount
    }

    public init(rendering: Data) {
        self.init(digest: ByteDigest(rendering), entryCount: BlockRenderer.entryCount(in: rendering))
    }
}
