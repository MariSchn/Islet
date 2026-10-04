import Foundation
import Testing
@testable import ScriptsPlugin

struct IsletCommandTests {
    struct Result {
        var status: Int32
        var stderr: String
        var calls: [[String]]
    }

    final class Fixture {
        let root = FileManager.default.temporaryDirectory.appending(path: "IsletCommandTests." + UUID().uuidString)
        let command: IsletCommand
        var bin: URL { root.appending(path: "bin") }
        var capture: URL { root.appending(path: "calls") }
        var tokenFile: URL { root.appending(path: "token") }

        init(withToken: Bool = true) throws {
            try FileManager.default.createDirectory(at: root.appending(path: "bin"), withIntermediateDirectories: true)
            if withToken { try "tok123".write(to: root.appending(path: "token"), atomically: true, encoding: .utf8) }
            command = IsletCommand(port: 7777, tokenFile: root.appending(path: "token"), directory: root.appending(path: "installed"))
            try command.install()
            let fake = bin.appending(path: "curl")
            try "#!/bin/sh\nfor a in \"$@\"; do printf '%s\\n' \"$a\"; done >> '\(capture.path)'\nprintf 'STDIN:' >> '\(capture.path)'\ncat >> '\(capture.path)'\nprintf '\\n--END--\\n' >> '\(capture.path)'\nexit \"${FAKE_CURL_EXIT:-0}\"\n".write(to: fake, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        }

        deinit {
            try? FileManager.default.removeItem(at: root)
        }

        func run(_ arguments: [String], curlExit: Int = 0) throws -> Result {
            let process = Process()
            process.executableURL = command.url
            process.arguments = arguments
            process.environment = ["PATH": bin.path + ":/usr/bin:/bin", "FAKE_CURL_EXIT": String(curlExit)]
            let errors = Pipe()
            process.standardError = errors
            process.standardOutput = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            try process.run()
            let data = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = (try? String(contentsOf: capture, encoding: .utf8)) ?? ""
            let calls = text.components(separatedBy: "--END--\n").filter { !$0.isEmpty }.map { $0.components(separatedBy: "\n") }
            return Result(status: process.terminationStatus, stderr: String(decoding: data, as: UTF8.self), calls: calls)
        }
    }

    private func body(_ call: [String]) -> String? {
        call.firstIndex(of: "--data-binary").map { call[$0 + 1] }
    }

    private func method(_ call: [String]) -> String? {
        call.firstIndex(of: "-X").map { call[$0 + 1] }
    }

    private func url(_ call: [String]) -> String? {
        call.first { $0.hasPrefix("http://") }
    }

    @Test func announceSendsTextSymbolAndPriority() throws {
        let fixture = try Fixture()
        let result = try fixture.run(["announce", "Build finished", "--symbol", "hammer.fill", "--priority", "attention"])
        #expect(result.status == 0)
        let call = try #require(result.calls.first)
        #expect(method(call) == "POST")
        #expect(url(call) == "http://127.0.0.1:7777/announce")
        #expect(body(call) == #"{"text":"Build finished","symbol":"hammer.fill","priority":"attention"}"#)
        #expect(call.contains("STDIN:header = \"Authorization: Bearer tok123\""))
        #expect(!call.contains { $0.contains("tok123") && $0 != "STDIN:header = \"Authorization: Bearer tok123\"" })
        let plain = try Fixture().run(["announce", "Hi"])
        #expect(body(try #require(plain.calls.first)) == #"{"text":"Hi"}"#)
    }

    @Test func activityAndProgressSendTheRightBodies() throws {
        let activity = try #require(try Fixture().run(["activity", "x", "y"]).calls.first)
        #expect(method(activity) == "POST")
        #expect(url(activity) == "http://127.0.0.1:7777/activity")
        #expect(body(activity) == #"{"id":"x","text":"y"}"#)
        let full = try #require(try Fixture().run(["activity", "build", "Compiling", "--symbol", "gear", "--priority", "info", "--ttl", "30"]).calls.first)
        #expect(body(full) == #"{"id":"build","text":"Compiling","symbol":"gear","priority":"info","ttl":30}"#)

        let progress = try #require(try Fixture().run(["progress", "build", "0.4", "Compiling"]).calls.first)
        #expect(body(progress) == #"{"id":"build","text":"Compiling","progress":0.4}"#)
        let cases = [("40%", "0.40"), ("5%", "0.05"), ("100%", "1.00"), ("0%", "0.00"), ("12.5%", "0.125"), ("1", "1"), ("0", "0")]
        for (input, expected) in cases {
            let call = try #require(try Fixture().run(["progress", "p", input, "t"]).calls.first)
            #expect(body(call) == #"{"id":"p","text":"t","progress":\#(expected)}"#, "\(input)")
        }
    }

