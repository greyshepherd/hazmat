import Foundation

func bytes(_ text: String) -> Data { Data(text.utf8) }

func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

/// The repository root, from this file's own location.
func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

func sourceFiles(in relativePath: String) -> [(String, String)] {
    let root = repositoryRoot().appendingPathComponent(relativePath)
    let contents = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
    return contents
        .filter { $0.pathExtension == "swift" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .compactMap { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return (url.lastPathComponent, text)
        }
}

/// A throwaway store with the files a composition reads.
final class TemporaryStore {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("hazmat-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func write(_ contents: String, to relativePath: String) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
