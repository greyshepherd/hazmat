import Foundation

/// Reads a file whole. A file of `pageThreshold` bytes or more is read into
/// anonymous pages the kernel takes back the moment the `Data` dies; a
/// smaller one is read the ordinary way. What malloc frees it keeps — a freed
/// block the size of the hosts file stays with the process, dirty, until
/// something the same size asks for it — and a read that repeats every
/// refresh must not leave one behind each time.
///
/// Anonymous pages rather than a mapping of the file itself: a mapping raises
/// `SIGBUS` when the file is truncated underneath a parse, and a copy in pages
/// of its own has no failure a plain read does not.
public enum FileBytes {
    /// The size from which a file is read into pages of its own: 128 KiB,
    /// above the largest block malloc serves from a magazine.
    public static let pageThreshold = 128 << 10

    public static func read(_ url: URL) throws -> Data {
        try read(url, sizing: { try Self.size(of: $0) })
    }

    /// The seam a test grows a file through: `sizing` answers the file's size
    /// before its bytes are read.
    static func read(_ url: URL, sizing: (URL) throws -> Int) throws -> Data {
        let size = try sizing(url)
        guard size >= pageThreshold else { return try Data(contentsOf: url) }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let pages = mmap(nil, size, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0), pages != MAP_FAILED else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }

        var filled = 0
        while filled < size {
            let got = Darwin.read(handle.fileDescriptor, pages.advanced(by: filled), size - filled)
            if got < 0 {
                munmap(pages, size)
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            if got == 0 { break }
            filled += got
        }

        // A file that grew since its size was asked has bytes past the pages;
        // rather than hand back a prefix, read it again the ordinary way.
        var probe: UInt8 = 0
        if filled == size, Darwin.read(handle.fileDescriptor, &probe, 1) > 0 {
            munmap(pages, size)
            return try Data(contentsOf: url)
        }

        return Data(bytesNoCopy: pages, count: filled, deallocator: .custom { pointer, _ in
            munmap(pointer, size)
        })
    }

    private static func size(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.intValue ?? 0
    }
}
