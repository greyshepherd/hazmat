// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hazmat",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "HazmatCore", targets: ["HazmatCore"]),
        .executable(name: "HazmatDaemon", targets: ["HazmatDaemon"])
    ],
    targets: [
        .target(name: "HazmatCore"),
        .target(name: "HazmatProtocol"),
        .target(name: "HazmatPrivileged", dependencies: ["HazmatCore", "HazmatProtocol"]),
        .executableTarget(
            name: "HazmatDaemon",
            dependencies: ["HazmatCore", "HazmatPrivileged", "HazmatProtocol"]
        ),
        .testTarget(
            name: "HazmatCoreTests",
            dependencies: ["HazmatCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "HazmatPrivilegedTests",
            dependencies: ["HazmatCore", "HazmatPrivileged", "HazmatProtocol"]
        )
    ]
)
