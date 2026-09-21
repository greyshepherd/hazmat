import HazmatAppSupport
import HazmatCore
import SwiftUI

/// The content pane: what the sidebar selected, edited in place. The phase
/// decides what fills it when there is nothing to edit, and always offers at
/// most one prominent action.
struct ContentPane: View {
    @Bindable var model: ShellModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .safeAreaInset(edge: .bottom) { StatusRow(model: model) }
    }

    /// The selected item, or the phase when there is nothing to edit. The
    /// selection is asked first, so an item the sidebar shows is always
    /// editable, whatever the phase the store is in.
    @ViewBuilder
    private var content: some View {
        switch model.content {
        case .fragment(let fragment):
            FragmentEditor(model: model, fragment: fragment)
        case .profile(let profile):
            LayerStackPane(model: model, profile: profile)
        case .phase(.noStore):
            NoStorePane(model: model)
        case .phase(let phase):
            PhasePane(phase: phase)
        }
    }
}

/// A phase with nothing to edit: what the phase means. The action that fills
/// it lives in the sidebar section or the toolbar it belongs to.
struct PhasePane: View {
    let phase: WindowPhase

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(phase.title)
                .font(.title3)
                .bold()
                .foregroundStyle(.primary)
            Text(phase.explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: 520, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// No store yet: what a store is, where it would go, the three steps that get
/// from here to a written block, and creating it as the only prominent action.
struct NoStorePane: View {
    @Bindable var model: ShellModel

    private var steps: [(String, String)] {
        [
            ("Store", "A folder that holds your profiles and fragments. Hazmat keeps it in Application Support unless you point it elsewhere."),
            ("First profile", "A profile is an ordered stack of fragments; it resolves to the block Hazmat manages."),
            ("Write to the hosts file", "Applying replaces only the block between the two Hazmat markers. Nothing else in the file is touched.")
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("No store yet")
                .font(.title3)
                .bold()
                .foregroundStyle(.primary)
            Text("A store is a folder that holds your profiles and fragments. Nothing is written to the hosts file until you ask.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Location")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(model.storeRoot.path)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.primary)
                    Button {
                        model.copyStorePath()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy the location")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(step.0)
                                .font(.callout)
                                .foregroundStyle(.primary)
                            Text(step.1)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                PrimaryActionButton(action: .createStore) { model.perform($0) }
                Button(WindowAction.chooseLocation.title) { model.perform(.chooseLocation) }
            }
        }
        .padding(20)
        .frame(maxWidth: 620, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A selected fragment: its labelled name, its text in a monospaced editor, and
/// whether the draft is saved. A fragment fetched from a URL is shown read-only
/// with the URL it comes from and the action that refreshes it, because the next
/// refresh replaces its text.
struct FragmentEditor: View {
    @Bindable var model: ShellModel
    let fragment: FragmentID
    @State private var nameDraft = ""

    var body: some View {
        let editor: EditorPresentation = model.editor
        let origin = editor.origin(of: fragment)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Fragment")
                    .font(.title3)
                    .bold()
                    .foregroundStyle(.primary)
                Spacer()
                if let origin {
                    // The chip carries the state, not the kind: where the text
                    // comes from is the row below it and the sidebar's mark.
                    StatusLabel(
                        symbolName: origin.isOutOfDate ? "arrow.triangle.2.circlepath" : "checkmark.circle",
                        word: origin.isOutOfDate ? "Out of date" : "Fetched",
                        tone: origin.isOutOfDate ? .warning : .success
                    )
                } else if model.fragmentIsDirty {
                    StatusLabel(symbolName: "pencil", word: "Unsaved changes", tone: .warning)
                } else {
                    StatusLabel(symbolName: "checkmark.circle", word: "Saved", tone: .success)
                }
            }

            LabeledContent("Name") {
                HStack(spacing: 6) {
                    TextField("Fragment name", text: $nameDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                    Button("Rename") { model.renameFragment(to: nameDraft) }
                        .disabled(!NameSyntax.isIdentifier(nameDraft) || nameDraft == fragment.rawValue)
                }
            }
            .onAppear { nameDraft = fragment.rawValue }
            .onChange(of: fragment) { _, name in nameDraft = name.rawValue }

            if let origin {
                LabeledContent("Fetched from") {
                    Text(origin.url?.absoluteString ?? "the source record cannot be read")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                LabeledContent("Refresh") {
                    Text(origin.state)
                        .foregroundStyle(origin.isOutOfDate ? .orange : .secondary)
                }
            }

            LabeledContent("Entries") {
                let count = editor.entryCount(of: fragment) ?? 0
                Text(EntryCount.phrase(count))
                    .foregroundStyle(.secondary)
            }

            PlainTextView(text: model.fragmentDraft, isEditable: origin == nil) { text in
                model.fragmentDraft = text
            }
            .frame(minHeight: 220)
            .background(
                Color(nsColor: origin == nil ? .controlBackgroundColor : .underPageBackgroundColor),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(nsColor: .separatorColor))
            }

            HStack(spacing: 8) {
                if origin != nil {
                    Button("Refresh Now") { model.refreshSource(fragment) }
                    Spacer()
                    Text("Fetched text is read-only here; the next refresh replaces it. Edit the file itself to keep changes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button(WindowAction.save.title) { model.saveFragment(text: model.fragmentDraft) }
                        .disabled(!model.fragmentIsDirty)
                    Spacer()
                    Text("Saved edits to the applied profile re-apply its block.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
    }
}

/// A selected profile: its layers in order, each with the entries it holds, the
/// rule that decides conflicts, drag reordering and removal.
struct LayerStackPane: View {
    @Bindable var model: ShellModel
    let profile: ProfileID

    var body: some View {
        let editor: EditorPresentation = model.editor
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Layers")
                    .font(.title3)
                    .bold()
                    .foregroundStyle(.primary)
                Text(profile.rawValue)
                    .foregroundStyle(.secondary)
                Spacer()
                if !editor.fragmentRows.isEmpty {
                    Menu("Add a Fragment") {
                        ForEach(editor.fragmentRows) { row in
                            Button("\(row.fragment.rawValue) — \(row.entryCount) entries") {
                                model.addLayer(row.fragment)
                            }
                        }
                    }
                    .frame(maxWidth: 160)
                }
            }

            Text("Layers are applied in order, and a later layer wins a conflict. Drag a layer to reorder it.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if editor.layerRows.isEmpty {
                emptyLayers
            } else {
                List {
                    ForEach(editor.layerRows) { row in
                        layerRow(row)
                    }
                    .onMove { indices, destination in
                        guard let source = indices.first else { return }
                        model.moveLayer(from: source, beforeInsertionAt: destination)
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 200)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(nsColor: .separatorColor))
                }
            }
        }
        .padding(16)
    }

    private func layerRow(_ row: LayerRow) -> some View {
        HStack(spacing: 10) {
            Text("\(row.position).")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .trailing)
            Text(row.fragment.rawValue)
                .foregroundStyle(.primary)
            Spacer(minLength: 4)
            Text(EntryCount.phrase(row.entryCount))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                model.removeLayer(at: row.position - 1)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove this layer")
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Remove", role: .destructive) { model.removeLayer(at: row.position - 1) }
        }
    }

    private var emptyLayers: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No layers yet")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("Layers are applied in order and a later layer wins a conflict. Adding a fragment is the first step.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 520, alignment: .leading)
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}
