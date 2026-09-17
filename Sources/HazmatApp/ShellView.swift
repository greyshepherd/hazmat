import HazmatAppSupport
import HazmatCore
import SwiftUI

/// The window: the store's profiles and fragments, the selected fragment's
/// text, the selected profile's layer stack, and what that profile resolves to.
/// Every value comes from the presentation in app support, so this renders and
/// forwards rather than deciding.
struct ShellView: View {
    @Bindable var model: ShellModel
    @State private var fragmentDraft = ""
    @State private var newProfileName = ""
    @State private var newFragmentName = ""

    var body: some View {
        let editor = model.editor
        VStack(alignment: .leading, spacing: 12) {
            header
            store(editor)
            HStack(alignment: .top, spacing: 12) {
                profiles(editor)
                fragments(editor)
            }
            fragmentText(editor)
            layerStack(editor)
            resolved(editor)
            hostsFile(editor)
            Text(model.notice)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 760)
        .task { model.refresh() }
        .onAppear { fragmentDraft = editor.fragmentText }
        .onChange(of: model.editor.fragmentText) { _, text in fragmentDraft = text }
        .onChange(of: model.selectedProfile) { model.selectionChanged() }
        .onChange(of: model.selectedFragment) { model.selectionChanged() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hazmat")
                .font(.title2)
                .bold()
            Text(model.helper.summary)
            HStack {
                Button("Register") { model.register() }
                    .disabled(model.helper != .notRegistered || model.busy)
                Button("Unregister") { model.unregister() }
                    .disabled(model.helper == .notRegistered || model.busy)
                Button("Refresh") { model.refresh() }
                    .disabled(model.busy)
            }
        }
    }

    @ViewBuilder
    private func store(_ editor: EditorPresentation) -> some View {
        if editor.storeExists {
            Text(editor.storePath)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            GroupBox("Store") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No store at \(editor.storePath) yet. Creating a profile makes one.")
                    HStack {
                        TextField("Profile name", text: $newProfileName)
                        Button("Create Profile") { model.createProfile(named: newProfileName) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
        }
    }

    private func profiles(_ editor: EditorPresentation) -> some View {
        GroupBox("Profiles") {
            VStack(alignment: .leading, spacing: 8) {
                List(selection: $model.selectedProfile) {
                    ForEach(editor.profiles, id: \.self) { profile in
                        HStack {
                            Text(profile.rawValue)
                            if editor.isApplied, editor.selectedProfile == profile {
                                Spacer()
                                Text("applied")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(Optional(profile))
                    }
                }
                .frame(minHeight: 110)

                TextField("Name", text: $newProfileName)
                HStack {
                    Button("New") { model.createProfile(named: newProfileName) }
                    Button("Rename") { model.renameProfile(to: newProfileName) }
                        .disabled(editor.selectedProfile == nil)
                    Button("Duplicate") { model.duplicateProfile(as: newProfileName) }
                        .disabled(editor.selectedProfile == nil)
                    Button("Delete") { model.deleteProfile() }
                        .disabled(editor.selectedProfile == nil)
                }
            }
            .padding(.top, 4)
        }
    }

    private func fragments(_ editor: EditorPresentation) -> some View {
        GroupBox("Fragments") {
            VStack(alignment: .leading, spacing: 8) {
                List(selection: $model.selectedFragment) {
                    ForEach(editor.fragments, id: \.self) { fragment in
                        Text(fragment.rawValue).tag(Optional(fragment))
                    }
                }
                .frame(minHeight: 110)

                TextField("Name", text: $newFragmentName)
                HStack {
                    Button("New") { model.createFragment(named: newFragmentName) }
                    Button("Rename") { model.renameFragment(to: newFragmentName) }
                        .disabled(editor.selectedFragment == nil)
                    Button("Duplicate") { model.duplicateFragment(as: newFragmentName) }
                        .disabled(editor.selectedFragment == nil)
                    Button("Delete") { model.deleteFragment() }
                        .disabled(editor.selectedFragment == nil)
                }
            }
            .padding(.top, 4)
        }
    }

    private func fragmentText(_ editor: EditorPresentation) -> some View {
        GroupBox("Fragment \(editor.selectedFragment?.rawValue ?? "—")") {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $fragmentDraft)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 120)
                Button("Save") { model.saveFragment(text: fragmentDraft) }
                    .disabled(editor.selectedFragment == nil || model.busy)
            }
            .padding(.top, 4)
        }
    }

    private func layerStack(_ editor: EditorPresentation) -> some View {
        GroupBox("Layers of \(editor.selectedProfile?.rawValue ?? "—")") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(editor.layers.enumerated()), id: \.offset) { index, layer in
                    HStack {
                        Text("\(index + 1). \(layer.rawValue)")
                        Spacer()
                        Button("Up") { model.moveLayer(from: index, to: index - 1) }
                            .disabled(index == 0)
                        Button("Down") { model.moveLayer(from: index, to: index + 1) }
                            .disabled(index == editor.layers.count - 1)
                        Button("Remove") { model.removeLayer(at: index) }
                    }
                }
                if editor.layers.isEmpty {
                    Text("No layers. The profile renders an empty block.")
                        .foregroundStyle(.secondary)
                }
                Menu("Add Layer") {
                    ForEach(editor.fragments, id: \.self) { fragment in
                        Button(fragment.rawValue) { model.addLayer(fragment) }
                    }
                }
                .disabled(editor.selectedProfile == nil || editor.fragments.isEmpty)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private func resolved(_ editor: EditorPresentation) -> some View {
        GroupBox("Resolved") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(editor.entries.enumerated()), id: \.offset) { _, entry in
                    Text("\(entry.address) \(entry.name) — \(entry.source.fragment.rawValue):\(entry.source.line)")
                }
                ForEach(Array(editor.displacements.enumerated()), id: \.offset) { _, displaced in
                    Text(
                        "\(displaced.address) \(displaced.name) displaced by \(displaced.displacedBy.fragment.rawValue):\(displaced.displacedBy.line) over \(displaced.source.fragment.rawValue):\(displaced.source.line)"
                    )
                    .foregroundStyle(.secondary)
                }
                ForEach(Array(editor.problems.enumerated()), id: \.offset) { _, problem in
                    Text(problem.message)
                }
                if editor.problems.isEmpty, editor.entries.isEmpty, editor.selectedProfile != nil {
                    Text("This profile resolves to nothing.")
                        .foregroundStyle(.secondary)
                }
                if let problem = editor.storeProblem {
                    Text(problem)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private func hostsFile(_ editor: EditorPresentation) -> some View {
        GroupBox("Hosts file") {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.liveDescription)
                HStack {
                    Button("Apply") { model.apply() }
                    Button("Overwrite Drift") { model.overwriteDrift() }
                        .disabled(editor.live.liveBlock == nil)
                    Button("Remove Block") { model.removeBlock() }
                }
                .disabled(model.helper != .enabled || model.busy)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }
}
