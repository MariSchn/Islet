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
                    SettingsSidebarRow(String(localized: "General", bundle: .module), systemImage: "gearshape.fill", tint: .gray).tag(Pane.general)
                    SettingsSidebarRow(String(localized: "Notch", bundle: .module), systemImage: "macbook", tint: .blue).tag(Pane.notch)
                    SettingsSidebarRow(String(localized: "Animation", bundle: .module), systemImage: "waveform.path", tint: .orange).tag(Pane.animation)
                    SettingsSidebarRow(String(localized: "Plugins", bundle: .module), systemImage: "puzzlepiece.extension.fill", tint: .indigo).tag(Pane.plugins)
                }
                let entries = pluginsWithSettings
                if !entries.isEmpty {
                    Section(String(localized: "Plugin Settings", bundle: .module)) {
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
                SettingsPane(String(localized: "General", bundle: .module), systemImage: "gearshape.fill", tint: .gray, description: String(localized: "Startup, menu bar and drag & drop behavior.", bundle: .module)) {
                    GeneralSettingsView(settings: settings, loginItem: loginItem)
                }
            case .notch:
                SettingsPane(String(localized: "Notch", bundle: .module), systemImage: "macbook", tint: .blue, description: String(localized: "Size, appearance and placement of the notch.", bundle: .module)) {
                    NotchSettingsView(settings: settings)
                }
            case .animation:
                SettingsPane(String(localized: "Animation", bundle: .module), systemImage: "waveform.path", tint: .orange, description: String(localized: "How the notch expands and collapses.", bundle: .module)) {
                    AnimationSettingsView(settings: settings)
                }
            case .plugins:
                SettingsPane(String(localized: "Plugins", bundle: .module), systemImage: "puzzlepiece.extension.fill", tint: .indigo, description: String(localized: "Choose which plugins run and appear in the notch.", bundle: .module)) {
                    PluginsSettingsView(registry: registry)
                }
            case .plugin(let id):
                if let entry = pluginsWithSettings.first(where: { $0.id == id }), let view = entry.settingsView {
                    SettingsPane(entry.manifest.displayName, systemImage: entry.manifest.systemImage, tint: .teal, description: String(localized: "Settings for the \(entry.manifest.displayName) plugin.", bundle: .module)) {
                        view
                    }
                    .id(id)
                } else {
                    Text("Plugin not available", bundle: .module).foregroundStyle(.secondary)
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
                Toggle(String(localized: "Open at login", bundle: .module), isOn: Binding(
                    get: { loginItem.isEnabled || loginItem.requiresApproval },
                    set: { loginItem.setEnabled($0) }
                ))
                if loginItem.requiresApproval {
                    HStack {
                        Text("macOS needs your approval before Islet can open at login.", bundle: .module)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(String(localized: "Open Login Items", bundle: .module)) { loginItem.openSystemSettings() }
                    }
                }
                if let error = loginItem.error {
                    Text(error).foregroundStyle(.red)
                }
            } header: {
                Text("Startup", bundle: .module)
            } footer: {
                Text("Starts Islet automatically when you log in. You can also change this under System Settings › General › Login Items.", bundle: .module)
            }
            Section {
                Toggle(String(localized: "Show icon in the menu bar", bundle: .module), isOn: $settings.showsMenuBarIcon)
            } header: {
                Text("Menu Bar", bundle: .module)
            } footer: {
                Text("Without the icon, open the settings from the gear in the expanded notch or by opening Islet again from Finder or Spotlight.", bundle: .module)
            }
            Section {
                Toggle(String(localized: "Switch to a plugin that accepts files", bundle: .module), isOn: $settings.switchesToDropTargetOnDrag)
            } header: {
                Text("Drag & Drop", bundle: .module)
            } footer: {
                Text("When you drag files over the notch, the plugin that can take them is shown automatically.", bundle: .module)
            }
            Section {
                LabeledContent(String(localized: "All settings", bundle: .module)) {
                    Button(String(localized: "Reset…", bundle: .module)) { confirmsReset = true }
                }
            } footer: {
                Text("Restores every setting in the General, Notch and Animation tabs to its default. Plugin settings are not affected.", bundle: .module)
            }
        }
        .onAppear { loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
        }
        .confirmationDialog(String(localized: "Reset all settings?", bundle: .module), isPresented: $confirmsReset) {
            Button(String(localized: "Reset", bundle: .module), role: .destructive) { settings.resetAll() }
        } message: {
            Text("This restores the General, Notch and Animation settings to their defaults.", bundle: .module)
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
        case 0: return String(localized: "No display is connected.", bundle: .module)
        case 1: return String(localized: "The notch is currently shown on \(shown[0].name).", bundle: .module)
        default: return String(localized: "The notch is currently shown on \(shown.count) displays.", bundle: .module)
        }
    }

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "Size", bundle: .module), selection: $settings.notchSize) {
                    ForEach(NotchSize.allCases) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Size", bundle: .module)
            } footer: {
                Text("How large the notch grows when it expands. Larger sizes also enlarge the plugin content.", bundle: .module)
            }
            Section {
                Picker(String(localized: "Open on", bundle: .module), selection: $settings.openTrigger) {
                    ForEach(NotchOpenTrigger.allCases) { trigger in
                        Text(trigger.displayName).tag(trigger)
                    }
                }
                .pickerStyle(.segmented)
                Picker(String(localized: "Shortcut", bundle: .module), selection: $settings.openShortcut) {
                    ForEach(NotchShortcut.allCases) { shortcut in
                        Text(shortcut.displayName).tag(shortcut)
                    }
                }
            } header: {
                Text("Opening", bundle: .module)
            } footer: {
                Text("With Click, hovering only highlights the notch. The shortcut opens the notch on the display with the pointer from any app; ← and → switch plugins and Esc closes it.", bundle: .module)
            }
            Section {
                Toggle(String(localized: "Always draw the notch shape", bundle: .module), isOn: $settings.drawsIdleNotchShape)
            } header: {
                Text("Appearance", bundle: .module)
            } footer: {
                Text("Keeps a black notch visible even while nothing is shown. When off, the shape can briefly flash while switching Spaces.", bundle: .module)
            }
            Section {
                Picker(String(localized: "Show", bundle: .module), selection: $settings.pillSelection) {
                    ForEach(PillSelection.allCases) { selection in
                        Text(selection.displayName).tag(selection)
                    }
                }
            } header: {
                Text("Collapsed Pill", bundle: .module)
            } footer: {
                Text("\(settings.pillSelection.summary) Anything that needs you, like a permission request, is always shown. Opening the notch shows the plugin from the pill.", bundle: .module)
            }
            Section {
                Picker(String(localized: "Show on", bundle: .module), selection: $settings.displayPlacement) {
                    ForEach(placementOptions, id: \.self) { placement in
                        Text(label(for: placement)).tag(placement)
                    }
                }
            } header: {
                Text("Displays", bundle: .module)
            } footer: {
                Text("\(placementSummary) A chosen display falls back to the built-in display while it is disconnected.", bundle: .module)
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
                Picker(String(localized: "Curve", bundle: .module), selection: isSpring) {
                    Text("Ease out", bundle: .module).tag(false)
                    Text("Spring", bundle: .module).tag(true)
                }
                if isSpring.wrappedValue {
                    LabeledSlider(String(localized: "Bounciness", bundle: .module), value: damping, in: 0.3...1, format: .number.precision(.fractionLength(2)))
                }
            } header: {
                Text("Curve", bundle: .module)
            } footer: {
                Text("Spring animations overshoot slightly; lower bounciness makes them wobble more.", bundle: .module)
            }
            Section(String(localized: "Duration", bundle: .module)) {
                LabeledSlider(String(localized: "Expand", bundle: .module), value: $settings.animation.expandDuration, in: 0.1...1.2, format: .number.precision(.fractionLength(2)), unit: "s")
                LabeledSlider(String(localized: "Collapse", bundle: .module), value: $settings.animation.collapseDuration, in: 0.1...1.2, format: .number.precision(.fractionLength(2)), unit: "s")
            }
            Section {
                LabeledSlider(String(localized: "Expand", bundle: .module), value: milliseconds($settings.animation.expandDelay), in: 0...500, format: .number.precision(.fractionLength(0)), unit: "ms")
                LabeledSlider(String(localized: "Collapse", bundle: .module), value: milliseconds($settings.animation.collapseDelay), in: 0...1000, format: .number.precision(.fractionLength(0)), unit: "ms")
            } header: {
                Text("Delay", bundle: .module)
            } footer: {
                Text("How long the pointer has to rest on or leave the notch before it reacts.", bundle: .module)
            }
            Section {
                LabeledContent(String(localized: "Animation", bundle: .module)) {
                    Button(String(localized: "Reset", bundle: .module)) { settings.resetAnimation() }
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
                Text(verbatim: "\(value.formatted(format))\(unit.isEmpty ? "" : " \(unit)")")
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
                            .accessibilityLabel(String(localized: "Move \(entry.manifest.displayName) up", bundle: .module))
                            Button {
                                registry.move(entry.id, by: 1)
                            } label: {
                                Image(systemName: "chevron.down")
                                    .frame(width: 18, height: 12)
                                    .contentShape(Rectangle())
                            }
                            .disabled(index == entries.count - 1)
                            .accessibilityLabel(String(localized: "Move \(entry.manifest.displayName) down", bundle: .module))
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
                Text("Disabled plugins are removed from the notch and stop running. Plugins with their own settings get a tab in the sidebar while enabled. Use the arrows to change the order of the plugins in the notch.", bundle: .module)
            }
        }
    }
}
