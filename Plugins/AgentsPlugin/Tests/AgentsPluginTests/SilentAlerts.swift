@testable import AgentsPlugin

extension AlertSettings {
    /// Keeps test runs from playing real sounds.
    static var silent: AlertSettings {
        var settings = AlertSettings()
        settings.attentionSound = false
        settings.finishedSound = false
        return settings
    }
}
