import AppKit
import SwiftUI

struct AgentsScreen: View {
    let controller: AgentsController
    @Environment(\.notchAnimation) private var animation
    @State private var installError: String?
    @State private var frozenOrder: [String]?

    var body: some View {
        VStack(spacing: AgentsPlugin.rowSpacing) {
            if let usage = controller.visibleUsage {
                UsageBar(usage: usage, showsResetTimes: controller.display.showsResetTimes, dailyCost: controller.dailyCost)
                    .frame(height: AgentsPlugin.usageBarHeight)
            }
            if let quota = controller.visibleAntigravityQuota {
                AntigravityQuotaBar(quota: quota, showsResetTimes: controller.display.showsResetTimes)
                    .frame(height: AgentsPlugin.usageBarHeight)
            }
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if controller.store.sessions.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                if let error = controller.serverError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                } else if controller.isAnyHookInstalled {
                    Text("No agent sessions")
                        .foregroundStyle(.secondary)
                    Text("Sessions started after installing the hooks appear here once you send a prompt.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Agent hooks are not installed")
                        .foregroundStyle(.secondary)
                    Button("Install Hooks") {
                        do {
                            try controller.installHooks()
                            installError = nil
                        } catch {
                            installError = error.localizedDescription
                        }
                    }
                    .buttonStyle(.bordered)
                    if let installError {
                        Text(installError)
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { controller.refreshInstallState() }
        } else {
            ScrollView {
                VStack(spacing: AgentsPlugin.rowSpacing) {
                    ForEach(SessionOrder.applying(frozen: frozenOrder, to: controller.store.orderedSessions)) { session in
                        SessionRow(
                            session: session,
                            terminal: controller.terminal(for: session),
                            isExpanded: controller.expandedSessionIDs.contains(session.id),
                            historyLength: controller.display.historyLength,
                            showTerminal: { controller.showTerminal(for: session) },
                            isMuted: controller.mutedSessionIDs.contains(session.id),
                            toggleMute: { controller.toggleMute(session.id) },
                            dismiss: { controller.store.dismiss(session.id) },
                            toggleExpanded: { controller.toggleExpanded(session.id) },
                            decide: { controller.decide($0, $1) }
                        )
                    }
                }
                .animation(animation, value: controller.expandedSessionIDs)
                .animation(animation, value: SessionOrder.applying(frozen: frozenOrder, to: controller.store.orderedSessions).map(\.id))
            }
            .onHover { isHovering in
                frozenOrder = isHovering ? controller.store.orderedSessions.map(\.id) : nil
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

private struct SessionRow: View {
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

private struct RequestView: View {
    let request: PendingRequest
    let showTerminal: () -> Void
    let decide: (PermissionDecision) -> Void

    var body: some View {
        switch request.kind {
        case .permission(_, let detail):
            VStack(alignment: .leading, spacing: AgentsPlugin.requestSpacing) {
                Text(detail ?? request.toolName)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: AgentsPlugin.requestDetailHeight, maxHeight: AgentsPlugin.requestDetailHeight, alignment: .topLeading)
                HStack(spacing: AgentsPlugin.requestSpacing) {
                    RequestButton("Allow", systemImage: "checkmark", tint: .green) { decide(.allow) }
                    if request.alwaysAllowRule != nil {
                        RequestButton("Always allow", systemImage: "checkmark.circle", tint: .green) { decide(.allowAlways) }
                            .help(request.alwaysAllowDescription ?? "")
                    }
                    RequestButton("Deny", systemImage: "xmark", tint: .red) { decide(.deny) }
                }
            }
            .padding(.vertical, AgentsPlugin.requestPadding)
        case .question(let questions):
            QuestionView(questions: questions, answerInTerminal: request.isAnswerable ? nil : showTerminal) { decide(.answers($0)) }
                .padding(.vertical, AgentsPlugin.requestPadding)
        }
    }
}

private struct QuestionView: View {
    let answerInTerminal: (() -> Void)?
    let submit: ([String: String]) -> Void
    @State private var state: QuestionAnswers
    @State private var isTyping = false
    @State private var text = ""
    @FocusState private var fieldFocused: Bool

    init(questions: [PendingRequest.Question], answerInTerminal: (() -> Void)? = nil, submit: @escaping ([String: String]) -> Void) {
        self.answerInTerminal = answerInTerminal
        self.submit = submit
        _state = State(initialValue: QuestionAnswers(questions: questions))
    }

    private var question: PendingRequest.Question { state.question }
    private var detailHeight: CGFloat { AgentsPlugin.questionDetailHeight(for: state.questions) }
    private var canSubmitText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var confirmTitle: String { state.isLast ? "Submit" : "Next" }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentsPlugin.requestSpacing) {
            HStack(alignment: .top, spacing: 6) {
                if state.canGoBack {
                    Button {
                        state.back()
                        closeTyping()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .help("Previous question")
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let header = question.header {
                        Text(state.questions.count > 1 ? "\(header) · \(state.index + 1) of \(state.questions.count)" : header)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                    }
                    Text(question.text)
                        .font(.system(size: 12))
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: detailHeight, maxHeight: detailHeight, alignment: .topLeading)
            if isTyping {
                TextField("Your answer", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .padding(.horizontal, 10)
                    .frame(height: AgentsPlugin.requestButtonHeight)
                    .background(Capsule().fill(Color.primary.opacity(0.1)))
                    .focused($fieldFocused)
                    .onAppear { fieldFocused = true }
                    .onSubmit(submitText)
                HStack(spacing: AgentsPlugin.requestSpacing) {
                    RequestButton(confirmTitle, systemImage: "checkmark", tint: .green, action: submitText)
                        .disabled(!canSubmitText)
                        .opacity(canSubmitText ? 1 : 0.4)
                    RequestButton("Cancel", systemImage: "xmark", tint: .red, action: closeTyping)
                }
            } else {
                ForEach(Array(question.options.enumerated()), id: \.offset) { offset, option in
                    RequestButton(
                        option.label,
                        subtitle: option.description,
                        systemImage: question.multiSelect ? (state.selection.contains(offset) ? "checkmark.square.fill" : "square") : "arrow.turn.down.right",
                        tint: .accentColor,
                        fullWidth: true
                    ) { choose(offset) }
                    .disabled(answerInTerminal != nil)
                    .opacity(answerInTerminal == nil ? 1 : 0.6)
                }
                if let answerInTerminal {
                    RequestButton("Answer in terminal", systemImage: "terminal", tint: .accentColor, fullWidth: true, action: answerInTerminal)
                } else {
                    RequestButton("Other…", systemImage: "pencil", tint: .accentColor, fullWidth: true) {
                        isTyping = true
                    }
                }
                if question.multiSelect {
                    RequestButton(confirmTitle, systemImage: "checkmark", tint: .green) {
                        state.submitSelection()
                        finishStep()
                    }
                    .disabled(state.selection.isEmpty)
                    .opacity(state.selection.isEmpty ? 0.4 : 1)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func choose(_ offset: Int) {
        state.choose(offset)
        finishStep()
    }

    private func submitText() {
        guard canSubmitText else { return }
        state.submitOther(text)
        closeTyping()
        finishStep()
    }

    private func closeTyping() {
        isTyping = false
        fieldFocused = false
        text = ""
    }

    private func finishStep() {
        if state.isComplete { submit(state.answers) }
    }
}

private struct RequestButton: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: Color
    let fullWidth: Bool
    let action: () -> Void

    init(_ title: String, subtitle: String? = nil, systemImage: String, tint: Color, fullWidth: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.fullWidth = fullWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .layoutPriority(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
                .padding(.horizontal, 10)
                .frame(maxWidth: fullWidth ? .infinity : nil, alignment: .leading)
                .frame(height: AgentsPlugin.requestButtonHeight)
                .background(Capsule().fill(tint.opacity(0.18)))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
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

enum SessionColors {
    static let workingTint = Color.Resolved(red: 0.4, green: 0.65, blue: 1)
    static let attentionTint = Color.Resolved(red: 1, green: 0.62, blue: 0.04)
    static let finishedTint = Color.Resolved(red: 0.2, green: 0.78, blue: 0.35)
    static let idleTint = Color.Resolved(red: 0.56, green: 0.56, blue: 0.58)
    static let failedTint = Color.Resolved(red: 1, green: 0.27, blue: 0.23)
    static let working = Color(workingTint)
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
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(style)
        .lineLimit(1)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.white.opacity(0.12)))
        .fixedSize()
    }
}

private struct PullRequestChip: View {
    let pullRequest: SessionDetails.PullRequest

    var body: some View {
        Button {
            if let url = pullRequest.url.flatMap(URL.init(string:)) {
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

private struct UsageBar: View {
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

private struct AntigravityQuotaBar: View {
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
