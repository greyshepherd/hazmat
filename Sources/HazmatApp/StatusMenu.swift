import AppKit
import HazmatAppSupport
import SwiftUI

/// The status item's menu. Every item and label comes from the presentation, so
/// this renders and forwards the choice rather than deciding anything.
///
/// SwiftUI builds a `MenuBarExtra` menu once and only rebuilds it when an
/// observed value changes, so an appearance callback alone shows the last look.
/// Menu tracking is what makes the menu read the store and the live file when it
/// is opened.
struct StatusMenu: View {
    let model: ShellModel

    var body: some View {
        let menu = model.menu
        Group {
            ForEach(Array(menu.sections.enumerated()), id: \.element.id) { index, section in
                if index > 0 {
                    Divider()
                }
                ForEach(section.items) { item in
                    row(item)
                }
            }
        }
        .onAppear { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
            model.refresh()
        }
    }

    @ViewBuilder
    private func row(_ item: MenuPresentation.Item) -> some View {
        if let action = item.action {
            Button {
                perform(action)
            } label: {
                if item.isMarked {
                    Label(item.title, systemImage: "checkmark")
                } else {
                    Text(item.title)
                }
            }
        } else {
            Text(item.title)
        }
    }

    private func perform(_ action: MenuPresentation.Action) {
        switch action {
        case .activate(let profile):
            model.activate(profile)
        case .overwriteDrift(let profile, let block):
            model.overwriteDrift(with: profile, liveBlock: block)
        case .turnOff:
            model.removeBlock()
        case .registerHelper:
            model.register()
        case .repairHelper:
            model.repairHelper()
        case .checkForUpdates:
            model.checkForUpdates()
        }
    }
}
