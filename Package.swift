// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PinkShirtKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17), .visionOS(.v1)],
    products: [
        .library(name: "PinkShirtKit", targets: ["PinkShirtKit"]),
    ],
    targets: [
        .target(name: "PinkShirtKit", resources: [.process("Resources")]),
        .testTarget(name: "PinkShirtKitTests", dependencies: ["PinkShirtKit"]),
    ]
)
