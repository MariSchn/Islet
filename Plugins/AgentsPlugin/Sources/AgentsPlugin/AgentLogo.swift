import AppKit
import SwiftUI

struct AgentLogo: View {
    enum Kind {
        case claude
        case codex
        case gemini
    }

    private static let claudeColor = Color(red: 0.85, green: 0.47, blue: 0.34)
    private static let claude = image(named: "claude", isTemplate: true)
    private static let codex = image(named: "codex", isTemplate: false)
    private static let gemini = image(named: "gemini", isTemplate: false)

    let kind: Kind

    init(_ kind: Kind) {
        self.kind = kind
    }

    var body: some View {
        switch kind {
        case .claude:
            template(Self.claude, color: Self.claudeColor)
        case .codex:
            original(Self.codex)
        case .gemini:
            original(Self.gemini)
        }
    }

    @ViewBuilder
    private func template(_ image: NSImage?, color: Color) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(color)
        }
    }

    @ViewBuilder
    private func original(_ image: NSImage?) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
        }
    }

    private static func image(named name: String, isTemplate: Bool) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "svg"), let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = isTemplate
        return image
    }
}
