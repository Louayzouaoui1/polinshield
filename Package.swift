// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PolinShield",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PolinShield", targets: ["PolinShield"])
    ],
    targets: [
        .executableTarget(
            name: "PolinShield",
            path: "Sources/PolinShield",
            resources: [.copy("../../Resources")]
        )
    ]
)
