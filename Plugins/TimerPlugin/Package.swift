// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TimerPlugin",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TimerPlugin", targets: ["TimerPlugin"])
    ],
    dependencies: [
        .package(path: "../../Packages/IsletCore")
    ],
    targets: [
        .target(name: "TimerPlugin", dependencies: ["IsletCore"]),
        .testTarget(name: "TimerPluginTests", dependencies: ["TimerPlugin"])
    ]
)
