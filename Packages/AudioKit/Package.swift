// swift-tools-version: 6.4
// AudioKit: audio capture, stroke-anchored replay and transcription metadata.

import PackageDescription

let package = Package(
    name: "AudioKit",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(
            name: "AudioKit",
            targets: ["AudioKit"]
        ),
    ],
    dependencies: [
        // The only local dependency: `StrokeRecord` is the anchor for replay.
        .package(path: "../NoteCore"),
    ],
    targets: [
        .target(
            name: "AudioKit",
            dependencies: [
                .product(name: "NoteCore", package: "NoteCore"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .testTarget(
            name: "AudioKitTests",
            dependencies: [
                "AudioKit",
                .product(name: "NoteCore", package: "NoteCore"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
    ]
)
