import Foundation
import IsletCore
import Testing
@testable import AgentsPlugin

struct HookInstallerTests {
    func makeInstaller(agent: AgentSession.Agent = .claudeCode) throws -> HookInstaller {
        let directory = FileManager.default.temporaryDirectory.appending(path: "AgentsPluginTests." + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return HookInstaller(agent: agent, directory: directory, port: 7365, token: "deadbeef")
    }

    @Test func installsCodexHooksIntoHooksJSON() throws {
        let installer = try makeInstaller(agent: .codex)
        #expect(installer.settingsURL.lastPathComponent == "hooks.json")
        #expect(!installer.events.contains("Notification"))
        try installer.install()
        #expect(installer.isInstalled)
        #expect(try String(contentsOf: installer.scriptURL, encoding: .utf8).contains("-H \"X-Islet-Agent: codex\""))
        let hooks = (try JSONSerialization.jsonObject(with: Data(contentsOf: installer.settingsURL)) as? [String: Any])?["hooks"] as? [String: Any]
        #expect(Set(hooks?.keys.map { $0 } ?? []) == Set(installer.events))
        try installer.uninstall()
        #expect(!installer.isInstalled)
    }

    @Test func scriptForwardsThePayloadWithTheSessionTitleFromItsTranscript() throws {
        let installer = try makeInstaller()
        try installer.install()
        let transcript = installer.directory.appending(path: "transcript.jsonl")
        try """
        {"type":"custom-title","customTitle":"first","sessionId":"a"}
        {"type":"user","message":"hello"}
        {"type":"custom-title","customTitle":"islet main","sessionId":"a"}
        {"type":"ai-title","aiTitle":"generated later","sessionId":"a"}
        {"type":"ai-title","aiTitle":"quoted \\"ai\\" title","sessionId":"a"}

        """.write(to: transcript, atomically: true, encoding: .utf8)
        let capture = installer.directory.appending(path: "curl-call")
        let fakeCurl = installer.directory.appending(path: "curl")
        try "#!/bin/sh\nprintf '%s\\n' \"$@\" > '\(capture.path)'\ncat >> '\(capture.path)'\nfor a in \"$@\"; do case \"$a\" in @*) cat \"${a#@}\" >> '\(capture.path)';; esac; done\n".write(to: fakeCurl, atomically: true, encoding: .utf8)
        let cwd = installer.directory.appending(path: "project")
        try FileManager.default.createDirectory(at: cwd.appending(path: "db"), withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCurl.path)
        let payload = #"{"session_id":"a","hook_event_name":"Stop","transcript_path":"\#(transcript.path)"}"#

        let path = installer.directory.path + ":/usr/bin:/bin"
        let environments: [(exists: Bool, title: String, terminal: String, environment: [String: String])] = [
            (true, "islet main", "com.example.terminal", ["__CFBundleIdentifier": "com.example.terminal", "TERM_PROGRAM": "fallback"]),
            (true, "islet main", "cursor", ["TERM_PROGRAM": "vscode", "VSCODE_GIT_ASKPASS_MAIN": "/home/me/.cursor-server/bin/abc/extensions/git/dist/askpass-main.js"]),
            (true, "islet main", "vscode", ["TERM_PROGRAM": "vscode", "VSCODE_GIT_ASKPASS_MAIN": "/home/me/.vscode-server/bin/abc/extensions/git/dist/askpass-main.js"]),
            (false, "", "fallback", ["TERM_PROGRAM": "fallback"]),
        ]
        for (transcriptExists, expectedTitle, expectedTerminal, environment) in environments {
            if !transcriptExists { try FileManager.default.removeItem(at: transcript) }
            let process = Process()
            process.executableURL = URL(filePath: "/bin/sh")
            process.arguments = [installer.scriptURL.path]
            process.environment = environment.merging(["PATH": path]) { $1 }
            process.currentDirectoryURL = cwd
            let input = Pipe()
            process.standardInput = input
            try process.run()
            input.fileHandleForWriting.write(Data(payload.utf8))
            try input.fileHandleForWriting.close()
            process.waitUntilExit()
            let call = try String(contentsOf: capture, encoding: .utf8).components(separatedBy: "\n")
            #expect(call.contains("X-Islet-Title: \(expectedTitle)"))
            #expect(call.contains("X-Islet-Agent: claude-code"))
            #expect(call.contains("X-Islet-Terminal: \(expectedTerminal)"))
            #expect(call.filter { $0.contains("deadbeef") } == ["header = \"Authorization: Bearer deadbeef\""])
            #expect(call.contains { $0.hasPrefix("X-Islet-TTY: ") && !$0.contains("/dev/db") })
            #expect(call.last == payload)
        }
    }

    @Test func scriptOnlyReadsTheTranscriptWhenTheTitleCanChange() throws {
        let installer = try makeInstaller()
        try installer.install()
        let transcript = installer.directory.appending(path: "transcript.jsonl")
        try #"{"type":"custom-title","customTitle":"named","sessionId":"a"}"#.write(to: transcript, atomically: true, encoding: .utf8)
        let capture = installer.directory.appending(path: "curl-call")
        let fakeCurl = installer.directory.appending(path: "curl")
        try "#!/bin/sh\nprintf '%s\\n' \"$@\" > '\(capture.path)'\n".write(to: fakeCurl, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCurl.path)
        for (event, expectedTitle) in [("PreToolUse", ""), ("PostToolUseFailure", ""), ("PermissionRequest", ""), ("Notification", ""), ("UserPromptSubmit", "named"), ("Stop", "named")] {
            let process = Process()
            process.executableURL = URL(filePath: "/bin/sh")
            process.arguments = [installer.scriptURL.path]
            process.environment = ["PATH": installer.directory.path + ":/usr/bin:/bin"]
            let input = Pipe()
            process.standardInput = input
            try process.run()
            input.fileHandleForWriting.write(Data(#"{"session_id":"a","hook_event_name":"\#(event)","transcript_path":"\#(transcript.path)"}"#.utf8))
            try input.fileHandleForWriting.close()
            process.waitUntilExit()
            let call = try String(contentsOf: capture, encoding: .utf8).components(separatedBy: "\n")
            #expect(call.contains("X-Islet-Title: \(expectedTitle)"), "\(event)")
        }
    }

    @Test func scriptFallsBackToTheGeneratedTitleAndReportsTheAgentProcess() throws {
        let installer = try makeInstaller()
        try installer.install()
        let transcript = installer.directory.appending(path: "transcript.jsonl")
        try """
        {"type":"ai-title","aiTitle":"first guess","sessionId":"a"}
        {"type":"user","message":"hello"}
        {"type":"ai-title","aiTitle":"fix \\"hook\\" titles \\\\ now","sessionId":"a"}

        """.write(to: transcript, atomically: true, encoding: .utf8)
        let capture = installer.directory.appending(path: "curl-call")
        let fakeCurl = installer.directory.appending(path: "curl")
        try "#!/bin/sh\nprintf '%s\\n' \"$@\" > '\(capture.path)'\n".write(to: fakeCurl, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCurl.path)
        let payload = #"{"session_id":"a","hook_event_name":"Stop","transcript_path":"\#(transcript.path)"}"#

        let agent = installer.directory.appending(path: "claude")
        try FileManager.default.createSymbolicLink(at: agent, withDestinationURL: URL(filePath: "/bin/bash"))
        let process = Process()
        process.executableURL = agent
        process.arguments = ["-c", "/usr/bin/time sh \"$0\" 2>/dev/null; true", installer.scriptURL.path]
        process.environment = ["PATH": installer.directory.path + ":/usr/bin:/bin"]
        let input = Pipe()
        process.standardInput = input
        try process.run()
        input.fileHandleForWriting.write(Data(payload.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        let call = try String(contentsOf: capture, encoding: .utf8).components(separatedBy: "\n")
        #expect(call.contains(#"X-Islet-Title: fix "hook" titles \ now"#))
        #expect(call.contains("X-Islet-PID: \(process.processIdentifier)"))
    }

    @Test func scriptReportsTheCodexThreadNameAndGitBranch() throws {
        let installer = try makeInstaller(agent: .codex)
        try installer.install()
        let transcript = installer.directory.appending(path: "rollout.jsonl")
        try """
        {"type":"session_meta","payload":{"id":"a","git":{"commit_hash":"be3e","branch":"feature/x","repository_url":"git@example.com:r.git"}}}
        {"type":"event_msg","payload":{"type":"task_started"}}

        """.write(to: transcript, atomically: true, encoding: .utf8)
        try """
        {"id":"a","thread_name":"old name","updated_at":"2026-10-04T09:40:56Z"}
        {"id":"b","thread_name":"other","updated_at":"2026-10-04T09:41:00Z"}
        {"id":"a","thread_name":"Fix \\"two\\" sum","updated_at":"2026-10-04T09:42:00Z"}

        """.write(to: installer.directory.appending(path: "session_index.jsonl"), atomically: true, encoding: .utf8)
        let capture = installer.directory.appending(path: "curl-call")
        let fakeCurl = installer.directory.appending(path: "curl")
        try "#!/bin/sh\nprintf '%s\\n' \"$@\" > '\(capture.path)'\n".write(to: fakeCurl, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCurl.path)
        let payload = #"{"session_id":"a","hook_event_name":"Stop","transcript_path":"\#(transcript.path)"}"#

        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = [installer.scriptURL.path]
        process.environment = ["PATH": installer.directory.path + ":/usr/bin:/bin"]
        let input = Pipe()
        process.standardInput = input
        try process.run()
        input.fileHandleForWriting.write(Data(payload.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        let call = try String(contentsOf: capture, encoding: .utf8).components(separatedBy: "\n")
        #expect(call.contains(#"X-Islet-Title: Fix "two" sum"#))
        #expect(call.contains("X-Islet-Branch: feature/x"))
    }

    @Test func killingTheScriptAbortsTheRequestAndCleansUp() throws {
        let installer = try makeInstaller()
        try installer.install()
        let capture = installer.directory.appending(path: "curl-call")
        let fakeCurl = installer.directory.appending(path: "curl")
        try "#!/bin/sh\nfor a in \"$@\"; do case \"$a\" in @*) body=\"${a#@}\";; esac; done\nprintf '%s\\n%s\\n' \"$$\" \"$body\" > '\(capture.path)'\nexec sleep 30\n".write(to: fakeCurl, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCurl.path)

        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = [installer.scriptURL.path, "600"]
        process.environment = ["PATH": installer.directory.path + ":/usr/bin:/bin"]
        let input = Pipe()
        process.standardInput = input
        try process.run()
        input.fileHandleForWriting.write(Data(#"{"session_id":"a","hook_event_name":"PermissionRequest"}"#.utf8))
        try input.fileHandleForWriting.close()

        let deadline = Date().addingTimeInterval(10)
        var call: [String] = []
        while call.count < 2, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
            call = ((try? String(contentsOf: capture, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        }
        let request = try #require(Int32(call.first ?? ""))
        #expect(FileManager.default.fileExists(atPath: call[1]))

        kill(process.processIdentifier, SIGTERM)
        process.waitUntilExit()
        let exitDeadline = Date().addingTimeInterval(5)
        while kill(request, 0) == 0, Date() < exitDeadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        #expect(kill(request, 0) != 0)
        #expect(!FileManager.default.fileExists(atPath: call[1]))
    }

    @Test func installsScriptAndMergesHooksWithoutTouchingOtherSettings() throws {
        let installer = try makeInstaller()
        let existing = """
        {"model":"opus","hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo hi"}]}]}}
        """
        try existing.write(to: installer.settingsURL, atomically: true, encoding: .utf8)
        #expect(!installer.isInstalled)

        try installer.install()
        #expect(installer.isInstalled)

        let settings = try JSONSerialization.jsonObject(with: Data(contentsOf: installer.settingsURL)) as! [String: Any]
        #expect(settings["model"] as? String == "opus")
        let hooks = settings["hooks"] as! [String: Any]
        #expect(Set(hooks.keys) == Set(installer.events))
        let preToolUse = hooks["PreToolUse"] as! [[String: Any]]
        #expect(preToolUse.count == 2)
        #expect((preToolUse[0]["matcher"] as? String) == "Bash")
        let permissionHook = ((hooks["PermissionRequest"] as! [[String: Any]])[0]["hooks"] as! [[String: Any]])[0]
        #expect(permissionHook["command"] as? String == "'" + installer.scriptURL.path + "' 600")
        #expect(permissionHook["timeout"] as? Int == 605)
        #expect((((preToolUse[1]["hooks"] as! [[String: Any]])[0])["timeout"] as? Int) == 10)
        let sessionEnd = ((hooks["SessionEnd"] as! [[String: Any]])[0]["hooks"] as! [[String: Any]])[0]
        #expect(sessionEnd["timeout"] as? Int == 3)
        #expect(sessionEnd["command"] as? String == "'" + installer.scriptURL.path + "' 2")

        let script = try String(contentsOf: installer.scriptURL, encoding: .utf8)
        #expect(script.contains("Bearer deadbeef"))
        #expect(script.contains("127.0.0.1:7365/hook"))
        #expect(script.contains(#"-H "X-Islet-Terminal: $terminal""#))
        #expect(script.contains(#"-H "X-Islet-TTY: $tty""#))
        #expect(script.contains(#"-H "X-Islet-Tmux: $TMUX""#))
        #expect(script.contains(#"-H "X-Islet-Tmux-Pane: $TMUX_PANE""#))
        let permissions = try FileManager.default.attributesOfItem(atPath: installer.scriptURL.path)[.posixPermissions] as! Int
        #expect(permissions == 0o700)
        #expect(try String(contentsOf: installer.settingsURL, encoding: .utf8).contains("\"command\" : \"'/"))

        try installer.install()
        #expect((try JSONSerialization.jsonObject(with: Data(contentsOf: installer.settingsURL)) as! [String: Any])["hooks"].map { ($0 as! [String: Any])["PreToolUse"] as! [[String: Any]] }?.count == 2)

        try installer.uninstall()
        #expect(!installer.isInstalled)
        let after = try JSONSerialization.jsonObject(with: Data(contentsOf: installer.settingsURL)) as! [String: Any]
        let afterHooks = after["hooks"] as! [String: Any]
        #expect(Array(afterHooks.keys) == ["PreToolUse"])
        #expect(!FileManager.default.fileExists(atPath: installer.scriptURL.path))
    }

    @Test func installsIntoMissingSettingsFile() throws {
        let installer = try makeInstaller()
        try installer.install()
        #expect(installer.isInstalled)
        try installer.uninstall()
        let after = try JSONSerialization.jsonObject(with: Data(contentsOf: installer.settingsURL)) as! [String: Any]
        #expect(after.isEmpty)
    }

    @Test func writesThroughASymlinkedSettingsFile() throws {
        let installer = try makeInstaller()
        let dotfiles = installer.directory.appending(path: "dotfiles", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dotfiles, withIntermediateDirectories: true)
        let target = dotfiles.appending(path: "settings.json")
        try #"{"model":"opus"}"#.write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: installer.settingsURL, withDestinationURL: target)

        try installer.install()

        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: installer.settingsURL.path) == target.path)
        let settings = try JSONSerialization.jsonObject(with: Data(contentsOf: target)) as? [String: Any]
        #expect(settings?["model"] as? String == "opus")
        #expect(settings?["hooks"] != nil)
        #expect(installer.isInstalled)
    }

    @Test func writesThroughADanglingRelativeSymlink() throws {
        let installer = try makeInstaller()
        let dotfiles = installer.directory.appending(path: "dotfiles", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dotfiles, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: installer.settingsURL.path, withDestinationPath: "dotfiles/settings.json")

        try installer.install()

        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: installer.settingsURL.path) == "dotfiles/settings.json")
        let settings = try JSONSerialization.jsonObject(with: Data(contentsOf: dotfiles.appending(path: "settings.json"))) as? [String: Any]
        #expect(settings?["hooks"] != nil)
    }

    @Test func refusesToOverwriteSettingsThatAreNotAnObject() throws {
        let installer = try makeInstaller()
        try "[1, 2]".write(to: installer.settingsURL, atomically: true, encoding: .utf8)
        #expect(throws: SettingsFile.Unreadable.self) { try installer.install() }
        #expect(try String(contentsOf: installer.settingsURL, encoding: .utf8) == "[1, 2]")
    }

    @Test func remoteInstallScriptReproducesTheLocalInstallation() throws {
        let installer = try makeInstaller()
        let codex = try makeInstaller(agent: .codex)
        let remote = FileManager.default.temporaryDirectory.appending(path: "AgentsPluginTests.remote." + UUID().uuidString)
        let remoteCodex = remote.appending(path: "codex")
        try FileManager.default.createDirectory(at: remoteCodex, withIntermediateDirectories: true)
        try #"{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo done"}]}]}}"#.write(to: remote.appending(path: "settings.json"), atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.environment = ["HOME": "/nonexistent", "PATH": "/usr/bin:/bin", "CLAUDE_CONFIG_DIR": remote.path, "CODEX_HOME": remoteCodex.path]
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = Pipe()
        try process.run()
        input.fileHandleForWriting.write(Data(HookInstaller.remoteInstallScript(for: [installer, codex]).utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)

        let remoteInstaller = HookInstaller(directory: remote, port: 7365, token: "deadbeef")
        #expect(remoteInstaller.isInstalled)
        #expect(HookInstaller(agent: .codex, directory: remoteCodex, port: 7365, token: "deadbeef").isInstalled)
        let settings = try JSONSerialization.jsonObject(with: Data(contentsOf: remoteInstaller.settingsURL)) as? [String: Any]
        #expect(settings?["model"] as? String == "opus")
        let stop = (settings?["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]
        #expect(stop?.count == 2)
        let command = ((stop?.last?["hooks"] as? [[String: Any]])?.first?["command"] as? String) ?? ""
        #expect(command == "'\(remoteInstaller.scriptURL.path)'")
        #expect(installer.remoteInstallCommand(code: "c0de").contains("Bearer c0de"))
        #expect(!installer.remoteInstallCommand(code: "c0de").contains("deadbeef"))
        #expect(installer.remoteInstallCommand(code: "c0de").contains("127.0.0.1:7365/install"))
        #expect(installer.sshConfigSnippet == "RemoteForward 7365 127.0.0.1:7365")
    }

    @Test func outdatedScriptCountsAsNotInstalled() throws {
        let installer = try makeInstaller()
        try installer.install()
        try "#!/bin/sh\nexit 0\n".write(to: installer.scriptURL, atomically: true, encoding: .utf8)
        #expect(!installer.isInstalled)
        #expect(installer.needsUpgrade)
    }

    @Test func outdatedHookEntriesCountAsNotInstalled() throws {
        let installer = try makeInstaller()
        try installer.install()
        var settings = try JSONSerialization.jsonObject(with: Data(contentsOf: installer.settingsURL)) as! [String: Any]
        var hooks = settings["hooks"] as! [String: Any]
        hooks["SessionEnd"] = [["hooks": [["type": "command", "command": "'" + installer.scriptURL.path + "'", "timeout": 10]]]]
        settings["hooks"] = hooks
        try JSONSerialization.data(withJSONObject: settings).write(to: installer.settingsURL)
        #expect(!installer.isInstalled)
        #expect(installer.needsUpgrade)
        try installer.install()
        #expect(installer.isInstalled)
    }

    @Test func scriptForwardsTheTmuxLocation() throws {
        let installer = try makeInstaller()
        try installer.install()
        let capture = installer.directory.appending(path: "curl-call")
        let fakeCurl = installer.directory.appending(path: "curl")
        try "#!/bin/sh\nprintf '%s\\n' \"$@\" > '\(capture.path)'\n".write(to: fakeCurl, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCurl.path)
        let payload = #"{"session_id":"a","hook_event_name":"Stop"}"#
        for (environment, expectedTmux, expectedPane) in [(["TMUX": "/tmp/tmux-501/default,1234,0", "TMUX_PANE": "%3"], "/tmp/tmux-501/default,1234,0", "%3"), ([:], "", "")] {
            let process = Process()
            process.executableURL = URL(filePath: "/bin/sh")
            process.arguments = [installer.scriptURL.path]
            process.environment = environment.merging(["PATH": installer.directory.path + ":/usr/bin:/bin"]) { $1 }
            let input = Pipe()
            process.standardInput = input
            try process.run()
            input.fileHandleForWriting.write(Data(payload.utf8))
            try input.fileHandleForWriting.close()
            process.waitUntilExit()
            let call = try String(contentsOf: capture, encoding: .utf8).components(separatedBy: "\n")
            #expect(call.contains("X-Islet-Tmux: \(expectedTmux)"))
            #expect(call.contains("X-Islet-Tmux-Pane: \(expectedPane)"))
        }
    }
}
