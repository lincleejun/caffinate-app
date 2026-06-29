// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Caffinate",
    platforms: [.macOS(.v14)],
    dependencies: [
        // 自动更新：Sparkle 用自生成的 EdDSA 密钥给更新包签名，无需 Apple 证书。
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(name: "CaffinateKit", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "Caffinate",
            dependencies: [
                "CaffinateKit",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
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
