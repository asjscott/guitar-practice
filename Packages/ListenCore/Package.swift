// swift-tools-version: 6.0
// ListenCore: audio samples in, tuner readings and played notes out.
// Pure: no UI, no AVFoundation, no SwiftData — Foundation and Accelerate only (ADR 0002).
import PackageDescription

let package = Package(
    name: "ListenCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ListenCore", targets: ["ListenCore"]),
    ],
    targets: [
        .target(name: "ListenCore"),
        .testTarget(
            name: "ListenCoreTests",
            dependencies: ["ListenCore"],
            resources: [.copy("Fixtures")]      // self-recorded clips (ADR 0002)
        ),
    ]
)
