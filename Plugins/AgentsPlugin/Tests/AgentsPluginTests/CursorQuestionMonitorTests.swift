import Foundation
import SQLite3
import Testing
@testable import AgentsPlugin

@MainActor
struct CursorQuestionMonitorTests {
    /// Cursor marks the header of an open question as completed; only the bubble holds the question's status.
    struct Bubble {
        var toolCallCase: String?
        var status: String?
        var isPrompt = false

        static let prompt = Bubble(isPrompt: true)
        static func question(_ status: String) -> Bubble { Bubble(toolCallCase: "askQuestionToolCall", status: status) }
        static func tool(_ status: String) -> Bubble { Bubble(toolCallCase: "shellToolCall", status: status) }
    }

    static func makeDatabase(_ chats: [String: [Bubble]]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "CursorQuestionMonitorTests.\(UUID().uuidString).vscdb")
        var connection: OpaquePointer?
        defer { sqlite3_close(connection) }
        try #require(sqlite3_open(url.path, &connection) == SQLITE_OK)
        var sql = "create table cursorDiskKV (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);"
        for (id, bubbles) in chats {
            var headers: [String] = []
            for bubble in bubbles {
                let bubbleID = UUID().uuidString
                let grouping = bubble.toolCallCase.map { #""grouping":{"toolCallCase":"\#($0)","toolFormerStatus":"completed"},"# } ?? ""
                headers.append(#"{"bubbleId":"\#(bubbleID)",\#(grouping)"type":\#(bubble.isPrompt ? 1 : 2)}"#)
                let toolFormerData = bubble.status.map { #"{"toolFormerData":{"status":"completed","additionalData":{"status":"\#($0)"}}}"# } ?? "{}"
                sql += "insert into cursorDiskKV values ('bubbleId:\(id):\(bubbleID)', '\(toolFormerData)');"
            }
            sql += "insert into cursorDiskKV values ('composerData:\(id)', '{\"fullConversationHeadersOnly\":[\(headers.joined(separator: ","))]}');"
        }
        try #require(sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK)
        return url
    }

    @Test func findsChatsWithAnOpenQuestion() throws {
        let database = try Self.makeDatabase([
            "asking": [.prompt, .tool("success"), .question("pending")],
            "answered": [.prompt, .question("submitted"), .tool("pending")],
            "cancelled": [.prompt, .question("cancelled")],
            "abandoned": [.prompt, .question("pending"), .prompt],
            "unsaved": [.prompt, Bubble(toolCallCase: "askQuestionToolCall")]
        ])
        defer { try? FileManager.default.removeItem(at: database) }

        let asking = CursorQuestionMonitor.sessionsAsking(among: ["asking", "answered", "cancelled", "abandoned", "unsaved", "unknown"], in: database.path)
        #expect(asking == ["asking", "unsaved"])
        #expect(CursorQuestionMonitor.sessionsAsking(among: ["asking"], in: database.path + ".missing").isEmpty)
    }

    @Test func showsAWorkingCursorSessionAsNeedingAttentionWhileItAsks() async throws {
        let database = try Self.makeDatabase(["chat": [.prompt, .question("pending")]])
        defer { try? FileManager.default.removeItem(at: database) }
        let store = AgentSessionStore()
        var alerts: [AgentSessionStore.Alert] = []
        store.onAlert = { alerts.append($0) }
        let monitor = CursorQuestionMonitor(database: database.path) { store.setAskingQuestion($0, $1) }
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "chat", prompt: "x", agent: .cursor))
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "claude", prompt: "x"))
        monitor.track(store.sessions)

        await monitor.poll()
        #expect(store.sessions.first { $0.id == "chat" }?.state == .needsAttention(CursorQuestionMonitor.attentionReason))
        #expect(store.sessions.first { $0.id == "claude" }?.state == .working)
        #expect(alerts.map(\.session.id) == ["chat"])

        monitor.track(store.sessions)
        try FileManager.default.removeItem(at: database)
        await monitor.poll()
        #expect(store.sessions.first { $0.id == "chat" }?.state == .working)
    }

    @Test func leavesOtherStatesAlone() {
        let store = AgentSessionStore()
        store.apply(HookEvent(kind: .userPromptSubmit, sessionID: "chat", prompt: "x", agent: .cursor))
        store.apply(HookEvent(kind: .stop, sessionID: "chat", agent: .cursor))
        store.setAskingQuestion("chat", true)
        #expect(store.sessions.first?.state == .done)
    }
}
