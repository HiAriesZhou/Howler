// swift-tools-version:5.9
import PackageDescription

var products: [Product] = [
    .library(name: "NapkinCore", targets: ["NapkinCore"]),
]
var targets: [Target] = [
    .target(name: "NapkinCore"),
    .testTarget(name: "NapkinCoreTests", dependencies: ["NapkinCore"]),
]

// The menu bar app needs AppKit/Carbon; elsewhere (Linux CI) only the core library and tests build.
#if os(macOS)
products.append(.executable(name: "Napkin", targets: ["Napkin"]))
targets.append(
    .executableTarget(
        name: "Napkin",
        dependencies: ["NapkinCore"],
        linkerSettings: [.linkedFramework("Carbon")]
    )
)
#endif

let package = Package(
    name: "Napkin",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