    @Test func doneAndClearRemoveActivities() throws {
        let done = try Fixture().run(["done", "build", "Build finished"])
        #expect(done.status == 0)
        #expect(done.calls.count == 2)
        #expect(method(done.calls[0]) == "DELETE")
        #expect(url(done.calls[0]) == "http://127.0.0.1:7777/activity/build")
        #expect(body(done.calls[0]) == nil)
        #expect(url(done.calls[1]) == "http://127.0.0.1:7777/announce")
        #expect(body(done.calls[1]) == #"{"text":"Build finished"}"#)

        let defaulted = try Fixture().run(["done", "build"])
        #expect(body(defaulted.calls[1]) == #"{"text":"build finished"}"#)

        let clear = try Fixture().run(["clear", "build"])
        #expect(clear.calls.count == 1)
        #expect(method(clear.calls[0]) == "DELETE")
        #expect(url(clear.calls[0]) == "http://127.0.0.1:7777/activity/build")
    }

    @Test func escapesJSONStrings() throws {
        let call = try #require(try Fixture().run(["announce", "say \"hi\" \\ back\tslash\nnew\r\nline"]).calls.first)
        #expect(body(call) == #"{"text":"say \"hi\" \\ back\tslash\nnew\r\nline"}"#)
    }

    @Test func dropsControlCharactersAndReportsRejections() throws {
        let call = try #require(try Fixture().run(["announce", "a\u{1B}b\u{7}c"]).calls.first)
        #expect(body(call) == #"{"text":"abc"}"#)
        let rejected = try Fixture().run(["announce", "x"], curlExit: 22)
        #expect(rejected.status == 1)
        #expect(rejected.stderr.contains("rejected"))
        let partial = try Fixture().run(["done", "a"], curlExit: 22)
        #expect(partial.status == 1)
    }

    @Test func runWrapsTheCommandAndKeepsItsStatus() throws {
        let ok = try Fixture().run(["run", "tests", "--", "sh", "-c", "exit 0"])
        #expect(ok.status == 0)
        #expect(ok.calls.count == 3)
        #expect(method(ok.calls[0]) == "POST")
        #expect(url(ok.calls[0]) == "http://127.0.0.1:7777/activity")
        #expect(body(ok.calls[0]) == #"{"id":"tests","text":"Running sh -c exit 0","ttl":86400}"#)
        #expect(method(ok.calls[1]) == "DELETE")
        #expect(url(ok.calls[1]) == "http://127.0.0.1:7777/activity/tests")
        #expect(body(ok.calls[2]) == #"{"text":"tests finished"}"#)

        let failed = try Fixture().run(["run", "tests", "--", "sh", "-c", "exit 3"])
        #expect(failed.status == 3)
        #expect(failed.calls.count == 3)
        #expect(body(failed.calls[2]) == #"{"text":"tests failed (exit 3)","priority":"attention"}"#)
    }

    @Test func runShortensLongCommandsToFitTheActivityText() throws {
        let long = String(repeating: "x", count: 300)
        let result = try Fixture().run(["run", "tests", "--", "sh", "-c", "exit 0", long])
        #expect(body(result.calls[0]) == #"{"id":"tests","text":"Running sh","ttl":86400}"#)
    }

    @Test func installedCommandIsOutdatedWhenItsScriptChanged() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "IsletCommandTests.outdated." + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let command = IsletCommand(port: 7777, tokenFile: directory.appending(path: "token"), directory: directory)
        try command.install()
        #expect(!command.isOutdated)
        try (command.script + "# old\n").write(to: command.url, atomically: true, encoding: .utf8)
        #expect(command.isOutdated)
    }

