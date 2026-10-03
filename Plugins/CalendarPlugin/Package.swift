// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CalendarPlugin",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CalendarPlugin", targets: ["CalendarPlugin"])
    ],
    dependencies: [
        .package(path: "../../Packages/IsletCore")
    ],
    targets: [
        .target(name: "CalendarPlugin", dependencies: ["IsletCore"]),
        .testTarget(name: "CalendarPluginTests", dependencies: ["CalendarPlugin"])
    ]
)
