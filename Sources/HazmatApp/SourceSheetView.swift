import HazmatAppSupport
import HazmatCore
import SwiftUI

/// The add-source or edit-source sheet: a name, a URL, and how often to refresh.
/// A URL that is not HTTPS or an interval below the floor is reported here, while
/// the fields are still on screen, rather than after the sheet closes.
struct SourceSheetView: View {
    @Bindable var model: ShellModel

    var body: some View {
        let sheet = model.sourceSheet ?? SourceSheetPresentation(mode: .adding)
        VStack(alignment: .leading, spacing: 14) {
            Text(title(for: sheet))
                .font(.title3)
                .bold()
                .foregroundStyle(.primary)

            Text("Hazmat fetches the file over HTTPS and keeps it as an ordinary fragment, so profiles stack it the same way they stack one you pasted in.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                if sheet.asksForAName {
                    labelled("Name") {
                        TextField("Fragment name", text: $model.sourceSheetName)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 320)
                    }
                }

                labelled("URL") {
                    TextField("https://example.com/hosts.txt", text: $model.sourceSheetURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 320)
                        .autocorrectionDisabled()
                }

                labelled("Interval") {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Refresh only when asked", isOn: $model.sourceSheetIsManual)
                        HStack(spacing: 6) {
                            TextField("Hours", value: $model.sourceSheetHours, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .disabled(model.sourceSheetIsManual)
                            Text("hours between refreshes")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let problem = sheet.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let hint = sheet.hint {
                // Nothing is wrong yet, so this is not an error: it is what the
                // confirm action is waiting for.
                Text(hint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { model.cancelSourceSheet() }
                    .keyboardShortcut(.cancelAction)
                Button(sheet.asksForAName ? "Add Source" : "Save") { model.commitSourceSheet() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!sheet.isUsable)
            }
        }
        .padding(20)
        .frame(minWidth: 460)
    }

    private func title(for sheet: SourceSheetPresentation) -> String {
        switch sheet.mode {
        case .adding: return "Add a Source"
        case .editing(let name): return "Refresh Settings for '\(name)'"
        }
    }

    private func labelled<Content: View>(
        _ title: String,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }
}
