// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ClipboardManager",
    platforms: [
        .macOS("14.0")
    ],
    products: [
        .executable(
            name: "ClipboardManager",
            targets: ["ClipboardManager"]
        ),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "ClipboardManager",
            dependencies: [],
            path: "Sources/ClipboardManager",
            resources: []
        ),
    ]
)
