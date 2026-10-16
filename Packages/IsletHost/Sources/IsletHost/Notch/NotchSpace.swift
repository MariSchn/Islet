import AppKit
import os

@MainActor
final class NotchSpace {
    static let shared = NotchSpace()

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, CFDictionary?) -> UInt64
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, UInt64, Int32) -> Void
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Void
    private typealias MoveWindows = @convention(c) (Int32, CFArray, CFArray) -> Void

    private struct Space {
        let connection: Int32
        let id: UInt64
        let addWindows: MoveWindows
        let removeWindows: MoveWindows
    }

    private let space: Space?

    private init() {
        guard let mainConnectionID = Self.symbol("CGSMainConnectionID", as: MainConnectionID.self),
              let spaceCreate = Self.symbol("CGSSpaceCreate", as: SpaceCreate.self),
              let setAbsoluteLevel = Self.symbol("CGSSpaceSetAbsoluteLevel", as: SpaceSetAbsoluteLevel.self),
              let showSpaces = Self.symbol("CGSShowSpaces", as: ShowSpaces.self),
              let addWindows = Self.symbol("CGSAddWindowsToSpaces", as: MoveWindows.self),
              let removeWindows = Self.symbol("CGSRemoveWindowsFromSpaces", as: MoveWindows.self)
        else {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "Islet", category: "notch").error("Private window space API is unavailable; the notch uses a regular window level")
            space = nil
            return
        }
        let connection = mainConnectionID()
        let id = spaceCreate(connection, 1, nil)
        setAbsoluteLevel(connection, id, Int32.max)
        showSpaces(connection, [id] as CFArray)
        space = Space(connection: connection, id: id, addWindows: addWindows, removeWindows: removeWindows)
    }

    func add(_ window: NSWindow) {
        guard let space else { return }
        space.addWindows(space.connection, [window.windowNumber] as CFArray, [space.id] as CFArray)
    }

    func remove(_ window: NSWindow) {
        guard let space else { return }
        space.removeWindows(space.connection, [window.windowNumber] as CFArray, [space.id] as CFArray)
    }

    private static func symbol<Function>(_ name: String, as type: Function.Type) -> Function? {
        guard let pointer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }
}
