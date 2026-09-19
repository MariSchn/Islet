import Foundation

struct AppleScriptError: LocalizedError {
    static let automationDenied = -1743
    static let applicationNotRunning = -600

    let code: Int?
    let message: String

    init(_ info: NSDictionary?) {
        code = info?[NSAppleScript.errorNumber] as? Int
        message = info?[NSAppleScript.errorMessage] as? String ?? "The script could not be run."
    }

    var errorDescription: String? {
        switch code {
        case Self.automationDenied:
            "Islet is not allowed to control this app. Allow it under System Settings › Privacy & Security › Automation."
        default:
            message
        }
    }
}

actor AppleScriptRunner {
    private var compiled: [String: NSAppleScript] = [:]

    func run(_ source: String) throws {
        try run(source) { _ in }
    }

    func run<Value: Sendable>(_ source: String, _ transform: @Sendable (NSAppleEventDescriptor) -> Value) throws -> Value {
        let script: NSAppleScript
        if let cached = compiled[source] {
            script = cached
        } else {
            guard let fresh = NSAppleScript(source: source) else { throw AppleScriptError(nil) }
            compiled[source] = fresh
            script = fresh
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error { throw AppleScriptError(error) }
        return transform(result)
    }
}
