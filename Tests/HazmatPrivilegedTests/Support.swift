import Darwin
import Foundation
import HazmatCore
import XCTest
@testable import HazmatPrivileged

func bytes(_ text: String) -> Data { Data(text.utf8) }

func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

func XCTAssertEqualBytes(_ actual: Data, _ expected: Data, _ label: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(Array(actual), Array(expected), label, file: file, line: line)
}

/// A throwaway directory holding one target file, standing in for `/etc`.
final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("hazmat-write-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    var target: URL { url.appendingPathComponent("hosts") }

    func write(_ data: Data) throws {
        try data.write(to: target)
    }

    func contents() throws -> Data {
        try Data(contentsOf: target)
    }

    func entries() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

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

/// The owner a test can actually set: the daemon configures root, which a
/// non-root suite cannot, so the mechanism is verified with the test's own uid.
func testOwnership() -> FileOwnership {
    FileOwnership(uid: getuid(), gid: getgid())
}

/// Sets an extended access-control list without a shell, so the suite stays free
/// of external programs.
func setAccessControlList(at url: URL) throws {
    var acl: acl_t? = acl_init(1)
    var entry: acl_entry_t?
    guard acl_create_entry(&acl, &entry) == 0, let entry else {
        throw testError("acl_create_entry")
    }
    guard acl_set_tag_type(entry, ACL_EXTENDED_ALLOW) == 0 else {
        throw testError("acl_set_tag_type")
    }
    var permset: acl_permset_t?
    guard acl_get_permset(entry, &permset) == 0, let permset else {
        throw testError("acl_get_permset")
    }
    guard acl_add_perm(permset, acl_perm_t(ACL_READ_DATA.rawValue)) == 0 else {
        throw testError("acl_add_perm")
    }
    guard acl_set_permset(entry, permset) == 0 else {
        throw testError("acl_set_permset")
    }
    guard acl_set_file(url.path, ACL_TYPE_EXTENDED, acl) == 0 else {
        throw testError("acl_set_file")
    }
}

func testError(_ call: String) -> NSError {
    NSError(
        domain: "hazmat-tests",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "\(call): \(String(cString: strerror(errno)))"]
    )
}

/// A file holding exactly one well-formed block, which is what the byte
/// contract asks for.
func appliedHosts() -> Data {
    bytes(
        "##\n"
            + "# Host Database\n"
            + "##\n"
            + "127.0.0.1\tlocalhost\n"
            + "255.255.255.255\tbroadcasthost\n"
            + "::1             localhost\n"
            + "# >>> hazmat:managed v1 >>>\n"
            + "127.0.0.1 hazmat.local\n"
            + "::1 api.internal\n"
            + "# <<< hazmat:managed v1 <<<\n"
    )
}
