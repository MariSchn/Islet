import AppKit
import UserNotifications

struct AlertSettings: Sendable, Equatable {
    var attentionSound = true
    var attentionNotification = false
    var finishedSound = true
    var finishedNotification = false
    var announcesInNotch = true

    init() {}

    var usesNotifications: Bool { attentionNotification || finishedNotification }
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
    var onOpenSession: ((String) -> Void)?

    private lazy var responder = NotificationResponder { [weak self] sessionID in
        self?.onOpenSession?(sessionID)
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
                notify(id: "attention-\(session.id)", sessionID: session.id, title: "\(session.displayName) needs you", body: Self.reason(for: session))
            }
        case .finished(let session):
            if settings.finishedSound { play(Self.finishedSound) }
            if settings.finishedNotification {
                notify(id: "finished-\(session.id)", sessionID: session.id, title: "\(session.displayName) finished", body: session.task ?? session.agent.displayName)
            }
        }
    }

    private static func reason(for session: AgentSession) -> String {
        switch session.state {
        case .needsAttention(let reason), .failed(let reason): reason
        case .starting, .working, .done, .interrupted: session.task ?? session.agent.displayName
        }
    }

    private func play(_ name: String) {
        NSSound(named: name)?.play()
    }

    private func notify(id: String, sessionID: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil
        content.userInfo = [NotificationResponder.sessionIDKey: sessionID]
        notificationCenter.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    private func requestAuthorization() {
        notificationCenter.requestAuthorization(options: [.alert]) { _, _ in }
    }

    private var notificationCenter: UNUserNotificationCenter {
        let center = UNUserNotificationCenter.current()
        if center.delegate !== responder {
            center.delegate = responder
        }
        return center
    }
}

private final class NotificationResponder: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let sessionIDKey = "sessionID"

    private let open: @MainActor @Sendable (String) -> Void

    init(open: @escaping @MainActor @Sendable (String) -> Void) {
        self.open = open
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let sessionID = response.notification.request.content.userInfo[Self.sessionIDKey] as? String
        else { return }
        await open(sessionID)
    }
}
