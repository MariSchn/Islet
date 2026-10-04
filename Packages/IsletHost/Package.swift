// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "IsletHost",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "IsletHost", targets: ["IsletHost"])
    ],
    dependencies: [
        .package(path: "../IsletCore")
    ],
    targets: [
        .target(name: "IsletHost", dependencies: ["IsletCore"]),
        .testTarget(name: "IsletHostTests", dependencies: ["IsletHost", .product(name: "IsletTestSupport", package: "IsletCore")])
    ]
)
