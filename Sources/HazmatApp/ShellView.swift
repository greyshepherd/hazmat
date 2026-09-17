import HazmatAppSupport
import HazmatCore
import SwiftUI

/// The development shell: helper state, the selected profile's drift, and the
/// register, apply, and remove-block actions. No menu bar item, no profile
/// editor, no resolved view.
struct ShellView: View {
    @Bindable var model: ShellModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Hazmat")
                .font(.title2)
                .bold()

            GroupBox("Helper") {
                VStack(alignment: .leading, spacing: 8) {
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }

            GroupBox("Profile") {
                VStack(alignment: .leading, spacing: 8) {
                    if model.profiles.isEmpty {
                        Text("No profiles in \(model.storePath)")
                    } else {
                        Picker("Profile", selection: $model.selectedProfile) {
                            ForEach(model.profiles, id: \.self) { profile in
                                Text(profile.rawValue).tag(Optional(profile))
                            }
                        }
                        .onChange(of: model.selectedProfile) { model.refreshDrift() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }

            GroupBox("Hosts file") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.drift)
                    HStack {
                        Button("Apply") { model.apply(overwriteDrift: false) }
                        Button("Overwrite drift") { model.apply(overwriteDrift: true) }
                        Button("Remove block") { model.removeBlock() }
                    }
                    .disabled(model.helper != .enabled || model.selectedProfile == nil || model.busy)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }

            Text(model.notice)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 460)
        .task { model.refresh() }
    }
}
