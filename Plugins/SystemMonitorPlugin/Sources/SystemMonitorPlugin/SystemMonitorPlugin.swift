import IsletCore
import SwiftUI

@MainActor
public final class SystemMonitorPlugin: IsletPlugin {
    public static let manifest = PluginManifest(id: "islet.system", displayName: "System", systemImage: "gauge.with.dots.needle.67percent")
    static let contentWidth: CGFloat = 420
    static let contentPadding: CGFloat = 12
    static let rowHeight: CGFloat = 28
    static let processHeaderHeight: CGFloat = 20
    static let emptyContentHeight: CGFloat = 80

    static func contentSize(for rows: [SystemRow]) -> CGSize {
        guard !rows.isEmpty else { return CGSize(width: contentWidth, height: emptyContentHeight) }
        return CGSize(width: contentWidth, height: 2 * contentPadding + rows.map(height(of:)).reduce(0, +))
    }

    static func height(of row: SystemRow) -> CGFloat {
        switch row {
        case .processes: processHeaderHeight + CGFloat(SystemSampler.topProcessCount) * rowHeight
        default: rowHeight
        }
    }

    private static let alwaysShowsCPUKey = "alwaysShowCPU"
    private static let thresholdKeys: [(key: String, value: WritableKeyPath<AlertThresholds, Int>)] = [
        ("cpuThreshold", \.cpuPercent),
        ("cpuSeconds", \.cpuSeconds),
        ("batteryThreshold", \.batteryPercent),
        ("batteryAttentionThreshold", \.batteryAttentionPercent),
        ("diskFreeGigabytes", \.diskFreeGigabytes),
    ]

    let monitor: SystemMonitor

    public init(context: PluginContext) {
        let settings = context.settings
        var thresholds = AlertThresholds()
        for (key, value) in Self.thresholdKeys {
            thresholds[keyPath: value] = settings.value(forKey: key) ?? thresholds[keyPath: value]
        }
        let monitor = SystemMonitor(
            sampler: SystemSampler(reader: LiveSystemReader(logger: context.logger)),
            enabledRows: Set(SystemRow.allCases.filter { settings.value(forKey: $0.settingsKey) ?? true }),
            thresholds: thresholds,
            alwaysShowsCPU: settings.value(forKey: Self.alwaysShowsCPUKey) ?? false
        )
        self.monitor = monitor
        context.derive(\.contentSize) { Self.contentSize(for: monitor.visibleRows) }
        context.derive(\.pillStatus) { monitor.pillStatus }
        context.observe({ monitor.enabledRows }) { rows in
            for row in SystemRow.allCases {
                settings.set(rows.contains(row), forKey: row.settingsKey)
            }
        }
        context.observe({ monitor.thresholds }) { thresholds in
            for (key, value) in Self.thresholdKeys {
                settings.set(thresholds[keyPath: value], forKey: key)
            }
        }
        context.observe({ monitor.alwaysShowsCPU }) { settings.set($0, forKey: Self.alwaysShowsCPUKey) }
        context.observe({ monitor.announcement }) { [unowned context] announcement in
            if let announcement {
                context.announce(announcement)
            }
        }
        context.observe({ [unowned context] in context.isScreenVisible }) { monitor.isScreenVisible = $0 }
    }

    public func activate() async throws {
        monitor.start()
    }

    public func deactivate() async {
        monitor.stop()
    }

    public func makeScreen() -> AnyView {
        AnyView(SystemScreen(monitor: monitor))
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(SystemSettings(monitor: monitor))
    }
}

private struct SystemSettings: View {
    @Bindable var monitor: SystemMonitor

    var body: some View {
        Form {
            Section {
                ForEach(SystemRow.allCases) { row in
                    Toggle(row.title, isOn: binding(for: row))
                }
            } header: {
                Text("Rows")
            } footer: {
                Text("The battery row only appears on Macs with a battery.")
            }
            Section {
                Toggle("Always show CPU in the closed notch", isOn: $monitor.alwaysShowsCPU)
            } header: {
                Text("Closed notch")
            } footer: {
                Text("Otherwise the closed notch only shows system information when one of the alerts below is active.")
            }
            Section {
                Stepper("CPU above \(monitor.thresholds.cpuPercent)%", value: $monitor.thresholds.cpuPercent, in: 50...95, step: 5)
                Stepper("for \(monitor.thresholds.cpuSeconds) seconds", value: $monitor.thresholds.cpuSeconds, in: 5...300, step: 5)
                Stepper("Battery at or below \(monitor.thresholds.batteryPercent)%", value: batteryPercent, in: 5...50, step: 5)
                Stepper("Needs attention at or below \(monitor.thresholds.batteryAttentionPercent)%", value: batteryAttentionPercent, in: 5...50, step: 5)
                Stepper("Startup disk below \(monitor.thresholds.diskFreeGigabytes) GB free", value: $monitor.thresholds.diskFreeGigabytes, in: 1...500)
            } header: {
                Text("Alerts")
            } footer: {
                Text("Memory pressure and a hot Mac always count as alerts. Each alert is announced once when it starts, and again only after it has been clear for a minute.")
            }
        }
    }

    private var batteryPercent: Binding<Int> {
        Binding(
            get: { monitor.thresholds.batteryPercent },
            set: { value in
                monitor.thresholds.batteryPercent = value
                monitor.thresholds.batteryAttentionPercent = min(monitor.thresholds.batteryAttentionPercent, value)
            }
        )
    }

    private var batteryAttentionPercent: Binding<Int> {
        Binding(
            get: { monitor.thresholds.batteryAttentionPercent },
            set: { value in
                monitor.thresholds.batteryAttentionPercent = value
                monitor.thresholds.batteryPercent = max(monitor.thresholds.batteryPercent, value)
            }
        )
    }

    private func binding(for row: SystemRow) -> Binding<Bool> {
        Binding(
            get: { monitor.enabledRows.contains(row) },
            set: { isOn in
                if isOn {
                    monitor.enabledRows.insert(row)
                } else {
                    monitor.enabledRows.remove(row)
                }
            }
        )
    }
}
