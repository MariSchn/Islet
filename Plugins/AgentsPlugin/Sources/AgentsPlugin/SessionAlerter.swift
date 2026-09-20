import AppKit
import UserNotifications

public struct AlertSettings: Sendable, Equatable {
    public var attentionSound = true
    public var attentionNotification = false
    public var finishedSound = true
    public var finishedNotification = false

    public init() {}

    public var usesNotifications: Bool { attentionNotification || finishedNotification }
}

@MainActor
final class SessionAlerter {
    static let attentionSound = "Ping"
    static let finishedSound = "Glass"

    var settings: AlertSettings {
        didSet {
            if settings.usesNotifications, !oldValue.usesNotifications { requestAuthorization() }
        }
    }

    init(settings: AlertSettings) {
        self.settings = settings
        if settings.usesNotifications { requestAuthorization() }
    }

    func handle(_ alert: AgentSessionStore.Alert) {
        switch alert {
        case .needsAttention(let session):
            if settings.attentionSound { play(Self.attentionSound) }
            if settings.attentionNotification {
                notify(id: "attention-\(session.id)", title: "\(session.projectName) needs you", body: Self.reason(for: session))
            }
        case .finished(let session):
            if settings.finishedSound { play(Self.finishedSound) }
            if settings.finishedNotification {
                notify(id: "finished-\(session.id)", title: "\(session.projectName) finished", body: session.task ?? session.agent.displayName)
            }
        }
    }

    private static func reason(for session: AgentSession) -> String {
        if case .needsAttention(let reason) = session.state { return reason }
        return session.task ?? session.agent.displayName
    }

    private func play(_ name: String) {
        NSSound(named: name)?.play()
    }

    private func notify(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    private func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }
}
