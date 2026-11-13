// swift-tools-version: 6.4
// BoardKit: the infinite-canvas model for the NOTEAPP whiteboard.

import PackageDescription

let package = Package(
    name: "BoardKit",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "BoardKit", targets: ["BoardKit"]),
    ],
    dependencies: [
        .package(path: "../NoteCore"),
    ],
    targets: [
        .target(
            name: "BoardKit",
            dependencies: [
                .product(name: "NoteCore", package: "NoteCore"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        ),
        .testTarget(
            name: "BoardKitTests",
            dependencies: [
                "BoardKit",
                .product(name: "NoteCore", package: "NoteCore"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        ),
    ]
)
