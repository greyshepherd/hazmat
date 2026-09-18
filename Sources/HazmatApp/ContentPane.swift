import HazmatAppSupport
import HazmatCore
import SwiftUI

/// The content pane: what the sidebar selected, edited in place. The phase
/// decides what fills it when there is nothing to edit, and always offers at
/// most one prominent action.
struct ContentPane: View {
    @Bindable var model: ShellModel
    @Environment(\.brand) private var palette

    var body: some View {
        let editor: EditorPresentation = model.editor
        VStack(alignment: .leading, spacing: 0) {
            content(editor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .safeAreaInset(edge: .bottom) { StatusRow(model: model) }
        .sheet(isPresented: $model.isAddingLayer) {
            AddLayerSheet(model: model)
        }
    }

    @ViewBuilder
    private func content(_ editor: EditorPresentation) -> some View {
        switch model.phase {
        case .noStore:
            NoStorePane(model: model)
        case .noProfiles:
            PhasePane(
                phase: model.phase,
                action: model.primaryAction,
                palette: palette,
                perform: { model.perform($0) }
            )
        default:
            switch editor.selection {
            case .fragment(let fragment):
                FragmentEditor(model: model, fragment: fragment)
            case .profile(let profile):
                LayerStackPane(model: model, profile: profile)
            case nil:
                PhasePane(
                    phase: model.phase,
                    action: model.primaryAction,
                    palette: palette,
                    perform: { model.perform($0) }
                )
            }
        }
    }
}

/// A phase with nothing to edit: what the phase means, and its one prominent
/// action.
struct PhasePane: View {
    let phase: WindowPhase
    let action: WindowAction?
    let palette: BrandPalette
    let perform: (WindowAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(phase.title)
                .font(.title3)
                .bold()
                .foregroundStyle(palette.textPrimary.color)
            Text(phase.explanation)
                .font(.callout)
                .foregroundStyle(palette.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                PrimaryActionButton(action: action, palette: palette, perform: perform)
            }
            Spacer(minLength: 0)
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
    @Environment(\.brand) private var palette

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
                .foregroundStyle(palette.textPrimary.color)
            Text("A store is a folder that holds your profiles and fragments. Nothing is written to the hosts file until you ask.")
                .font(.callout)
                .foregroundStyle(palette.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Location")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary.color)
                HStack(spacing: 8) {
                    Text(model.storeRoot.path)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(palette.textPrimary.color)
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
                            .foregroundStyle(palette.textSecondary.color)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(step.0)
                                .font(.callout)
                                .foregroundStyle(palette.textPrimary.color)
                            Text(step.1)
                                .font(.caption)
                                .foregroundStyle(palette.textSecondary.color)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                PrimaryActionButton(action: .createStore, palette: palette) { model.perform($0) }
                Button(WindowAction.chooseLocation.title) { model.perform(.chooseLocation) }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: 620, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A selected fragment: its labelled name, its text in a monospaced editor, and
/// whether the draft is saved.
struct FragmentEditor: View {
    @Bindable var model: ShellModel
    let fragment: FragmentID
    @Environment(\.brand) private var palette
    @State private var nameDraft = ""

    var body: some View {
        let editor: EditorPresentation = model.editor
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Fragment")
                    .font(.title3)
                    .bold()
                    .foregroundStyle(palette.textPrimary.color)
                Spacer()
                if model.fragmentIsDirty {
                    StatusLabel(symbolName: "pencil", word: "Unsaved changes", tone: .warning, palette: palette)
                } else {
                    StatusLabel(symbolName: "checkmark.circle", word: "Saved", tone: .success, palette: palette)
                }
            }

            LabeledContent("Name") {
                HStack(spacing: 6) {
                    TextField("Fragment name", text: $nameDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                    Button("Rename") { model.renameFragment(to: nameDraft) }
                        .disabled(nameDraft == fragment.rawValue || nameDraft.isEmpty)
                }
            }
            .onAppear { nameDraft = fragment.rawValue }
            .onChange(of: fragment) { _, name in nameDraft = name.rawValue }

            LabeledContent("Entries") {
                let count = editor.entryCount(of: fragment) ?? 0
                Text("\(count) \(count == 1 ? "entry" : "entries")")
                    .foregroundStyle(palette.textSecondary.color)
            }

            TextEditor(text: $model.fragmentDraft)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 220)
                .scrollContentBackground(.hidden)
                .background(palette.surface.color, in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(palette.border.color)
                }

            HStack(spacing: 8) {
                Button(WindowAction.save.title) { model.saveFragment(text: model.fragmentDraft) }
                    .disabled(!model.fragmentIsDirty)
                Spacer()
                Text("Saved edits to the applied profile re-apply its block.")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary.color)
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
    @Environment(\.brand) private var palette

    var body: some View {
        let editor: EditorPresentation = model.editor
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Layers")
                    .font(.title3)
                    .bold()
                    .foregroundStyle(palette.textPrimary.color)
                Text(profile.rawValue)
                    .foregroundStyle(palette.textSecondary.color)
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
                .foregroundStyle(palette.textSecondary.color)

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
                .background(palette.surface.color, in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(palette.border.color)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private func layerRow(_ row: LayerRow) -> some View {
        HStack(spacing: 10) {
            Text("\(row.position).")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(palette.textSecondary.color)
                .frame(width: 22, alignment: .trailing)
            Text(row.fragment.rawValue)
                .foregroundStyle(palette.textPrimary.color)
            Spacer(minLength: 4)
            Text("\(row.entryCount) \(row.entryCount == 1 ? "entry" : "entries")")
                .font(.caption)
                .foregroundStyle(palette.textSecondary.color)
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
                .foregroundStyle(palette.textPrimary.color)
            Text("Layers are applied in order and a later layer wins a conflict. Adding a fragment is the first step.")
                .font(.callout)
                .foregroundStyle(palette.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
            if model.primaryAction == .addFragment {
                PrimaryActionButton(action: .addFragment, palette: palette) { model.perform($0) }
            } else if model.primaryAction == .newFragment {
                PrimaryActionButton(action: .newFragment, palette: palette) { model.perform($0) }
            } else if !model.editor.fragmentRows.isEmpty {
                Button(WindowAction.addFragment.title) { model.perform(.addFragment) }
            } else {
                Button(WindowAction.newFragment.title) { model.perform(.newFragment) }
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
        .padding(12)
        .background(palette.well.color, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// The sheet that adds a fragment to the selected profile, shown by the
/// prominent action of a profile with no layers.
struct AddLayerSheet: View {
    @Bindable var model: ShellModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.brand) private var palette

    var body: some View {
        let editor: EditorPresentation = model.editor
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a Fragment")
                .font(.title3)
                .bold()
                .foregroundStyle(palette.textPrimary.color)
            Text("The layer is appended to the stack, so it wins a conflict with the layers above it.")
                .font(.callout)
                .foregroundStyle(palette.textSecondary.color)

            if editor.fragmentRows.isEmpty {
                Text("The store holds no fragments yet.")
                    .foregroundStyle(palette.textSecondary.color)
                Button(WindowAction.newFragment.title) {
                    dismiss()
                    model.beginCreate(.newFragment)
                }
            } else {
                List(editor.fragmentRows) { row in
                    Button {
                        dismiss()
                        model.addLayer(row.fragment)
                    } label: {
                        HStack {
                            Text(row.fragment.rawValue)
                                .foregroundStyle(palette.textPrimary.color)
                            Spacer()
                            Text("\(row.entryCount) \(row.entryCount == 1 ? "entry" : "entries")")
                                .font(.caption)
                                .foregroundStyle(palette.textSecondary.color)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .frame(minHeight: 180)
            }

            HStack {
                Button(WindowAction.newFragment.title) {
                    dismiss()
                    model.beginCreate(.newFragment)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
