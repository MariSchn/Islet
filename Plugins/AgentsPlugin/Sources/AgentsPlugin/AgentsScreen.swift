import AppKit
import SwiftUI

struct AgentsScreen: View {
    let controller: AgentsController
    @Environment(\.notchAnimation) private var animation
    @State private var installError: String?

    var body: some View {
        VStack(spacing: AgentsPlugin.rowSpacing) {
            if controller.showsUsageBar, let usage = controller.usage.usage {
                UsageBar(usage: usage)
                    .frame(height: AgentsPlugin.usageBarHeight)
            }
            content
        }
        .task { controller.usage.refresh() }
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
                    ForEach(controller.store.sessions) { session in
                        SessionRow(
                            session: session,
                            terminal: session.terminal.flatMap(InstalledTerminal.lookup),
                            isExpanded: controller.expandedSessionIDs.contains(session.id),
                            dismiss: { controller.store.dismiss(session.id) },
                            toggleExpanded: { controller.toggleExpanded(session.id) },
                            decide: { controller.decide($0, $1) }
                        )
                    }
                }
                .animation(animation, value: controller.expandedSessionIDs)
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
                RequestView(request: request) { decide(request.id, $0) }
                    .id(request.id)
                    .frame(height: AgentsPlugin.requestHeight(for: request))
            }
            ActivityView(session: session)
                .frame(height: AgentsPlugin.detailHeight(for: session), alignment: .top)
                .frame(height: isExpanded ? AgentsPlugin.detailHeight(for: session) : 0, alignment: .top)
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
                    if let terminal {
                        Button { terminal.activate(tty: session.isRemote ? nil : session.tty, cwd: session.isRemote ? nil : session.cwd) } label: {
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
                    AgentBadge(agent: session.agent)
                    StateLabel(session: session)
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
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(detailStyle)
                    .lineLimit(1)
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
        }
    }

    private var detail: String {
        if session.isUnreachable { return "Unreachable" }
        switch session.state {
        case .starting: return "Starting…"
        case .working: return session.activity ?? "Working…"
        case .needsAttention(let reason): return reason
        case .done: return "Finished"
        }
    }
}

private struct ActivityView: View {
    let session: AgentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
            ForEach(session.activities) { entry in
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
                    if !entry.isComplete {
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
                    RequestButton("Deny", systemImage: "xmark", tint: .red) { decide(.deny) }
                }
            }
            .padding(.vertical, AgentsPlugin.requestPadding)
        case .question(let questions):
            QuestionView(questions: questions) { decide(.answers($0)) }
                .padding(.vertical, AgentsPlugin.requestPadding)
        }
    }
}

private struct QuestionView: View {
    let questions: [PendingRequest.Question]
    let submit: ([String: String]) -> Void
    @State private var index = 0
    @State private var answers: [String: String] = [:]
    @State private var selection: [Int] = []

    private var question: PendingRequest.Question { questions[index] }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentsPlugin.requestSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                if let header = question.header {
                    Text(questions.count > 1 ? "\(header) · \(index + 1) of \(questions.count)" : header)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                }
                Text(question.text)
                    .font(.system(size: 12))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: AgentsPlugin.questionDetailHeight, maxHeight: AgentsPlugin.questionDetailHeight, alignment: .topLeading)
            ForEach(Array(question.options.enumerated()), id: \.offset) { offset, option in
                RequestButton(
                    option.label,
                    subtitle: option.description,
                    systemImage: question.multiSelect ? (selection.contains(offset) ? "checkmark.square.fill" : "square") : "arrow.turn.down.right",
                    tint: .accentColor,
                    fullWidth: true
                ) { choose(offset) }
            }
            if question.multiSelect {
                RequestButton(index + 1 < questions.count ? "Next" : "Submit", systemImage: "checkmark", tint: .green) {
                    record(selection.sorted().map { question.options[$0].label }.joined(separator: ", "))
                }
                .disabled(selection.isEmpty)
                .opacity(selection.isEmpty ? 0.4 : 1)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func choose(_ offset: Int) {
        if question.multiSelect {
            if let position = selection.firstIndex(of: offset) {
                selection.remove(at: position)
            } else {
                selection.append(offset)
            }
        } else {
            record(question.options[offset].label)
        }
    }

    private func record(_ answer: String) {
        answers[question.text] = answer
        selection = []
        if index + 1 < questions.count {
            index += 1
        } else {
            submit(answers)
        }
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
        case .working, .starting:
            Text(session.turnStartedAt, style: .timer)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        case .needsAttention:
            Text("Needs you")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.orange)
        case .done:
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
    static let working = Color(red: 0.4, green: 0.65, blue: 1)
}

private struct AgentBadge: View {
    let agent: AgentSession.Agent

    var body: some View {
        switch agent {
        case .claudeCode:
            ClaudeLogo()
                .frame(width: 14, height: 14)
                .help(agent.displayName)
        case .codex:
            Chip(agent.displayName)
        }
    }
}

