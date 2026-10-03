// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ScriptsPlugin",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ScriptsPlugin", targets: ["ScriptsPlugin"])
    ],
    dependencies: [
        .package(path: "../../Packages/IsletCore")
    ],
    targets: [
        .target(name: "ScriptsPlugin", dependencies: ["IsletCore"]),
        .testTarget(name: "ScriptsPluginTests", dependencies: ["ScriptsPlugin"])
    ]
)
