// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Courier",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "Courier", targets: ["Courier"]),
        .library(name: "CourierTesting", targets: ["CourierTesting"]),
    ],
    targets: [
        .target(name: "Courier"),
        .target(name: "CourierTesting", dependencies: ["Courier"]),
        .testTarget(name: "CourierTests", dependencies: ["Courier", "CourierTesting"]),
    ]
)
