// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Caffinate",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CaffinateKit", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "Caffinate",
            dependencies: ["CaffinateKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "caf",
            dependencies: ["CaffinateKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "caffinate-tests",
            dependencies: ["CaffinateKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
