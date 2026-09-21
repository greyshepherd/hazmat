import Foundation

/// What an authoring operation did.
public enum StoreWrite: Equatable, Sendable {
    /// The file now holds the text that was written.
    case wrote
    /// The file already held that text; nothing was written.
    case unchanged
    /// The file was removed.
    case deleted
    /// The store held nothing under the name; nothing was done.
    case nothingToDo

    /// Whether the store is different afterwards.
    public var didChange: Bool {
        switch self {
        case .wrote, .deleted: return true
        case .unchanged, .nothingToDo: return false
        }
    }
}

/// What stopped an authoring operation. A refused name is a decision taken
/// before any file is touched; a failed write leaves the previous text readable.
public enum StoreWriteError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidName(String)
    case nameTaken(String)
    case missing(String)
    case failed(String)

    public var description: String {
        switch self {
        case .invalidName(let name):
            return "'\(name)' is not a usable name. \(NameSyntax.refusal(name) ?? NameSyntax.requirement)"
        case .nameTaken(let name):
            return "the store already holds '\(name)'"
        case .missing(let name):
            return "the store holds no '\(name)'"
        case .failed(let reason):
            return reason
        }
    }
}

/// Writes the store: create, replace, duplicate, rename, and delete a fragment
/// or a profile. Every operation is unprivileged and confined to the store's own
/// directories, validates its names before touching anything, and replaces a
/// file by renaming a temporary file over it, so a failed write leaves the
/// previous text readable and a reader sees one complete version.
public struct StoreWriter: Sendable {
    public let layout: StoreLayout

    public init(layout: StoreLayout) {
        self.layout = layout
    }

    // MARK: Fragments

    /// Creates or replaces the fragment `name`, or reports that it already held
    /// this text.
    @discardableResult
    public func save(_ text: String, asFragment name: FragmentID) throws -> StoreWrite {
        try save(text, as: .fragment(name))
    }

    /// Creates or replaces the source `name`'s sidecar. The fragment is written
    /// by its own call, so a sidecar can be recorded for a fragment whose first
    /// fetch has not landed yet.
    @discardableResult
    public func save(_ source: RemoteSource, as name: FragmentID) throws -> StoreWrite {
        try save(try source.encoded(), asRemote: name)
    }

    /// Creates or replaces the sidecar `name`, or reports that it already held
    /// these bytes.
    @discardableResult
    public func save(_ contents: Data, asRemote name: FragmentID) throws -> StoreWrite {
        guard name.isValid else { throw StoreWriteError.invalidName(name.rawValue) }
        let url = layout.remoteURL(name)
        if let existing = try? Data(contentsOf: url), existing == contents {
            return .unchanged
        }
        try write(contents, to: url)
        return .wrote
    }

