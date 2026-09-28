// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IsletCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "IsletCore", targets: ["IsletCore"]),
        .library(name: "IsletTestSupport", targets: ["IsletTestSupport"])
    ],
    targets: [
        .target(name: "IsletCore"),
        .target(name: "IsletTestSupport", dependencies: ["IsletCore"]),
        .testTarget(name: "IsletCoreTests", dependencies: ["IsletCore", "IsletTestSupport"])
    ]
)
