// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SearchKit",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SearchKit",
            targets: ["SearchKit"]
        ),
    ],
    dependencies: [
        .package(path: "../NoteCore"),
        .package(path: "../InkKit"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SearchKit",
            dependencies: [
                .product(name: "NoteCore", package: "NoteCore"),
                .product(name: "InkKit", package: "InkKit"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .testTarget(
            name: "SearchKitTests",
            dependencies: [
                "SearchKit",
                .product(name: "NoteCore", package: "NoteCore"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
    ]
)
