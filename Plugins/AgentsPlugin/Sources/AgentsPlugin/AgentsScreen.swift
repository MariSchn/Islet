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
                        SessionRow(session: session) { controller.store.dismiss(session.id) }
                    }
                }
            }
            .scrollDisabled(controller.store.sessions.count <= AgentsPlugin.maxVisibleRows)
        }
    }
}

private struct SessionRow: View {
    let session: AgentSession
    let dismiss: () -> Void
    @State private var isHovering = false

    var body: some View {
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
                    StateLabel(session: session)
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
        .padding(.horizontal, 10)
        .frame(height: AgentsPlugin.rowHeight)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(isHovering ? 0.1 : 0.06)))
        .overlay(alignment: .topTrailing) {
            Button(action: dismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove from list")
            .padding(6)
            .opacity(isHovering ? 1 : 0)
        }
        .onHover { isHovering = $0 }
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
