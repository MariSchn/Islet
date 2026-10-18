import Foundation

struct BackgroundTask: Sendable, Equatable, Codable {
    static let wakeUpID = "wake-up"

    var id: String
    var toolUseID: String?
    var label: String
    var until: Date?

    init(id: String, toolUseID: String? = nil, label: String, until: Date? = nil) {
        self.id = id
        self.toolUseID = toolUseID
        self.label = label
        self.until = until
    }

    init?(launchedBy event: HookEvent) {
        guard event.kind == .postToolUse, event.agentID == nil, let response = event.toolResponse else { return nil }
        let input = event.toolInput
        let description = input?["description"]?.stringValue
        switch event.toolName {
        case "Bash":
            guard let id = response.backgroundTaskID else { return nil }
            self.init(id: id, toolUseID: event.toolUseID, label: "Waiting: \(description ?? HookEvent.command(in: input).map { "$ \($0)" } ?? "background command")")
        case "Agent", "Task":
            guard response.status == "async_launched", let id = response.agentID else { return nil }
            self.init(id: id, toolUseID: event.toolUseID, label: "Waiting for agent: \(description ?? "background agent")")
        case "Monitor":
            guard let id = response.taskID else { return nil }
            self.init(id: id, toolUseID: event.toolUseID, label: "Monitoring: \(description ?? "background command")")
        case "ScheduleWakeup":
            guard let scheduledFor = response.scheduledFor else { return nil }
            let date = Date(timeIntervalSince1970: scheduledFor / 1000)
            self.init(id: Self.wakeUpID, label: "Waking up at \(date.formatted(date: .omitted, time: .shortened))", until: date)
        default:
            return nil
        }
    }

    /// IDs of the tasks with a notification that carries a final `<status>`; "resumed" notifications have none.
    static func finishedIDs(of tasks: [BackgroundTask], in data: Data) -> Set<String> {
        Set(tasks.filter { task in
            let needles = [Data("<task-id>\(task.id)</task-id>".utf8)] + (task.toolUseID.map { [Data("<tool-use-id>\($0)</tool-use-id>".utf8)] } ?? [])
            return needles.contains { hasFinalNotification(for: $0, in: data) }
        }.map(\.id))
    }

    private static func hasFinalNotification(for needle: Data, in data: Data) -> Bool {
        let (closing, status) = (Data("</task-notification>".utf8), Data("<status>".utf8))
        var start = data.startIndex
        while let match = data.range(of: needle, in: start..<data.endIndex) {
            let window = match.upperBound..<min(match.upperBound + 4096, data.endIndex)
            let end = data.range(of: closing, in: window)?.lowerBound ?? window.upperBound
            if data.range(of: status, in: match.upperBound..<end) != nil { return true }
            start = match.upperBound
        }
        return false
    }

    static func update(_ tasks: inout [BackgroundTask], for event: HookEvent, at timestamp: Date) {
        switch event.kind {
        case .userPromptSubmit where event.isTaskNotification:
            let finished = finishedIDs(of: tasks, in: Data((event.prompt ?? "").utf8))
            tasks.removeAll { finished.contains($0.id) }
        case .userPromptSubmit:
            tasks.removeAll { $0.id == wakeUpID && ($0.until ?? .distantPast) <= timestamp }
        case .postToolUse where event.agentID == nil:
            if let task = BackgroundTask(launchedBy: event) {
                tasks.removeAll { $0.id == task.id }
                tasks.append(task)
            } else if event.toolName == "TaskStop" || event.toolName == "KillShell", let id = (event.toolInput?["task_id"] ?? event.toolInput?["shell_id"])?.stringValue {
                tasks.removeAll { $0.id == id }
            } else if event.toolName == "ScheduleWakeup", event.toolInput?["stop"]?.boolValue == true {
                tasks.removeAll { $0.id == wakeUpID }
            }
        case .sessionStart:
            tasks = []
        default:
            break
        }
    }

    static func label(for tasks: [BackgroundTask]) -> String {
        tasks.count == 1 ? tasks[0].label : "Waiting on \(tasks.count) background tasks"
    }
}

struct ToolResponse: Sendable, Equatable, Decodable {
    var backgroundTaskID: String?
    var status: String?
    var agentID: String?
    var taskID: String?
    var scheduledFor: Double?

    private enum CodingKeys: String, CodingKey {
        case backgroundTaskID = "backgroundTaskId"
        case status
        case agentID = "agentId"
        case taskID = "taskId"
        case scheduledFor
    }

    init(backgroundTaskID: String? = nil, status: String? = nil, agentID: String? = nil, taskID: String? = nil, scheduledFor: Double? = nil) {
        self.backgroundTaskID = backgroundTaskID
        self.status = status
        self.agentID = agentID
        self.taskID = taskID
        self.scheduledFor = scheduledFor
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        backgroundTaskID = try? container.decodeIfPresent(String.self, forKey: .backgroundTaskID)
        status = try? container.decodeIfPresent(String.self, forKey: .status)
        agentID = try? container.decodeIfPresent(String.self, forKey: .agentID)
        taskID = try? container.decodeIfPresent(String.self, forKey: .taskID)
        scheduledFor = try? container.decodeIfPresent(Double.self, forKey: .scheduledFor)
    }
}
