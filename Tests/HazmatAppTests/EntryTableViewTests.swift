import AppKit
import HazmatCore
import SwiftUI
import XCTest

@testable import HazmatApp

/// The resolved block's table is an `NSTableView` fed by a data source, so a
/// block of a hundred thousand entries costs the rows on screen, not one view
/// per entry.
@MainActor
final class EntryTableViewTests: XCTestCase {
    func testTheTableShowsOneRowPerEntryWithItsAddressNamesAndSource() throws {
        let entries = [
            entry("127.0.0.1", ["localhost", "alpha.example"], line: 1),
            entry("10.0.0.9", ["beta.example"], line: 2),
            entry("::1", ["ip6-localhost"], line: 3)
        ]
        let host = Self.host(EntryTableView(entries: entries, rendering: Data("v1".utf8)))
        let table = try XCTUnwrap(Self.tableView(in: host))

        XCTAssertEqual(table.numberOfRows, 3)
        XCTAssertEqual(Self.text(table, row: 0, column: 0), "127.0.0.1")
        XCTAssertEqual(Self.text(table, row: 0, column: 1), "localhost, alpha.example")
        XCTAssertEqual(Self.text(table, row: 0, column: 2), "base:1")
        XCTAssertEqual(Self.text(table, row: 2, column: 0), "::1")
    }

    func testAHundredThousandEntriesMaterialiseOnlyTheRowsOnScreen() throws {
        let entries = (1...100_000).map { line in
            entry("0.0.0.0", ["host\(line).example"], line: line)
        }
        let host = Self.host(EntryTableView(entries: entries, rendering: Data("v1".utf8)))
        let table = try XCTUnwrap(Self.tableView(in: host))

        XCTAssertEqual(table.numberOfRows, 100_000)
        let rowViews = Self.allSubviews(of: table).filter { $0 is NSTableRowView }
        XCTAssertLessThan(rowViews.count, 200, "only the rows on screen have views")
    }

    func testANewRenderingReloadsTheRows() throws {
        let first = [entry("127.0.0.1", ["localhost"], line: 1)]
        let second = first + [entry("10.0.0.9", ["beta.example"], line: 2)]
        let host = Self.host(EntryTableView(entries: first, rendering: Data("v1".utf8)))
        let table = try XCTUnwrap(Self.tableView(in: host))
        XCTAssertEqual(table.numberOfRows, 1)

        host.rootView = EntryTableView(entries: second, rendering: Data("v2".utf8))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(table.numberOfRows, 2)
    }

    // MARK: - Helpers

    private func entry(_ address: String, _ names: [String], line: Int) -> BlockEntry {
        BlockEntry(
            address: address,
            family: address.contains(":") ? .ipv6 : .ipv4,
            names: names,
            source: SourceLocation(fragment: FragmentID("base"), line: line)
        )
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
