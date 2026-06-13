import SwiftUI

struct AppIconImageView: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: Self.icon)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .frame(width: size, height: size)
            .drawingGroup(opaque: false, colorMode: .linear)
    }

    private static var icon: NSImage {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            icon.isTemplate = false
            return icon
        }
        return NSApp.applicationIconImage
    }
}
