// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "S1-StrokeRoundTrip",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "StrokeRoundTrip", targets: ["StrokeRoundTrip"])
    ],
    targets: [
        .target(name: "StrokeRoundTrip"),
        .testTarget(name: "StrokeRoundTripTests", dependencies: ["StrokeRoundTrip"])
    ]
)
