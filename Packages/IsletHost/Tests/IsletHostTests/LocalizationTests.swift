import Foundation
import Testing
@testable import IsletHost

struct LocalizationTests {
    @Test func resolvesAGermanString() throws {
        let path = try #require(Bundle.module.path(forResource: "de", ofType: "lproj"))
        let german = try #require(Bundle(path: path))
        #expect(german.localizedString(forKey: "Islet Settings", value: nil, table: nil) == "Islet-Einstellungen")
    }

    @Test func everyKeyIsTranslatedToGerman() throws {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/IsletHost/Resources/Localizable.xcstrings")
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try #require(json["strings"] as? [String: [String: Any]])
        #expect(!strings.isEmpty)
        for (key, entry) in strings {
            let localizations = entry["localizations"] as? [String: [String: Any]]
            let unit = localizations?["de"]?["stringUnit"] as? [String: String]
            #expect(unit?["state"] == "translated", "\(key) has no translated German entry")
            #expect(unit?["value"]?.isEmpty == false, "\(key) has an empty German entry")
        }
    }
}
