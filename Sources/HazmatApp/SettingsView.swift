import HazmatAppSupport
import HazmatCore
import SwiftUI

/// The settings scene: where the store is read from, and the helper's state with
/// the action that resolves it.
struct SettingsView: View {
    @Bindable var model: ShellModel
    @Environment(\.brand) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Store")
                .font(.headline)
                .foregroundStyle(palette.textPrimary.color)

            LabeledContent("Location") {
                HStack(spacing: 8) {
                    Text(model.storeRoot.path)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button(WindowAction.chooseLocation.title) { model.perform(.chooseLocation) }
                }
            }

            if model.locationIsOverridden {
                StatusLabel(
                    symbolName: "exclamationmark.triangle",
                    word: "The environment names a store root, which overrides the chosen location.",
                    tone: .warning,
                    palette: palette
                )
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button(WindowAction.createStore.title) { model.perform(.createStore) }
                    .disabled(model.editor.storeExists)
                Button(WindowAction.revealHostsFile.title) { model.perform(.revealHostsFile) }
                Button("Copy the Location") { model.copyStorePath() }
            }

            Divider()

            Text("Helper")
                .font(.headline)
                .foregroundStyle(palette.textPrimary.color)

            HStack(alignment: .top, spacing: 8) {
                StatusLabel(
                    symbolName: model.helper.symbolName,
                    word: model.helper.label,
                    tone: model.helper.tone,
                    palette: palette
                )
                Text(model.helper.summary)
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if model.helper.canWrite {
                    Button("Unregister the Helper") { model.unregister() }
                } else {
                    Button(WindowAction.installHelper.title) { model.perform(.installHelper) }
                }
                if model.helper == .awaitingApproval {
                    Button("Open Login Items Settings") { model.openLoginItemsSettings() }
                }
            }

            if !model.notice.isEmpty {
                Text(model.notice)
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 520, alignment: .leading)
    }
}