    @Test func runStillRunsTheCommandWhenIsletIsNotAvailable() throws {
        let marker = FileManager.default.temporaryDirectory.appending(path: "IsletCommandTests.marker." + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: marker) }
        let noToken = try Fixture(withToken: false)
        let result = try noToken.run(["run", "job", "--", "sh", "-c", "touch '\(marker.path)'; exit 4"])
        #expect(result.status == 4)
        #expect(FileManager.default.fileExists(atPath: marker.path))
        #expect(result.stderr.contains("Islet is not running"))
        #expect(result.stderr.split(separator: "\n").count == 1)
        #expect(result.calls.isEmpty)

        let unreachable = try Fixture()
        let failed = try unreachable.run(["run", "job", "--", "sh", "-c", "exit 5"], curlExit: 7)
        #expect(failed.status == 5)
        #expect(failed.stderr.contains("could not reach Islet"))
        #expect(failed.stderr.split(separator: "\n").count == 1)
    }

    @Test func reportsWhenIsletIsNotRunning() throws {
        let missing = try Fixture(withToken: false).run(["announce", "x"])
        #expect(missing.status == 1)
        #expect(missing.stderr.contains("not running"))
        let unreachable = try Fixture().run(["clear", "x"], curlExit: 7)
        #expect(unreachable.status == 1)
        #expect(unreachable.stderr.contains("could not reach"))
    }

    @Test func usageErrorsExitWithTwo() throws {
        let invocations: [[String]] = [
            [], ["bogus"], ["announce"], ["announce", "x", "--symbol"], ["announce", "x", "--bogus", "y"], ["announce", "x", "--ttl", "5"],
            ["activity", "id"], ["activity", "bad id", "t"], ["activity", "id", "t", "--ttl", "abc"],
            ["progress", "id", "0.4"], ["progress", "id", "abc", "t"], ["progress", "id", "x%", "t"], ["progress", "id", ".5", "t"], ["progress", "id", "05", "t"], ["progress", "id", "0.5\n,\"x\":1", "t"], ["activity", "id", "t", "--ttl", "007"], ["activity", "id", "t", "--ttl", "5\n1"],
            ["done"], ["done", "a", "b", "c"], ["done", "a/b"], ["clear"], ["clear", "a", "b"],
            ["run"], ["run", "id"], ["run", "id", "--"], ["run", "id", "sleep", "1"], ["run", "bad/id", "--", "true"],
        ]
        for arguments in invocations {
            let fixture = try Fixture()
            let result = try fixture.run(arguments)
            #expect(result.status == 2, "\(arguments)")
            #expect(result.stderr.contains("usage:"), "\(arguments)")
            #expect(result.calls.isEmpty, "\(arguments)")
        }
    }

    @Test func installsAndRemovesTheScript() throws {
        let fixture = try Fixture()
        let command = fixture.command
        #expect(command.isInstalled)
        let permissions = try FileManager.default.attributesOfItem(atPath: command.url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o755)
        let content = try String(contentsOf: command.url, encoding: .utf8)
        #expect(content.hasPrefix("#!/bin/sh\n"))
        #expect(content.contains("port=7777"))
        #expect(content.contains(fixture.tokenFile.path))
        #expect(!content.contains("tok123"))
        try command.uninstall()
        #expect(!command.isInstalled)
        #expect(!FileManager.default.fileExists(atPath: command.url.path))
    }

    @Test func refusesToReplaceAForeignFile() throws {
        let fixture = try Fixture()
        try fixture.command.uninstall()
        try "#!/bin/sh\necho mine\n".write(to: fixture.command.url, atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) { try fixture.command.install() }
        try fixture.command.uninstall()
        #expect(try String(contentsOf: fixture.command.url, encoding: .utf8) == "#!/bin/sh\necho mine\n")
    }

    @Test func quotesTokenPathsWithSpacesAndQuotes() throws {
        let fixture = try Fixture()
        let odd = fixture.root.appending(path: "it's a dir")
        try FileManager.default.createDirectory(at: odd, withIntermediateDirectories: true)
        try "tok123".write(to: odd.appending(path: "token"), atomically: true, encoding: .utf8)
        let command = IsletCommand(port: 7777, tokenFile: odd.appending(path: "token"), directory: fixture.root.appending(path: "other"))
        try command.install()
        let process = Process()
        process.executableURL = command.url
        process.arguments = ["clear", "a"]
        process.environment = ["PATH": fixture.bin.path + ":/usr/bin:/bin"]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(try String(contentsOf: fixture.capture, encoding: .utf8).contains("Bearer tok123"))
    }
}
