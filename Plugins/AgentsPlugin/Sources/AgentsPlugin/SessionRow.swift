import AppKit
import SwiftUI

struct SessionRow: View {
    let session: AgentSession
    let terminal: InstalledTerminal?
    let isExpanded: Bool
    let historyLength: Int
    let showTerminal: () -> Void
    let isMuted: Bool
    let toggleMute: () -> Void
    let dismiss: () -> Void
    let toggleExpanded: () -> Void
    let decide: (UUID, PermissionDecision) -> Void
    @State private var isHovering = false
    @State private var isHoveringTerminal = false

    var body: some View {
        VStack(spacing: 0) {
            summary
                .frame(height: AgentsPlugin.rowHeight)
            if let request = session.pendingRequest {
                RequestView(request: request, showTerminal: showTerminal) { decide(request.id, $0) }
                    .id(request.id)
                    .frame(height: AgentsPlugin.requestHeight(for: request))
            }
            ActivityView(session: session, historyLength: historyLength)
                .frame(height: AgentsPlugin.detailHeight(for: session, historyLength: historyLength), alignment: .top)
                .frame(height: isExpanded ? AgentsPlugin.detailHeight(for: session, historyLength: historyLength) : 0, alignment: .top)
                .clipped()
                .allowsHitTesting(isExpanded)
                .accessibilityHidden(!isExpanded)
        }
        .padding(.horizontal, AgentsPlugin.rowPadding)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(isHovering ? 0.1 : 0.06)))
        .contentShape(Rectangle())
        .onTapGesture(perform: toggleExpanded)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: isExpanded ? "Hide recent actions" : "Show recent actions", toggleExpanded)
    }

    private var summary: some View {
        HStack(alignment: .center, spacing: 12) {
            StateIndicator(state: session.state, isUnreachable: session.isUnreachable)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    SessionTitle(session: session)
                        .layoutPriority(-1)
                    if let terminal {
                        Button(action: showTerminal) {
                            Image(nsImage: terminal.icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                                .padding(2)
                                .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(isHoveringTerminal ? 0.18 : 0)))
                        }
                        .buttonStyle(.plain)
                        .onHover { isHoveringTerminal = $0 }
                        .help("Show in \(terminal.name)")
                        .accessibilityLabel("Show in \(terminal.name)")
                    }
                    if session.isRemote, let host = session.host {
                        Label(host, systemImage: session.isUnreachable ? "network.slash" : "network")
                            .font(.system(size: 11))
                            .foregroundStyle(session.isUnreachable ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                            .lineLimit(1)
                            .help(session.isUnreachable ? "No updates from \(host) for a while. Is the SSH tunnel still up?" : "Running on \(host)")
                    }
                    Spacer(minLength: 0)
                    if let badge = session.details.badgeText {
                        Text(badge)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    if let percentage = session.details.contextPercentage {
                        ContextMeter(percentage: percentage)
                    }
                    AgentBadge(session: session)
                    if isMuted, !isHovering {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .help("Muted")
                    }
                    StateLabel(session: session)
                    Button(action: toggleMute) {
                        Image(systemName: isMuted ? "bell.slash" : "bell")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(isMuted ? "Unmute" : "Mute")
                    .accessibilityLabel(isMuted ? "Unmute" : "Mute")
                    .opacity(isHovering ? 1 : 0)
                    .frame(width: isHovering ? nil : 0)
                    .clipped()
                    ZStack {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .opacity(isHovering ? 0 : 1)
                        Button(action: dismiss) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove from list")
                        .accessibilityLabel("Remove from list")
                        .opacity(isHovering ? 1 : 0)
                    }
                    .frame(width: 16, height: 16)
                }
                if let task = session.task {
                    Text("You: \(task)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(detailStyle)
                        .lineLimit(1)
                        .layoutPriority(-1)
                    if session.details.worktree != nil || session.details.branch != nil || session.details.pullRequest != nil {
                        Spacer(minLength: 4)
                        if let worktree = session.details.worktree ?? session.details.branch {
                            DetailChip(systemImage: "arrow.triangle.branch", text: worktree, style: AnyShapeStyle(.secondary))
                        }
                        if let pullRequest = session.details.pullRequest {
                            PullRequestChip(pullRequest: pullRequest)
                        }
                    }
                }
            }
        }
    }

    private var detailStyle: AnyShapeStyle {
        if session.isUnreachable { return AnyShapeStyle(.secondary) }
        switch session.state {
        case .starting: return AnyShapeStyle(.tertiary)
        case .working: return AnyShapeStyle(SessionColors.working)
        case .needsAttention: return AnyShapeStyle(.orange)
        case .done: return AnyShapeStyle(.green)
        case .interrupted: return AnyShapeStyle(.secondary)
        case .failed: return AnyShapeStyle(.red)
        }
    }

    private var detail: String {
        if session.isUnreachable { return "Unreachable" }
        switch session.state {
        case .starting: return "Ready"
        case .working: return session.activity ?? "Working…"
        case .needsAttention(let reason): return reason
        case .done: return "Finished"
        case .interrupted: return "Interrupted"
        case .failed(let reason): return reason
        }
    }
}

