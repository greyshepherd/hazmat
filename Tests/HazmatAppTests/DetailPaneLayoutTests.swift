import AppKit
import SwiftUI
import XCTest

@testable import HazmatApp

/// The resolved pane lays the block's text view out directly rather than inside
/// a scroll view, so it takes the pane's height; this is the regression guard for
/// the text view falling back to its minimum.
@MainActor
final class DetailPaneLayoutTests: XCTestCase {
    func testResolvedBlockTakesThePaneHeight() throws {
        let world = try ShellWorld()
        defer { world.remove() }
        let model = world.model()

        let host = NSHostingView(rootView: DetailPane(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 800)
        host.layoutSubtreeIfNeeded()

        let scrolls = Self.allSubviews(of: host).compactMap { $0 as? NSScrollView }
        let block = try XCTUnwrap(scrolls.first { $0.documentView is NSTextView }, "the block's text view")
        XCTAssertGreaterThan(block.convert(block.bounds, to: host).height, 400)

        let listHeights = scrolls
            .filter { !($0.documentView is NSTextView) }
            .map { $0.convert($0.bounds, to: host).height }
        XCTAssertFalse(listHeights.isEmpty, "the displaced list's scroll view")
        for height in listHeights {
            XCTAssertLessThanOrEqual(height, 160)
        }
    }

    private static func allSubviews(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { allSubviews(of: $0) }
    }
}
