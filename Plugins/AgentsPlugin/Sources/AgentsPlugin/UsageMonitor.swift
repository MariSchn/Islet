import Foundation
import Security

struct UsageWindow: Sendable, Equatable {
    var utilization: Double
    var resetsAt: Date?

    init(utilization: Double, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }
}

struct ClaudeUsage: Sendable, Equatable {
    var fiveHour: UsageWindow?
    var sevenDay: UsageWindow?

    init(fiveHour: UsageWindow?, sevenDay: UsageWindow?) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }

    var isEmpty: Bool { fiveHour == nil && sevenDay == nil }

    static func decode(_ data: Data) throws -> ClaudeUsage {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw UsageError.unexpectedResponse }
        return ClaudeUsage(fiveHour: window(object["five_hour"]), sevenDay: window(object["seven_day"]))
    }

    private static func date(from string: String) -> Date? {
        if let date = try? Date(string, strategy: .iso8601.year().month().day().dateTimeSeparator(.standard).time(includingFractionalSeconds: true).timeZone(separator: .colon)) { return date }
        return try? Date(string, strategy: .iso8601)
    }

    private static func window(_ value: Any?) -> UsageWindow? {
        guard let object = value as? [String: Any], let utilization = object["utilization"] as? Double else { return nil }
        let resetsAt = (object["resets_at"] as? String).flatMap { Self.date(from: $0) }
        return UsageWindow(utilization: utilization, resetsAt: resetsAt)
    }
}

enum UsageError: Error, LocalizedError, Equatable {
    case notLoggedIn
    case unexpectedResponse
    case status(Int)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn: "Claude Code is not logged in"
        case .unexpectedResponse: "Unexpected usage response"
        case .status(let code): "Usage request failed (\(code))"
        }
    }
}

struct ClaudeCredentials: Sendable {
    static let keychainService = "Claude Code-credentials"

    static func accessToken(from data: Data) -> String? {
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (object?["claudeAiOauth"] as? [String: Any])?["accessToken"] as? String
    }

    static func keychainAccessToken() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return accessToken(from: data)
    }

    static func fileAccessToken(in directory: URL) -> String? {
        guard let data = try? Data(contentsOf: directory.appending(path: ".credentials.json")) else { return nil }
        return accessToken(from: data)
    }
}

@MainActor
@Observable
final class UsageMonitor {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let refreshInterval: TimeInterval = 5 * 60
    static let minimumInterval: TimeInterval = 30
    static let maximumStaleness: TimeInterval = 30 * 60

    private(set) var usage: ClaudeUsage?
    private(set) var error: String?
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled { startTimer() } else { clear() }
        }
    }

    private let accessToken: @Sendable () -> String?
    private let load: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private var lastFetch: Date?
    private var lastSuccess: Date?
    private var task: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var isActive = false

    init(
        isEnabled: Bool = false,
        accessToken: @escaping @Sendable () -> String? = { ClaudeCredentials.keychainAccessToken() ?? ClaudeCredentials.fileAccessToken(in: URL.homeDirectory.appending(path: ".claude")) },
        load: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }
    ) {
        self.isEnabled = isEnabled
        self.accessToken = accessToken
        self.load = load
    }

    func start() {
        isActive = true
        startTimer()
    }

    func stop() {
        isActive = false
        clear()
    }

    private func startTimer() {
        guard isActive, isEnabled, timer == nil else { return }
        refresh(force: true)
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.refreshInterval))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    private func clear() {
        timer?.cancel()
        timer = nil
        task?.cancel()
        task = nil
        usage = nil
        error = nil
        lastFetch = nil
        lastSuccess = nil
    }

    private static func invalidatesUsage(_ error: any Error) -> Bool {
        switch error as? UsageError {
        case .notLoggedIn, .status(401), .status(403): true
        default: false
        }
    }

    func refresh(force: Bool = false) {
        guard isEnabled, task == nil else { return }
        if !force, let lastFetch, Date().timeIntervalSince(lastFetch) < Self.minimumInterval { return }
        lastFetch = Date()
        task = Task { [accessToken, load] in
            let result: Result<ClaudeUsage, any Error>
            do {
                guard let token = await Task.detached(operation: accessToken).value else { throw UsageError.notLoggedIn }
                var request = URLRequest(url: Self.endpoint)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await load(request)
                if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 { throw UsageError.status(status) }
                result = .success(try ClaudeUsage.decode(data))
            } catch {
                result = .failure(error)
            }
            guard !Task.isCancelled else { return }
            task = nil
            switch result {
            case .success(let usage):
                self.usage = usage
                error = nil
                lastSuccess = Date()
            case .failure(let failure):
                if Self.invalidatesUsage(failure) || lastSuccess.map({ Date().timeIntervalSince($0) > Self.maximumStaleness }) != false {
                    usage = nil
                }
                error = failure.localizedDescription
            }
        }
    }
}
