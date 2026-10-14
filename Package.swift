// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GitAppBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "GitAppBarCore",
            path: "Sources/GitAppBarCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "GitAppBar",
            dependencies: ["GitAppBarCore"],
            path: "Sources/GitAppBar",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "GitAppBarCoreTests",
            dependencies: ["GitAppBarCore"],
            path: "Tests/GitAppBarCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
