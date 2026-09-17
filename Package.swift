// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hazmat",
    products: [
        .library(name: "HazmatCore", targets: ["HazmatCore"])
    ],
    targets: [
        .target(name: "HazmatCore"),
        .testTarget(
            name: "HazmatCoreTests",
            dependencies: ["HazmatCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
