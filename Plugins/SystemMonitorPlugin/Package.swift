// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SystemMonitorPlugin",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SystemMonitorPlugin", targets: ["SystemMonitorPlugin"])
    ],
    dependencies: [
        .package(path: "../../Packages/IsletCore")
    ],
    targets: [
        .target(name: "SystemMonitorPlugin", dependencies: ["IsletCore"]),
        .testTarget(name: "SystemMonitorPluginTests", dependencies: ["SystemMonitorPlugin"])
    ]
)
