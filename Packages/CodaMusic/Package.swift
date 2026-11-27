// swift-tools-version: 6.1
import PackageDescription

// Readcc iOS integration of Coda v0.1.2. Original manifest is preserved in
// Package.upstream.swift.txt. macOS launcher/ObjC/Sparkle sources stay intact,
// but do not participate in this iOS-only dependency graph.
let package = Package(
    name: "CodaMusic",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS("16.0")],
    products: [.library(name: "CodaCore", targets: ["CodaCore"])],
    dependencies: [],
    targets: [
        .target(
            name: "CodaCore",
            path: "Sources/Coda",
            resources: [
                .process("Resources/en.lproj"),
                .process("Resources/zh-Hans.lproj"),
                .copy("Resources/PrivacyInfo.xcprivacy"),
                .copy("Resources/CodaLegal"),
                .copy("Features/Home/QishuiModeIcons"),
                .copy("Core/API/QishuiVerificationAssets"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CodaCoreTests",
            dependencies: ["CodaCore"],
            path: "Tests/CodaCoreTests",
            exclude: ["OfflineArtworkTests.swift", "NowPlayingArtworkStoreTests.swift"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
