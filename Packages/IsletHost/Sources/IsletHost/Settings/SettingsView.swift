import AppKit
import IsletCore
import SwiftUI

public enum SettingsPane: Hashable, Sendable {
    case general
    case notch
    case plugins
    case plugin(String)
    case about
}

@MainActor
@Observable
public final class SettingsNavigation {
    public var pane: SettingsPane? = .general

    public init() {}
}

@MainActor
public protocol AppUpdater: AnyObject {
    var canCheckForUpdates: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    func checkForUpdates()
}

public struct AppInfo: Sendable {
    public let name: String
    public let version: String
    public let build: String
    public let copyright: String
    public let sourceURL: URL
    public let issuesURL: URL
    public let licenseURL: URL
    public let acknowledgementsURL: URL

    public init(bundle: Bundle = .main, sourceURL: URL) {
        name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Islet"
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
        copyright = bundle.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? ""
        self.sourceURL = sourceURL
        issuesURL = sourceURL.appending(path: "issues")
        licenseURL = sourceURL.appending(path: "blob/main/LICENSE")
        acknowledgementsURL = sourceURL.appending(path: "blob/main/ACKNOWLEDGEMENTS.md")
    }
}

public struct SettingsView: View {
    private let settings: AppSettings
    private let registry: PluginRegistry
    private let info: AppInfo
    private let updater: (any AppUpdater)?
    @Bindable private var navigation: SettingsNavigation
    @State private var loginItem = LoginItem()

    public init(settings: AppSettings, registry: PluginRegistry, navigation: SettingsNavigation, info: AppInfo, updater: (any AppUpdater)?) {
        self.settings = settings
        self.registry = registry
        self.navigation = navigation
        self.info = info
        self.updater = updater
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $navigation.pane) {
                Section {
                    SidebarRow("General", systemImage: "gearshape.fill", tint: .gray).tag(SettingsPane.general)
                    SidebarRow("Notch", systemImage: "macbook", tint: .blue).tag(SettingsPane.notch)
                    SidebarRow("Plugins", systemImage: "puzzlepiece.extension.fill", tint: .indigo).tag(SettingsPane.plugins)
                }
                Section {
                    ForEach(registry.orderedEntries) { entry in
                        SidebarRow(entry.manifest.displayName, systemImage: entry.manifest.systemImage, tint: entry.manifest.settingsTint, isOff: !registry.isEnabled(entry.id))
                            .tag(SettingsPane.plugin(entry.id))
                    }
                }
                Section {
                    Label {
                        Text("About \(info.name)")
                    } icon: {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 22, height: 22)
                    }
                    .tag(SettingsPane.about)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 215, max: 260)
        } detail: {
            detail
                .id(navigation.pane)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: 720, minHeight: 500)
    }

    @ViewBuilder private var detail: some View {
        switch navigation.pane ?? .general {
        case .general:
            SettingsPage("General", systemImage: "gearshape.fill", tint: .gray, summary: "Startup, the menu bar icon and updates.") {
                GeneralSettings(settings: settings, loginItem: loginItem, updater: updater)
            }
        case .notch:
            SettingsPage("Notch", systemImage: "macbook", tint: .blue, summary: "How the notch looks, opens and moves, and where it appears.") {
                NotchSettings(settings: settings)
                AnimationSettings(settings: settings)
            }
        case .plugins:
            SettingsPage("Plugins", systemImage: "puzzlepiece.extension.fill", tint: .indigo, summary: "Every screen in the notch is a plugin. Turn them on or off and choose their order.") {
                PluginList(registry: registry, navigation: navigation)
            }
        case .plugin(let id):
            if let entry = registry.entry(for: id) {
                PluginPage(entry: entry, registry: registry)
            }
        case .about:
            AboutPage(info: info, updater: updater)
        }
    }
}

extension PluginManifest {
    var settingsTint: Color {
        tint ?? .gray
    }
}

private struct SidebarRow: View {
    let title: String
    let systemImage: String
    let tint: Color
    let isOff: Bool

    init(_ title: String, systemImage: String, tint: Color, isOff: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.isOff = isOff
    }

    var body: some View {
        Label {
            HStack {
                Text(title)
                Spacer(minLength: 4)
                if isOff {
                    Text("Off")
                        .foregroundStyle(.tertiary)
                }
            }
        } icon: {
            SettingsIcon(systemImage: systemImage, tint: tint, size: 22)
        }
        .accessibilityValue(isOff ? "Off" : "")
    }
}

struct SettingsIcon: View {
    let systemImage: String
    let tint: Color
    let size: CGFloat

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.55, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(tint.gradient))
            .accessibilityHidden(true)
    }
}

struct SettingsPage<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    let summary: String
    let content: Content

    init(_ title: String, systemImage: String, tint: Color, summary: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.summary = summary
        self.content = content()
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    SettingsIcon(systemImage: systemImage, tint: tint, size: 48)
                        .padding(.bottom, 4)
                    Text(title)
                        .font(.title2.weight(.semibold))
                    if !summary.isEmpty {
                        Text(summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
            }
            content
        }
        .formStyle(.grouped)
        .navigationTitle(title)
    }
}

