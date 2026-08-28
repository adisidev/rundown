// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "rundown",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "rundown", targets: ["rundown"]),
        .library(name: "RundownCore", targets: ["RundownCore"]),
    ],
    targets: [
        .target(name: "RundownCore"),
        .executableTarget(
            name: "rundown",
            dependencies: ["RundownCore"],
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(name: "RundownCoreTests", dependencies: ["RundownCore"]),
    ],
    swiftLanguageVersions: [.v5]
)
