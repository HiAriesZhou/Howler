// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "QuickAsk",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "QuickAskCore", targets: ["QuickAskCore"]),
        .executable(name: "QuickAsk", targets: ["QuickAsk"]),
    ],
    targets: [
        .target(name: "QuickAskCore"),
        .executableTarget(
            name: "QuickAsk",
            dependencies: ["QuickAskCore"],
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(name: "QuickAskCoreTests", dependencies: ["QuickAskCore"]),
    ]
)
