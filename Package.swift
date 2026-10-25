// swift-tools-version:5.9
import PackageDescription

var products: [Product] = [
    .library(name: "QuickAskCore", targets: ["QuickAskCore"]),
]
var targets: [Target] = [
    .target(name: "QuickAskCore"),
    .testTarget(name: "QuickAskCoreTests", dependencies: ["QuickAskCore"]),
]

// The menu bar app needs AppKit/Carbon; elsewhere (Linux CI) only the core library and tests build.
#if os(macOS)
products.append(.executable(name: "QuickAsk", targets: ["QuickAsk"]))
targets.append(
    .executableTarget(
        name: "QuickAsk",
        dependencies: ["QuickAskCore"],
        linkerSettings: [.linkedFramework("Carbon")]
    )
)
#endif

let package = Package(
    name: "QuickAsk",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
