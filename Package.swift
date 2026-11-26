// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nabiz",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Nabiz",
            path: "Sources/Nabiz",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("ServiceManagement"), .linkedFramework("IOBluetooth"), .linkedFramework("CoreAudio")]
        ),
        .testTarget(
            name: "NabizTests",
            dependencies: ["Nabiz"],
            path: "Tests/NabizTests"
        ),
    ]
)
