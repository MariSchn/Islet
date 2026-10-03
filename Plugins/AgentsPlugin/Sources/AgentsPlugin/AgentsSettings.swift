import AppKit
import SwiftUI

struct AgentsSettings: View {
    @Bindable var controller: AgentsController
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                InstallRow(title: "Claude Code hooks", isInstalled: controller.isHookInstalled, error: $error) { installed in
                    installed ? try controller.uninstallHooks(for: .claudeCode) : try controller.installHooks(for: .claudeCode)
                }
                if controller.isCodexAvailable {
                    InstallRow(title: "Codex hooks", isInstalled: controller.isCodexHookInstalled, error: $error) { installed in
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
                StatusLineRow(state: controller.statusLineState, error: $error) {
                    switch controller.statusLineState {
                    case .installed, .outdated: try controller.uninstallStatusLine()
                    case .notInstalled, .replaced: try controller.installStatusLine()
                    }
                }
                if controller.statusLineState == .replaced {
                    Text("The status line was changed outside Islet, so usage limits and session names no longer reach Islet. Reinstalling keeps showing your new status line.")
                        .foregroundStyle(.orange)
                } else if controller.statusLineState == .installed, let original = controller.statusLineInstaller.originalCommand {
                    LabeledContent("Your status line") {
                        Text(original)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            } header: {
                Text("Status line")
            } footer: {
                Text("Claude Code passes its status line command the session name and your usage limits. Installing adds a small script to ~/.claude that forwards this data to Islet and then runs your own status line command, so Claude Code still shows the same status line. While any status line is configured, Claude Code hides its keyboard hints below the prompt. Removing restores your previous status line.")
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
                Text("Alerts fire when a session asks for permission, has a question or waits for input, and when it finishes its turn. Notifications need permission from macOS the first time they are enabled; clicking one shows the session in its terminal.")
            }
            Section {
                Picker("Next to the notch", selection: $controller.display.pillContent) {
                    ForEach(DisplaySettings.PillContent.allCases) { content in
                        Text(content.displayName).tag(content)
                    }
                }
                if controller.display.pillContent == .ring {
                    Picker("Finished sessions in the ring", selection: $controller.display.ringKeepsFinishedSessions) {
                        Text("Stay green until the next prompt").tag(true)
                        Text("Turn gray after \(Int(AgentSessionStore.finishedPillDuration / 60)) minutes").tag(false)
                    }
                }
                LabeledContent("Show the pill") {
                    VStack(alignment: .leading) {
                        Toggle("While agents are working", isOn: $controller.display.pillShowsWorking)
                        Toggle("When an agent has just finished", isOn: $controller.display.pillShowsFinished)
                    }
                }
                LabeledContent("Status changes") {
                    Toggle("Show briefly in the notch", isOn: $controller.alerts.announcesInNotch)
                }
            } header: {
                Text("Pill")
            } footer: {
                Text("The status ring shows how many sessions need you, are working, have finished or are idle. Summary text shows what the agents are doing instead. Hiding finished sessions also skips their status change. The pill always appears when an agent needs you.")
            }
            Section {
                LabeledContent("Recent actions") {
                    Stepper("\(controller.display.historyLength)", value: $controller.display.historyLength, in: DisplaySettings.historyLengthRange)
                }
            } header: {
                Text("Session list")
            } footer: {
                Text("The number of recent tool calls listed when a session is expanded.")
            }
            Section {
                Toggle("Show Claude usage limits", isOn: $controller.showsUsage)
                if controller.showsUsage {
                    LabeledContent("Show") {
                        VStack(alignment: .leading) {
                            Toggle("5-hour limit", isOn: $controller.display.showsFiveHourLimit)
                                .disabled(!controller.display.showsWeeklyLimit)
                            Toggle("Weekly limit", isOn: $controller.display.showsWeeklyLimit)
                                .disabled(!controller.display.showsFiveHourLimit)
                            Toggle("Time until reset", isOn: $controller.display.showsResetTimes)
                        }
                    }
                    switch controller.statusLineState {
                    case .notInstalled, .replaced:
                        Text("Needs the Claude Code status line above.")
                            .foregroundStyle(.orange)
                    case .installed, .outdated:
                        if controller.usage.usage == nil {
                            Text("Appears after your next message in Claude Code. Usage limits are only reported for Claude Pro and Max plans, and not by sessions in projects that set their own status line.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Usage")
            } footer: {
                Text("Shows how much of the 5-hour and 7-day Claude quota is used above the session list. The numbers come from Claude Code's status line and update while you use Claude Code.")
            }
            Section {
                CopyableCommand(title: "SSH config") { [snippet = controller.installer.sshConfigSnippet] in snippet }
                CopyableCommand(title: "Install on the remote", makeText: controller.makeRemoteInstallCommand)
            } header: {
                Text("Remote machines")
            } footer: {
                Text("Add the config line to the machine's Host entry in ~/.ssh/config (or pass -R \(controller.installer.port):127.0.0.1:\(controller.installer.port) to ssh) so the remote can reach Islet through the tunnel, then run the install command once on the remote machine. Its code works once and expires after \(Int(HookServer.installCodeLifetime.components.seconds / 60)) minutes, so copy a fresh command for each machine. Sessions there show the host name and are marked unreachable when no updates arrive for \(Int(AgentSessionStore.unreachableTimeout / 60)) minutes.")
            }
        }
        .onAppear { controller.refreshInstallState() }
    }
}

private struct InstallRow: View {
    let title: String
    let status: String
    let action: String
    @Binding var error: String?
    let perform: () throws -> Void

    init(title: String, isInstalled: Bool, error: Binding<String?>, toggle: @escaping (Bool) throws -> Void) {
        self.init(title: title, status: isInstalled ? "Installed" : "Not installed", action: isInstalled ? "Remove" : "Install", error: error) {
            try toggle(isInstalled)
        }
    }

    init(title: String, status: String, action: String, error: Binding<String?>, perform: @escaping () throws -> Void) {
        self.title = title
        self.status = status
        self.action = action
        self._error = error
        self.perform = perform
    }

    var body: some View {
        LabeledContent(title) {
            HStack {
                Text(status)
                    .foregroundStyle(.secondary)
                Button(action) {
                    do {
                        try perform()
                        error = nil
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
            }
        }
    }
}

private struct StatusLineRow: View {
    let state: StatusLineInstaller.State
    @Binding var error: String?
    let perform: () throws -> Void

    var body: some View {
        switch state {
        case .installed, .outdated:
            InstallRow(title: "Claude Code status line", status: "Installed", action: "Remove", error: $error, perform: perform)
        case .notInstalled:
            InstallRow(title: "Claude Code status line", status: "Not installed", action: "Install", error: $error, perform: perform)
        case .replaced:
            InstallRow(title: "Claude Code status line", status: "Replaced", action: "Reinstall", error: $error, perform: perform)
        }
    }
}

private struct CopyableCommand: View {
    let title: String
    let makeText: () async -> String
    @State private var text = ""
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
                    Task {
                        text = await makeText()
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        copied = true
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                }
            }
        }
        .task { text = await makeText() }
    }
}
