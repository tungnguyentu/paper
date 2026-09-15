// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Paper",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Paper", targets: ["Paper"])
    ],
    targets: [
        .executableTarget(
            name: "Paper",
            path: ".",
            exclude: [".codex", "dist", "script"],
            sources: ["App", "Models", "Stores", "Support", "Views"]
        )
    ]
)
