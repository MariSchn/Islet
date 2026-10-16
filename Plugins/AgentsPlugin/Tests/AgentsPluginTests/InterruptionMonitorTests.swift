import Foundation
import IsletCore
import Testing
@testable import AgentsPlugin

@MainActor
struct InterruptionMonitorTests {
    static let interrupted = #"{"parentUuid":"a","isSidechain":false,"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]},"uuid":"b"}"#
    static let deniedTool = #"{"isSidechain":false,"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}"#
    static let assistantQuote = #"{"isSidechain":false,"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"[Request interrupted by user]"}]}}"#
    static let promptQuote = #"{"isSidechain":false,"type":"user","message":{"role":"user","content":"Why does [Request interrupted by user] appear?"}}"#
    static let sidechain = #"{"isSidechain":true,"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]}}"#
    static let progress = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Working on it"}]}}"#

    @Test func recognizesOnlyTheAgentsOwnInterruptionEntries() {
        #expect(InterruptionMonitor.containsInterruption(Data((Self.progress + "\n" + Self.interrupted + "\n").utf8)))
        #expect(InterruptionMonitor.containsInterruption(Data((Self.deniedTool + "\n").utf8)))
        #expect(!InterruptionMonitor.containsInterruption(Data((Self.assistantQuote + "\n").utf8)))
        #expect(!InterruptionMonitor.containsInterruption(Data((Self.promptQuote + "\n").utf8)))
        #expect(!InterruptionMonitor.containsInterruption(Data((Self.sidechain + "\n").utf8)))
        #expect(!InterruptionMonitor.containsInterruption(Data("[Request interrupted by user] not json\n".utf8)))
    }

    @Test func readsPastLinesLongerThanTheReadLimit() throws {
        let transcript = FileManager.default.temporaryDirectory.appending(path: "InterruptionMonitorTests.\(UUID().uuidString).jsonl")
        try Data().write(to: transcript)
        defer { try? FileManager.default.removeItem(at: transcript) }
        var interrupted: [String] = []
        let monitor = InterruptionMonitor { interrupted.append($0) }
        let store = AgentSessionStore()
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "local", transcriptPath: transcript.path, prompt: "x"))
        monitor.track(store.sessions)

        let image = #"{"type":"user","message":{"content":""# + String(repeating: "A", count: Int(TranscriptReader.tailSize) + 200_000) + #""}}"#
        try Data((image + "\n" + Self.interrupted + "\n").utf8).write(to: transcript)
        for _ in 0..<5 { monitor.poll() }
        #expect(interrupted == ["local"])
    }

    @Test func reportsInterruptionsAppendedWhileASessionWorks() throws {
        let transcript = FileManager.default.temporaryDirectory.appending(path: "InterruptionMonitorTests.\(UUID().uuidString).jsonl")
        try Data((Self.interrupted + "\n").utf8).write(to: transcript)
        defer { try? FileManager.default.removeItem(at: transcript) }
        func append(_ text: String) throws {
            let handle = try FileHandle(forWritingTo: transcript)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
            try handle.close()
        }

        var interrupted: [String] = []
        let monitor = InterruptionMonitor { interrupted.append($0) }
        let store = AgentSessionStore()
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "local", transcriptPath: transcript.path, prompt: "x"))
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "remote", transcriptPath: transcript.path, prompt: "x", host: "elsewhere"))
        store.apply(HookEvent(kind: .stop, sessionID: "finished", transcriptPath: transcript.path))
        monitor.track(store.sessions)

        monitor.poll()
        #expect(interrupted.isEmpty)

        try append(Self.progress + "\n")
        monitor.poll()
        #expect(interrupted.isEmpty)

        try append(String(Self.interrupted.prefix(40)))
        monitor.poll()
        #expect(interrupted.isEmpty)

        try append(String(Self.interrupted.dropFirst(40)) + "\n")
        monitor.poll()
        #expect(interrupted == ["local"])

        monitor.poll()
        #expect(interrupted == ["local"])

        try Data((Self.progress + "\n").utf8).write(to: transcript)
        monitor.poll()
        try append(Self.interrupted + "\n")
        monitor.poll()
        #expect(interrupted == ["local", "local"])

        store.markInterrupted("local")
        monitor.track(store.sessions)
        try append(Self.interrupted + "\n")
        monitor.poll()
        #expect(interrupted == ["local", "local"])
    }

    @Test func anInterruptionBeforeTheNextPromptDoesNotEndTheNewTurn() throws {
        let transcript = FileManager.default.temporaryDirectory.appending(path: "InterruptionMonitorTests.\(UUID().uuidString).jsonl")
        try Data((Self.progress + "\n").utf8).write(to: transcript)
        defer { try? FileManager.default.removeItem(at: transcript) }
        var clock = Date(timeIntervalSince1970: 1_000_000)
        var interrupted: [String] = []
        let monitor = InterruptionMonitor { interrupted.append($0) }
        let store = AgentSessionStore(now: { clock })
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "s", transcriptPath: transcript.path, prompt: "first"))
        monitor.track(store.sessions)

        let handle = try FileHandle(forWritingTo: transcript)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((Self.interrupted + "\n").utf8))
        try handle.close()
        clock += 1
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "s", prompt: "second"))
        monitor.track(store.sessions)
        monitor.poll()

        #expect(interrupted.isEmpty)
        #expect(store.sessions[0].state == .working)
    }
}
