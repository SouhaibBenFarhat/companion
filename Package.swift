// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Companion",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Whisper, converted to Core ML and run on the Neural Engine.
        //
        // The first external dependency in this package, and it is here for one
        // reason: accuracy on technical speech. Apple's on-device transcriber is
        // free and needs no download, but a pairing call is full of identifiers
        // and library names, which is exactly where it is weakest.
        //
        // Both engines stay selectable. This is an option, not a replacement.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.1.0"),
    ],
    targets: [
        // Pure logic (agent command building, event decoding, persistence,
        // panel geometry) — no AppKit, so it stays unit-testable.
        .target(
            name: "CompanionCore",
            path: "Sources/CompanionCore"
        ),
        .executableTarget(
            name: "Companion",
            dependencies: [
                "CompanionCore",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ],
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
