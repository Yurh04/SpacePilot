// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpacePilot",
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
            dependencies: ["SpacePilotCore"]
        ),
        .testTarget(
            name: "SpacePilotCoreTests",
            dependencies: ["SpacePilotCore"]
        )
    ],
    swiftLanguageModes: [.v6]
)
