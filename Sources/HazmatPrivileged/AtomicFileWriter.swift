import Darwin
import Foundation

/// Who owns the file after a write.
public struct FileOwnership: Equatable, Sendable {
    public let uid: uid_t
    public let gid: gid_t

    public init(uid: uid_t, gid: gid_t) {
        self.uid = uid
        self.gid = gid
    }

    /// Root in the wheel group: what the hosts file carries.
    public static let system = FileOwnership(uid: 0, gid: 0)
}

public enum WriteFailure: Error, Equatable, Sendable, CustomStringConvertible {
    /// The file carries an access-control list. It is refused rather than
    /// replaced, because replacing it would either carry the list over or lock
    /// out the tools that put it there.
    case accessControlList(path: String)
    case temporaryFile(String)
    case write(String)
    case attributes(String)
    case flush(String)
    case replace(String)
    case directoryFlush(String)

    public var description: String {
        switch self {
        case .accessControlList(let path):
            return "\(path) carries an access-control list"
        case .temporaryFile(let detail):
            return "creating the temporary file: \(detail)"
        case .write(let detail):
            return "writing: \(detail)"
        case .attributes(let detail):
            return "setting mode and owner: \(detail)"
        case .flush(let detail):
            return "flushing: \(detail)"
        case .replace(let detail):
            return "replacing the file: \(detail)"
        case .directoryFlush(let detail):
            return "flushing the directory: \(detail)"
        }
    }
}

/// Replaces a file in one step: a uniquely named temporary file in the target's
/// own directory, mode and owner set on the descriptor, flushed, renamed into
/// place, then the directory flushed.
///
/// The target is a parameter, so this is testable against a temporary
/// directory; only the daemon hard-wires the hosts file.
public struct AtomicFileWriter: Sendable {
    /// The mode the hosts file carries. It is set on the descriptor, because the
    /// mode passed to `open` is filtered through the umask.
    public static let mode: mode_t = 0o644

    public let target: URL
    public let owner: FileOwnership
    /// Test seam: runs once the temporary file is complete, before it is renamed
    /// over the target. Throwing here is the simulated interruption.
    public var interruption: (@Sendable () throws -> Void)?

    public init(target: URL, owner: FileOwnership = .system) {
        self.target = target
        self.owner = owner
    }

    public func write(_ data: Data) throws {
        if try hasAccessControlList(at: target.path) {
            throw WriteFailure.accessControlList(path: target.path)
        }

        let directory = target.deletingLastPathComponent()
        let temporaryPath = directory
            .appendingPathComponent(".\(target.lastPathComponent).hazmat-\(UUID().uuidString)")
            .path

        var descriptor = open(temporaryPath, O_CREAT | O_EXCL | O_WRONLY, 0o600)
        guard descriptor >= 0 else {
            throw WriteFailure.temporaryFile(errnoText("open"))
        }
        var replaced = false
        defer {
            if descriptor >= 0 {
                _ = close(descriptor)
            }
            if !replaced {
                _ = unlink(temporaryPath)
            }
        }

        try writeAll(data, to: descriptor)
        try setAttributes(on: descriptor)
        guard fsync(descriptor) == 0 else {
            throw WriteFailure.flush(errnoText("fsync"))
        }
        if try hasAccessControlList(at: temporaryPath) {
            throw WriteFailure.accessControlList(path: temporaryPath)
        }

        try interruption?()

        guard close(descriptor) == 0 else {
            throw WriteFailure.write(errnoText("close"))
        }
        descriptor = -1

        guard rename(temporaryPath, target.path) == 0 else {
            throw WriteFailure.replace(errnoText("rename"))
        }
        replaced = true

        try flushDirectory(directory)
    }

    private func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(descriptor, base + offset, buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw WriteFailure.write(errnoText("write"))
                }
                offset += written
            }
        }
    }

    private func setAttributes(on descriptor: Int32) throws {
        guard fchmod(descriptor, Self.mode) == 0 else {
            throw WriteFailure.attributes(errnoText("fchmod"))
        }
        guard fchown(descriptor, owner.uid, owner.gid) == 0 else {
            throw WriteFailure.attributes(errnoText("fchown"))
        }
    }

    private func flushDirectory(_ directory: URL) throws {
        let descriptor = open(directory.path, O_RDONLY | O_DIRECTORY)
        guard descriptor >= 0 else {
            throw WriteFailure.directoryFlush(errnoText("open"))
        }
        defer { _ = close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw WriteFailure.directoryFlush(errnoText("fsync"))
        }
    }

    /// A file with no extended access-control list has no entries. A missing
    /// file has no list either.
    func hasAccessControlList(at path: String) throws -> Bool {
        guard let list = acl_get_file(path, ACL_TYPE_EXTENDED) else {
            if errno == ENOENT { return false }
            throw WriteFailure.attributes(errnoText("acl_get_file"))
        }
        defer { acl_free(UnsafeMutableRawPointer(list)) }
        var entry: acl_entry_t?
        return acl_get_entry(list, Int32(ACL_FIRST_ENTRY.rawValue), &entry) == 0
    }
}

func errnoText(_ call: String) -> String {
    "\(call): \(String(cString: strerror(errno)))"
}
