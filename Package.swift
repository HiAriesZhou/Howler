// swift-tools-version:5.9
import PackageDescription

var products: [Product] = [
    .library(name: "HowlerCore", targets: ["HowlerCore"]),
]
var dependencies: [Package.Dependency] = []
var targets: [Target] = [
    .target(name: "HowlerCore"),
    .testTarget(name: "HowlerCoreTests", dependencies: ["HowlerCore"]),
]

// The menu bar app needs AppKit/Carbon; elsewhere (Linux CI) only the core library and tests build.
// Sparkle, its one dependency, installs updates; scripts/bundle.sh embeds and signs it.
#if os(macOS)
dependencies.append(.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"))
products.append(.executable(name: "Howler", targets: ["Howler"]))
targets.append(
    .executableTarget(
        name: "Howler",
        dependencies: ["HowlerCore", .product(name: "Sparkle", package: "Sparkle")],
        linkerSettings: [.linkedFramework("Carbon")]
    )
)
#endif

let package = Package(
    name: "Howler",
    platforms: [.macOS(.v14)],
    products: products,
    dependencies: dependencies,
    targets: targets
)
