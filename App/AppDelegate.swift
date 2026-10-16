import AgentsPlugin
import AppKit
import CalendarPlugin
import DownloadsPlugin
import GitHubPlugin
import IsletCore
import IsletHost
import MediaPlugin
import os
import ScriptsPlugin
import ShelfPlugin
import SystemMonitorPlugin
import TimerPlugin

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let builtInPlugins: [any IsletPlugin.Type] = [
        ShelfPlugin.self,
        MediaPlugin.self,
        AgentsPlugin.self,
        CalendarPlugin.self,
        GitHubPlugin.self,
        TimerPlugin.self,
        SystemMonitorPlugin.self,
        DownloadsPlugin.self,
        ScriptsPlugin.self,
    ]
    private static let terminationTimeout: Duration = .seconds(2)
    private static let sourceURL = URL(string: "https://github.com/MariSchn/Islet")!
    private static let hasLaunchedKey = "islet.hasLaunched"
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Islet", category: "app")

    let settings = AppSettings(defaults: .standard)
    let registry = PluginRegistry(
        storageRoot: URL.applicationSupportDirectory.appending(path: "Islet/Plugins", directoryHint: .isDirectory)
    )
    private(set) lazy var displays = NotchDisplayManager(settings: settings) { [unowned self] display in
        makePanel(for: display)
    }
    private var statusItem: NSStatusItem?
    private var registration: Task<Void, Never>?
    private let updater = SparkleUpdater()
    private lazy var settingsWindow = SettingsWindowController(settings: settings, registry: registry, info: AppInfo(sourceURL: Self.sourceURL), updater: updater)
    private lazy var hotKey = GlobalHotKey { [unowned self] in
        displays.toggleNotch(at: NSEvent.mouseLocation)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        displays.start()
        observeMenuBarIconSetting()
        observeShortcutSetting()
        registration = Task { @MainActor in
            await registerBuiltInPlugins()
        }
        if !UserDefaults.standard.bool(forKey: Self.hasLaunchedKey) {
            UserDefaults.standard.set(true, forKey: Self.hasLaunchedKey)
            showSettings()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        var replied = false
        let reply = {
            guard !replied else { return }
            replied = true
            sender.reply(toApplicationShouldTerminate: true)
        }
        Task { @MainActor [registry, registration] in
            await registration?.value
            await registry.deactivateAll()
            reply()
        }
        Task { @MainActor in
            try? await Task.sleep(for: Self.terminationTimeout)
            reply()
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func showSettings() {
        settingsWindow.show()
    }

    @objc private func showAbout() {
        settingsWindow.show(.about)
    }

    @objc private func checkForUpdates() {
        updater?.checkForUpdates()
    }

    private func makePanel(for display: NotchDisplay) -> NotchPanel {
        let controller = NotchController(settings: settings)
        controller.attach(registry)
        return NotchPanel(display: display, controller: controller) { [registry, weak self] in
            NotchHostView(controller: controller, registry: registry) { self?.showSettings() }
        }
    }

    private func observeMenuBarIconSetting() {
        withObservationTracking {
            updateStatusItem(visible: settings.showsMenuBarIcon)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeMenuBarIconSetting()
            }
        }
    }

    private func observeShortcutSetting() {
        withObservationTracking {
            settings.isShortcutUnavailable = !hotKey.register(settings.openShortcut)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeShortcutSetting()
            }
        }
    }

    private func updateStatusItem(visible: Bool) {
        if visible {
            if statusItem == nil {
                statusItem = makeStatusItem()
            }
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "circle.hexagongrid", accessibilityDescription: "Islet")
        let menu = NSMenu()
        menu.addItem(withTitle: "About Islet", action: #selector(showAbout), keyEquivalent: "").target = self
        if updater != nil {
            menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Islet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        return item
    }

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let app = NSMenu(title: "Islet")
        app.addItem(withTitle: "About Islet", action: #selector(showAbout), keyEquivalent: "").target = self
        if updater != nil {
            app.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        }
        app.addItem(.separator())
        app.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Islet", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Quit Islet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "Islet", action: nil, keyEquivalent: "").submenu = app

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = window
        NSApp.windowsMenu = window

        return main
    }

    @objc private func openSettings() {
        showSettings()
    }

    private func registerBuiltInPlugins() async {
        for plugin in Self.builtInPlugins {
            do {
                try await registry.register(plugin)
            } catch {
                Self.logger.error("Failed to register \(plugin.manifest.id, privacy: .public): \(error, privacy: .public)")
            }
        }
    }
}
