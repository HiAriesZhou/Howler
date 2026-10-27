// swift-tools-version:5.9
import PackageDescription

var products: [Product] = [
    .library(name: "HowlerCore", targets: ["HowlerCore"]),
]
var targets: [Target] = [
    .target(name: "HowlerCore"),
    .testTarget(name: "HowlerCoreTests", dependencies: ["HowlerCore"]),
]

// The menu bar app needs AppKit/Carbon; elsewhere (Linux CI) only the core library and tests build.
#if os(macOS)
products.append(.executable(name: "Howler", targets: ["Howler"]))
targets.append(
    .executableTarget(
        name: "Howler",
        dependencies: ["HowlerCore"],
        linkerSettings: [.linkedFramework("Carbon")]
    )
)
#endif

let package = Package(
    name: "Howler",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
