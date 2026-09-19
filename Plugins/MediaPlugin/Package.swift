// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MediaPlugin",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MediaPlugin", targets: ["MediaPlugin"])
    ],
    dependencies: [
        .package(path: "../../Packages/IsletCore")
    ],
    targets: [
        .target(name: "MediaPlugin", dependencies: ["IsletCore"]),
        .testTarget(name: "MediaPluginTests", dependencies: ["MediaPlugin"])
    ]
)
