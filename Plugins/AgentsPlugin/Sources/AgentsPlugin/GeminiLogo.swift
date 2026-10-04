import AppKit
import SwiftUI

struct GeminiLogo: View {
    private static let image: NSImage? = {
        guard let url = Bundle.module.url(forResource: "gemini", withExtension: "svg") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .resizable()
        }
    }
}
