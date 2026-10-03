// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShekatiCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "ShekatiCore", targets: ["ShekatiCore"])],
    targets: [
        .target(name: "ShekatiCore"),
        .testTarget(name: "ShekatiCoreTests", dependencies: ["ShekatiCore"])
    ]
)
