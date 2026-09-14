// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PunkteRetter",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PunkteRetter", targets: ["PunkteRetterApp"]),
        .executable(name: "PunkteRetterAgent", targets: ["PunkteRetterAgent"]),
    ],
    targets: [
        .target(name: "PunkteRetterCore"),
        .executableTarget(name: "PunkteRetterApp", dependencies: ["PunkteRetterCore"]),
        .executableTarget(name: "PunkteRetterAgent", dependencies: ["PunkteRetterCore"]),
        .testTarget(name: "PunkteRetterCoreTests", dependencies: ["PunkteRetterCore"]),
    ]
)
