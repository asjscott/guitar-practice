// swift-tools-version: 6.0
// PracticeCore: pure drill engines driven by played notes and a clock.
// Depends on TheoryCore only; never on ListenCore, AVFoundation, UI or SwiftData.
import PackageDescription

let package = Package(
    name: "PracticeCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PracticeCore", targets: ["PracticeCore"]),
    ],
    dependencies: [
        .package(path: "../TheoryCore"),
    ],
    targets: [
        .target(name: "PracticeCore", dependencies: ["TheoryCore"]),
        .testTarget(name: "PracticeCoreTests", dependencies: ["PracticeCore", "TheoryCore"]),
    ]
)
