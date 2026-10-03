// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ShelfPlugin",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ShelfPlugin", targets: ["ShelfPlugin"])
    ],
    dependencies: [
        .package(path: "../../Packages/IsletCore")
    ],
    targets: [
        .target(name: "ShelfPlugin", dependencies: ["IsletCore"]),
        .testTarget(name: "ShelfPluginTests", dependencies: ["ShelfPlugin"])
    ]
)