private struct PluginPage: View {
    let entry: PluginEntry
    let registry: PluginRegistry

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { registry.isEnabled(entry.id) },
            set: { enabled in Task { await registry.setEnabled(enabled, for: entry.id) } }
        )
    }

    var body: some View {
        SettingsPage(entry.manifest.displayName, systemImage: entry.manifest.systemImage, tint: entry.manifest.settingsTint, summary: entry.manifest.summary ?? "") {
            Section {
                Toggle("Show \(entry.manifest.displayName) in the notch", isOn: isEnabled)
                if case .failed(let error) = entry.state, registry.isEnabled(entry.id) {
                    Label("\(entry.manifest.displayName) could not start: \(error.localizedDescription)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            } footer: {
                if !registry.isEnabled(entry.id), entry.settingsView != nil {
                    Text("Turn \(entry.manifest.displayName) on to change its settings.")
                }
            }
            if registry.isEnabled(entry.id), let view = entry.settingsView {
                view
            }
        }
    }
}

struct PluginList: View {
    let registry: PluginRegistry
    let navigation: SettingsNavigation

    var body: some View {
        Section {
            let entries = registry.orderedEntries
            ForEach(entries) { entry in
                PluginListRow(entry: entry, registry: registry) {
                    navigation.pane = .plugin(entry.id)
                }
                .contextMenu {
                    Button("Move Up") { registry.move(entry.id, by: -1) }
                        .disabled(entry.id == entries.first?.id)
                    Button("Move Down") { registry.move(entry.id, by: 1) }
                        .disabled(entry.id == entries.last?.id)
                }
                .accessibilityAction(named: "Move up") { registry.move(entry.id, by: -1) }
                .accessibilityAction(named: "Move down") { registry.move(entry.id, by: 1) }
            }
            .onMove { registry.move(fromOffsets: $0, toOffset: $1) }
        } footer: {
            Text("Drag plugins to change their order in the notch. Turned off plugins stop running.")
        }
    }
}

private struct PluginListRow: View {
    let entry: PluginEntry
    let registry: PluginRegistry
    let open: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            SettingsIcon(systemImage: entry.manifest.systemImage, tint: entry.manifest.settingsTint, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.manifest.displayName)
                if let summary = entry.manifest.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            Toggle(entry.manifest.displayName, isOn: Binding(
                get: { registry.isEnabled(entry.id) },
                set: { enabled in Task { await registry.setEnabled(enabled, for: entry.id) } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            Button(action: open) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 16, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Settings for \(entry.manifest.displayName)")
            .accessibilityLabel("Settings for \(entry.manifest.displayName)")
        }
        .padding(.vertical, 2)
    }
}

struct GeneralSettings: View {
    @Bindable var settings: AppSettings
    let loginItem: LoginItem
    let updater: (any AppUpdater)?
    @State private var confirmsReset = false

    var body: some View {
        Section {
            Toggle("Open Islet at login", isOn: Binding(
                get: { loginItem.isEnabled || loginItem.requiresApproval },
                set: { loginItem.setEnabled($0) }
            ))
            if loginItem.requiresApproval {
                LabeledContent("macOS needs your approval first.") {
                    Button("Open Login Items") { loginItem.openSystemSettings() }
                }
                .foregroundStyle(.secondary)
            }
            if let error = loginItem.error {
                Text(error).foregroundStyle(.red)
            }
            Toggle("Show Islet in the menu bar", isOn: $settings.showsMenuBarIcon)
        } header: {
            Text("Startup and Menu Bar")
        } footer: {
            Text("Without the menu bar icon, open the settings from the gear in the notch, or open Islet again from Finder or Spotlight.")
        }
        Section {
            Toggle("Switch to a plugin that accepts what you drag", isOn: $settings.switchesToDropTargetOnDrag)
        } header: {
            Text("Drag and Drop")
        } footer: {
            Text("Drag files, links or text over the notch and the Shelf opens to take them.")
        }
        if let updater {
            UpdateSettings(updater: updater)
        }
        Section {
            LabeledContent("Notch and general settings") {
                Button("Reset…") { confirmsReset = true }
            }
        } footer: {
            Text("Plugin settings are kept.")
        }
        .onAppear { loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
        }
        .confirmationDialog("Reset the notch and general settings?", isPresented: $confirmsReset) {
            Button("Reset", role: .destructive) { settings.resetAll() }
        } message: {
            Text("This restores the settings on the General and Notch pages to their defaults.")
        }
    }
}

private struct UpdateSettings: View {
    let updater: any AppUpdater

    var body: some View {
        Section {
            Toggle("Check for updates automatically", isOn: Binding(
                get: { updater.automaticallyChecksForUpdates },
                set: { updater.automaticallyChecksForUpdates = $0 }
            ))
            LabeledContent("Islet checks once a day.") {
                Button("Check Now") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
            .foregroundStyle(.secondary)
        } header: {
            Text("Updates")
        }
    }
}

struct NotchSettings: View {
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
        case 1: return "Shown on \(shown[0].name)."
        default: return "Shown on \(shown.count) displays."
        }
    }

    var body: some View {
        Section {
            Picker("Size", selection: $settings.notchSize) {
                ForEach(NotchSize.allCases) { size in
                    Text(size.displayName).tag(size)
                }
            }
            .pickerStyle(.segmented)
            Toggle("Always draw the notch shape", isOn: $settings.drawsIdleNotchShape)
        } header: {
            Text("Appearance")
        } footer: {
            Text("Larger sizes also enlarge the plugins. Drawing the shape all the time avoids a brief flash when you switch Spaces.")
        }
        Section {
            Picker("Open on", selection: $settings.openTrigger) {
                ForEach(NotchOpenTrigger.allCases) { trigger in
                    Text(trigger.displayName).tag(trigger)
                }
            }
            .pickerStyle(.segmented)
            Picker("Keyboard shortcut", selection: $settings.openShortcut) {
                ForEach(NotchShortcut.allCases) { shortcut in
                    Text(shortcut.displayName).tag(shortcut)
                }
            }
            if settings.isShortcutUnavailable {
                Label("Another app already uses this shortcut. Choose a different one.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Opening")
        } footer: {
            Text("The shortcut opens the notch on the display with the pointer. Use ← and → to switch plugins and Esc to close it.")
        }
        Section {
            Picker("Show", selection: $settings.pillSelection) {
                ForEach(PillSelection.allCases) { selection in
                    Text(selection.displayName).tag(selection)
                }
            }
        } header: {
            Text("Collapsed Notch")
        } footer: {
            Text("\(settings.pillSelection.summary) Anything that needs you, like a permission request, is always shown.")
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
            Text("\(placementSummary) Displays without a notch get a virtual one. A chosen display falls back to the built-in display while it is disconnected.")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            displays = NotchDisplay.connected()
        }
    }
}

struct AnimationSettings: View {
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
        Section {
            Picker("Curve", selection: isSpring) {
                Text("Ease out").tag(false)
                Text("Spring").tag(true)
            }
            .pickerStyle(.segmented)
            if isSpring.wrappedValue {
                LabeledSlider("Bounciness", value: damping, in: 0.3...1, format: .number.precision(.fractionLength(2)))
            }
            LabeledSlider("Expand in", value: $settings.animation.expandDuration, in: 0.1...1.2, format: .number.precision(.fractionLength(2)), unit: "s")
            LabeledSlider("Collapse in", value: $settings.animation.collapseDuration, in: 0.1...1.2, format: .number.precision(.fractionLength(2)), unit: "s")
            LabeledSlider("Wait before expanding", value: milliseconds($settings.animation.expandDelay), in: 0...500, format: .number.precision(.fractionLength(0)), unit: "ms")
            LabeledSlider("Wait before collapsing", value: milliseconds($settings.animation.collapseDelay), in: 0...1000, format: .number.precision(.fractionLength(0)), unit: "ms")
            LabeledContent("Animation") {
                Button("Restore Defaults") { settings.resetAnimation() }
            }
        } header: {
            Text("Animation")
        } footer: {
            Text("A lower bounciness makes the spring wobble more. The waits are how long the pointer has to rest on or leave the notch.")
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
                    .labelsHidden()
                    .frame(width: 160)
                    .accessibilityLabel(title)
                Text("\(value.formatted(format))\(unit.isEmpty ? "" : " \(unit)")")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)
            }
        }
    }
}

private struct AboutPage: View {
    let info: AppInfo
    let updater: (any AppUpdater)?

    var body: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 96, height: 96)
                    Text(info.name)
                        .font(.title.weight(.semibold))
                    Text("Version \(info.version) (\(info.build))")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("Your MacBook's notch, finally pulling its weight.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            if let updater {
                Section {
                    LabeledContent("Updates") {
                        Button("Check for Updates…") { updater.checkForUpdates() }
                            .disabled(!updater.canCheckForUpdates)
                    }
                }
            }
            Section {
                LinkRow(title: "Source code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right", url: info.sourceURL)
                LinkRow(title: "Report an issue or request a feature", systemImage: "ladybug", url: info.issuesURL)
                LinkRow(title: "License", systemImage: "doc.text", url: info.licenseURL)
                LinkRow(title: "Acknowledgements", systemImage: "heart", url: info.acknowledgementsURL)
            } footer: {
                Text(info.copyright)
            }
            Section {
                LabeledContent("Quit Islet and remove the notch until you open it again.") {
                    Button("Quit Islet") { NSApp.terminate(nil) }
                }
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("About \(info.name)")
    }
}

private struct LinkRow: View {
    let title: String
    let systemImage: String
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack {
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: systemImage)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isLink)
    }
}
