// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MoveEyes",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "MoveEyes", path: "Sources/MoveEyes")
    ]
)
