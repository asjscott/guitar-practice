// swift-tools-version: 6.0
// TheoryCore: pure music theory. No UI, no audio, no SwiftData — Foundation only.
import PackageDescription

let package = Package(
    name: "TheoryCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TheoryCore", targets: ["TheoryCore"]),
    ],
    targets: [
        .target(name: "TheoryCore"),
        .testTarget(name: "TheoryCoreTests", dependencies: ["TheoryCore"]),
    ]
)
