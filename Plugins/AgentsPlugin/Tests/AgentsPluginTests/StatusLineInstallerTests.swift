import Foundation
import IsletCore
import Testing
@testable import AgentsPlugin

struct StatusLineInstallerTests {
    func makeInstaller(settings: String? = nil, name: String = "StatusLineInstallerTests") throws -> StatusLineInstaller {
        let directory = FileManager.default.temporaryDirectory.appending(path: name + "." + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let settings {
            try settings.write(to: directory.appending(path: "settings.json"), atomically: true, encoding: .utf8)
        }
        return StatusLineInstaller(directory: directory, port: 7365, token: "deadbeef")
    }

    @Test func antigravityStatusLineReportsAsAntigravity() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "StatusLineInstallerTests." + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try #"{"statusLine":"broken"}"#.write(to: directory.appending(path: "settings.json"), atomically: true, encoding: .utf8)
        let installer = StatusLineInstaller(agent: .antigravity, directory: directory, port: 7365, token: "deadbeef")
        #expect(installer.script.contains("-H \"X-Islet-Agent: antigravity\""))
        let error = #expect(throws: StatusLineInstaller.InvalidStatusLine.self) { try installer.install() }
        #expect(error?.localizedDescription.contains(directory.appending(path: "settings.json").path) == true)
        try #"{"model":"Gemini"}"#.write(to: directory.appending(path: "settings.json"), atomically: true, encoding: .utf8)
        try installer.install()
        #expect(installer.state == .installed)
        #expect(try settings(of: installer)["model"] as? String == "Gemini")
    }

