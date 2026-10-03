import AppKit
import IsletCore
import SwiftUI

public struct SettingsView: View {
    private enum Pane: Hashable {
        case general
        case notch
        case animation
        case plugins
        case plugin(String)
    }

    private let settings: AppSettings
    private let registry: PluginRegistry
    @State private var loginItem = LoginItem()
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
                Section {
                    SettingsSidebarRow("General", systemImage: "gearshape.fill", tint: .gray).tag(Pane.general)
                    SettingsSidebarRow("Notch", systemImage: "macbook", tint: .blue).tag(Pane.notch)
                    SettingsSidebarRow("Animation", systemImage: "waveform.path", tint: .orange).tag(Pane.animation)
                    SettingsSidebarRow("Plugins", systemImage: "puzzlepiece.extension.fill", tint: .indigo).tag(Pane.plugins)
                }
                let entries = pluginsWithSettings
                if !entries.isEmpty {
                    Section("Plugin Settings") {
                        ForEach(entries) { entry in
                            SettingsSidebarRow(entry.manifest.displayName, systemImage: entry.manifest.systemImage, tint: .teal)
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
                SettingsPane("General", systemImage: "gearshape.fill", tint: .gray, description: "Startup, menu bar and drag & drop behavior.") {
                    GeneralSettingsView(settings: settings, loginItem: loginItem)
                }
            case .notch:
                SettingsPane("Notch", systemImage: "macbook", tint: .blue, description: "Size, appearance and placement of the notch.") {
                    NotchSettingsView(settings: settings)
                }
            case .animation:
                SettingsPane("Animation", systemImage: "waveform.path", tint: .orange, description: "How the notch expands and collapses.") {
                    AnimationSettingsView(settings: settings)
                }
            case .plugins:
                SettingsPane("Plugins", systemImage: "puzzlepiece.extension.fill", tint: .indigo, description: "Choose which plugins run and appear in the notch.") {
                    PluginsSettingsView(registry: registry)
                }
            case .plugin(let id):
                if let entry = pluginsWithSettings.first(where: { $0.id == id }), let view = entry.settingsView {
                    SettingsPane(entry.manifest.displayName, systemImage: entry.manifest.systemImage, tint: .teal, description: "Settings for the \(entry.manifest.displayName) plugin.") {
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
    let loginItem: LoginItem
    @State private var confirmsReset = false

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(
                    get: { loginItem.isEnabled || loginItem.requiresApproval },
                    set: { loginItem.setEnabled($0) }
                ))
                if loginItem.requiresApproval {
                    HStack {
                        Text("macOS needs your approval before Islet can open at login.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { loginItem.openSystemSettings() }
                    }
                }
                if let error = loginItem.error {
                    Text(error).foregroundStyle(.red)
                }
            } header: {
                Text("Startup")
            } footer: {
                Text("Starts Islet automatically when you log in. You can also change this under System Settings › General › Login Items.")
            }
            Section {
                Toggle("Show icon in the menu bar", isOn: $settings.showsMenuBarIcon)
            } header: {
                Text("Menu Bar")
            } footer: {
                Text("Without the icon, open the settings from the gear in the expanded notch or by opening Islet again from Finder or Spotlight.")
            }
            Section {
                Toggle("Switch to a plugin that accepts files", isOn: $settings.switchesToDropTargetOnDrag)
            } header: {
                Text("Drag & Drop")
            } footer: {
                Text("When you drag files over the notch, the plugin that can take them is shown automatically.")
            }
            Section {
                LabeledContent("All settings") {
                    Button("Reset…") { confirmsReset = true }
                }
            } footer: {
                Text("Restores every setting in the General, Notch and Animation tabs to its default. Plugin settings are not affected.")
            }
        }
        .onAppear { loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
        }
        .confirmationDialog("Reset all settings?", isPresented: $confirmsReset) {
            Button("Reset", role: .destructive) { settings.resetAll() }
        } message: {
            Text("This restores the General, Notch and Animation settings to their defaults.")
        }
    }
}

struct NotchSettingsView: View {
    @Bindable var settings: AppSettings
    @State private var displays = NotchDisplay.connected()

    private var placementOptions: [NotchDisplayPlacement] {
        var options: [NotchDisplayPlacement] = [.builtIn, .primary, .all]
        options += displays.map { display in
            if case .display(let id, _) = settings.displayPlacement, id == display.persistentID {
                return settings.displayPlacement
            }
            return .display(id: display.persistentID, name: display.name)
        }
        if case .display(let id, _) = settings.displayPlacement, !displays.contains(where: { $0.persistentID == id }) {
            options.append(settings.displayPlacement)
        }
        return options
    }

    private func label(for placement: NotchDisplayPlacement) -> String {
        guard case .display(let id, let storedName) = placement else { return placement.displayName }
        guard let display = displays.first(where: { $0.persistentID == id }) else { return storedName }
        let namesakes = displays.filter { $0.name == display.name }
        guard namesakes.count > 1, let index = namesakes.firstIndex(of: display) else { return display.name }
        return "\(display.name) (\(index + 1))"
    }

    private var placementSummary: String {
        let shown = settings.displayPlacement.displays(among: displays)
        switch shown.count {
        case 0: return "No display is connected."
        case 1: return "The notch is currently shown on \(shown[0].name)."
        default: return "The notch is currently shown on \(shown.count) displays."
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Size", selection: $settings.notchSize) {
                    ForEach(NotchSize.allCases) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Size")
            } footer: {
                Text("How large the notch grows when it expands. Larger sizes also enlarge the plugin content.")
            }
            Section {
                Picker("Open on", selection: $settings.openTrigger) {
                    ForEach(NotchOpenTrigger.allCases) { trigger in
                        Text(trigger.displayName).tag(trigger)
                    }
                }
                .pickerStyle(.segmented)
                Picker("Shortcut", selection: $settings.openShortcut) {
                    ForEach(NotchShortcut.allCases) { shortcut in
                        Text(shortcut.displayName).tag(shortcut)
                    }
                }
            } header: {
                Text("Opening")
            } footer: {
                Text("With Click, hovering only highlights the notch. The shortcut opens the notch on the display with the pointer from any app; ← and → switch plugins and Esc closes it.")
            }
            Section {
                Toggle("Always draw the notch shape", isOn: $settings.drawsIdleNotchShape)
            } header: {
                Text("Appearance")
            } footer: {
                Text("Keeps a black notch visible even while nothing is shown. When off, the shape can briefly flash while switching Spaces.")
            }
            Section {
                Picker("Show", selection: $settings.pillSelection) {
                    ForEach(PillSelection.allCases) { selection in
                        Text(selection.displayName).tag(selection)
                    }
                }
            } header: {
                Text("Collapsed Pill")
            } footer: {
                Text("\(settings.pillSelection.summary) Anything that needs you, like a permission request, is always shown. Opening the notch shows the plugin from the pill.")
            }
            Section {
                Picker("Show on", selection: $settings.displayPlacement) {
                    ForEach(placementOptions, id: \.self) { placement in
                        Text(label(for: placement)).tag(placement)
                    }
                }
            } header: {
                Text("Displays")
            } footer: {
                Text("\(placementSummary) A chosen display falls back to the built-in display while it is disconnected.")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            displays = NotchDisplay.connected()
        }
    }
}

struct AnimationSettingsView: View {
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
                Picker("Curve", selection: isSpring) {
                    Text("Ease out").tag(false)
                    Text("Spring").tag(true)
                }
                if isSpring.wrappedValue {
                    LabeledSlider("Bounciness", value: damping, in: 0.3...1, format: .number.precision(.fractionLength(2)))
                }
            } header: {
                Text("Curve")
            } footer: {
                Text("Spring animations overshoot slightly; lower bounciness makes them wobble more.")
            }
            Section("Duration") {
                LabeledSlider("Expand", value: $settings.animation.expandDuration, in: 0.1...1.2, format: .number.precision(.fractionLength(2)), unit: "s")
                LabeledSlider("Collapse", value: $settings.animation.collapseDuration, in: 0.1...1.2, format: .number.precision(.fractionLength(2)), unit: "s")
            }
            Section {
                LabeledSlider("Expand", value: milliseconds($settings.animation.expandDelay), in: 0...500, format: .number.precision(.fractionLength(0)), unit: "ms")
                LabeledSlider("Collapse", value: milliseconds($settings.animation.collapseDelay), in: 0...1000, format: .number.precision(.fractionLength(0)), unit: "ms")
            } header: {
                Text("Delay")
            } footer: {
                Text("How long the pointer has to rest on or leave the notch before it reacts.")
            }
            Section {
                LabeledContent("Animation") {
                    Button("Reset") { settings.resetAnimation() }
                }
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
                let entries = registry.orderedEntries
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    HStack(spacing: 12) {
                        VStack(spacing: 0) {
                            Button {
                                registry.move(entry.id, by: -1)
                            } label: {
                                Image(systemName: "chevron.up")
                                    .frame(width: 18, height: 12)
                                    .contentShape(Rectangle())
                            }
                            .disabled(index == 0)
                            .accessibilityLabel("Move \(entry.manifest.displayName) up")
                            Button {
                                registry.move(entry.id, by: 1)
                            } label: {
                                Image(systemName: "chevron.down")
                                    .frame(width: 18, height: 12)
                                    .contentShape(Rectangle())
                            }
                            .disabled(index == entries.count - 1)
                            .accessibilityLabel("Move \(entry.manifest.displayName) down")
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 9, weight: .semibold))
                        Toggle(isOn: Binding(
                            get: { registry.isEnabled(entry.id) },
                            set: { enabled in Task { await registry.setEnabled(enabled, for: entry.id) } }
                        )) {
                            Label {
                                Text(entry.manifest.displayName)
                            } icon: {
                                SettingsIcon(systemImage: entry.manifest.systemImage, tint: .teal, size: 24)
                            }
                        }
                    }
                }
            } footer: {
                Text("Disabled plugins are removed from the notch and stop running. Plugins with their own settings get a tab in the sidebar while enabled. Use the arrows to change the order of the plugins in the notch.")
            }
        }
    }
}
