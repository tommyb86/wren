// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WrenCore",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "WrenCore", targets: ["WrenCore"])
    ],
    targets: [
        .target(name: "WrenCore"),
        .testTarget(name: "WrenCoreTests", dependencies: ["WrenCore"])
    ]
)
