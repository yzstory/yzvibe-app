// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "YzVibeKit",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "YzVibeKit", targets: ["YzVibeKit"]),
    ],
    targets: [
        .target(
            name: "YzVibeKit",
            path: "Sources/YzVibeKit",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "YzVibeKitTests",
            dependencies: ["YzVibeKit"],
            path: "Tests/YzVibeKitTests"
        ),
    ]
)
