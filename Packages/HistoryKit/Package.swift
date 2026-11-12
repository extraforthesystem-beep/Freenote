// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "HistoryKit",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(
            name: "HistoryKit",
            targets: ["HistoryKit"]
        ),
    ],
    targets: [
        .target(
            name: "HistoryKit",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .testTarget(
            name: "HistoryKitTests",
            dependencies: ["HistoryKit"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
    ]
)
