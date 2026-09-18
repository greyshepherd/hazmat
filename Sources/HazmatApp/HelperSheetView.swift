import HazmatAppSupport
import HazmatCore
import SwiftUI

/// The helper, explained: what it may do, which states it can be in, and the one
/// action that moves it forward. Reachable from the first-run phase and from the
/// sidebar footer.
struct HelperSheetView: View {
    @Bindable var model: ShellModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let sheet: HelperSheetPresentation = model.helperSheet
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("The Hazmat Helper")
                    .font(.title3)
                    .bold()
                    .foregroundStyle(.primary)
                Spacer()
                StatusLabel(
                    symbolName: sheet.current.symbolName,
                    word: sheet.current.label,
                    tone: sheet.current.tone,
                )
            }

            Text("Rewriting the hosts file needs administrator rights. The helper is a small background service that has them — and does nothing else.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(sheet.privileges) { privilege in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.shield")
                            .foregroundStyle(.green)
                        Text(privilege.detail)
                            .font(.callout)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                Text("States")
                    .font(.headline)
                    .foregroundStyle(.primary)
                ForEach(sheet.states) { note in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: note.state.symbolName)
                            .foregroundStyle(note.state.tone.color)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(note.state.label)
                                .font(.callout)
                                .foregroundStyle(
                                    note.state == sheet.current
                                        ? note.state.tone.color
                                        : .secondary
                                )
                            Text(note.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                if sheet.current == .notAnswering {
                    PrimaryActionButton(action: .repairHelper) { _ in model.repairHelper() }
                } else if sheet.current.canWrite {
                    Button("Unregister the Helper") { model.unregister() }
                } else {
                    PrimaryActionButton(action: .installHelper) { _ in model.register() }
                }
                if sheet.current == .awaitingApproval {
                    Button("Open Login Items Settings") { model.openLoginItemsSettings() }
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
