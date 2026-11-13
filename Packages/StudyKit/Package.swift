// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "StudyKit",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(
            name: "StudyKit",
            targets: ["StudyKit"]
        ),
    ],
    targets: [
        .target(
            name: "StudyKit",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .testTarget(
            name: "StudyKitTests",
            dependencies: ["StudyKit"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
    ]
)
