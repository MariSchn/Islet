import IsletCore
import SwiftUI

@MainActor
public final class SystemMonitorPlugin: IsletPlugin {
    public static let manifest = PluginManifest(id: "islet.system", displayName: "System", systemImage: "gauge.with.dots.needle.67percent", summary: "CPU, memory, network, disk and battery at a glance.", tint: .green)
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

private struct ValueStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let unit: String

    init(_ title: String, value: Binding<Int>, in range: ClosedRange<Int>, step: Int, unit: String) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.unit = unit
    }

    var body: some View {
        LabeledContent(title) {
            Stepper(value: $value, in: range, step: step) {
                Text("\(value) \(unit)")
                    .monospacedDigit()
            }
        }
    }
}

private struct SystemSettings: View {
    @Bindable var monitor: SystemMonitor

    var body: some View {
        Section {
            ForEach(SystemRow.allCases) { row in
                Toggle(row.title, isOn: binding(for: row))
            }
        } header: {
            Text("Show")
        } footer: {
            Text("Battery only appears on Macs with a battery.")
        }
        Section {
            Toggle("Always show CPU usage", isOn: $monitor.alwaysShowsCPU)
        } header: {
            Text("Collapsed Notch")
        } footer: {
            Text("Otherwise the collapsed notch only shows system information while an alert is active.")
        }
        Section {
            ValueStepper("CPU usage above", value: $monitor.thresholds.cpuPercent, in: 50...95, step: 5, unit: "%")
            ValueStepper("for at least", value: $monitor.thresholds.cpuSeconds, in: 5...300, step: 5, unit: "s")
            ValueStepper("Battery at or below", value: batteryPercent, in: 5...50, step: 5, unit: "%")
            ValueStepper("Urgent at or below", value: batteryAttentionPercent, in: 5...50, step: 5, unit: "%")
            ValueStepper("Free disk space below", value: $monitor.thresholds.diskFreeGigabytes, in: 1...500, step: 1, unit: "GB")
        } header: {
            Text("Alerts")
        } footer: {
            Text("High memory pressure and a hot Mac always raise an alert. Each alert is announced once, and again only after it has been clear for a minute.")
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
