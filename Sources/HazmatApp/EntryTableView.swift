import AppKit
import HazmatCore
import SwiftUI

/// The resolved block as a table that costs only the rows on screen: an
/// `NSTableView` fed by a data source, which is what makes a hundred thousand
/// entries usable where a SwiftUI `Table` is not. A SwiftUI `Table` keeps a
/// view identity, a trait array and an attribute subgraph per row — about
/// 1.5 KB an entry, for every entry, whether or not it is visible.
///
/// The rows are reloaded when the rendering they came from changes, so an
/// update that carries the same block does not reload the table for nothing.
struct EntryTableView: NSViewRepresentable {
    /// The block's entry lines, in order.
    var entries: [BlockEntry]
    /// The bytes the entries were rendered from: the identity a reload keys on.
    var rendering: Data?

    func makeCoordinator() -> Coordinator {
        Coordinator(entries: entries, rendering: rendering)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.rowHeight = 20
        table.style = .plain
        for column in Column.allCases {
            let tableColumn = NSTableColumn(identifier: column.identifier)
            tableColumn.title = column.title
            tableColumn.width = column.width
            tableColumn.minWidth = 80
            table.addTableColumn(tableColumn)
        }
        table.dataSource = context.coordinator
        table.delegate = context.coordinator

        let scrollView = NSScrollView()
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        context.coordinator.table = table
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        guard coordinator.rendering != rendering || coordinator.entries.count != entries.count else { return }
        coordinator.entries = entries
        coordinator.rendering = rendering
        coordinator.table?.reloadData()
    }

    /// The three columns, each a plain text cell the table reuses as it scrolls.
    enum Column: CaseIterable {
        case address, names, source

        var identifier: NSUserInterfaceItemIdentifier {
            switch self {
            case .address: return NSUserInterfaceItemIdentifier("address")
            case .names: return NSUserInterfaceItemIdentifier("names")
            case .source: return NSUserInterfaceItemIdentifier("source")
            }
        }

        var title: String {
            switch self {
            case .address: return "Address"
            case .names: return "Names"
            case .source: return "Source"
            }
        }

        var width: CGFloat {
            switch self {
            case .address: return 140
            case .names: return 320
            case .source: return 160
            }
        }

        func text(of entry: BlockEntry) -> String {
            switch self {
            case .address: return entry.address
            case .names: return entry.names.joined(separator: ", ")
            case .source: return "\(entry.source.fragment.rawValue):\(entry.source.line)"
            }
        }

        var font: NSFont {
            switch self {
            case .address: return NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            case .names, .source: return NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            }
        }

        var textColor: NSColor {
            switch self {
            case .address, .names: return .labelColor
            case .source: return .secondaryLabelColor
            }
        }
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var entries: [BlockEntry]
        var rendering: Data?
        weak var table: NSTableView?

        init(entries: [BlockEntry], rendering: Data?) {
            self.entries = entries
            self.rendering = rendering
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            entries.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn, let column = Column.allCases.first(where: { $0.identifier == tableColumn.identifier }) else {
                return nil
            }
            let cell = tableView.makeView(withIdentifier: column.identifier, owner: nil) as? NSTableCellView
                ?? Self.makeCell(for: column)
            cell.textField?.stringValue = column.text(of: entries[row])
            return cell
        }

        /// A cell the table reuses: one text field that can be selected and
        /// copied, the way the block's text can.
        @MainActor
        private static func makeCell(for column: Column) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = column.identifier
            let field = NSTextField(labelWithString: "")
            field.font = column.font
            field.textColor = column.textColor
            field.lineBreakMode = .byTruncatingTail
            field.isSelectable = true
            field.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(field)
            cell.textField = field
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }
    }
}
