import AppKit
import SwiftUI

struct AgentsSettings: View {
    @Bindable var controller: AgentsController
    @State private var error: String?
    @State private var confirmsRemoteReset = false

    private var claudeStatusLine: StatusLineInstaller.State {
        controller.statusLineStates[.claudeCode] ?? .notInstalled
    }

    var body: some View {
        Section {
            ForEach(controller.availableAgents, id: \.self) { agent in
                AgentRow(agent: agent.displayName, isInstalled: controller.installedHooks.contains(agent), error: $error) {
                    try controller.toggleHooks(for: agent)
                }
            }
            if let serverError = controller.serverError {
                Label(serverError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Connected Agents")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Connecting adds a small hook script to the agent's settings folder, so the agent reports its sessions to Islet. Restart sessions that are already running. Nothing leaves your Mac.")
                if controller.isAvailable(.codex) {
                    Text("Codex also needs its hooks feature turned on in ~/.codex/config.toml, and the hooks trusted once with /hooks.")
                }
                if controller.isAvailable(.antigravity) {
                    Text("Antigravity can't ask for permission through hooks, so answer its prompts in the terminal.")
                }
            }
        }
        .onAppear { controller.refreshInstallState() }

        Section {
            Toggle("Show Claude usage limits", isOn: $controller.showsUsage)
            if controller.showsUsage {
                Toggle("5-hour limit", isOn: $controller.display.showsFiveHourLimit)
                    .disabled(!controller.display.showsWeeklyLimit)
                Toggle("Weekly limit", isOn: $controller.display.showsWeeklyLimit)
                    .disabled(!controller.display.showsFiveHourLimit)
                Toggle("Time until the limits reset", isOn: $controller.display.showsResetTimes)
            }
            StatusLineRow(title: "Claude Code status line", state: claudeStatusLine, original: controller.statusLineInstaller(for: .claudeCode)?.originalCommand, error: $error) {
                try controller.toggleStatusLine(for: .claudeCode)
            }
            if claudeStatusLine == .replaced {
                Label("The status line was changed outside Islet, so usage limits and session names no longer arrive. Reconnecting keeps your new status line.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if controller.showsUsage, claudeStatusLine == .notInstalled {
                Label("Usage limits need the status line connection.", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            } else if controller.showsUsage, controller.usage.usage == nil, claudeStatusLine != .notInstalled {
                Text("The limits appear after your next message in Claude Code.")
                    .foregroundStyle(.secondary)
            }
            if controller.isAvailable(.antigravity), let state = controller.statusLineStates[.antigravity] {
                StatusLineRow(title: "Antigravity status line", state: state, original: controller.statusLineInstaller(for: .antigravity)?.originalCommand, error: $error) {
                    try controller.toggleStatusLine(for: .antigravity)
                }
            }
        } header: {
            Text("Usage Limits")
        } footer: {
            Text("Claude Code reports usage limits and session names only to its status line, and only on Pro and Max plans. The connection forwards them to Islet and then runs your own status line command, so your status line stays the same. While any status line is set, Claude Code hides its keyboard hints.")
        }

        Section {
            Toggle("Play a sound when an agent needs you", isOn: $controller.alerts.attentionSound)
            Toggle("Notify me when an agent needs you", isOn: $controller.alerts.attentionNotification)
            Toggle("Play a sound when an agent finishes", isOn: $controller.alerts.finishedSound)
            Toggle("Notify me when an agent finishes", isOn: $controller.alerts.finishedNotification)
            Toggle("Announce status changes below the notch", isOn: $controller.alerts.announcesInNotch)
        } header: {
            Text("Alerts")
        } footer: {
            Text("An agent needs you when it asks for permission, has a question or waits for input. Clicking a notification shows the session in its terminal.")
        }

        Section {
            Picker("Show", selection: $controller.display.pillContent) {
                ForEach(DisplaySettings.PillContent.allCases) { content in
                    Text(content.displayName).tag(content)
                }
            }
            if controller.display.pillContent == .ring {
                Picker("Finished sessions", selection: $controller.display.ringKeepsFinishedSessions) {
                    Text("Stay green until the next prompt").tag(true)
                    Text("Turn gray after \(Int(AgentSessionStore.finishedPillDuration / 60)) minutes").tag(false)
                }
            }
            Toggle("Show while agents are working", isOn: $controller.display.pillShowsWorking)
            Toggle("Show when an agent has finished", isOn: $controller.display.pillShowsFinished)
        } header: {
            Text("Collapsed Notch")
        } footer: {
            Text("The status ring counts sessions that need you, are working, have finished or are idle. The notch always shows an agent that needs you.")
        }

        Section {
            LabeledContent("Recent actions per session") {
                Stepper(value: $controller.display.historyLength, in: DisplaySettings.historyLengthRange) {
                    Text("\(controller.display.historyLength)")
                        .monospacedDigit()
                }
            }
        } header: {
            Text("Session List")
        }

        Section {
            CopyableCommand(title: "SSH config line", preview: controller.sshConfigSnippet) { [snippet = controller.sshConfigSnippet] in snippet }
            CopyableCommand(title: "Install command", preview: controller.remoteInstallCommandPreview, makeText: controller.makeRemoteInstallCommand)
            LabeledContent("Disconnect every remote machine") {
                Button("Reset Remote Access…") { confirmsRemoteReset = true }
            }
        } header: {
            Text("Remote Machines")
        } footer: {
            Text("Follow agents running over SSH: add the config line to the machine's Host entry in ~/.ssh/config, connect, and run the install command there once. Each copied command works once within \(Int(HookServer.installCodeLifetime.components.seconds / 60)) minutes, and copying again replaces it. Sessions show their host and are marked unreachable when no updates arrive for \(Int(AgentSessionStore.unreachableTimeout / 60)) minutes.")
        }
        .confirmationDialog("Reset remote access?", isPresented: $confirmsRemoteReset) {
            Button("Reset", role: .destructive) { Task { await controller.resetRemoteAccess() } }
        } message: {
            Text("Remote machines stop reporting to Islet until you run a new install command on them.")
        }
    }
}

private struct AgentRow: View {
    let agent: String
    let isInstalled: Bool
    @Binding var error: String?
    let toggle: () throws -> Void

    var body: some View {
        LabeledContent {
            Button(isInstalled ? "Disconnect" : "Connect") {
                do {
                    try toggle()
                    error = nil
                } catch {
                    self.error = error.localizedDescription
                }
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(isInstalled ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(agent)
                    Text(isInstalled ? "Connected" : "Not connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct StatusLineRow: View {
    let title: String
    let state: StatusLineInstaller.State
    let original: String?
    @Binding var error: String?
    let perform: () throws -> Void

    private var status: String {
        switch state {
        case .installed, .outdated: "Connected"
        case .notInstalled: "Not connected"
        case .replaced: "Changed outside Islet"
        }
    }

    private var action: String {
        switch state {
        case .installed, .outdated: "Disconnect"
        case .notInstalled: "Connect"
        case .replaced: "Reconnect"
        }
    }

    var body: some View {
        LabeledContent {
            Button(action) {
                do {
                    try perform()
                    error = nil
                } catch {
                    self.error = error.localizedDescription
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(state == .replaced ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                if state == .installed, let original {
                    Text("Shows your status line: \(original)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }
}

private struct CopyableCommand: View {
    let title: String
    let preview: String
    let makeText: () async -> String
    @State private var copied = false

    var body: some View {
        LabeledContent {
            Button(copied ? "Copied" : "Copy") {
                Task {
                    let text = await makeText()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(preview)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}
