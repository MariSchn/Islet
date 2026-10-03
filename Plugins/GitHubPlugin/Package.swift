// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GitHubPlugin",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "GitHubPlugin", targets: ["GitHubPlugin"])
    ],
    dependencies: [
        .package(path: "../../Packages/IsletCore")
    ],
    targets: [
        .target(name: "GitHubPlugin", dependencies: ["IsletCore"]),
        .testTarget(name: "GitHubPluginTests", dependencies: ["GitHubPlugin"])
    ]
)
