// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sharingan",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "SharinganCore",
            path: "Sources/SharinganCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "Sharingan",
            dependencies: ["SharinganCore"],
            path: "Sources/Sharingan",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "SelfTest",
            dependencies: ["SharinganCore"],
            path: "Sources/SelfTest"
        ),
        .executableTarget(
            name: "tired",
            dependencies: ["SharinganCore"],
            path: "Sources/tired"
        ),
        .testTarget(
            name: "SharinganTests",
            dependencies: ["SharinganCore"],
            path: "Tests/SharinganTests"
        )
    ]
)