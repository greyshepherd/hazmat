import AppKit
import SwiftUI

/// The status item's mark. It ships in the bundle as a black-plus-alpha template
/// image, so macOS supplies the tint, the dark-mode appearance and the highlight
/// inversion; nothing here may colour it. A bundle without the image shows the
/// state title alone rather than an empty status item.
enum StatusMark {
    static let imageName = "menu-bar-template"

    static var image: NSImage? {
        guard let image = NSImage(named: imageName) else { return nil }
        image.isTemplate = true
        return image
    }
}

/// What the status item shows: the mark beside the state the presentation named.
/// The title is the part that says what is on, so it is shown either way.
struct StatusLabel: View {
    let title: String

    var body: some View {
        if let mark = StatusMark.image {
            HStack(spacing: 4) {
                Image(nsImage: mark)
                Text(title)
            }
        } else {
            Text(title)
        }
    }
}
