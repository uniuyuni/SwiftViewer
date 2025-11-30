// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftViewer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SwiftViewer", targets: ["SwiftViewer"]),
        .library(name: "SwiftViewerCore", targets: ["SwiftViewerCore"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SwiftViewerCore",
            dependencies: [],
            resources: [
                .process("SwiftViewer.xcdatamodeld")
            ]
        ),
        .executableTarget(
            name: "SwiftViewer",
            dependencies: ["SwiftViewerCore"],
            resources: [
                .process("Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "SwiftViewerTests",
            dependencies: ["SwiftViewerCore"]
        )
    ]
)
