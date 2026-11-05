// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MdCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MdCore", targets: ["MdCore"])],
    targets: [
        .binaryTarget(name: "MdCoreFFI", path: "MdCoreFFI.xcframework"),
        .target(name: "MdCore", dependencies: ["MdCoreFFI"]),
    ]
)
