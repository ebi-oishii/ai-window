// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AIWindow",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "AIWindow",
            path: "Sources/AIWindow",
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=minimal"])
            ]
        )
    ]
)
