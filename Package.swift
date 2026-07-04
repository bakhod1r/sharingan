// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Blink",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "BlinkCore",
            path: "Sources/BlinkCore"
        ),
        .executableTarget(
            name: "Blink",
            dependencies: ["BlinkCore"],
            path: "Sources/Blink",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "SelfTest",
            dependencies: ["BlinkCore"],
            path: "Sources/SelfTest"
        ),
        .executableTarget(
            name: "tired",
            dependencies: ["BlinkCore"],
            path: "Sources/tired"
        )
    ]
)