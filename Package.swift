// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DockDwight",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "DockDwight", targets: ["DockDwight"]),
        .library(name: "DockDwightLib", targets: ["DockDwightLib"])
    ],
    targets: [
        .target(
            name: "DockDwightLib",
            resources: [.process("Resources")],
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .executableTarget(name: "DockDwight", dependencies: ["DockDwightLib"]),
        .testTarget(name: "DockDwightTests", dependencies: ["DockDwightLib"])
    ]
)

