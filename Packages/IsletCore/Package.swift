// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "IsletCore",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "IsletCore", targets: ["IsletCore"]),
        .library(name: "IsletTestSupport", targets: ["IsletTestSupport"])
    ],
    targets: [
        .target(name: "IsletCore", resources: [.process("Resources")]),
        .target(name: "IsletTestSupport", dependencies: ["IsletCore"]),
        .testTarget(name: "IsletCoreTests", dependencies: ["IsletCore", "IsletTestSupport"])
    ]
)
