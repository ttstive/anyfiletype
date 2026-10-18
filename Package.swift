// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "FileFlip",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "FileFlip", path: "Sources/FileFlip")
    ]
)
