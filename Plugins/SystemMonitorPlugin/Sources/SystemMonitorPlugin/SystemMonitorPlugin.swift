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

    let monitor: SystemMonitor

    public init(context: PluginContext) {
        let settings = context.settings
        let monitor = SystemMonitor(
            sampler: SystemSampler(reader: LiveSystemReader(logger: context.logger)),
            enabledRows: Set(SystemRow.allCases.filter { settings.value(forKey: $0.settingsKey) ?? true })
        )
        self.monitor = monitor
        context.derive(\.contentSize) { Self.contentSize(for: monitor.visibleRows) }
        context.observe({ monitor.enabledRows }) { rows in
            for row in SystemRow.allCases {
                settings.set(rows.contains(row), forKey: row.settingsKey)
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
        }
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
