import SwiftUI

struct UsageBar: View {
    let usage: ClaudeUsage
    let showsResetTimes: Bool
    let dailyCost: Double

    var body: some View {
        HStack(spacing: 8) {
            AgentLogo(.claude)
                .frame(width: 13, height: 13)
            if let window = usage.fiveHour {
                UsageWindowView(label: "5h", window: window, showsResetTime: showsResetTimes)
            }
            if usage.fiveHour != nil, usage.sevenDay != nil {
                Text("|")
                    .foregroundStyle(.quaternary)
            }
            if let window = usage.sevenDay {
                UsageWindowView(label: "7d", window: window, showsResetTime: showsResetTimes)
            }
            Spacer(minLength: 0)
            if dailyCost > 0 {
                Text("\(SessionDetails.currency(dailyCost)) today")
                    .foregroundStyle(.secondary)
                    .help("Estimated at list price by Claude Code")
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, AgentsPlugin.rowPadding)
        .help("Claude usage limits: share of the 5-hour and 7-day quota used, and time until each resets")
    }
}

struct AntigravityQuotaBar: View {
    let quota: AntigravityQuota
    let showsResetTimes: Bool

    var body: some View {
        HStack(spacing: 8) {
            AgentLogo(.gemini)
                .frame(width: 13, height: 13)
            ForEach(Array(quota.buckets.enumerated()), id: \.element.name) { index, bucket in
                if index > 0 {
                    Text("|")
                        .foregroundStyle(.quaternary)
                }
                UsageWindowView(label: bucket.label, window: bucket.window, showsResetTime: showsResetTimes)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .padding(.horizontal, AgentsPlugin.rowPadding)
        .help("Antigravity weekly quota: share used per model group, and time until each resets")
    }
}

private struct UsageWindowView: View {
    let label: String
    let window: UsageWindow
    let showsResetTime: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .fontWeight(.semibold)
            Text(window.utilization / 100, format: .percent.precision(.fractionLength(0)))
                .fontWeight(.medium)
                .foregroundStyle(color)
            if showsResetTime, let resetsAt = window.resetsAt, resetsAt > .now {
                Text(resetsAt, style: .relative)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var color: Color {
        switch window.utilization {
        case ..<50: .green
        case ..<80: .yellow
        default: .orange
        }
    }
}
