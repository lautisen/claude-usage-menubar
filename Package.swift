// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeUsage",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ClaudeUsage"),
        .testTarget(name: "ClaudeUsageTests", dependencies: ["ClaudeUsage"]),
    ],
    swiftLanguageModes: [.v5]
)
