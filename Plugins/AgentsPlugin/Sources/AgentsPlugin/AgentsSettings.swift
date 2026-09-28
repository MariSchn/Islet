import AppKit
import SwiftUI

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
                    if let error = controller.usage.error {
                        Text(error).foregroundStyle(.orange)
                    }
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
