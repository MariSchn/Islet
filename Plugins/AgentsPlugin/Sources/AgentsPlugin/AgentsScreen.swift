import SwiftUI

struct AgentsScreen: View {
    let controller: AgentsController
    @State private var installError: String?

    var body: some View {
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
                } else if controller.isHookInstalled {
                    Text("No agent sessions")
                        .foregroundStyle(.secondary)
                    Text("Sessions started after installing the hooks appear here once you send a prompt.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Claude Code hooks are not installed")
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
                            dismiss: { controller.store.dismiss(session.id) },
                            decide: { controller.decide($0, $1) }
                        )
                    }
                }
            }
            .scrollDisabled(AgentsPlugin.contentSize(for: controller.store.sessions).height < AgentsPlugin.maxContentHeight)
        }
    }
}

private struct SessionRow: View {
    let session: AgentSession
    let dismiss: () -> Void
    let decide: (UUID, PermissionDecision) -> Void
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 0) {
            summary
                .frame(height: AgentsPlugin.rowHeight)
            if let request = session.pendingRequest {
                RequestView(request: request) { decide(request.id, $0) }
                    .id(request.id)
                    .frame(height: AgentsPlugin.requestHeight(for: request))
            }
        }
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(isHovering ? 0.1 : 0.06)))
        .onHover { isHovering = $0 }
    }

    private var summary: some View {
        HStack(alignment: .center, spacing: 10) {
            StateIndicator(state: session.state)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.projectName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if let host = session.host {
                        Text(host)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    ZStack(alignment: .trailing) {
                        StateLabel(session: session)
                            .opacity(isHovering ? 0 : 1)
                        Button(action: dismiss) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove from list")
                        .opacity(isHovering ? 1 : 0)
                    }
                }
                if let task = session.task {
                    Text(task)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(session.state.requiresAttention ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                    .lineLimit(1)
            }
        }
    }

    private var detail: String {
        switch session.state {
        case .starting: "Starting…"
        case .working: session.activity ?? "Working…"
        case .needsAttention(let reason): reason
        case .done: "Finished"
        }
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
    @State private var selection: [String] = []

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
            .frame(maxWidth: .infinity, minHeight: AgentsPlugin.requestDetailHeight, maxHeight: AgentsPlugin.requestDetailHeight, alignment: .topLeading)
            ForEach(question.options, id: \.label) { option in
                RequestButton(
                    option.label,
                    systemImage: question.multiSelect ? (selection.contains(option.label) ? "checkmark.square.fill" : "square") : "arrow.turn.down.right",
                    tint: .accentColor,
                    fullWidth: true
                ) { choose(option.label) }
                .help(option.description ?? "")
            }
            if question.multiSelect {
                RequestButton(index + 1 < questions.count ? "Next" : "Submit", systemImage: "checkmark", tint: .green) {
                    record(selection.joined(separator: ", "))
                }
                .disabled(selection.isEmpty)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func choose(_ label: String) {
        if question.multiSelect {
            if let position = selection.firstIndex(of: label) {
                selection.remove(at: position)
            } else {
                selection.append(label)
            }
        } else {
            record(label)
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
    let systemImage: String
    let tint: Color
    var fullWidth = false
    let action: () -> Void

    init(_ title: String, systemImage: String, tint: Color, fullWidth: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.fullWidth = fullWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
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
            Text(session.updatedAt, style: .relative)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }
}

private struct StateIndicator: View {
    let state: AgentSession.State

    var body: some View {
        switch state {
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
    let controller: AgentsController
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Claude Code hooks") {
                    HStack {
                        Text(controller.isHookInstalled ? "Installed" : "Not installed")
                            .foregroundStyle(.secondary)
                        Button(controller.isHookInstalled ? "Remove" : "Install") {
                            do {
                                if controller.isHookInstalled {
                                    try controller.uninstallHooks()
                                } else {
                                    try controller.installHooks()
                                }
                                error = nil
                            } catch {
                                self.error = error.localizedDescription
                            }
                        }
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
                Text("Installing adds a small script to ~/.claude and registers it in ~/.claude/settings.json (the file is reformatted) so Claude Code reports session activity to Islet. Already running Claude Code sessions need to be restarted. Nothing leaves your Mac.")
            }
        }
        .onAppear { controller.refreshInstallState() }
    }
}
