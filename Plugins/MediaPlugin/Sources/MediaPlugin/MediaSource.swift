import AppKit

public protocol MediaSource: Sendable {
    var displayName: String { get }
    var bundleIdentifier: String { get }

    @MainActor var isRunning: Bool { get }
    @MainActor func launch()

    func stateChanges() -> AsyncStream<Void>
    func nowPlaying() async throws -> NowPlaying?
    func playPause() async throws
    func nextTrack() async throws
    func previousTrack() async throws
    func seek(to position: TimeInterval) async throws
}

public extension MediaSource {
    @MainActor
    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    @MainActor
    func launch() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
