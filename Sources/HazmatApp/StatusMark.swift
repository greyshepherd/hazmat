import AppKit
import HazmatAppSupport
import SwiftUI

/// The status item's label: the brand's menu-bar mark, and nothing else. The
/// state the title used to name lives in the menu's first section, and survives
/// here as the mark's accessibility label, so reading the menu bar still names
/// what is live.
struct StatusMark: View {
    let model: ShellModel

    var body: some View {
        if let mark = MenuMark.image {
            Image(nsImage: mark)
                .accessibilityLabel(model.menu.statusTitle)
        }
    }
}
