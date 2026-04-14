// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "claude-mv",
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.0"),
    ],
    targets: [
        .target(
            name: "ClaudeMVCore"
        ),
        .executableTarget(
            name: "claude-mv",
            dependencies: [
                "ClaudeMVCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "claude-mvTests",
            dependencies: ["ClaudeMVCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
