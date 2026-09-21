import AppKit
import HazmatCore
import SwiftUI
import XCTest

@testable import HazmatApp

/// The resolved block's table is an `NSTableView` fed by a data source, so a
/// block of a hundred thousand entries costs the rows on screen, not one view
/// per entry. Its rows are built from the composition once per rendering, not
/// on every look at the pane.
@MainActor
final class EntryTableViewTests: XCTestCase {
    func testTheTableShowsOneRowPerEntryWithItsAddressNamesAndSource() throws {
        let composition = try composition(
            "127.0.0.1\tlocalhost alpha.example\n10.0.0.9\tbeta.example\n::1\tip6-localhost\n"
        )
        let host = Self.host(EntryTableView(composition: composition, rendering: Data("v1".utf8)))
        let table = try XCTUnwrap(Self.tableView(in: host))

        XCTAssertEqual(table.numberOfRows, 3)
        XCTAssertEqual(Self.text(table, row: 0, column: 0), "127.0.0.1")
        XCTAssertEqual(Self.text(table, row: 0, column: 1), "localhost, alpha.example")
        XCTAssertEqual(Self.text(table, row: 0, column: 2), "base:1")
        XCTAssertEqual(Self.text(table, row: 2, column: 0), "::1")
    }

    func testAHundredThousandEntriesMaterialiseOnlyTheRowsOnScreen() throws {
        let composition = try composition(
            (1...100_000).map { "0.0.0.0\thost\($0).example\n" }.joined()
        )
        let host = Self.host(EntryTableView(composition: composition, rendering: Data("v1".utf8)))
        let table = try XCTUnwrap(Self.tableView(in: host))

        XCTAssertEqual(table.numberOfRows, 100_000)
        let rowViews = Self.allSubviews(of: table).filter { $0 is NSTableRowView }
        XCTAssertLessThan(rowViews.count, 200, "only the rows on screen have views")
    }

    func testANewRenderingReloadsTheRows() throws {
        let first = try composition("127.0.0.1\tlocalhost\n")
        let second = try composition("127.0.0.1\tlocalhost\n10.0.0.9\tbeta.example\n")
        let host = Self.host(EntryTableView(composition: first, rendering: Data("v1".utf8)))
        let table = try XCTUnwrap(Self.tableView(in: host))
        XCTAssertEqual(table.numberOfRows, 1)

        host.rootView = EntryTableView(composition: second, rendering: Data("v2".utf8))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(table.numberOfRows, 2)
    }

    // MARK: - Helpers

    private func composition(_ text: String) throws -> Composition {
        let outcome = FragmentParser.parse(text, as: FragmentID("base"))
        return try HostsComposer.compose(profile: ProfileID("work"), layers: [outcome.fragment], problems: outcome.problems)
    }

    private static func host(_ view: EntryTableView) -> NSHostingView<EntryTableView> {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        host.layoutSubtreeIfNeeded()
        return host
    }

    private static func tableView(in host: NSView) -> NSTableView? {
        allSubviews(of: host).compactMap { $0 as? NSTableView }.first
    }

    private static func text(_ table: NSTableView, row: Int, column: Int) -> String? {
        let cell = table.view(atColumn: column, row: row, makeIfNecessary: true)
        return allSubviews(of: cell ?? NSView()).compactMap { $0 as? NSTextField }.first?.stringValue
    }

    static func allSubviews(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { allSubviews(of: $0) }
    }
}
