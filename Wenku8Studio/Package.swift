// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Wenku8Studio",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "Wenku8Core", targets: ["Wenku8Core"]),
        .executable(name: "Wenku8Studio", targets: ["Wenku8Studio"]),
    ],
    targets: [
        .target(
            name: "Wenku8Core",
            path: "Sources/Wenku8Core"
        ),
        .executableTarget(
            name: "Wenku8Studio",
            dependencies: ["Wenku8Core"],
            path: "Sources/Wenku8Studio"
        ),
        .testTarget(
            name: "Wenku8CoreTests",
            dependencies: ["Wenku8Core"],
            path: "Tests/Wenku8CoreTests"
        ),
    ]
)
