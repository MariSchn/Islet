// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentsPlugin",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AgentsPlugin", targets: ["AgentsPlugin"])
    ],
    dependencies: [
        .package(path: "../../Packages/IsletCore")
    ],
    targets: [
        .target(name: "AgentsPlugin", dependencies: ["IsletCore"]),
        .testTarget(name: "AgentsPluginTests", dependencies: ["AgentsPlugin"])
    ]
)
