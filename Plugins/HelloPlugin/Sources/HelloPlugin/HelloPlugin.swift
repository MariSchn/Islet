import IsletCore
import SwiftUI

@MainActor
public final class HelloPlugin: IsletPlugin {
    public static let manifest = PluginManifest(id: "com.example.hello", displayName: "Hello", systemImage: "hand.wave")
    static let greetingKey = "greeting"
    static let defaultGreeting = "Hello"

    private let context: PluginContext

    public init(context: PluginContext) {
        self.context = context
    }

    public func activate() async throws {
        context.contentSize = HelloScreen.compactSize
    }

    public func makeScreen() -> AnyView {
        AnyView(HelloScreen(context: context))
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(HelloSettings(settings: context.settings))
    }
}

private struct HelloSettings: View {
    let settings: PluginSettings

    var body: some View {
        Form {
            TextField("Greeting", text: Binding(
                get: { settings.value(forKey: HelloPlugin.greetingKey) ?? "" },
                set: { settings.set($0.isEmpty ? nil : $0, forKey: HelloPlugin.greetingKey) }
            ), prompt: Text(HelloPlugin.defaultGreeting))
        }
        .formStyle(.grouped)
    }
}

struct HelloScreen: View {
    static let compactSize = CGSize(width: 400, height: 140)
    static let largeSize = CGSize(width: 640, height: 300)

    let context: PluginContext

    private var isLarge: Bool {
        context.contentSize == Self.largeSize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(context.settings.value(forKey: HelloPlugin.greetingKey) ?? HelloPlugin.defaultGreeting) from \(context.manifest.displayName)")
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
            Button(isLarge ? "Shrink" : "Grow") {
                context.contentSize = isLarge ? Self.compactSize : Self.largeSize
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
