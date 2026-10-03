// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "IsletHost",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "IsletHost", targets: ["IsletHost"])
    ],
    dependencies: [
        .package(path: "../IsletCore")
    ],
    targets: [
        .target(
            name: "CSkyLight",
            linkerSettings: [.unsafeFlags(["-F/System/Library/PrivateFrameworks", "-framework", "SkyLight"])]
        ),
        .target(name: "IsletHost", dependencies: ["IsletCore", "CSkyLight"], resources: [.process("Resources")]),
        .testTarget(name: "IsletHostTests", dependencies: ["IsletHost", .product(name: "IsletTestSupport", package: "IsletCore")])
    ]
)
