import HazmatAppSupport
import HazmatCore
import SwiftUI

/// The helper, explained: what it may do, which states it can be in, and the one
/// action that moves it forward. Reachable from the first-run phase and from the
/// sidebar footer.
struct HelperSheetView: View {
    @Bindable var model: ShellModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.brand) private var palette

    var body: some View {
        let sheet: HelperSheetPresentation = model.helperSheet
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("The Hazmat Helper")
                    .font(.title3)
                    .bold()
                    .foregroundStyle(palette.textPrimary.color)
                Spacer()
                StatusLabel(
                    symbolName: sheet.current.symbolName,
                    word: sheet.current.label,
                    tone: sheet.current.tone,
                    palette: palette
                )
            }

            Text("Rewriting the hosts file needs administrator rights. The helper is a small background service that has them — and does nothing else.")
                .font(.callout)
                .foregroundStyle(palette.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(sheet.privileges) { privilege in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.shield")
                            .foregroundStyle(palette.mark(.success).color)
                        Text(privilege.detail)
                            .font(.callout)
                            .foregroundStyle(palette.textPrimary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(12)
            .background(palette.well.color, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                Text("States")
                    .font(.headline)
                    .foregroundStyle(palette.textPrimary.color)
                ForEach(sheet.states) { note in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: note.state.symbolName)
                            .foregroundStyle(palette.mark(note.state.tone).color)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(note.state.label)
                                .font(.callout)
                                .foregroundStyle(
                                    note.state == sheet.current
                                        ? palette.text(note.state.tone).color
                                        : palette.textSecondary.color
                                )
                            Text(note.detail)
                                .font(.caption)
                                .foregroundStyle(palette.textSecondary.color)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                if sheet.current.canWrite {
                    Button("Unregister the Helper") { model.unregister() }
                } else {
                    PrimaryActionButton(action: .installHelper, palette: palette) { _ in model.register() }
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
