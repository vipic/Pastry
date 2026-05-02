// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Pastry",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(
            name: "Pastry",
            targets: ["Pastry"]
        ),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Pastry",
            dependencies: [],
            path: "Sources/Pastry",
            resources: []
        ),
        .testTarget(
            name: "PastryTests",
            dependencies: ["Pastry"],
            path: "Tests/PastryTests"
        ),
    ]
)
