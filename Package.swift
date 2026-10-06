// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ZoomableImage",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "ZoomableImage", targets: ["ZoomableImage"]),
    ],
    targets: [
        .target(name: "ZoomableImage"),
        .testTarget(name: "ZoomableImageTests", dependencies: ["ZoomableImage"]),
    ]
)
