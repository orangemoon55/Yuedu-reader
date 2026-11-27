// swift-tools-version: 6.1
import Foundation
import PackageDescription

// Command Line Tools (no Xcode) ship Testing.framework outside the default
// search paths. Opt in with CODA_CLT_TESTING=1 to wire it up so `swift test`
// works there; leave it unset with Xcode (and in CI), where these flags are
// unnecessary.
//
// After a full .build wipe on a CLT-only machine, `swift test` needs a
// two-phase dance (SPM's derived runner compiles without these settings, so
// its canImport(Testing) fails and it silently runs 0 tests; but exposing
// the swiftmodule during the test-target compile kills the framework
// autolink and the link fails with undefined Testing symbols):
//   1. Build once (CODA_CLT_TESTING=1 swift build --build-tests) with NO
//      Testing.swiftmodule symlink present, so the test objects compile
//      against the framework (autolink intact).
//   2. ln -sfn "$CLT/Frameworks/Testing.framework/Versions/A/Modules/\
//      Testing.swiftmodule" .build/arm64-apple-macosx/debug/Modules/ ,
//      rm -rf .build/arm64-apple-macosx/debug/CodaPackageTests.derived ,
//      then CODA_CLT_TESTING=1 swift test — the runner regenerates with
//      Testing visible while the cached test objects keep their autolink
//      records.
let cltDeveloperDir = "/Library/Developer/CommandLineTools/Library/Developer"
let cltHasTesting = ProcessInfo.processInfo.environment["CODA_CLT_TESTING"] == "1"
let cltTestingSwiftSettings: [SwiftSetting] = cltHasTesting
    ? [.unsafeFlags(["-F", cltDeveloperDir + "/Frameworks"])]
    : []
let cltTestingLinkerSettings: [LinkerSetting] = cltHasTesting
    ? [.unsafeFlags([
        "-F", cltDeveloperDir + "/Frameworks",
        "-Xlinker", "-rpath", "-Xlinker", cltDeveloperDir + "/Frameworks",
        "-Xlinker", "-rpath", "-Xlinker", cltDeveloperDir + "/usr/lib",
    ])]
    : []

let package = Package(
    name: "Coda",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS("15.0"), .iOS("16.0")],
    products: [
        .executable(name: "Coda", targets: ["CodaLauncher"]),
        .library(name: "CodaCore", targets: ["CodaCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.5"),
    ],
    targets: [
        .target(
            name: "CodaCore",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle", condition: .when(platforms: [.macOS])),
                .target(name: "CodaObjC", condition: .when(platforms: [.macOS])),
            ],
            path: "Sources/Coda",
            exclude: ["Resources"],
            resources: [.copy("Features/Home/QishuiModeIcons"), .copy("Core/API/QishuiVerificationAssets")],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        // Objective-C exception catching for the playback engine (macOS only):
        // AVFAudio reports some failures as NSExceptions Swift cannot catch.
        .target(
            name: "CodaObjC",
            path: "Sources/CodaObjC"
        ),
        .executableTarget(
            name: "CodaLauncher",
            dependencies: [
                "CodaCore",
                .product(name: "Sparkle", package: "Sparkle", condition: .when(platforms: [.macOS])),
            ],
            path: "Sources/MacOS",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                // Sparkle.framework is embedded in Contents/Frameworks by Scripts/build-app.sh.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "CodaCoreTests",
            dependencies: [
                "CodaCore",
                .target(name: "CodaObjC", condition: .when(platforms: [.macOS])),
            ],
            path: "Tests/CodaCoreTests",
            resources: [.copy("Fixtures")],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ] + cltTestingSwiftSettings,
            linkerSettings: cltTestingLinkerSettings
        ),
    ]
)
