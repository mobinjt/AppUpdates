// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AppUpdates",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        /// The checker apps use: required and suggested updates, kept for offline use.
        .library(name: "AppUpdates", targets: ["AppUpdates"]),
        /// The policy model and the build header alone, Foundation only, for servers and tools
        /// (Linux included).
        .library(name: "AppUpdatesCore", targets: ["AppUpdatesCore"])
    ],
    targets: [
        .target(name: "AppUpdatesCore"),
        .target(name: "AppUpdates", dependencies: ["AppUpdatesCore"]),
        .testTarget(name: "AppUpdatesTests", dependencies: ["AppUpdates"])
    ]
)
