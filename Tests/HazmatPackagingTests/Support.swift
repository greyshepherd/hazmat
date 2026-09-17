import CoreGraphics
import Foundation
import ImageIO
import XCTest

/// The repository root, from this file's own location.
func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// Every text file under a repository-relative path, keyed by its path.
func textFiles(under relativePath: String) -> [(String, String)] {
    let root = repositoryRoot()
    let start = root.appendingPathComponent(relativePath)
    guard let enumerator = FileManager.default.enumerator(at: start, includingPropertiesForKeys: nil) else {
        return []
    }
    var files: [(String, String)] = []
    for case let url as URL in enumerator {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
        files.append((url.path.replacingOccurrences(of: root.path + "/", with: ""), text))
    }
    return files.sorted { $0.0 < $1.0 }
}

func releaseConfiguration() throws -> [String: Any] {
    let url = repositoryRoot().appendingPathComponent("release/config.json")
    let data = try Data(contentsOf: url)
    let object = try JSONSerialization.jsonObject(with: data)
    return try XCTUnwrap(object as? [String: Any], "release/config.json is not an object")
}

/// A decoded image, drawn into RGBA with the alpha premultiplied.
struct DecodedImage {
    let width: Int
    let height: Int
    let samples: [UInt8]

    func pixel(x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        let offset = (y * width + x) * 4
        return (samples[offset], samples[offset + 1], samples[offset + 2], samples[offset + 3])
    }

    var visiblePixels: Int {
        (0..<(width * height)).reduce(into: 0) { total, index in
            if samples[index * 4 + 3] > 0 { total += 1 }
        }
    }
}

enum ImageError: Error, CustomStringConvertible {
    case unreadable(String)
    case undrawable(String)

    var description: String {
        switch self {
        case .unreadable(let path): return "no image at \(path)"
        case .undrawable(let path): return "\(path) could not be drawn into a bitmap"
        }
    }
}

func decodeImage(at url: URL) throws -> DecodedImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw ImageError.unreadable(url.path)
    }
    let width = image.width
    let height = image.height
    var samples = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = samples.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(
            data: buffer.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard drawn else { throw ImageError.undrawable(url.path) }
    return DecodedImage(width: width, height: height, samples: samples)
}

/// The icon container as it is laid out: a magic number, a declared length, then
/// one entry per size.
struct IconFile {
    let declaredLength: Int
    let actualLength: Int
    let types: [String]

    static func read(at url: URL) throws -> IconFile {
        let data = try Data(contentsOf: url)
        guard data.count > 8, data.prefix(4) == Data("icns".utf8) else {
            throw ImageError.unreadable("\(url.path) is not an icon file")
        }
        let declared = Int(data[4]) << 24 | Int(data[5]) << 16 | Int(data[6]) << 8 | Int(data[7])
        var types: [String] = []
        var offset = 8
        while offset + 8 <= data.count {
            let type = String(decoding: data[offset..<(offset + 4)], as: UTF8.self)
            let length = Int(data[offset + 4]) << 24 | Int(data[offset + 5]) << 16
                | Int(data[offset + 6]) << 8 | Int(data[offset + 7])
            guard length >= 8, offset + length <= data.count else { break }
            types.append(type)
            offset += length
        }
        return IconFile(declaredLength: declared, actualLength: data.count, types: types)
    }
}
