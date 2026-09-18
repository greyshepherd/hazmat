import AppKit

/// The menu-bar mark as the bundle carries it: both representations at their own
/// scales, so a Retina display draws the larger one instead of upscaling the
/// 22-pixel bitmap. Loading by URL reads the one file only, which is why the
/// @2x representation is attached by hand. The mark is a template image, so the
/// system tints it for the appearance and the highlight.
public enum MenuMark {
    public static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "menu-bar-template", withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        if let retina = Bundle.main.url(forResource: "menu-bar-template@2x", withExtension: "png"),
           let data = try? Data(contentsOf: retina),
           let representation = NSBitmapImageRep(data: data) {
            representation.size = NSSize(width: representation.pixelsWide / 2,
                                         height: representation.pixelsHigh / 2)
            image.addRepresentation(representation)
        }
        image.isTemplate = true
        return image
    }()
}
