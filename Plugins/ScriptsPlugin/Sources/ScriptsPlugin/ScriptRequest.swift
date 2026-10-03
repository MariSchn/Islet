import AppKit
import Foundation
import IsletCore

struct ScriptRequestError: Error, Equatable {
    let message: String
}

struct ScriptActivityRequest: Equatable {
    static let defaultTTL: TimeInterval = 600
    static let maxTTL: TimeInterval = 86400

    var id: String
    var text: String
    var symbol: String?
    var progress: Double?
    var priority: PillStatus.Priority
    var ttl: TimeInterval

    static func decode(_ data: Data) throws -> ScriptActivityRequest {
        let fields = try ScriptFields(data)
        let id = try fields.string("id", required: true) ?? ""
        guard (1...64).contains(id.count), id.unicodeScalars.allSatisfy(ScriptFields.idCharacters.contains) else {
            throw ScriptRequestError(message: "id must be 1 to 64 characters from A-Z a-z 0-9 . _ -")
        }
        let ttl = try fields.number("ttl") ?? defaultTTL
        guard ttl > 0, ttl <= maxTTL else {
            throw ScriptRequestError(message: "ttl must be greater than 0 and at most \(Int(maxTTL))")
        }
        let progress = try fields.number("progress")
        if let progress, !(0...1).contains(progress) {
            throw ScriptRequestError(message: "progress must be between 0 and 1")
        }
        return ScriptActivityRequest(id: id, text: try fields.text(), symbol: try fields.string("symbol"), progress: progress, priority: try fields.priority(), ttl: ttl)
    }
}

struct ScriptAnnounceRequest: Equatable {
    var text: String
    var symbol: String?
    var priority: PillStatus.Priority

    static func decode(_ data: Data) throws -> ScriptAnnounceRequest {
        let fields = try ScriptFields(data)
        return ScriptAnnounceRequest(text: try fields.text(), symbol: try fields.string("symbol"), priority: try fields.priority())
    }
}

enum ScriptSymbol {
    static let fallback = "bolt.fill"

    static func resolved(_ name: String?) -> String {
        guard let name, NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil else { return fallback }
        return name
    }
}

private struct ScriptFields {
    static let idCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")

    let values: [String: Any]

    init(_ data: Data) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data), let values = object as? [String: Any] else {
            throw ScriptRequestError(message: "body must be a JSON object")
        }
        self.values = values
    }

    func string(_ key: String, required: Bool = false) throws -> String? {
        guard let value = values[key], !(value is NSNull) else {
            if required { throw ScriptRequestError(message: "\(key) is required") }
            return nil
        }
        guard let string = value as? String else { throw ScriptRequestError(message: "\(key) must be a string") }
        return string
    }

    func number(_ key: String) throws -> Double? {
        guard let value = values[key], !(value is NSNull) else { return nil }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
            throw ScriptRequestError(message: "\(key) must be a number")
        }
        return number.doubleValue
    }

    func text() throws -> String {
        let text = try string("text", required: true) ?? ""
        guard (1...200).contains(text.count) else { throw ScriptRequestError(message: "text must be 1 to 200 characters") }
        return text
    }

    func priority() throws -> PillStatus.Priority {
        guard let name = try string("priority") else { return .info }
        switch name {
        case "ambient": return .ambient
        case "info": return .info
        case "attention": return .attention
        case "urgent": return .urgent
        default: throw ScriptRequestError(message: "priority must be ambient, info, attention or urgent")
        }
    }
}
