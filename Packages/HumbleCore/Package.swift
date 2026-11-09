// swift-tools-version: 6.2
import PackageDescription

// Everything of the app that does not draw: API, session, permissions, sync, offline copy,
// real time, assistant stream, Markdown, grid layout, formats. Foundation only, so that
// `swift test` runs it on the Mac as well as in the simulator.
let package = Package(
    name: "HumbleCore",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "HumbleCore", targets: ["HumbleCore"]),
    ],
    targets: [
        .target(name: "HumbleCore"),
        .testTarget(name: "HumbleCoreTests", dependencies: ["HumbleCore"]),
    ]
)
