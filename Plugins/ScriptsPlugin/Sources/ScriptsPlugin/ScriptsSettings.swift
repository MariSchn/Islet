import AppKit
import SwiftUI

struct ScriptsSettings: View {
    let controller: ScriptsController

    private var example: String {
        "curl -s -X POST -H \"Authorization: Bearer $(cat '\(controller.tokenFile.path)')\" -d '{\"id\":\"demo\",\"text\":\"Hello\"}' http://127.0.0.1:\(controller.port)/activity"
    }

    var body: some View {
        Form {
            Section {
                if let serverError = controller.serverError {
                    Text(serverError).foregroundStyle(.orange)
                } else {
                    LabeledContent("Listening on", value: "127.0.0.1:\(controller.port)")
                }
                LabeledContent("Token file") {
                    Text(controller.tokenFile.path)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                }
                Button("Regenerate token") { controller.regenerateToken() }
            } footer: {
                Text("Requests need the token from the file as a bearer token. Regenerating it invalidates the old one.")
            }
            Section {
                LabeledContent("islet command") {
                    Button(controller.isCommandInstalled ? "Remove" : "Install command-line tool") {
                        controller.isCommandInstalled ? controller.removeCommand() : controller.installCommand()
                    }
                }
                if let error = controller.commandError {
                    Text(error).foregroundStyle(.red)
                }
            } header: {
                Text("Command-line tool")
            } footer: {
                Text("Installs \(controller.command.url.path). Make sure ~/.local/bin is in your PATH.")
            }
            Section {
                Text(example)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                Button("Copy example") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(example, forType: .string)
                }
            } header: {
                Text("Example")
            }
        }
        .formStyle(.grouped)
    }
}
