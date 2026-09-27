// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ValleyCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "ValleyCore", targets: ["ValleyCore"]),
    ],
    targets: [
        .target(name: "ValleyCore"),
        .testTarget(name: "ValleyCoreTests", dependencies: ["ValleyCore"]),
    ]
)
