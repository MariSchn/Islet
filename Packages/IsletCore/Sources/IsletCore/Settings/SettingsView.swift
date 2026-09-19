import SwiftUI

public struct SettingsView: View {
    private enum Pane: Hashable {
        case general
        case plugins
        case plugin(String)
    }

    private let settings: AppSettings
    private let registry: PluginRegistry
    @State private var selection: Pane? = .general

    public init(settings: AppSettings, registry: PluginRegistry) {
        self.settings = settings
        self.registry = registry
    }

    private var pluginsWithSettings: [PluginEntry] {
        registry.enabledEntries.filter { $0.settingsView != nil }
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                SettingsSidebarRow("General", systemImage: "gearshape.fill", tint: .gray).tag(Pane.general)
                SettingsSidebarRow("Plugins", systemImage: "puzzlepiece.extension.fill", tint: .indigo).tag(Pane.plugins)
                let entries = pluginsWithSettings
                if !entries.isEmpty {
                    Section("Plugin Settings") {
                        ForEach(entries) { entry in
                            SettingsSidebarRow(entry.manifest.displayName, systemImage: entry.manifest.systemImage, tint: .blue)
                                .tag(Pane.plugin(entry.id))
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            switch selection {
            case .general, nil:
                SettingsPane("General", systemImage: "gearshape.fill", tint: .gray, description: "Appearance, animation and drag & drop behavior of the notch.") {
                    GeneralSettingsView(settings: settings)
                }
            case .plugins:
                SettingsPane("Plugins", systemImage: "puzzlepiece.extension.fill", tint: .indigo, description: "Choose which plugins run and appear in the notch.") {
                    PluginsSettingsView(registry: registry)
                }
            case .plugin(let id):
                if let entry = pluginsWithSettings.first(where: { $0.id == id }), let view = entry.settingsView {
                    SettingsPane(entry.manifest.displayName, systemImage: entry.manifest.systemImage, tint: .blue, description: "Settings for the \(entry.manifest.displayName) plugin.") {
                        view
                    }
                    .id(id)
                } else {
                    Text("Plugin not available").foregroundStyle(.secondary)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .onChange(of: registry.disabledIDs) {
            if case .plugin(let id) = selection, !registry.isEnabled(id) {
                selection = .plugins
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}

private struct SettingsSidebarRow: View {
    let title: String
    let systemImage: String
    let tint: Color

    init(_ title: String, systemImage: String, tint: Color) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            SettingsIcon(systemImage: systemImage, tint: tint, size: 22)
        }
    }
}

private struct SettingsIcon: View {
    let systemImage: String
    let tint: Color
    let size: CGFloat

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.55, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(tint.gradient))
    }
}

private struct SettingsPane<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    let description: String
    let content: Content

    init(_ title: String, systemImage: String, tint: Color, description: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.description = description
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                SettingsIcon(systemImage: systemImage, tint: tint, size: 56)
                Text(title)
                    .font(.title2.weight(.bold))
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 28)
            .padding(.bottom, 12)
            .padding(.horizontal, 24)
            content
                .formStyle(.grouped)
        }
        .navigationTitle(title)
    }
}

struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    @State private var lastDamping = 0.7

    private var isSpring: Binding<Bool> {
        Binding(
            get: { if case .spring = settings.animation.curve { true } else { false } },
            set: { settings.animation.curve = $0 ? .spring(dampingFraction: lastDamping) : .easeOut }
        )
    }

    private var damping: Binding<Double> {
        Binding(
            get: { if case .spring(let d) = settings.animation.curve { d } else { lastDamping } },
            set: {
                lastDamping = $0
                settings.animation.curve = .spring(dampingFraction: $0)
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("Draw the notch shape when idle", isOn: $settings.drawsIdleNotchShape)
            } header: {
                Text("Appearance")
            } footer: {
                Text("Keeps a black notch shape visible at all times. Turning it off hides the shape, but it can briefly flash while switching Spaces.")
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
                LabeledContent("Defaults") {
                    Button("Reset") { settings.resetAnimation() }
                }
            }
            Section("Drag & Drop") {
                Toggle("Switch to a plugin that accepts files when dragging over the notch", isOn: $settings.switchesToDropTargetOnDrag)
            }
        }
    }

    private func milliseconds(_ duration: Binding<Duration>) -> Binding<Double> {
        Binding(
            get: { duration.wrappedValue.milliseconds },
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
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: $value, in: range)
                    .frame(width: 160)
                Text("\(value.formatted(format))\(unit.isEmpty ? "" : " \(unit)")")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)
            }
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
                        Label {
                            Text(entry.manifest.displayName)
                        } icon: {
                            SettingsIcon(systemImage: entry.manifest.systemImage, tint: .blue, size: 24)
                        }
                    }
                }
            } footer: {
                Text("Disabled plugins are removed from the notch and stop running.")
            }
        }
    }
}
