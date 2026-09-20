import AppKit
import SwiftUI

struct ClaudeLogo: View {
    static let color = Color(red: 0.85, green: 0.47, blue: 0.34)
    private static let image: NSImage? = {
        guard let url = Bundle.module.url(forResource: "claude", withExtension: "svg"), let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }()

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(Self.color)
        }
    }
}
