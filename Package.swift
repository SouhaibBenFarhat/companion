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
            path: "Sources/Companion",
            linkerSettings: [
                // Embeds Info.plist into the bare `swift run` binary. Without
                // this there is no usage description in development, and macOS
                // terminates the process the first time it asks for the
                // microphone — with no error that points at the cause.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "packaging/Info.dev.plist",
                ])
            ]
        ),
        .testTarget(
            name: "CompanionCoreTests",
            dependencies: ["CompanionCore"],
            path: "Tests/CompanionCoreTests"
        ),
    ]
)
