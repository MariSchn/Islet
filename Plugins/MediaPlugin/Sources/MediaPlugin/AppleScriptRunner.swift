import Foundation

struct AppleScriptError: LocalizedError {
    static let automationDenied = -1743
    static let consentRequired = -1744
    static let applicationNotRunning = -600

    let code: Int?
    let message: String

    init(_ info: NSDictionary?) {
        code = info?[NSAppleScript.errorNumber] as? Int
        message = info?[NSAppleScript.errorMessage] as? String ?? "The script could not be run."
    }

    var isApplicationNotRunning: Bool {
        code == Self.applicationNotRunning
    }

    var isAutomationDenied: Bool {
        code == Self.automationDenied || code == Self.consentRequired
    }

    var errorDescription: String? {
        switch code {
        case Self.automationDenied, Self.consentRequired:
            "Islet is not allowed to control this app. Allow it under System Settings › Privacy & Security › Automation."
        default:
            message
        }
    }
}

enum AppleScript {
    static func tell(_ application: String, timeout: Int = 2, _ body: String) -> String {
        """
        if application "\(application)" is not running then error "Application isn't running." number -600
        with timeout of \(timeout) seconds
            tell application "\(application)"
                \(body)
            end tell
        end timeout
        """
    }
}

actor AppleScriptRunner {
    private var compiled: [String: NSAppleScript] = [:]

    func run(_ source: String, cached: Bool = true) throws {
        try run(source, cached: cached) { _ in }
    }

    func run<Value: Sendable>(_ source: String, cached: Bool = true, _ transform: @Sendable (NSAppleEventDescriptor) -> Value) throws -> Value {
        let script: NSAppleScript
        if let existing = compiled[source] {
            script = existing
        } else {
            guard let fresh = NSAppleScript(source: source) else { throw AppleScriptError(nil) }
            if cached {
                compiled[source] = fresh
            }
            script = fresh
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error { throw AppleScriptError(error) }
        return transform(result)
    }
}
