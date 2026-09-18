import AppKit
import HazmatAppSupport
import SwiftUI

/// The status item's label: the brand's menu-bar mark beside the state title.
/// The mark is a template image, so the system tints it for the appearance and
/// the highlight. When the bundle does not carry it, the title alone is shown.
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
        guard let url = Bundle.main.url(forResource: "menu-bar-template", withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        image.isTemplate = true
        return image
    }()
}
