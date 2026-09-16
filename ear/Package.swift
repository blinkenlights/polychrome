// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Ear",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Ear", targets: ["Ear"]),
    ],
    targets: [
        // The ring buffer between the two audio clocks, in C for plain atomics.
        .target(name: "EarRing"),
        .target(name: "EarKit", dependencies: ["EarRing"]),
        .executableTarget(name: "Ear", dependencies: ["EarKit"]),
        .testTarget(name: "EarKitTests", dependencies: ["EarKit", "EarRing"]),
    ],
    swiftLanguageModes: [.v5]
)
