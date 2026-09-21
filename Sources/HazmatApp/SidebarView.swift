import HazmatAppSupport
import HazmatCore
import SwiftUI

/// The sidebar: the store's profiles and fragments as selectable rows, each
/// section saying what belongs in it when it is empty, and the helper's state
/// in its footer in every phase.
struct SidebarView: View {
    @Bindable var model: ShellModel

    var body: some View {
        let editor: EditorPresentation = model.editor
        List(selection: $model.selection) {
            Section("Profiles") {
                if editor.profileRows.isEmpty {
                    EmptyListEntry(
                        title: "No profiles",
                        detail: "A profile is an ordered stack of fragments, and it resolves to the block Hazmat writes.",
                        actionTitle: WindowAction.newProfile.title,
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
        .safeAreaInset(edge: .bottom) { helperFooter }
        .onChange(of: model.selection) { _, _ in model.selectionChanged() }
    }

    private func profileRow(_ row: ProfileRow) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.profile.rawValue)
                    .foregroundStyle(.primary)
                Text("\(row.layerCount) \(row.layerCount == 1 ? "layer" : "layers")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if row.isApplied {
                Label("Applied", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            }
        }
    }

    private func fragmentRow(_ row: FragmentRow) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(row.fragment.rawValue)
                        .foregroundStyle(.primary)
                    if row.isRemote {
                        // A globe, not a download arrow: this marks where the
                        // text comes from, and an arrow read as something the
                        // row was about to do.
                        Image(systemName: "globe")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help(row.origin?.url?.absoluteString ?? "the source record cannot be read")
                    }
                }
                if let origin = row.origin {
                    // A source's row names where its text comes from and how the
                    // last refresh went, in place of the entry count that would
                    // only say how much arrived. The domain, not the whole
                    // address: a sidebar column truncates an address to the point
                    // where two sources look alike.
                    Text(origin.host ?? "the source record cannot be read")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(origin.url?.absoluteString ?? "the source record cannot be read")
                    Text(origin.state)
                        .font(.caption)
                        .foregroundStyle(origin.isOutOfDate ? .orange : .secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            if !row.isRemote {
                Text("\(row.entryCount) \(row.entryCount == 1 ? "entry" : "entries")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(row))
    }

    private func accessibilityLabel(_ row: FragmentRow) -> String {
        guard let origin = row.origin else {
            return "\(row.fragment.rawValue), \(row.entryCount) entries"
        }
        return "\(row.fragment.rawValue), fetched from \(origin.url?.absoluteString ?? "an unreadable source record"), \(origin.state)"
    }

    /// A row's own menu acts on that row, not on the selection: opening it does
    /// not select the row, so each item names the row it was opened on.
    @ViewBuilder
    private func contextMenu(for row: SidebarSelection) -> some View {
        if case .fragment(let fragment) = row, model.editor.isRemote(fragment) {
            Button("Refresh Now") { model.refreshSource(fragment) }
            Divider()
        }
        Button(WindowAction.rename.title + "…") { model.beginRename(row) }
        Button(WindowAction.duplicate.title + "…") { model.beginDuplicate(row) }
        if case .fragment(let fragment) = row, let profile = model.editor.selectedProfile {
            Divider()
            Button("Add to \(profile.rawValue)") { model.addLayer(fragment) }
        }
        Divider()
        Button(WindowAction.delete.title + "…", role: .destructive) { model.requestDelete(row) }
    }

    /// The helper as a glyph, a word and a colour, with the action that resolves
    /// it. Present in every phase, and never in the content flow.
    private var helperFooter: some View {
        let helper = model.helper
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: helper.symbolName)
                .foregroundStyle(helper.tone.color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(helper.label)
                    .font(.callout)
                    .foregroundStyle(helper.tone.color)
                Text(helper.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
    let perform: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.primary)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(actionTitle, action: perform)
                .controlSize(.small)
                .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }
}
