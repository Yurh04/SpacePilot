// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpacePilot",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SpacePilotCore", targets: ["SpacePilotCore"]),
        .executable(name: "SpacePilot", targets: ["SpacePilot"])
    ],
    targets: [
        .target(
            name: "SpacePilotCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "SpacePilot",
            dependencies: ["SpacePilotCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "SpacePilotTests",
            dependencies: ["SpacePilot"]
        ),
        .testTarget(
            name: "SpacePilotCoreTests",
            dependencies: ["SpacePilotCore"]
        )
    ],
    swiftLanguageModes: [.v6]
)