    func settings(of installer: StatusLineInstaller) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: installer.directory.appending(path: "settings.json"))) as? [String: Any] ?? [:]
    }

    func ownCommand(_ installer: StatusLineInstaller) -> String {
        "'" + installer.scriptURL.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    @Test func installsWithoutAnExistingStatusLineAndRemovesItAgain() throws {
        let installer = try makeInstaller(settings: #"{"model":"opus"}"#)
        #expect(installer.state == .notInstalled)

        try installer.install()
        #expect(installer.state == .installed)
        #expect(installer.originalCommand == nil)
        let statusLine = try settings(of: installer)["statusLine"] as? [String: Any]
        #expect(statusLine?["type"] as? String == "command")
        #expect(statusLine?["command"] as? String == ownCommand(installer))

        try installer.uninstall()
        #expect(installer.state == .notInstalled)
        let restored = try settings(of: installer)
        #expect(restored["statusLine"] == nil)
        #expect(restored["model"] as? String == "opus")
        #expect(!FileManager.default.fileExists(atPath: installer.scriptURL.path))
    }

    @Test func wrapsAnExistingStatusLineAndRestoresIt() throws {
        let installer = try makeInstaller(settings: #"{"statusLine":{"type":"command","command":"~/.claude/statusline.sh","padding":2,"refreshInterval":5}}"#)

        try installer.install()
        #expect(installer.state == .installed)
        #expect(installer.originalCommand == "~/.claude/statusline.sh")
        var statusLine = try settings(of: installer)["statusLine"] as? [String: Any]
        #expect(statusLine?["command"] as? String == ownCommand(installer))
        #expect(statusLine?["padding"] as? Int == 2)
        #expect(statusLine?["refreshInterval"] as? Int == 5)

        try installer.install()
        #expect(installer.originalCommand == "~/.claude/statusline.sh")

        try installer.uninstall()
        statusLine = try settings(of: installer)["statusLine"] as? [String: Any]
        #expect(statusLine?["command"] as? String == "~/.claude/statusline.sh")
        #expect(statusLine?["padding"] as? Int == 2)
        #expect(installer.originalCommand == nil)
    }

    @Test func noticesWhenTheStatusLineWasReplacedOrIsOutdated() throws {
        let installer = try makeInstaller()
        try installer.install()

        var settings = try settings(of: installer)
        settings["statusLine"] = ["type": "command", "command": "echo new"]
        try JSONSerialization.data(withJSONObject: settings).write(to: installer.directory.appending(path: "settings.json"))
        #expect(installer.state == .replaced)

        try installer.install()
        #expect(installer.state == .installed)
        #expect(installer.originalCommand == "echo new")

        try "#!/bin/sh\n".write(to: installer.scriptURL, atomically: true, encoding: .utf8)
        #expect(installer.state == .outdated)
    }

    @Test func refusesToOverwriteSettingsThatAreNotAnObject() throws {
        let installer = try makeInstaller(settings: "[]")
        #expect(throws: SettingsFile.Unreadable.self) { try installer.install() }
        let statusLine = try makeInstaller(settings: #"{"statusLine":"~/bin/line"}"#)
        #expect(throws: StatusLineInstaller.InvalidStatusLine.self) { try statusLine.install() }
    }

    @Test func otherSpellingsOfItsOwnScriptAreNeverWrapped() throws {
        let installer = try makeInstaller()
        try installer.install()
        var settings = try settings(of: installer)
        settings["statusLine"] = ["type": "command", "command": "sh \(installer.scriptURL.path)"]
        try JSONSerialization.data(withJSONObject: settings).write(to: installer.directory.appending(path: "settings.json"))
        #expect(installer.state == .outdated)

        try installer.install()
        #expect(installer.state == .installed)
        #expect(installer.originalCommand == nil)
        try installer.uninstall()
        #expect(try self.settings(of: installer)["statusLine"] == nil)
    }

    @Test func aRemovedStatusLineCountsAsNotInstalled() throws {
        let installer = try makeInstaller()
        try installer.install()
        var settings = try settings(of: installer)
        settings["statusLine"] = nil
        try JSONSerialization.data(withJSONObject: settings).write(to: installer.directory.appending(path: "settings.json"))
        #expect(installer.state == .notInstalled)
    }

    @Test func scriptWorksFromADirectoryWithSpacesAndQuotes() throws {
        let installer = try makeInstaller(settings: #"{"statusLine":{"type":"command","command":"printf ok"}}"#, name: "status line's dir")
        try installer.install()
        #expect(try run(installer, input: #"{"session_id":"s1"}"#, path: "/nonexistent:/usr/bin:/bin") == "ok")
    }

    @Test func scriptForwardsTheInputAndShowsTheOriginalStatusLine() throws {
        let installer = try makeInstaller(settings: #"{"statusLine":{"type":"command","command":"printf 'original: '; cat"}}"#)
        try installer.install()
        let capture = installer.directory.appending(path: "curl-call")
        let fakeCurl = installer.directory.appending(path: "curl")
        try "#!/bin/sh\nprintf '%s\\n' \"$@\" > '\(capture.path).partial'\ncat /dev/fd/3 >> '\(capture.path).partial'\ncat >> '\(capture.path).partial'\nmv '\(capture.path).partial' '\(capture.path)'\n".write(to: fakeCurl, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCurl.path)
        let payload = #"{"session_id":"s1","session_name":"islet"}"#

        let output = try run(installer, input: payload, path: installer.directory.path + ":/usr/bin:/bin")
        #expect(output == "original: " + payload)

        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: capture.path), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        let call = try String(contentsOf: capture, encoding: .utf8).components(separatedBy: "\n")
        #expect(call.contains("http://127.0.0.1:7365/statusline"))
        #expect(call.contains("X-Islet-Agent: claude-code"))
        #expect(call.filter { $0.contains("deadbeef") } == ["header = \"Authorization: Bearer deadbeef\""])
        #expect(call.last == payload)
    }

    @Test func scriptPrintsNothingWithoutAnOriginalStatusLine() throws {
        let installer = try makeInstaller()
        try installer.install()
        #expect(try run(installer, input: #"{"session_id":"s1"}"#, path: "/nonexistent:/usr/bin:/bin").isEmpty)
    }

    private func run(_ installer: StatusLineInstaller, input: String, path: String) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", ownCommand(installer)]
        process.environment = ["PATH": path]
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        try process.run()
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: output, as: UTF8.self)
    }
}
