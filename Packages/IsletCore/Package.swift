// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IsletCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "IsletCore", targets: ["IsletCore"])
    ],
    targets: [
        .target(name: "IsletCore"),
        .testTarget(name: "IsletCoreTests", dependencies: ["IsletCore"])
    ]
)
