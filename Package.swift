// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MoniTuner",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "MoniTunerCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("AppKit"),
            ]
        ),
        .executableTarget(
            name: "MoniTuner",
            dependencies: ["MoniTunerCore"]
        ),
        .testTarget(
            name: "MoniTunerCoreTests",
            dependencies: ["MoniTunerCore"]
        ),
    ]
)
