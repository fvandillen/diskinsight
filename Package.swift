// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiskInsight",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DiskInsight",
            path: "Sources/DiskInsight",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
