import HazmatAppSupport
import HazmatCore
import SwiftUI

/// The status row: what a write would do, with the action that performs it when
/// there is one, and the revert when an apply this session can still be undone.
struct StatusRow: View {
    @Bindable var model: ShellModel

    var body: some View {
        let write: WriteState = model.writeState
        HStack(spacing: 10) {
            StatusLabel(
                symbolName: write.symbolName,
                word: write.label,
                tone: write.tone,
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(write.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if !model.notice.isEmpty {
                    Text(model.notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if model.busy {
                ProgressView()
                    .controlSize(.small)
            }
            if model.canRevert {
                Button(WindowAction.revert.title) { model.requestRevert() }
            }
            if model.primaryAction == .apply {
                PrimaryActionButton(action: .apply) { model.perform($0) }
                    .controlSize(.regular)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
