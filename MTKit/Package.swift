// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MTKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "MTKit", targets: ["MTKit"]),
    ],
    targets: [
        .target(name: "MTKit"),
        .testTarget(name: "MTKitTests", dependencies: ["MTKit"]),
    ]
)
