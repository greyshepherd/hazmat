// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hazmat",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "HazmatCore", targets: ["HazmatCore"]),
        .executable(name: "HazmatApp", targets: ["HazmatApp"]),
        .executable(name: "HazmatDaemon", targets: ["HazmatDaemon"])
    ],
    targets: [
        .target(name: "HazmatCore"),
        .target(name: "HazmatProtocol"),
        .target(name: "HazmatPrivileged", dependencies: ["HazmatCore", "HazmatProtocol"]),
        .target(name: "HazmatAppSupport", dependencies: ["HazmatCore", "HazmatProtocol"]),
        .executableTarget(
            name: "HazmatDaemon",
            dependencies: ["HazmatCore", "HazmatPrivileged", "HazmatProtocol"]
        ),
        .executableTarget(
            name: "HazmatApp",
            dependencies: ["HazmatCore", "HazmatAppSupport", "HazmatProtocol"]
        ),
        .testTarget(
            name: "HazmatCoreTests",
            dependencies: ["HazmatCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "HazmatPrivilegedTests",
            dependencies: ["HazmatCore", "HazmatPrivileged", "HazmatProtocol"]
        ),
        .testTarget(
            name: "HazmatAppSupportTests",
            dependencies: ["HazmatCore", "HazmatAppSupport", "HazmatProtocol"]
        )
    ]
)
