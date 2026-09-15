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
            exclude: [
                ".codex",
                "AGENTS.md",
                "README.md",
                "dist",
                "docs",
                "script"
            ],
            sources: ["App", "Models", "Stores", "Support", "Views"],
            resources: [.copy("Resources")]
        )
    ]
)
