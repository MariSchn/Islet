// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HelloPlugin",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "HelloPlugin", targets: ["HelloPlugin"])
    ],
    dependencies: [
        .package(path: "../../Packages/IsletCore")
    ],
    targets: [
        .target(name: "HelloPlugin", dependencies: ["IsletCore"]),
        .testTarget(name: "HelloPluginTests", dependencies: ["HelloPlugin"])
    ]
)
