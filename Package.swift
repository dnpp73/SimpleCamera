// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "SimpleCamera",
    platforms: [
        .iOS(.v12),
        .macOS(.v10_11),
    ],
    products: [
        .library(name: "SimpleCamera", targets: ["SimpleCamera"]),
    ],
    targets: [
        .target(
            name: "SimpleCamera",
            dependencies: [],
            path: "Sources"
        ),
    ]
)
