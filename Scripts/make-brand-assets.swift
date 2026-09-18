// Generates the brand assets: Assets/Hazmat.icns and the menu-bar template
// images. Run from the repository root:
//
//     swift Scripts/make-brand-assets.swift
//
// Every size is drawn from geometry, never downscaled from a master, so the
// 16 px icon is laid out for sixteen pixels. The mark is the mask: the app
// replaces Gas Mask, and the successor wears the mask.
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Assets")

// MARK: - Colour

struct Ink {
    var r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat

    init(_ hex: UInt32, alpha: CGFloat = 1) {
        r = CGFloat((hex >> 16) & 0xFF) / 255
        g = CGFloat((hex >> 8) & 0xFF) / 255
        b = CGFloat(hex & 0xFF) / 255
        a = alpha
    }

    private init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    func alpha(_ value: CGFloat) -> Ink { Ink(r: r, g: g, b: b, a: value) }
    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

/// The field is deep petrol; the mark is bone; the lenses are glass.
let fieldTop = Ink(0x14282D)
let fieldBottom = Ink(0x080F11)
let bone = Ink(0xE7E0D2)
let lensGlass = Ink(0x16333A)

// MARK: - Shapes

/// Points along one corner curve, from the vertical-edge touch to the
/// horizontal-edge touch. The curve leaves each edge tangentially, and the
/// radius and exponent are fitted to the system's icon shape, so the tile is
/// the platform's, not an invention.
func cornerArc(center: CGPoint, radius r: CGFloat, exponent n: CGFloat,
               sx: CGFloat, sy: CGFloat, reversed: Bool) -> [CGPoint] {
    var points: [CGPoint] = []
    for i in 0...200 {
        let u = CGFloat(i) / 200
        let mx = pow(1 - pow(u, n), 1 / n)
        points.append(CGPoint(x: center.x + sx * r * mx, y: center.y + sy * r * u))
    }
    return reversed ? points.reversed() : points
}

func squircle(_ rect: CGRect, radius r0: CGFloat, exponent n: CGFloat = 1.86) -> CGPath {
    let r = min(r0, min(rect.width, rect.height) / 2)
    let topLeft = CGPoint(x: rect.minX + r, y: rect.maxY - r)
    let topRight = CGPoint(x: rect.maxX - r, y: rect.maxY - r)
    let bottomRight = CGPoint(x: rect.maxX - r, y: rect.minY + r)
    let bottomLeft = CGPoint(x: rect.minX + r, y: rect.minY + r)
    var outline: [CGPoint] = []
    outline += cornerArc(center: topRight, radius: r, exponent: n, sx: 1, sy: 1, reversed: true)
    outline += cornerArc(center: bottomRight, radius: r, exponent: n, sx: 1, sy: -1, reversed: false)
    outline += cornerArc(center: bottomLeft, radius: r, exponent: n, sx: -1, sy: -1, reversed: true)
    outline += cornerArc(center: topLeft, radius: r, exponent: n, sx: -1, sy: 1, reversed: false)
    let path = CGMutablePath()
    path.move(to: outline[0])
    for point in outline.dropFirst() { path.addLine(to: point) }
    path.closeSubpath()
    return path
}

func disc(_ center: CGPoint, _ diameter: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2,
                             width: diameter, height: diameter), transform: nil)
}

func slab(center: CGPoint, width: CGFloat, height: CGFloat, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height),
           cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// MARK: - The mask
//
// Positions are fractions of the mark's square. The chin filter is drawn past
// the face piece's edge so the silhouette reads as hardware rather than a face;
// the filter's slats and the lens rims are what carry that reading at small
// sizes, which is why they are shapes and not detail.

func drawPositive(_ ctx: CGContext, _ s: CGFloat, _ ink: Ink) {
    // Straps, behind the face piece.
    for sign in [CGFloat(-1), 1] {
        ctx.addPath(slab(center: CGPoint(x: sign * 0.310 * s, y: 0.055 * s),
                         width: 0.095 * s, height: 0.15 * s, radius: 0.032 * s))
        ctx.setFillColor(ink.cg)
        ctx.fillPath()
    }
    // Face piece.
    ctx.addPath(disc(CGPoint(x: 0, y: 0.055 * s), 0.62 * s))
    ctx.setFillColor(ink.cg)
    ctx.fillPath()
    // Chin filter, breaking the silhouette below the face.
    ctx.addPath(disc(CGPoint(x: 0, y: -0.235 * s), 0.250 * s))
    ctx.setFillColor(ink.cg)
    ctx.fillPath()
}

