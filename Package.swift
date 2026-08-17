// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Companion",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic (agent command building, event decoding, persistence,
        // panel geometry) — no AppKit, so it stays unit-testable.
        .target(
            name: "CompanionCore",
            path: "Sources/CompanionCore"
        ),
        .executableTarget(
            name: "Companion",
            dependencies: ["CompanionCore"],
            path: "Sources/Companion"
        ),
        .testTarget(
            name: "CompanionCoreTests",
            dependencies: ["CompanionCore"],
            path: "Tests/CompanionCoreTests"
        ),
    ]
)
