import AppKit
import HazmatAppSupport
import SwiftUI

/// The status item's label: the brand's menu-bar mark beside the state title.
/// The mark is a template image, so the system tints it for the appearance and
/// the highlight, and it is looked up by name so both the one-times and the
/// two-times file in the bundle are loaded. When the bundle does not carry it,
/// the title alone is shown — the title is the part that says what is on.
struct StatusMark: View {
    let model: ShellModel

    var body: some View {
        HStack(spacing: 4) {
            if let mark = Self.mark {
                Image(nsImage: mark)
            }
            Text(model.menu.statusTitle)
        }
    }

    private static let mark: NSImage? = {
        guard let image = NSImage(named: "menu-bar-template") else { return nil }
        image.isTemplate = true
        return image
    }()
}
