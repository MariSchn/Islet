import SwiftUI

public struct SettingsView: View {
    private enum Section: Hashable {
        case general
        case plugins
        case plugin(String)
    }

    private let settings: AppSettings
    private let registry: PluginRegistry
    @State private var selection: Section? = .general

    public init(settings: AppSettings, registry: PluginRegistry) {
        self.settings = settings
        self.registry = registry
    }

    private var pluginsWithSettings: [(PluginEntry, AnyView)] {
        registry.enabledEntries.compactMap { entry in
            entry.plugin.makeSettingsView().map { (entry, $0) }
        }
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("General", systemImage: "gearshape").tag(Section.general)
                Label("Plugins", systemImage: "puzzlepiece.extension").tag(Section.plugins)
                let entries = pluginsWithSettings
                if !entries.isEmpty {
                    SwiftUI.Section("Plugin Settings") {
                        ForEach(entries, id: \.0.id) { entry, _ in
                            Label(entry.manifest.displayName, systemImage: entry.manifest.systemImage)
                                .tag(Section.plugin(entry.id))
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            Group {
                switch selection {
                case .general, nil:
                    GeneralSettingsView(settings: settings)
                case .plugins:
                    PluginsSettingsView(registry: registry)
                case .plugin(let id):
                    if let (_, view) = pluginsWithSettings.first(where: { $0.0.id == id }) {
                        view
                    } else {
                        Text("Plugin not available").foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 620, minHeight: 420)
    }
}

struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings

    private var isSpring: Binding<Bool> {
        Binding(
            get: { if case .spring = settings.animation.curve { true } else { false } },
            set: { settings.animation.curve = $0 ? .spring(dampingFraction: 0.7) : .easeOut }
        )
    }

    private var damping: Binding<Double> {
        Binding(
            get: { if case .spring(let d) = settings.animation.curve { d } else { 0.7 } },
            set: { settings.animation.curve = .spring(dampingFraction: $0) }
        )
    }

    var body: some View {
        Form {
            Section("Appearance") {
                Toggle("Show notch outline when idle", isOn: $settings.showsIdleNotchOutline)
            }
            Section("Animation") {
                Picker("Curve", selection: isSpring) {
                    Text("Ease out").tag(false)
                    Text("Spring").tag(true)
                }
                if isSpring.wrappedValue {
                    LabeledSlider("Bounciness", value: damping, in: 0.3...1, format: .number.precision(.fractionLength(2)))
                }
                LabeledSlider("Expand duration", value: $settings.animation.expandDuration, in: 0.1...1.2, format: .number.precision(.fractionLength(2)), unit: "s")
                LabeledSlider("Collapse duration", value: $settings.animation.collapseDuration, in: 0.1...1.2, format: .number.precision(.fractionLength(2)), unit: "s")
                LabeledSlider("Expand delay", value: milliseconds($settings.animation.expandDelay), in: 0...500, format: .number.precision(.fractionLength(0)), unit: "ms")
                LabeledSlider("Collapse delay", value: milliseconds($settings.animation.collapseDelay), in: 0...1000, format: .number.precision(.fractionLength(0)), unit: "ms")
                Button("Reset to Defaults") { settings.resetAnimation() }
            }
            Section("Drag & Drop") {
                Toggle("Switch to a plugin that accepts files when dragging over the notch", isOn: $settings.switchesToDropTargetOnDrag)
            }
        }
    }

    private func milliseconds(_ duration: Binding<Duration>) -> Binding<Double> {
        Binding(
            get: { Double(duration.wrappedValue.components.seconds) * 1000 + Double(duration.wrappedValue.components.attoseconds) / 1e15 },
            set: { duration.wrappedValue = .milliseconds($0.rounded()) }
        )
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: FloatingPointFormatStyle<Double>
    var unit: String = ""

    init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, format: FloatingPointFormatStyle<Double>, unit: String = "") {
        self.title = title
        self._value = value
        self.range = range
        self.format = format
        self.unit = unit
    }

    var body: some View {
        HStack {
            Text(title)
            Slider(value: $value, in: range)
            Text("\(value.formatted(format))\(unit.isEmpty ? "" : " \(unit)")")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
    }
}

struct PluginsSettingsView: View {
    let registry: PluginRegistry

    var body: some View {
        Form {
            Section {
                ForEach(registry.entries) { entry in
                    Toggle(isOn: Binding(
                        get: { registry.isEnabled(entry.id) },
                        set: { enabled in Task { await registry.setEnabled(enabled, for: entry.id) } }
                    )) {
                        Label(entry.manifest.displayName, systemImage: entry.manifest.systemImage)
                    }
                }
            } footer: {
                Text("Disabled plugins are removed from the notch and stop running.")
            }
        }
    }
}