private struct Chip: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.white.opacity(0.12)))
            .lineLimit(1)
    }
}

private struct UsageBar: View {
    let usage: ClaudeUsage

    var body: some View {
        HStack(spacing: 8) {
            ClaudeLogo()
                .frame(width: 13, height: 13)
            if let window = usage.fiveHour {
                UsageWindowView(label: "5h", window: window)
            }
            if usage.fiveHour != nil, usage.sevenDay != nil {
                Text("|")
                    .foregroundStyle(.quaternary)
            }
            if let window = usage.sevenDay {
                UsageWindowView(label: "7d", window: window)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .padding(.horizontal, AgentsPlugin.rowPadding)
        .help("Claude usage limits: share of the 5-hour and 7-day quota used, and time until each resets")
    }
}

private struct UsageWindowView: View {
    let label: String
    let window: UsageWindow

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .fontWeight(.semibold)
            Text("\(Int(window.utilization.rounded()))%")
                .fontWeight(.medium)
                .foregroundStyle(color)
            if let resetsAt = window.resetsAt, resetsAt > .now {
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
        case .starting, .working:
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
        }
    }
}

struct AgentsSettings: View {
    @Bindable var controller: AgentsController
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                HookRow(title: "Claude Code hooks", isInstalled: controller.isHookInstalled, error: $error) { installed in
                    installed ? try controller.uninstallHooks(for: .claudeCode) : try controller.installHooks(for: .claudeCode)
                }
                if controller.isCodexAvailable {
                    HookRow(title: "Codex hooks", isInstalled: controller.isCodexHookInstalled, error: $error) { installed in
                        installed ? try controller.uninstallHooks(for: .codex) : try controller.installHooks(for: .codex)
                    }
                }
                if let serverError = controller.serverError {
                    Text(serverError).foregroundStyle(.orange)
                } else {
                    LabeledContent("Listening on", value: "127.0.0.1:\(controller.installer.port)")
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            } footer: {
                Text("Installing adds a small script to ~/.claude (registered in ~/.claude/settings.json) or ~/.codex (registered in ~/.codex/hooks.json) so the agent reports session activity to Islet; the files are reformatted. Already running sessions need to be restarted. Codex additionally needs the hooks feature enabled in ~/.codex/config.toml and the hooks trusted once via /hooks. Nothing leaves your Mac.")
            }
            Section {
                LabeledContent("Needs attention") {
                    VStack(alignment: .leading) {
                        Toggle("Play a sound", isOn: $controller.alerts.attentionSound)
                        Toggle("Show a notification", isOn: $controller.alerts.attentionNotification)
                    }
                }
                LabeledContent("Finished") {
                    VStack(alignment: .leading) {
                        Toggle("Play a sound", isOn: $controller.alerts.finishedSound)
                        Toggle("Show a notification", isOn: $controller.alerts.finishedNotification)
                    }
                }
            } header: {
                Text("Alerts")
            } footer: {
                Text("Alerts fire when a session asks for permission, has a question or waits for input, and when it finishes its turn. Notifications need permission from macOS the first time they are enabled.")
            }
            Section {
                Toggle("Show Claude usage limits", isOn: $controller.showsUsage)
                if controller.showsUsage, let error = controller.usage.error {
                    Text(error).foregroundStyle(.orange)
                }
            } header: {
                Text("Usage")
            } footer: {
                Text("Shows how much of the 5-hour and 7-day Claude quota is used above the session list. Islet reads the Claude Code login from the Keychain to ask Anthropic for the numbers; macOS asks for permission the first time.")
            }
            Section {
                CopyableCommand(title: "SSH config", text: controller.installer.sshConfigSnippet)
                CopyableCommand(title: "Install on the remote", text: controller.installer.remoteInstallCommand)
            } header: {
                Text("Remote machines")
            } footer: {
                Text("Add the config line to the machine's Host entry in ~/.ssh/config (or pass -R \(controller.installer.port):127.0.0.1:\(controller.installer.port) to ssh) so the remote can reach Islet through the tunnel, then run the install command once on the remote machine. Sessions there show the host name and are marked unreachable when no updates arrive for \(Int(AgentSessionStore.unreachableTimeout / 60)) minutes.")
            }
        }
        .onAppear { controller.refreshInstallState() }
    }
}

private struct HookRow: View {
    let title: String
    let isInstalled: Bool
    @Binding var error: String?
    let toggle: (Bool) throws -> Void

    var body: some View {
        LabeledContent(title) {
            HStack {
                Text(isInstalled ? "Installed" : "Not installed")
                    .foregroundStyle(.secondary)
                Button(isInstalled ? "Remove" : "Install") {
                    do {
                        try toggle(isInstalled)
                        error = nil
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
            }
        }
    }
}

private struct CopyableCommand: View {
    let title: String
    let text: String
    @State private var copied = false

    var body: some View {
        LabeledContent(title) {
            HStack {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                }
            }
        }
    }
}
