import HazmatAppSupport
import HazmatCore
import SwiftUI

/// The sidebar: the store's profiles and fragments as selectable rows, each
/// section saying what belongs in it when it is empty, and the helper's state
/// in its footer in every phase.
struct SidebarView: View {
    @Bindable var model: ShellModel
    @Environment(\.brand) private var palette

    var body: some View {
        let editor: EditorPresentation = model.editor
        List(selection: $model.selection) {
            Section("Profiles") {
                if editor.profileRows.isEmpty {
                    EmptyListEntry(
                        title: "No profiles",
                        detail: "A profile is an ordered stack of fragments, and it resolves to the block Hazmat writes.",
                        actionTitle: WindowAction.newProfile.title,
                        palette: palette
                    ) {
                        model.beginCreate(.newProfile)
                    }
                } else {
                    ForEach(editor.profileRows) { row in
                        profileRow(row)
                            .tag(SidebarSelection.profile(row.profile))
                            .contextMenu { contextMenu(for: .profile(row.profile)) }
                    }
                }
            }

            Section("Fragments") {
                if editor.fragmentRows.isEmpty {
                    EmptyListEntry(
                        title: "No fragments",
                        detail: "A fragment is a piece of a hosts file: entries one profile can stack.",
                        actionTitle: WindowAction.newFragment.title,
                        palette: palette
                    ) {
                        model.beginCreate(.newFragment)
                    }
                } else {
                    ForEach(editor.fragmentRows) { row in
                        fragmentRow(row)
                            .tag(SidebarSelection.fragment(row.fragment))
                            .contextMenu { contextMenu(for: .fragment(row.fragment)) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 236, max: 320)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                scopePicker
                helperFooter
            }
        }
        .onChange(of: model.selection) { _, _ in model.selectionChanged() }
    }

    private func profileRow(_ row: ProfileRow) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.profile.rawValue)
                    .foregroundStyle(palette.textPrimary.color)
                Text("\(row.layerCount) \(row.layerCount == 1 ? "layer" : "layers")")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary.color)
            }
            Spacer(minLength: 4)
            if row.isApplied {
                Label("Applied", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(palette.text(.success).color)
                    .labelStyle(.titleAndIcon)
            }
        }
    }

    private func fragmentRow(_ row: FragmentRow) -> some View {
        HStack(spacing: 8) {
            Text(row.fragment.rawValue)
                .foregroundStyle(palette.textPrimary.color)
            Spacer(minLength: 4)
            Text("\(row.entryCount) \(row.entryCount == 1 ? "entry" : "entries")")
                .font(.caption)
                .foregroundStyle(palette.textSecondary.color)
        }
    }

    @ViewBuilder
    private func contextMenu(for selection: SidebarSelection) -> some View {
        Button(WindowAction.rename.title + "…") { model.beginRename() }
        Button(WindowAction.duplicate.title + "…") { model.beginDuplicate() }
        if case .fragment(let fragment) = selection, let profile = model.editor.selectedProfile {
            Divider()
            Button("Add to \(profile.rawValue)") { model.addLayer(fragment) }
        }
        Divider()
        Button(WindowAction.delete.title, role: .destructive) { model.deleteSelected() }
    }

    /// What the search covers, so the field over the sidebar can be told to
    /// look at one section or both.
    private var scopePicker: some View {
        Picker("Scope", selection: $model.searchScope) {
            ForEach(SearchScope.allCases, id: \.self) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(palette.sidebar.color)
        .overlay(alignment: .top) { Divider() }
        .onChange(of: model.searchScope) { _, _ in model.searchChanged() }
        .accessibilityLabel("Search scope")
    }

    /// The helper as a glyph, a word and a colour, with the action that resolves
    /// it. Present in every phase, and never in the content flow.
    private var helperFooter: some View {
        let helper = model.helper
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: helper.symbolName)
                .foregroundStyle(palette.mark(helper.tone).color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(helper.label)
                    .font(.callout)
                    .foregroundStyle(palette.text(helper.tone).color)
                Text(helper.summary)
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary.color)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            if let remedy = helper.remedy {
                Button(remedy.title) { model.perform(remedy) }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(palette.sidebar.color)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .combine)
    }
}

/// An empty section in the sidebar: what belongs there, and the action that
/// fills it. Never a bare well.
struct EmptyListEntry: View {
    let title: String
    let detail: String
    let actionTitle: String
    let palette: BrandPalette
    let perform: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.callout)
                .foregroundStyle(palette.textPrimary.color)
            Text(detail)
                .font(.caption)
                .foregroundStyle(palette.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
            Button(actionTitle, action: perform)
                .controlSize(.small)
                .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }
}
