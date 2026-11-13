// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "TextDocKit",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(
            name: "TextDocKit",
            targets: ["TextDocKit"]
        ),
    ],
    targets: [
        .target(
            name: "TextDocKit",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        ),
        .testTarget(
            name: "TextDocKitTests",
            dependencies: ["TextDocKit"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        ),
    ]
)
