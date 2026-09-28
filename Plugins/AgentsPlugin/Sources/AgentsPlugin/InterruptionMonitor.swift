import Foundation

@MainActor
final class InterruptionMonitor {
    static let markers: Set<String> = ["[Request interrupted by user]", "[Request interrupted by user for tool use]"]
    static let pollInterval: Duration = .seconds(1)
    private static let markerPrefix = Data("[Request interrupted by user".utf8)

    private struct Watch {
        let path: String
        let turnStartedAt: Date
        var offset: UInt64
    }

    private var watches: [String: Watch] = [:]
    private var task: Task<Void, Never>?
    private let onInterrupt: (String) -> Void

    init(onInterrupt: @escaping (String) -> Void) {
        self.onInterrupt = onInterrupt
    }

    func track(_ sessions: [AgentSession]) {
        var next: [String: Watch] = [:]
        for session in sessions where !session.isRemote && Self.canBeInterrupted(session.state) {
            guard let path = session.transcriptPath else { continue }
            if let existing = watches[session.id], existing.path == path, existing.turnStartedAt == session.turnStartedAt {
                next[session.id] = existing
            } else {
                next[session.id] = Watch(path: path, turnStartedAt: session.turnStartedAt, offset: Self.size(of: path))
            }
        }
        watches = next
    }

    private static func canBeInterrupted(_ state: AgentSession.State) -> Bool {
        switch state {
        case .working, .needsAttention: true
        case .starting, .done, .interrupted, .failed: false
        }
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard !Task.isCancelled else { return }
                self?.poll()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        watches = [:]
    }

    func poll() {
        for (id, watch) in watches {
            guard let (lines, offset) = Self.readCompleteLines(of: watch) else { continue }
            watches[id]?.offset = offset
            if Self.containsInterruption(lines) {
                onInterrupt(id)
            }
        }
    }

    private static func size(of path: String) -> UInt64 {
        ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    private static func readCompleteLines(of watch: Watch) -> (Data, UInt64)? {
        guard let handle = FileHandle(forReadingAtPath: watch.path) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd(), end != watch.offset else { return nil }
        guard end > watch.offset else { return (Data(), end) }
        guard (try? handle.seek(toOffset: watch.offset)) != nil,
              let data = try? handle.read(upToCount: Int(end - watch.offset)),
              let lastNewline = data.lastIndex(of: UInt8(ascii: "\n"))
        else { return nil }
        let complete = data[data.startIndex...lastNewline]
        return (Data(complete), watch.offset + UInt64(complete.count))
    }

    static func containsInterruption(_ lines: Data) -> Bool {
        lines.split(separator: UInt8(ascii: "\n")).contains { line in
            line.range(of: markerPrefix) != nil && isInterruption(Data(line))
        }
    }

    private static func isInterruption(_ line: Data) -> Bool {
        guard let entry = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              entry["type"] as? String == "user",
              entry["isSidechain"] as? Bool != true,
              let message = entry["message"] as? [String: Any]
        else { return false }
        if let text = message["content"] as? String {
            return markers.contains(text)
        }
        let blocks = message["content"] as? [[String: Any]] ?? []
        return blocks.contains { $0["type"] as? String == "text" && markers.contains($0["text"] as? String ?? "") }
    }
}
