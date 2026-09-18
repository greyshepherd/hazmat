import HazmatAppSupport
import HazmatCore
import SwiftUI

/// How the resolved block is read.
enum ResolvedViewMode: String, CaseIterable, Equatable {
    case text
    case table

    var title: String {
        switch self {
        case .text: return "Text"
        case .table: return "Table"
        }
    }
}

/// The detail pane: the block the selected profile resolves to, or the profiles
/// that use the selected fragment. It reads and shows; it never writes.
struct DetailPane: View {
    @Bindable var model: ShellModel
    @State private var mode: ResolvedViewMode = .text

    var body: some View {
        let editor: EditorPresentation = model.editor
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch editor.selection {
                case .profile:
                    resolved(editor)
                case .fragment(let fragment):
                    usedIn(editor, fragment)
                case nil:
                    Text("Nothing is selected.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - A profile's resolved block

    @ViewBuilder
    private func resolved(_ editor: EditorPresentation) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Resolved")
                .font(.title3)
                .bold()
                .foregroundStyle(.primary)
            Spacer()
            Picker("View", selection: $mode) {
                ForEach(ResolvedViewMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
        }

        if let problem = editor.storeProblem {
            problemRow(problem)
        }

        if editor.layers.isEmpty {
            note("This profile stacks no layers, so there is nothing to write yet.")
        }

        if !editor.problems.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(editor.problems.enumerated()), id: \.offset) { _, problem in
                    problemRow(problem.message)
                }
            }
        }

        if editor.rendering != nil {
            let count = editor.entryCount
            Text("\(count) \(count == 1 ? "entry" : "entries")")
                .font(.caption)
                .foregroundStyle(.secondary)

            switch mode {
            case .text:
                blockText(editor)
            case .table:
                blockTable(editor)
            }
        }

        if !editor.displacements.isEmpty {
            DisplacementsView(displacements: editor.displacements)
        }
    }

    /// The block as selectable monospaced text: the bytes that would be written.
    private func blockText(_ editor: EditorPresentation) -> some View {
        let rendered = editor.rendering.map { String(decoding: $0, as: UTF8.self) } ?? ""
        return Text(rendered)
            .font(.system(.callout, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor))
            }
    }

    /// One row per address line: the address, the names on it, and the fragment
    /// that supplied it.
    private func blockTable(_ editor: EditorPresentation) -> some View {
        let rows = editor.entryLines.enumerated().map { EntryTableRow(id: $0.offset, entry: $0.element) }
        return Table(rows) {
            TableColumn("Address") { row in
                Text(row.entry.address)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
            }
            TableColumn("Names") { row in
                Text(row.entry.names.joined(separator: ", "))
                    .textSelection(.enabled)
            }
            TableColumn("Source") { row in
                Text("\(row.entry.source.fragment.rawValue):\(row.entry.source.line)")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 220)
    }

    private func problemRow(_ message: String) -> some View {
        StatusLabel(
            symbolName: "exclamationmark.triangle",
            word: message,
            tone: .danger,
            font: .callout
        )
    }

    private func note(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    // MARK: - A fragment's using profiles

    @ViewBuilder
    private func usedIn(_ editor: EditorPresentation, _ fragment: FragmentID) -> some View {
        let users = editor.usingProfiles
        HStack(alignment: .firstTextBaseline) {
            Text("Used in")
                .font(.title3)
                .bold()
                .foregroundStyle(.primary)
            Spacer()
            Text("\(users.count) \(users.count == 1 ? "profile" : "profiles")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        let entries = editor.entryCount(of: fragment) ?? 0
        Text("\(fragment) holds \(entries) \(entries == 1 ? "entry" : "entries").")
            .font(.caption)
            .foregroundStyle(.secondary)

        if users.isEmpty {
            StatusLabel(
                symbolName: "questionmark.circle",
                word: "No profile uses this fragment yet.",
                tone: .neutral,
            )
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(users, id: \.self) { profile in
                    HStack(spacing: 8) {
                        Image(systemName: "square.stack.3d.up")
                            .foregroundStyle(.secondary)
                        Text(profile.rawValue)
                            .foregroundStyle(.primary)
                        Spacer()
                        if editor.isApplied(profile) {
                            Label("Applied", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor))
            }
        }
    }
}

/// A table row for one entry line, with an identity the table can diff.
struct EntryTableRow: Identifiable {
    let id: Int
    let entry: BlockEntry
}

/// The entries a later layer displaced, with both fragments named.
struct DisplacementsView: View {
    let displacements: [Displacement]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Overridden")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("A later layer won these names.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(Array(displacements.enumerated()), id: \.offset) { pair in
                Text(
                    "\(pair.element.name) — \(pair.element.address) from \(pair.element.source.fragment.rawValue):\(pair.element.source.line) overridden by \(pair.element.displacedBy.fragment.rawValue):\(pair.element.displacedBy.line)"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
