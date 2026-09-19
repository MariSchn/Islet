import IsletCore
import SwiftUI

@MainActor
public final class HelloPlugin: IsletPlugin {
    public static let manifest = PluginManifest(id: "islet.hello", displayName: "Hello", systemImage: "hand.wave")

    private let context: PluginContext

    public init(context: PluginContext) {
        self.context = context
    }

    public func makeScreen() -> AnyView {
        AnyView(HelloScreen(context: context))
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(HelloSettings(context: context))
    }
}

private struct HelloSettings: View {
    let context: PluginContext
    @State private var greeting = ""

    var body: some View {
        Form {
            TextField("Greeting", text: $greeting)
                .onChange(of: greeting) { context.settings.set(greeting, forKey: "greeting") }
        }
        .onAppear { greeting = context.settings.value(forKey: "greeting") ?? "Hello" }
    }
}

private struct HelloScreen: View {
    let context: PluginContext

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(context.settings.value(forKey: "greeting") ?? "Hello") from \(context.manifest.displayName)")
                .font(.title3.weight(.semibold))
            Text("Pill: \(context.pillStatus?.text ?? "none")")
                .foregroundStyle(.secondary)
            HStack {
                pillButton("Ambient", priority: .ambient)
                pillButton("Info", priority: .info)
                pillButton("Attention", priority: .attention)
                pillButton("Urgent", priority: .urgent)
                Button("Clear") { context.pillStatus = nil }
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pillButton(_ title: String, priority: PillStatus.Priority) -> some View {
        Button(title) {
            context.pillStatus = PillStatus(text: "\(title) from Hello", systemImage: "hand.wave", priority: priority)
        }
    }
}
