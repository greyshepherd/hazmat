import HazmatAppSupport
import HazmatCore
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
            // The layers pane opens at the width a layer list reads at, and the
            // divider narrows it to its minimum or widens it for a long list.
            ContentPane(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 350)
        } detail: {
            DetailPane(model: model)
                .navigationSplitViewColumnWidth(min: 400, ideal: 600)
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
        .sheet(isPresented: sourceSheetIsPresented) {
            SourceSheetView(model: model)
        }
        .modifier(WindowAsks(model: model))
    }

    /// The source sheet is a value the model holds, so its presence is derived
    /// from it and a dismissal cancels it.
    private var sourceSheetIsPresented: Binding<Bool> {
        Binding(
            get: { model.sourceSheet != nil },
            set: { presented in
                if !presented { model.cancelSourceSheet() }
            }
        )
    }

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { model.sidebarVisible ? .all : .doubleColumn },
            set: { model.sidebarVisible = $0 == .all }
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
                Button(commands.item("new-source")?.title ?? WindowAction.newSource.title) {
                    model.perform(.newSource)
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

/// What the window asks before it acts: a write's confirmation, a deletion's,
/// and a name. Each is a value on the model; the modifier presents it and hands
/// the answer back.
private struct WindowAsks: ViewModifier {
    @Bindable var model: ShellModel

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                model.confirmation?.title ?? "",
                isPresented: presented(\.confirmation, dismiss: model.cancelConfirmation),
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
            .confirmationDialog(
                model.deletion?.title ?? "",
                isPresented: presented(\.deletion, dismiss: model.cancelDelete),
                titleVisibility: .visible,
                presenting: model.deletion
            ) { request in
                Button(request.confirmTitle, role: .destructive) { model.confirmDelete() }
                Button("Cancel", role: .cancel) { model.cancelDelete() }
            } message: { request in
                Text(request.message)
            }
            .alert(
                model.nameEntry?.title ?? "",
                isPresented: presented(\.nameEntry, dismiss: model.cancelNameEntry),
                presenting: model.nameEntry
            ) { entry in
                TextField(entry.placeholder, text: $model.nameDraft)
                Button(entry.confirmTitle) { model.commitNameEntry() }
                    .disabled(!model.nameDraftIsUsable)
                Button("Cancel", role: .cancel) { model.cancelNameEntry() }
            } message: { _ in
                Text(NameSyntax.requirement)
            }
    }

    /// Whether an ask is on the model; dismissing it from the window clears it.
    private func presented<Value>(
        _ ask: KeyPath<ShellModel, Value?>,
        dismiss: @escaping () -> Void
    ) -> Binding<Bool> {
        Binding(
            get: { model[keyPath: ask] != nil },
            set: { shown in if !shown { dismiss() } }
        )
    }
}
