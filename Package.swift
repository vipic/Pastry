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
        .target(
            name: "CSQLCipher",
            path: "Sources/CSQLCipher",
            sources: ["include/shim.c"],
            publicHeadersPath: "include",
            cSettings: [
                .define("SQLITE_HAS_CODEC"),
                .define("SQLCIPHER_CRYPTO_CC"),
            ],
            linkerSettings: [
                .unsafeFlags(["-LSources/CSQLCipher", "-lsqlcipher"]),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("Security"),
            ]
        ),
        .executableTarget(
            name: "Pastry",
            dependencies: ["CSQLCipher"],
            path: "Sources/Pastry",
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("Security"),
            ]
        ),
        .testTarget(
            name: "PastryTests",
            dependencies: ["Pastry", "CSQLCipher"],
            path: "Tests/PastryTests",
            exclude: ["__Snapshots__"]
        ),
    ]
)