func drawCuts(_ ctx: CGContext, _ s: CGFloat, lensPorts: Bool) {
    ctx.setBlendMode(.destinationOut)
    ctx.setFillColor(Ink(0x000000).cg)
    ctx.saveGState()
    ctx.addPath(disc(CGPoint(x: 0, y: -0.235 * s), 0.250 * s))
    ctx.clip()
    for y in [-0.305, -0.260, -0.215, -0.170] {
        ctx.addPath(slab(center: CGPoint(x: 0, y: CGFloat(y) * s),
                         width: 0.175 * s, height: 0.023 * s, radius: 0.0115 * s))
        ctx.fillPath()
    }
    ctx.restoreGState()
    // The template carries the lens ports as true holes, so the menu bar shows
    // through them; the app icon draws glass there instead.
    if lensPorts {
        for sign in [CGFloat(-1), 1] {
            ctx.addPath(disc(CGPoint(x: sign * 0.148 * s, y: 0.075 * s), 0.230 * s))
            ctx.fillPath()
        }
    }
    ctx.setBlendMode(.normal)
}

func drawOverlays(_ ctx: CGContext, _ s: CGFloat) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    for sign in [CGFloat(-1), 1] {
        let center = CGPoint(x: sign * 0.148 * s, y: 0.075 * s)
        ctx.addPath(disc(center, 0.230 * s))
        ctx.setFillColor(lensGlass.cg)
        ctx.fillPath()
        // A sheen across the glass, never a catchlight: an eye is what a mask must not become.
        ctx.saveGState()
        ctx.addPath(disc(center, 0.230 * s))
        ctx.clip()
        let sheen = CGGradient(colorsSpace: space,
                               colors: [Ink(0xD8F3EC, alpha: 0.40).cg, Ink(0xD8F3EC, alpha: 0.0).cg] as CFArray,
                               locations: [0, 1])!
        ctx.drawLinearGradient(sheen,
                               start: CGPoint(x: center.x - sign * 0.07 * s, y: center.y + 0.08 * s),
                               end: CGPoint(x: center.x + sign * 0.05 * s, y: center.y - 0.07 * s),
                               options: [])
        ctx.restoreGState()
        // A bezel where the glass meets the face piece.
        ctx.addPath(disc(center, 0.168 * s))
        ctx.setStrokeColor(Ink(0x0B0D10, alpha: 0.35).cg)
        ctx.setLineWidth(0.012 * s)
        ctx.strokePath()
    }
}

// MARK: - Rendering

/// The mark on a transparent canvas: positive, cuts, then the colour passes the
/// template must not carry.
func drawMark(px: Int, ink: Ink, artFraction: CGFloat, template: Bool) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    let side = CGFloat(px) * artFraction
    ctx.translateBy(x: CGFloat(px) / 2, y: CGFloat(px) / 2)
    drawPositive(ctx, side, ink)
    drawCuts(ctx, side, lensPorts: template)
    if !template { drawOverlays(ctx, side) }
    return ctx.makeImage()!
}

func drawIcon(px: Int) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(px)
    ctx.setAllowsAntialiasing(true)

    let tile = squircle(CGRect(x: 0, y: 0, width: s, height: s), radius: 0.2237 * s)
    ctx.saveGState()
    ctx.addPath(tile)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: space,
                              colors: [fieldTop.cg, fieldBottom.cg] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
    ctx.restoreGState()

    ctx.draw(drawMark(px: px, ink: bone, artFraction: 1, template: false),
             in: CGRect(x: 0, y: 0, width: s, height: s))
    return ctx.makeImage()!
}

// MARK: - Output

func writePNG(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(url.path)") }
}

let iconsetSizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

let staging = FileManager.default.temporaryDirectory.appendingPathComponent("Hazmat.iconset")
try? FileManager.default.removeItem(at: staging)
try! FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
for (label, px) in iconsetSizes {
    writePNG(drawIcon(px: px), to: staging.appendingPathComponent("\(label).png"))
}

let icns = assets.appendingPathComponent("Hazmat.icns")
let assembled = Process()
assembled.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
assembled.arguments = ["-c", "icns", "-o", icns.path, staging.path]
try! assembled.run()
assembled.waitUntilExit()
guard assembled.terminationStatus == 0 else { fatalError("iconutil could not assemble \(icns.path)") }

for (name, px) in [("menu-bar-template", 22), ("menu-bar-template@2x", 44)] {
    writePNG(drawMark(px: px, ink: Ink(0x000000), artFraction: 0.86, template: true),
             to: assets.appendingPathComponent("\(name).png"))
}

print("wrote \(icns.path)")
print("wrote \(assets.path)/menu-bar-template.png and @2x")
