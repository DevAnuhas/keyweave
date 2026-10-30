import AppKit

/// Load from the SwiftPM resource bundle, which also works in the packaged app.
@MainActor
enum BrandAssets {
    static func menuBarIcon() -> NSImage? {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        for name in ["MenuBarIcon", "MenuBarIcon@2x"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Branding"),
                  let data = try? Data(contentsOf: url),
                  let representation = NSBitmapImageRep(data: data) else { return nil }
            representation.size = size
            image.addRepresentation(representation)
        }
        image.isTemplate = true
        return image
    }

    static func appIcon() -> NSImage? {
        guard let url = Bundle.module.url(forResource: "KeyWeaveIcon", withExtension: "png", subdirectory: "Branding") else { return nil }
        return NSImage(contentsOf: url)
    }
}