    /// Removes the source `name`'s sidecar. A store that holds none reports
    /// nothing to do, so a caller may ask without knowing.
    @discardableResult
    public func deleteRemoteSource(_ name: FragmentID) throws -> StoreWrite {
        guard name.isValid else { throw StoreWriteError.invalidName(name.rawValue) }
        let url = layout.remoteURL(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return .nothingToDo }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw StoreWriteError.failed("removing \(url.path): \(error)")
        }
        return .deleted
    }

    /// Copies the fragment `name` to `copy`, refusing a name the store holds.
    @discardableResult
    public func duplicate(fragment name: FragmentID, as copy: FragmentID) throws -> StoreWrite {
        try duplicate(from: .fragment(name), to: .fragment(copy))
    }

    /// Moves the fragment `name` to `newName`, keeping its bytes, and carries
    /// every profile reference to it, so no profile is left naming a fragment
    /// the store no longer holds. A fragment that records an origin carries its
    /// sidecar, so the source's URL and refresh state follow the text.
    @discardableResult
    public func rename(fragment name: FragmentID, to newName: FragmentID) throws -> StoreWrite {
        try check(.fragment(newName))
        guard name != newName else { return .nothingToDo }
        // A name a sidecar already holds is a source, even when its fragment is
        // not there yet, so renaming onto it is refused rather than clobbering
        // the other source's origin.
        guard !FileManager.default.fileExists(atPath: layout.remoteURL(newName).path) else {
            throw StoreWriteError.nameTaken(newName.rawValue)
        }
        let moved = try move(.fragment(name), to: .fragment(newName))
        guard moved == .wrote else { return moved }
        try carrySidecar(from: name, to: newName)
        try carryReferences(from: name, to: newName)
        return moved
    }

    /// Removes the fragment `name`, reporting nothing to do when it is absent.
    /// A sidecar under that name goes with it, and a sidecar whose fragment is
    /// not there at all is still removed and still reported as a change, so a
    /// source whose first fetch failed can be removed.
    @discardableResult
    public func delete(fragment name: FragmentID) throws -> StoreWrite {
        let removed = try delete(.fragment(name))
        let sidecar = try deleteRemoteSource(name)
        guard sidecar == .deleted else { return removed }
        return removed == .nothingToDo ? .deleted : removed
    }

    // MARK: Profiles

    /// Creates or replaces the profile `name`, or reports that it already held
    /// this text.
    @discardableResult
    public func save(_ text: String, asProfile name: ProfileID) throws -> StoreWrite {
        try save(text, as: .profile(name))
    }

    /// Copies the profile `name` to `copy`, refusing a name the store holds.
    @discardableResult
    public func duplicate(profile name: ProfileID, as copy: ProfileID) throws -> StoreWrite {
        try duplicate(from: .profile(name), to: .profile(copy))
    }

    /// Moves the profile `name` to `newName`, keeping its bytes.
    @discardableResult
    public func rename(profile name: ProfileID, to newName: ProfileID) throws -> StoreWrite {
        try move(.profile(name), to: .profile(newName))
    }

    /// Removes the profile `name`, reporting nothing to do when it is absent.
    @discardableResult
    public func delete(profile name: ProfileID) throws -> StoreWrite {
        try delete(.profile(name))
    }

    // MARK: The two kinds are written the same way

    private enum Entry {
        case fragment(FragmentID)
        case profile(ProfileID)

        var name: String {
            switch self {
            case .fragment(let id): return id.rawValue
            case .profile(let id): return id.rawValue
            }
        }

        var isValid: Bool {
            switch self {
            case .fragment(let id): return id.isValid
            case .profile(let id): return id.isValid
            }
        }

        func url(in layout: StoreLayout) -> URL {
            switch self {
            case .fragment(let id): return layout.fragmentURL(id)
            case .profile(let id): return layout.profileURL(id)
            }
        }
    }

    private func save(_ text: String, as entry: Entry) throws -> StoreWrite {
        try check(entry)
        let url = entry.url(in: layout)
        if let existing = try? String(contentsOf: url, encoding: .utf8), existing == text {
            return .unchanged
        }
        try write(Data(text.utf8), to: url)
        return .wrote
    }

    private func duplicate(from source: Entry, to copy: Entry) throws -> StoreWrite {
        try check(source)
        try check(copy)
        let from = source.url(in: layout)
        let to = copy.url(in: layout)
        guard FileManager.default.fileExists(atPath: from.path) else {
            throw StoreWriteError.missing(source.name)
        }
        guard !FileManager.default.fileExists(atPath: to.path) else {
            throw StoreWriteError.nameTaken(copy.name)
        }
        let contents: Data
        do {
            contents = try Data(contentsOf: from)
        } catch {
            throw StoreWriteError.failed("reading \(from.path): \(error)")
        }
        try write(contents, to: to)
        return .wrote
    }

    private func move(_ entry: Entry, to newName: Entry) throws -> StoreWrite {
        try check(entry)
        try check(newName)
        guard entry.name != newName.name else { return .nothingToDo }
        let from = entry.url(in: layout)
        let to = newName.url(in: layout)
        guard FileManager.default.fileExists(atPath: from.path) else {
            throw StoreWriteError.missing(entry.name)
        }
        guard !FileManager.default.fileExists(atPath: to.path) else {
            throw StoreWriteError.nameTaken(newName.name)
        }
        do {
            try FileManager.default.moveItem(at: from, to: to)
        } catch {
            throw StoreWriteError.failed("renaming \(from.path): \(error)")
        }
        return .wrote
    }

    /// Moves a source's sidecar to the fragment's new name, so an origin is
    /// never left naming a fragment the store no longer holds. A fragment with
    /// no sidecar carries nothing.
    private func carrySidecar(from old: FragmentID, to new: FragmentID) throws {
        let from = layout.remoteURL(old)
        guard FileManager.default.fileExists(atPath: from.path) else { return }
        let to = layout.remoteURL(new)
        do {
            try FileManager.default.moveItem(at: from, to: to)
        } catch {
            throw StoreWriteError.failed("renaming \(from.path): \(error)")
        }
    }

    /// Writes every profile line that named `old` as `new`, so a rename leaves
    /// no profile naming a fragment that is gone. A profile is replaced only
    /// when its text changed, and one that cannot be read is reported rather
    /// than passed over.
    private func carryReferences(from old: FragmentID, to new: FragmentID) throws {        for profile in layout.profiles() {
            let url = layout.profileURL(profile)
            let text: String
            do {
                text = try String(contentsOf: url, encoding: .utf8)
            } catch {
                throw StoreWriteError.failed("reading \(url.path): \(error)")
            }
            let carried = ProfileText.renaming(old, to: new, in: text)
            guard carried != text else { continue }
            try write(Data(carried.utf8), to: url)
        }
    }

    private func delete(_ entry: Entry) throws -> StoreWrite {
        try check(entry)
        let url = entry.url(in: layout)
        guard FileManager.default.fileExists(atPath: url.path) else { return .nothingToDo }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw StoreWriteError.failed("removing \(url.path): \(error)")
        }
        return .deleted
    }

    private func check(_ entry: Entry) throws {
        guard entry.isValid else { throw StoreWriteError.invalidName(entry.name) }
    }

    /// A uniquely named file in the target's own directory, renamed over the
    /// target: the store holds the old bytes or the new ones, never a partial
    /// write, and a failure leaves no temporary file behind.
    private func write(_ contents: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw StoreWriteError.failed("creating \(directory.path): \(error)")
        }

        let temporary = directory
            .appendingPathComponent(".\(url.lastPathComponent).hazmat-\(UUID().uuidString)")
        do {
            try contents.write(to: temporary, options: .withoutOverwriting)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw StoreWriteError.failed("writing \(temporary.path): \(error)")
        }

        guard replaceFile(from: temporary.path, to: url.path) == 0 else {
            let reason = String(cString: strerror(errno))
            try? FileManager.default.removeItem(at: temporary)
            throw StoreWriteError.failed("replacing \(url.path): \(reason)")
        }
    }
}

/// `rename(2)` replaces the target in one step. A free function, so the type's
/// own `rename` methods do not shadow the C one.
private func replaceFile(from: String, to: String) -> Int32 {
    rename(from, to)
}
