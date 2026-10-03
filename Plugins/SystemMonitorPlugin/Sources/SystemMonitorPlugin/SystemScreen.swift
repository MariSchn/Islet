import SwiftUI

struct SystemScreen: View {
    let monitor: SystemMonitor

    var body: some View {
        let rows = monitor.visibleRows
        if rows.isEmpty {
            Text("Choose which rows to show in the System settings.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    content(for: row)
                        .frame(height: SystemMonitorPlugin.height(of: row))
                }
            }
            .font(.system(size: 12))
            .monospacedDigit()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private func content(for row: SystemRow) -> some View {
        let sample = monitor.sample
        switch row {
        case .cpu:
            MetricRow(systemImage: "cpu", title: row.title) {
                Text(sample.map { SystemFormat.percent($0.cpuPercent) } ?? "–")
            } accessory: {
                Sparkline(series: [.init(values: monitor.cpuHistory.values, tint: .blue)], maximum: 100)
            }
        case .memory:
            MetricRow(systemImage: "memorychip", title: row.title) {
                HStack(spacing: 6) {
                    Text(sample.map { SystemFormat.memory(used: $0.memoryUsed, total: $0.memoryTotal) } ?? "–")
                    if let pressure = sample.flatMap({ SystemFormat.pressure($0.memoryPressure) }) {
                        Text(pressure)
                            .foregroundStyle(.orange)
                    }
                }
            } accessory: {
                Sparkline(series: [.init(values: monitor.memoryHistory.values, tint: .green)], maximum: Double(sample?.memoryTotal ?? 0))
            }
        case .network:
            MetricRow(systemImage: "network", title: row.title) {
                if let received = sample?.networkIn, let sent = sample?.networkOut {
                    Text("↓ \(SystemFormat.rate(received))  ↑ \(SystemFormat.rate(sent))")
                } else {
                    Text("–")
                }
            } accessory: {
                Sparkline(series: [
                    .init(values: monitor.networkInHistory.values, tint: .blue),
                    .init(values: monitor.networkOutHistory.values, tint: .orange),
                ])
            }
        case .disk:
            MetricRow(systemImage: "internaldrive", title: row.title) {
                Text(sample?.disk.map { "\(SystemFormat.bytes($0.free)) free" } ?? "–")
            } accessory: {
                UsageBar(fraction: sample?.disk?.usedFraction ?? 0)
            }
        case .battery:
            MetricRow(systemImage: sample?.battery?.isCharging == true ? "battery.100percent.bolt" : "battery.75percent", title: row.title) {
                Text(sample?.battery.map { SystemFormat.battery($0) } ?? "–")
            } accessory: {
                UsageBar(fraction: Double(sample?.battery?.percent ?? 0) / 100)
            }
        case .processes:
            TopProcesses(processes: sample?.topProcesses ?? [])
        }
    }
}

private struct MetricRow<Value: View, Accessory: View>: View {
    let systemImage: String
    let title: String
    @ViewBuilder let value: Value
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(title)
                .frame(width: 56, alignment: .leading)
                .foregroundStyle(.secondary)
            value
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            accessory
                .frame(width: 96, height: 18)
        }
        .frame(height: SystemMonitorPlugin.rowHeight)
    }
}

private struct TopProcesses: View {
    let processes: [ProcessUsage]

    var body: some View {
        VStack(spacing: 0) {
            Text("Top processes")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: SystemMonitorPlugin.processHeaderHeight, maxHeight: SystemMonitorPlugin.processHeaderHeight, alignment: .bottomLeading)
            ForEach(0..<SystemSampler.topProcessCount, id: \.self) { index in
                HStack {
                    if index < processes.count {
                        Text(processes[index].name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(SystemFormat.percent(processes[index].cpuPercent))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("–")
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                }
                .padding(.leading, 26)
                .frame(height: SystemMonitorPlugin.rowHeight)
            }
        }
    }
}

struct Sparkline: View {
    struct Series {
        var values: [Double]
        var tint: Color
    }

    let series: [Series]
    var maximum: Double?

    var body: some View {
        GeometryReader { geometry in
            let top = max(maximum ?? series.flatMap(\.values).max() ?? 0, 1)
            ZStack {
                ForEach(series.indices, id: \.self) { index in
                    Self.path(for: series[index].values, maximum: top, in: geometry.size)
                        .stroke(series[index].tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    static func path(for values: [Double], maximum: Double, in size: CGSize) -> Path {
        Path { path in
            guard values.count > 1 else { return }
            let step = size.width / CGFloat(SystemMonitor.historyLength - 1)
            let start = size.width - CGFloat(values.count - 1) * step
            for (index, value) in values.enumerated() {
                let point = CGPoint(x: start + CGFloat(index) * step, y: size.height * (1 - CGFloat(min(max(value / maximum, 0), 1))))
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
        }
    }
}

private struct UsageBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(.blue)
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 4)
    }
}
