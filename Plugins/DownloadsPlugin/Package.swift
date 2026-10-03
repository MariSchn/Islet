// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DownloadsPlugin",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DownloadsPlugin", targets: ["DownloadsPlugin"])
    ],
    dependencies: [
        .package(path: "../../Packages/IsletCore")
    ],
    targets: [
        .target(name: "DownloadsPlugin", dependencies: ["IsletCore"]),
        .testTarget(name: "DownloadsPluginTests", dependencies: ["DownloadsPlugin"])
    ]
)
