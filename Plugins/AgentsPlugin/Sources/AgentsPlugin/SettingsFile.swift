import Foundation

struct SettingsFile: Sendable {
    struct Unreadable: Error, LocalizedError {
        let path: String
        var errorDescription: String? { "\(path) is not a JSON object" }
    }

    let url: URL
    let description: String

    func read() throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        if String(decoding: data, as: UTF8.self).allSatisfy(\.isWhitespace) { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Unreadable(path: description) }
        return object
    }

    func write(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }
}
