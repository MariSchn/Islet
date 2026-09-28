import AppKit
import CSkyLight

@MainActor
final class NotchSpace {
    static let shared = NotchSpace()

    private let connection = CGSMainConnectionID()
    private let space: CGSSpaceID

    private init() {
        space = CGSSpaceCreate(connection, 1, nil)
        CGSSpaceSetAbsoluteLevel(connection, space, Int32.max)
        CGSShowSpaces(connection, [space] as CFArray)
    }

    func add(_ window: NSWindow) {
        CGSAddWindowsToSpaces(connection, [window.windowNumber] as CFArray, [space] as CFArray)
    }

    func remove(_ window: NSWindow) {
        CGSRemoveWindowsFromSpaces(connection, [window.windowNumber] as CFArray, [space] as CFArray)
    }
}
