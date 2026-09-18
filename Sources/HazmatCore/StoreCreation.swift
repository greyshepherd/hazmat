import Foundation

/// What an explicit store creation did.
public enum StoreCreation: Equatable, Sendable {
    /// The directories were made.
    case created
    /// The store was already there; nothing changed.
    case nothingToDo
}

extension StoreLayout {
    /// Creates the store's directories and nothing else: no profile, no
    /// fragment, and nothing outside the root. Ordinary file creation, so it
    /// needs no privileged access.
    @discardableResult
    public func create() throws -> StoreCreation {
        guard !exists else { return .nothingToDo }
        do {
            try FileManager.default.createDirectory(at: fragmentsDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: profilesDirectory, withIntermediateDirectories: true)
        } catch {
            throw StoreWriteError.failed("creating \(root.path): \(error)")
        }
        return .created
    }
}
