// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Announcements",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14), .visionOS(.v1)],
    products: [
        .library(name: "Announcements", targets: ["Announcements"]),
    ],
    targets: [
        .target(name: "Announcements", resources: [.process("Resources")]),
        .testTarget(name: "AnnouncementsTests", dependencies: ["Announcements"]),
    ]
)
