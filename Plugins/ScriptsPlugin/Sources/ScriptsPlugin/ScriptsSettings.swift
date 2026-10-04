import AppKit
import SwiftUI

struct ScriptsSettings: View {
    let controller: ScriptsController
    @State private var confirmsRegenerate = false

    private var example: String {
        "islet run backup -- rsync -a ~/Projects /Volumes/Backup"
    }

    private var curlExample: String {
        "curl -s -X POST -H \"Authorization: Bearer $(cat '\(controller.tokenFile.path)')\" -d '{\"id\":\"demo\",\"text\":\"Hello\"}' http://127.0.0.1:\(controller.port)/activity"
    }

    var body: some View {
        Section {
            LabeledContent {
                Button(controller.isCommandInstalled ? "Remove" : "Install") {
                    controller.isCommandInstalled ? controller.removeCommand() : controller.installCommand()
                }
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text("islet command")
                    Text(controller.isCommandInstalled ? "Installed in \(controller.command.url.deletingLastPathComponent().path)" : "Not installed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let error = controller.commandError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            CodeRow(code: example)
        } header: {
            Text("Command-Line Tool")
        } footer: {
            Text("Wrap a command with islet run to show it in the notch while it runs, and get an announcement when it ends. Run islet without arguments for all commands. Make sure ~/.local/bin is in your PATH.")
        }

        Section {
            if let serverError = controller.serverError {
                Label(serverError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                LabeledContent("Address", value: "127.0.0.1:\(controller.port)")
            }
            LabeledContent("Token") {
                HStack {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([controller.tokenFile]) }
                    Button("Regenerate…") { confirmsRegenerate = true }
                }
            }
            CodeRow(code: curlExample)
        } header: {
            Text("HTTP API")
        } footer: {
            Text("Any tool can post activities and announcements with the token from the token file as a bearer token. The islet command uses the same API.")
        }
        .confirmationDialog("Regenerate the token?", isPresented: $confirmsRegenerate) {
            Button("Regenerate", role: .destructive) { controller.regenerateToken() }
        } message: {
            Text("Scripts that copied the old token stop working. The islet command reads the new one automatically.")
        }
    }
}

private struct CodeRow: View {
    let code: String
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top) {
            Text(code)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(copied ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            }
        }
    }
}
