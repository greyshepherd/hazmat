import HazmatAppSupport
import SwiftUI

/// The window: three panes at once — the store's profiles and fragments, the
/// selected item, and the block it resolves to — with the phase deciding what
/// each pane offers. Every value comes from the presentation in app support, so
/// this renders and forwards rather than deciding.
struct ShellView: View {
    @Bindable var model: ShellModel
    @State private var searchPresented = false

    var body: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            SidebarView(model: model)
        } content: {
            ContentPane(model: model)
                .navigationSplitViewColumnWidth(min: 300, ideal: 300, max: 340)
        } detail: {
            DetailPane(model: model)
                .navigationSplitViewColumnWidth(min: 320, ideal: 600)
        }
        .navigationTitle("Hazmat")
        .searchable(
            text: $model.searchText,
            isPresented: $searchPresented,
            placement: .sidebar,
            prompt: "Search profiles and fragments"
        )
        .toolbar { toolbar }
        .frame(minWidth: 880, minHeight: 560)
        .task { model.refresh() }
        .onChange(of: model.searchText) { _, _ in model.searchChanged() }
        .onChange(of: model.searchFocusRequests) { _, _ in searchPresented = true }
        .sheet(isPresented: $model.showHelperSheet) {
            HelperSheetView(model: model)
        }
        .confirmationDialog(
            model.confirmation?.title ?? "",
            isPresented: confirmationPresented,
            titleVisibility: .visible,
            presenting: model.confirmation
        ) { request in
            Button(request.confirmTitle, role: request.isDestructive ? .destructive : nil) {
                model.confirm()
            }
            Button("Cancel", role: .cancel) { model.cancelConfirmation() }
        } message: { request in
            Text(request.message)
        }
        .alert(
            model.nameEntry?.title ?? "",
            isPresented: nameEntryPresented,
            presenting: model.nameEntry
        ) { entry in
            TextField(entry.placeholder, text: $model.nameDraft)
            Button(entry.confirmTitle) { model.commitNameEntry() }
            Button("Cancel", role: .cancel) { model.cancelNameEntry() }
        }
    }

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { model.sidebarVisible ? .all : .doubleColumn },
            set: { model.sidebarVisible = $0 == .all }
        )
    }

    private var confirmationPresented: Binding<Bool> {
        Binding(
            get: { model.confirmation != nil },
            set: { shown in if !shown { model.cancelConfirmation() } }
        )
    }

    private var nameEntryPresented: Binding<Bool> {
        Binding(
            get: { model.nameEntry != nil },
            set: { shown in if !shown { model.cancelNameEntry() } }
        )
    }

    /// The toolbar carries the new-item menu and reload: actions every phase can
    /// perform, each with the shortcut the menu bar binds. The sidebar toggle is
    /// the split view's own, so the toolbar does not draw a second one.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        let commands: CommandPresentation = model.commands
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button(commands.item("new-profile")?.title ?? WindowAction.newProfile.title) {
                    model.perform(.newProfile)
                }
                Button(commands.item("new-fragment")?.title ?? WindowAction.newFragment.title) {
                    model.perform(.newFragment)
                }
            } label: {
                Image(systemName: "plus")
            }
            .help("New Profile (⌘N) or New Fragment (⇧⌘N)")
            Button {
                model.perform(.reload)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help(
                "\(commands.item("reload")?.title ?? WindowAction.reload.title) (\(commands.item("reload")?.shortcut?.display ?? "⌘R"))"
            )
        }
    }
}
