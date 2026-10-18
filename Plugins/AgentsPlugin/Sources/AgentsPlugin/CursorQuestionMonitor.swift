import Foundation
import SQLite3

/// Cursor's ask_question tool fires no hook, so open questions are read from Cursor's chat database, only while a local Cursor session works.
/// Cursor writes a question's header at once but its status about 20 s later, so a question without a status counts as open.
@MainActor
final class CursorQuestionMonitor {
    static let pollInterval: Duration = .seconds(1)
    static let attentionReason = "Waiting for your answer in Cursor"
    private nonisolated static let query = """
        select 1 from cursorDiskKV as chat, json_each(chat.value, '$.fullConversationHeadersOnly') as header
        left join cursorDiskKV as bubble on bubble.key = 'bubbleId:' || ?1 || ':' || json_extract(header.value, '$.bubbleId')
        where chat.key = 'composerData:' || ?1
          and json_extract(header.value, '$.grouping.toolCallCase') = 'askQuestionToolCall'
          and header.key > (select max(prompt.key) from json_each(chat.value, '$.fullConversationHeadersOnly') as prompt where json_extract(prompt.value, '$.type') = 1)
          and coalesce(json_extract(bubble.value, '$.toolFormerData.additionalData.status'), 'pending') in ('loading', 'pending')
        limit 1
        """

    private let database: String
    private let onChange: (String, Bool) -> Void
    private var sessionIDs: Set<String> = []
    private var isStarted = false
    private var task: Task<Void, Never>?

    init(database: String, onChange: @escaping (_ sessionID: String, _ isAsking: Bool) -> Void) {
        self.database = database
        self.onChange = onChange
    }

    static func database(in home: URL) -> String {
        home.appending(path: "Library/Application Support/Cursor/User/globalStorage/state.vscdb").path
    }

    func track(_ sessions: [AgentSession]) {
        sessionIDs = Set(sessions.filter { $0.agent == .cursor && !$0.isRemote && Self.canAsk($0.state) }.map(\.id))
        updateTask()
    }

    private static func canAsk(_ state: AgentSession.State) -> Bool {
        switch state {
        case .working: true
        case .needsAttention(let reason): reason == attentionReason
        case .starting, .waiting, .done, .interrupted, .failed: false
        }
    }

    func start() {
        isStarted = true
        updateTask()
    }

    func stop() {
        isStarted = false
        updateTask()
    }

    private func updateTask() {
        guard isStarted, !sessionIDs.isEmpty else {
            task?.cancel()
            task = nil
            return
        }
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard !Task.isCancelled, let self else { return }
                await poll()
            }
        }
    }

    func poll() async {
        let ids = sessionIDs
        let database = database
        let asking = await Task.detached(priority: .utility) { Self.sessionsAsking(among: ids, in: database) }.value
        for id in ids where sessionIDs.contains(id) {
            onChange(id, asking.contains(id))
        }
    }

    nonisolated static func sessionsAsking(among ids: Set<String>, in database: String) -> Set<String> {
        var connection: OpaquePointer?
        defer { sqlite3_close(connection) }
        guard !ids.isEmpty, sqlite3_open_v2(database, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        sqlite3_busy_timeout(connection, 500)
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(connection, query, -1, &statement, nil) == SQLITE_OK else { return [] }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        return ids.filter { id in
            sqlite3_reset(statement)
            sqlite3_bind_text(statement, 1, id, -1, transient)
            return sqlite3_step(statement) == SQLITE_ROW
        }
    }
}
