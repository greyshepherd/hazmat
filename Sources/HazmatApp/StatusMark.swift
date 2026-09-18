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
        mark.accessibilityLabel(MenuPresentation.title(for: model.reading))
    }

    /// The bundle's mark, or a system glyph when there is no bundle to carry
    /// one, so the item is never an invisible target.
    @ViewBuilder
    private var mark: some View {
        if let image = MenuMark.image {
            Image(nsImage: image)
        } else {
            Image(systemName: "shield.lefthalf.filled")
        }
    }
}
