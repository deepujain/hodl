// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HODL",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "HODL",
            path: "Sources/HODL"
        ),
    ]
)