private struct SessionTitle: View {
    let session: AgentSession

    var body: some View {
        if let title = session.title {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(session.projectName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.system(size: 13))
        } else {
            Text(session.projectName)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
    }
}

private struct StateIndicator: View {
    let state: AgentSession.State
    let isUnreachable: Bool

    var body: some View {
        switch state {
        case _ where isUnreachable:
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        case .starting:
            Image(systemName: "circle.dashed")
                .font(.system(size: 16))
                .foregroundStyle(.tertiary)
        case .working:
            ProgressView()
                .controlSize(.small)
        case .needsAttention:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.orange)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.green)
        case .interrupted:
            Image(systemName: "stop.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 16))
                .foregroundStyle(.red)
        }
    }
}

private struct StateLabel: View {
    let session: AgentSession

    var body: some View {
        switch session.state {
        case .working where !session.isUnreachable:
            Text(session.turnStartedAt, style: .timer)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        case .starting:
            EmptyView()
        case .needsAttention:
            Text("Needs you")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.orange)
        case .failed:
            Text("Failed")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.red)
        case .working, .done, .interrupted:
            Text(Self.duration(session.updatedAt.timeIntervalSince(session.turnStartedAt)))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    static func duration(_ interval: TimeInterval) -> String {
        let seconds = Int(max(interval, 0))
        let (hours, minutes) = (seconds / 3600, seconds / 60 % 60)
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds % 60) : String(format: "%d:%02d", minutes, seconds % 60)
    }
}

private struct ContextMeter: View {
    let percentage: Double

    var body: some View {
        Capsule()
            .fill(.quaternary)
            .frame(width: 36, height: 4)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(fill)
                    .frame(width: 36 * CGFloat(min(max(percentage, 0), 100)) / 100)
            }
            .fixedSize()
            .help("Context \(SessionDetails.percentText(percentage))% used")
            .accessibilityElement()
            .accessibilityLabel("Context")
            .accessibilityValue("\(SessionDetails.percentText(percentage))% used")
    }

    private var fill: Color {
        if percentage >= 85 { return .orange }
        if percentage >= 70 { return .yellow }
        return .secondary
    }
}

private struct AgentBadge: View {
    let session: AgentSession

    var body: some View {
        AgentLogo(kind)
            .frame(width: 14, height: 14)
            .help(session.agent.displayName)
    }

    private var kind: AgentLogo.Kind {
        if session.isGeminiModel { return .gemini }
        switch session.agent {
        case .claudeCode: return .claude
        case .codex: return .codex
        case .antigravity: return .gemini
        }
    }
}

private struct DetailChip: View {
    var systemImage: String?
    var text: String
    var style: AnyShapeStyle

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
                .truncationMode(.middle)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(style)
        .lineLimit(1)
        .frame(maxWidth: 160)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.white.opacity(0.12)))
        .help(text)
    }
}

private struct PullRequestChip: View {
    let pullRequest: SessionDetails.PullRequest

    var body: some View {
        Button {
            if let url = pullRequest.url.flatMap(URL.init(string:)), ["http", "https"].contains(url.scheme?.lowercased()) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            DetailChip(text: pullRequest.label, style: reviewStyle)
        }
        .buttonStyle(.plain)
        .help(pullRequest.help)
    }

    private var reviewStyle: AnyShapeStyle {
        switch pullRequest.reviewState {
        case "approved": AnyShapeStyle(.green)
        case "changes_requested": AnyShapeStyle(.orange)
        case "draft": AnyShapeStyle(.tertiary)
        default: AnyShapeStyle(.secondary)
        }
    }
}

private struct ActivityView: View {
    let session: AgentSession
    let historyLength: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let summary = session.details.sessionSummary {
                SectionHeader("Session")
                Text(summary)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: AgentsPlugin.activityEntryHeight)
            }
            if let plan = session.plan {
                SectionHeader("Plan")
                ScrollView {
                    MarkdownText(plan)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: AgentsPlugin.planHeight)
                .padding(.bottom, AgentsPlugin.requestSpacing)
            }
            SectionHeader("Recent activity")
            if session.activities.isEmpty {
                Text("No tool calls yet")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(height: AgentsPlugin.activityEntryHeight)
            }
            ForEach(AgentsPlugin.visibleActivities(of: session, historyLength: historyLength)) { entry in
                HStack(spacing: 6) {
                    Image(systemName: entry.systemImage)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    Text(entry.title)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(entry.isComplete ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let detail = entry.detail {
                        Text(detail)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    if entry.didFail {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.red)
                    } else if !entry.isComplete {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
                .frame(height: AgentsPlugin.activityEntryHeight)
            }
        }
        .padding(.vertical, AgentsPlugin.requestPadding)
    }
}

private struct SectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .frame(height: AgentsPlugin.activityHeaderHeight, alignment: .leading)
    }
}
