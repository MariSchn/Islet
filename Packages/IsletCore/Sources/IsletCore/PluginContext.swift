import CoreGraphics
import Foundation
import Observation
import os

@MainActor
@Observable
public final class PluginContext {
    public let manifest: PluginManifest
    public let storageDirectory: URL
    public let settings: PluginSettings
    public let logger: Logger
    public var pillStatus: PillStatus? {
        didSet {
            guard let pillStatus else { return }
            if let oldValue, oldValue.priority >= pillStatus.priority {
                if oldValue.priority > pillStatus.priority { pillActivity = 0 }
                return
            }
            recordActivity()
        }
    }
    public var contentSize: CGSize?
    public internal(set) var isScreenVisible = false {
        didSet {
            if oldValue, !isScreenVisible { recordActivity() }
        }
    }
    var isActive = false
    public private(set) var announcement: PillAnnouncement?
    private(set) var pillActivity = 0

    private static var lastActivity = 0

    init(manifest: PluginManifest, storageDirectory: URL, settings: PluginSettings) {
        self.manifest = manifest
        self.storageDirectory = storageDirectory
        self.settings = settings
        logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Islet", category: manifest.id)
    }

    public func announce(_ announcement: PillAnnouncement) {
        self.announcement = announcement
    }

    func clearAnnouncement() {
        announcement = nil
    }

    private func recordActivity() {
        Self.lastActivity += 1
        pillActivity = Self.lastActivity
    }

    public func derive<Value: Equatable>(_ property: ReferenceWritableKeyPath<PluginContext, Value>, from value: @escaping @MainActor () -> Value) {
        track { [weak self] in
            guard let self, isActive else { return nil }
            let derived = value()
            guard self[keyPath: property] != derived else { return nil }
            return { self[keyPath: property] = derived }
        }
    }

    public func observe<Value: Equatable>(_ value: @escaping @MainActor () -> Value, initial: Bool = false, onChange: @escaping @MainActor (Value) -> Void) {
        var last: Value?
        var isFirst = true
        track {
            let current = value()
            if isFirst, !initial {
                isFirst = false
                last = current
                return nil
            }
            isFirst = false
            guard current != last else { return nil }
            return {
                last = current
                onChange(current)
            }
        }
    }

    private func track(_ evaluate: @escaping @MainActor () -> (@MainActor () -> Void)?) {
        let apply = withObservationTracking {
            evaluate()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.track(evaluate)
            }
        }
        apply?()
    }
}
