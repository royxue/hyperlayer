// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hyperlayer",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Hyperlayer",
            path: "Sources/Hyperlayer",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
